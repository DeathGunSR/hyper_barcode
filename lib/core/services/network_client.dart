import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'logging_service.dart';

/// دسته‌بندی خطاهای شبکه - مبنای پیام‌های دقیق و قابل اقدام به کاربر.
enum NetworkFailureKind {
  /// مجوز INTERNET در AndroidManifest ثبت نشده یا توسط سیستم رد شده است.
  permissionDenied,
  /// دستگاه آفلاین است / مسیری به شبکه ندارد.
  noInternet,
  /// DNS نمی‌تواند هاست را پیدا کند.
  dns,
  /// درخواست بیش از حد طول کشید.
  timeout,
  /// خطای TLS/SSL یا گواهی.
  tls,
  /// سرور با کد خطا پاسخ داد (4xx/5xx).
  http,
  /// پاسخ سرور از نظر ساختار JSON قابل استفاده نبود.
  badResponse,
  unknown,
}

extension NetworkFailureKindExtension on NetworkFailureKind {
  bool get isRetryable {
    switch (this) {
      case NetworkFailureKind.timeout:
      case NetworkFailureKind.noInternet:
      case NetworkFailureKind.dns:
      case NetworkFailureKind.unknown:
        return true;
      case NetworkFailureKind.permissionDenied:
      case NetworkFailureKind.tls:
      case NetworkFailureKind.http:
      case NetworkFailureKind.badResponse:
        return false;
    }
  }
}

/// خطای شبکه با پیام قابل نمایش + جزئیات فنی برای لاگ.
class NetworkFailure implements Exception {
  final NetworkFailureKind kind;
  final String url;
  final String technical;
  final int? statusCode;
  final String? responseBody;

  NetworkFailure({
    required this.kind,
    required this.url,
    required this.technical,
    this.statusCode,
    this.responseBody,
  });

  bool get retryable => kind.isRetryable;

  /// پیام کوتاه و قابل نمایش به کاربر.
  String get message {
    switch (kind) {
      case NetworkFailureKind.permissionDenied:
        return 'دسترسی اینترنت برنامه مسدود است (مجوز INTERNET).';
      case NetworkFailureKind.noInternet:
        return 'اتصال اینترنت برقرار نیست.';
      case NetworkFailureKind.dns:
        return 'آدرس سرور پیدا نشد (خطای DNS).';
      case NetworkFailureKind.timeout:
        return 'زمان انتظار پاسخ سرور به پایان رسید.';
      case NetworkFailureKind.tls:
        return 'خطای امنیتی/گواهی (TLS) در ارتباط با سرور.';
      case NetworkFailureKind.http:
        return 'سرور با خطا پاسخ داد (HTTP $statusCode).';
      case NetworkFailureKind.badResponse:
        return 'پاسخ سرور قابل خواندن نبود (ساختار نامعتبر).';
      case NetworkFailureKind.unknown:
        return 'خطای نامشخص در ارتباط با سرور.';
    }
  }

  /// راهنمای عملی برای رفع مشکل (برای صفحه تشخیص اتصال).
  String get hint {
    switch (kind) {
      case NetworkFailureKind.permissionDenied:
        return 'فایل android/app/src/main/AndroidManifest.xml باید '
            '<uses-permission android:name="android.permission.INTERNET"/> '
            'داشته باشد. سپس APK را دوباره بسازید و نصب کنید '
            '(نسخه debug این مجوز را دارد اما release ندارد).';
      case NetworkFailureKind.noInternet:
        return 'Wi-Fi یا داده موبایل را روشن کنید و دوباره تلاش کنید.';
      case NetworkFailureKind.dns:
        return 'DNS دستگاه یا اتصال Wi-Fi را بررسی کنید و با مرورگر '
            '${ApiConfig.wordpressBaseUrl} را باز کنید.';
      case NetworkFailureKind.timeout:
        return 'کیفیت شبکه یا کندی سرور را بررسی کنید. زمان انتظار فعلی '
            '${ApiConfig.requestTimeout.inSeconds} ثانیه است.';
      case NetworkFailureKind.tls:
        return 'تاریخ/ساعت دستگاه را درست کنید و از معتبر بودن گواهی SSL سایت مطمئن شوید.';
      case NetworkFailureKind.http:
        if (statusCode == 401 || statusCode == 403) {
          return 'کلیدهای ووکامرس (consumer_key/consumer_secret) نامعتبر است.';
        }
        if (statusCode == 404) {
          return 'اندپوینت پیدا نشد. بررسی کنید افزونه «Barcodify Shopping List» '
              'روی وردپرس نصب و فعال است.';
        }
        return 'لاگ سرور وردپرس را بررسی کنید (کد $statusCode).';
      case NetworkFailureKind.badResponse:
        return 'احتمالا افزونه وردپرس غیرفعال است و پاسخ HTML برگشته است.';
      case NetworkFailureKind.unknown:
        return 'پیام فنی را در پنل لاگ (منبع Network) بررسی کنید.';
    }
  }

  /// پیام کامل برای نمایش در لاگ/دیالوگ.
  String get fullMessage => '$message\n$hint\n\n[$technical]';

  @override
  String toString() => 'NetworkFailure(${kind.name}): $message | $technical';
}

/// کلاینت مرکزی HTTP: تایم‌اوت، تلاش مجدد، لاگ و ترجمه خطا.
///
/// همه درخواست‌های شبکه برنامه باید از این کلاس عبور کنند تا:
/// - هیچ درخواستی بی‌نهایت منتظر نماند (timeout).
/// - خطاهای موقت خودکار تکرار شوند (retry + backoff).
/// - هر رفت‌وبرگشت در [LoggingService] ثبت شود.
class NetworkClient {
  static final NetworkClient _instance = NetworkClient._internal();
  factory NetworkClient() => _instance;

  NetworkClient._internal({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;
  final LoggingService _log = LoggingService();

  /// ارسال درخواست با ثبت لاگ، تایم‌اوت و تلاش مجدد.
  Future<http.Response> send(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    dynamic body,
    bool retry = true,
    Duration? timeout,
  }) async {
    final Duration effectiveTimeout = timeout ?? ApiConfig.requestTimeout;
    final int maxAttempts = retry ? ApiConfig.maxRetries : 1;
    NetworkFailure? lastFailure;

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      _log.logNetworkRequest(
        method: method,
        url: uri.toString(),
        headers: headers,
        body: body,
        attemptNumber: attempt,
      );

      final DateTime started = DateTime.now();
      try {
        final http.Request request = http.Request(method, uri);
        if (headers != null) request.headers.addAll(headers);
        if (body != null) {
          request.body = body is String ? body : jsonEncode(body);
          if (!request.headers.containsKey('Content-Type')) {
            request.headers['Content-Type'] = 'application/json; charset=utf-8';
          }
        }

        final http.StreamedResponse streamed =
            await _client.send(request).timeout(effectiveTimeout);
        final http.Response response = await http.Response.fromStream(streamed);
        final Duration elapsed = DateTime.now().difference(started);

        _log.logNetworkResponse(
          method: method,
          url: uri.toString(),
          statusCode: response.statusCode,
          duration: elapsed,
          responseBody: response.body,
        );

        // خطاهای 5xx موقت هستند و ارزش تلاش مجدد دارند.
        if (response.statusCode >= 500 && attempt < maxAttempts) {
          lastFailure = NetworkFailure(
            kind: NetworkFailureKind.http,
            url: uri.toString(),
            technical: 'HTTP ${response.statusCode} (server error)',
            statusCode: response.statusCode,
            responseBody: response.body,
          );
          await _backoff(attempt);
          continue;
        }

        return response;
      } on TimeoutException catch (e, stack) {
        lastFailure = NetworkFailure(
          kind: NetworkFailureKind.timeout,
          url: uri.toString(),
          technical:
              'TimeoutException after ${effectiveTimeout.inSeconds}s: $e',
        );
        _log.logNetworkError(
          method: method,
          url: uri.toString(),
          error: lastFailure,
          stackTrace: stack,
          duration: DateTime.now().difference(started),
          attemptNumber: attempt,
        );
        if (attempt < maxAttempts) {
          await _backoff(attempt);
          continue;
        }
      } catch (e, stack) {
        lastFailure = mapError(e, uri.toString());
        _log.logNetworkError(
          method: method,
          url: uri.toString(),
          error: lastFailure,
          stackTrace: stack,
          duration: DateTime.now().difference(started),
          attemptNumber: attempt,
        );
        if (lastFailure.retryable && attempt < maxAttempts) {
          await _backoff(attempt);
          continue;
        }
      }
      break;
    }

    throw lastFailure ??
        NetworkFailure(
          kind: NetworkFailureKind.unknown,
          url: uri.toString(),
          technical: 'Request failed without a captured error',
        );
  }

  Future<void> _backoff(int attempt) {
    final int ms = ApiConfig.retryBaseDelay.inMilliseconds * (1 << (attempt - 1));
    final Duration delay = Duration(
      milliseconds: ms > ApiConfig.retryMaxDelay.inMilliseconds
          ? ApiConfig.retryMaxDelay.inMilliseconds
          : ms,
    );
    return Future<void>.delayed(delay);
  }
  // ==================== کمکی‌های درخواست ====================

  Future<http.Response> get(Uri uri, {Map<String, String>? headers}) =>
      send('GET', uri, headers: headers);

  Future<http.Response> postJson(Uri uri, dynamic body,
          {Map<String, String>? headers}) =>
      send('POST', uri, headers: headers, body: body);

  Future<http.Response> putJson(Uri uri, dynamic body,
          {Map<String, String>? headers}) =>
      send('PUT', uri, headers: headers, body: body);

  Future<http.Response> delete(Uri uri, {Map<String, String>? headers}) =>
      send('DELETE', uri, headers: headers);

  /// دریافت و رمزگشایی JSON با پیام خطای دقیق در صورت نامعتبر بودن.
  Future<dynamic> getJson(Uri uri, {Map<String, String>? headers}) async {
    final http.Response response = await get(uri, headers: headers);
    return decodeJson(response, uri.toString());
  }

  /// رمزگشایی امن پاسخ.
  dynamic decodeJson(http.Response response, String url) {
    if (response.body.trim().isEmpty) {
      throw NetworkFailure(
        kind: NetworkFailureKind.badResponse,
        url: url,
        technical: 'Empty response body (HTTP ${response.statusCode})',
        statusCode: response.statusCode,
      );
    }
    try {
      return json.decode(response.body);
    } catch (e) {
      final String preview = response.body.length > 200
          ? response.body.substring(0, 200)
          : response.body;
      throw NetworkFailure(
        kind: NetworkFailureKind.badResponse,
        url: url,
        technical: 'Invalid JSON (HTTP ${response.statusCode}): $e | body: $preview',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
  }

  /// ساخت [NetworkFailure] از یک استثنای خام با تشخیص دقیق علت.
  static NetworkFailure mapError(Object error, String url) {
    if (error is NetworkFailure) return error;

    final String text = error.toString();
    final String lower = text.toLowerCase();

    NetworkFailureKind kind = NetworkFailureKind.unknown;
    if (error is TimeoutException || lower.contains('timed out')) {
      kind = NetworkFailureKind.timeout;
    } else if (lower.contains('operation not permitted') ||
        lower.contains('errno = 1') ||
        lower.contains('permission denied')) {
      // علت اصلی قطع اتصال روی Android: نبود مجوز INTERNET در
      // AndroidManifest (به ویژه در بیلد release).
      kind = NetworkFailureKind.permissionDenied;
    } else if (lower.contains('failed host lookup') ||
        lower.contains('no address associated') ||
        lower.contains('nodename nor servname') ||
        lower.contains('errno = 7')) {
      kind = NetworkFailureKind.dns;
    } else if (lower.contains('network is unreachable') ||
        lower.contains('no route to host') ||
        lower.contains('errno = 101') ||
        lower.contains('errno = 113') ||
        lower.contains('errno = 51')) {
      kind = NetworkFailureKind.noInternet;
    } else if (lower.contains('handshake') ||
        lower.contains('certificate') ||
        lower.contains('tls') ||
        lower.contains('ssl')) {
      kind = NetworkFailureKind.tls;
    } else if (error is SocketException || error is http.ClientException) {
      kind = NetworkFailureKind.noInternet;
    }

    return NetworkFailure(
      kind: kind,
      url: url,
      technical: '${error.runtimeType}: $text',
    );
  }

  void dispose() {
    _client.close();
  }

}