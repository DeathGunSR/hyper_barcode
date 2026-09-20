import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// سطح لاگ برای سیستم ثبت وقایع.
enum LogLevel { debug, info, warning, error }

extension LogLevelExtension on LogLevel {
  String get label {
    switch (this) {
      case LogLevel.debug:
        return 'DEBUG';
      case LogLevel.info:
        return 'INFO';
      case LogLevel.warning:
        return 'WARN';
      case LogLevel.error:
        return 'ERROR';
    }
  }

  String get icon {
    switch (this) {
      case LogLevel.debug:
        return '🐛';
      case LogLevel.info:
        return 'ℹ️';
      case LogLevel.warning:
        return '⚠️';
      case LogLevel.error:
        return '❌';
    }
  }
}

/// وضعیت اتصال به سرور (برای نمایش در پنل دیباگ).
enum ConnectionStatus { unknown, connecting, online, serverError, offline }

extension ConnectionStatusExtension on ConnectionStatus {
  String get label {
    switch (this) {
      case ConnectionStatus.unknown:
        return 'Unknown';
      case ConnectionStatus.connecting:
        return 'Connecting...';
      case ConnectionStatus.online:
        return 'Online';
      case ConnectionStatus.serverError:
        return 'Server error';
      case ConnectionStatus.offline:
        return 'Offline';
    }
  }

  /// نشانگر متنی (به جای ایموجی) تا در همه دستگاه‌ها یکسان نمایش داده شود.
  String get icon {
    switch (this) {
      case ConnectionStatus.unknown:
        return '[?]';
      case ConnectionStatus.connecting:
        return '[...]';
      case ConnectionStatus.online:
        return '[OK]';
      case ConnectionStatus.serverError:
        return '[5xx]';
      case ConnectionStatus.offline:
        return '[X]';
    }
  }
}

/// ورودی لاگ شامل تمام اطلاعات لازم برای عیب‌یابی.
class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String source;
  final String message;
  final Map<String, dynamic>? metadata;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.source,
    required this.message,
    this.metadata,
  });

  String get timeString {
    final String h = timestamp.hour.toString().padLeft(2, '0');
    final String m = timestamp.minute.toString().padLeft(2, '0');
    final String s = timestamp.second.toString().padLeft(2, '0');
    final String ms = timestamp.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }

  String toDisplayString() {
    return '[$timeString] ${level.icon}[${level.label}] ($source): $message';
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'timestamp': timestamp.toIso8601String(),
      'level': level.name,
      'source': source,
      'message': message,
      if (metadata != null && metadata!.isNotEmpty) 'metadata': metadata,
    };
  }
}

/// سرویس ثبت وقایع سراسری برنامه (Singleton).
///
/// - از هر جای برنامه قابل دسترسی است.
/// - آخرین وضعیت اتصال به سرور را نگه می‌دارد.
/// - خطاهای ثبت‌نشده Flutter و async را هم می‌گیرد.
class LoggingService extends ChangeNotifier {
  static final LoggingService _instance = LoggingService._internal();
  factory LoggingService() => _instance;
  LoggingService._internal();

  final List<LogEntry> _logs = <LogEntry>[];
  static const int maxLogs = 1000;

  /// «توقف» فقط اسکرول خودکار را متوقف می‌کند و هرگز ثبت لاگ را متوقف نمی‌کند؛
  /// چون هدف این سرویس عیب‌یابی است و نباید شواهد از دست برود.
  bool _isPaused = false;
  bool _autoScroll = true;
  LogLevel _minLogLevel = LogLevel.debug;
  String _searchQuery = '';

  ConnectionStatus _connectionStatus = ConnectionStatus.unknown;
  String? _connectionDetail;
  int? _lastStatusCode;
  String? _lastRequestUrl;
  DateTime? _lastNetworkActivity;
  bool _isInstalled = false;

  // ==================== Getters ====================

  List<LogEntry> get logs => List<LogEntry>.unmodifiable(_logs);
  bool get isPaused => _isPaused;
  bool get autoScroll => _autoScroll;
  LogLevel get minLogLevel => _minLogLevel;
  String get searchQuery => _searchQuery;
  int get totalCount => _logs.length;
  int get errorCount =>
      _logs.where((LogEntry e) => e.level == LogLevel.error).length;
  int get warningCount =>
      _logs.where((LogEntry e) => e.level == LogLevel.warning).length;

  ConnectionStatus get connectionStatus => _connectionStatus;
  String? get connectionDetail => _connectionDetail;
  int? get lastStatusCode => _lastStatusCode;
  String? get lastRequestUrl => _lastRequestUrl;
  DateTime? get lastNetworkActivity => _lastNetworkActivity;

  /// خلاصه وضعیت اتصال برای هدر پنل دیباگ.
  String get connectionSummary {
    final String status =
        '${_connectionStatus.icon} ${_connectionStatus.label}';
    if (_lastStatusCode != null) {
      return '$status | HTTP $_lastStatusCode';
    }
    if (_connectionDetail != null && _connectionDetail!.isNotEmpty) {
      return '$status | $_connectionDetail';
    }
    return status;
  }

  // ==================== ثبت لاگ ====================

  void log(
    String message, {
    LogLevel level = LogLevel.info,
    String source = 'App',
    Map<String, dynamic>? metadata,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final Map<String, dynamic> meta = <String, dynamic>{
      if (metadata != null) ...metadata,
      if (error != null) 'error': error.toString(),
      if (stackTrace != null) 'stackTrace': _shortStack(stackTrace),
    };

    final LogEntry entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      source: source,
      message: message,
      metadata: meta.isEmpty ? null : meta,
    );

    _logs.add(entry);
    while (_logs.length > maxLogs) {
      _logs.removeAt(0);
    }

    if (kDebugMode) {
      // ignore: avoid_print
      print(entry.toDisplayString());
    }

    notifyListeners();
  }

  static String _shortStack(StackTrace stackTrace) {
    final String raw = stackTrace.toString();
    if (raw.length <= 400) return raw;
    return '${raw.substring(0, 400)}...';
  }

  void debug(String message,
      {String source = 'App', Map<String, dynamic>? metadata}) {
    log(message, level: LogLevel.debug, source: source, metadata: metadata);
  }

  void info(String message,
      {String source = 'App', Map<String, dynamic>? metadata}) {
    log(message, level: LogLevel.info, source: source, metadata: metadata);
  }

  void warning(String message,
      {String source = 'App', Map<String, dynamic>? metadata}) {
    log(message, level: LogLevel.warning, source: source, metadata: metadata);
  }

  void error(
    String message, {
    String source = 'App',
    Map<String, dynamic>? metadata,
    Object? exception,
    StackTrace? stackTrace,
  }) {
    log(
      message,
      level: LogLevel.error,
      source: source,
      metadata: metadata,
      error: exception,
      stackTrace: stackTrace,
    );
  }
  // ==================== لاگ شبکه ====================

  /// ثبت شروع یک درخواست شبکه.
  void logNetworkRequest({
    required String method,
    required String url,
    Map<String, String>? headers,
    dynamic body,
    int? attemptNumber,
  }) {
    _lastRequestUrl = url;
    _lastNetworkActivity = DateTime.now();
    _setConnectionStatus(ConnectionStatus.connecting, 'requesting $method');

    debug(
      '-> $method ${_shortUrl(url)}'
      '${attemptNumber != null && attemptNumber > 1 ? ' (attempt $attemptNumber)' : ''}',
      source: 'Network',
      metadata: <String, dynamic>{
        'method': method,
        if (headers != null && headers.isNotEmpty)
          'headers': _redactHeaders(headers),
        if (body != null) 'body': _truncate(body.toString(), 500),
      },
    );
  }

  /// ثبت پاسخ شبکه.
  void logNetworkResponse({
    required String method,
    required String url,
    required int statusCode,
    Duration? duration,
    String? responseBody,
  }) {
    _lastStatusCode = statusCode;
    _lastNetworkActivity = DateTime.now();

    final bool ok = statusCode >= 200 && statusCode < 300;
    final bool serverError = statusCode >= 500;
    _setConnectionStatus(
      serverError ? ConnectionStatus.serverError : ConnectionStatus.online,
      'HTTP $statusCode',
    );

    log(
      '<- $method ${_shortUrl(url)} -> $statusCode'
      '${duration != null ? ' (${duration.inMilliseconds}ms)' : ''}',
      level: ok ? LogLevel.info : LogLevel.warning,
      source: 'Network',
      metadata: <String, dynamic>{
        'method': method,
        'statusCode': statusCode,
        if (duration != null) 'durationMs': duration.inMilliseconds,
        if (responseBody != null && responseBody.isNotEmpty)
          'response': _truncate(responseBody, 300),
      },
    );
  }

  /// ثبت خطای شبکه همراه با متن دقیق فنی برای عیب‌یابی.
  void logNetworkError({
    required String method,
    required String url,
    required Object error,
    StackTrace? stackTrace,
    Duration? duration,
    int? attemptNumber,
  }) {
    _lastNetworkActivity = DateTime.now();
    _setConnectionStatus(ConnectionStatus.offline, _shortError(error));

    this.error(
      'x $method ${_shortUrl(url)} FAILED: ${_shortError(error)}'
      '${duration != null ? ' (${duration.inMilliseconds}ms)' : ''}'
      '${attemptNumber != null ? ' [attempt $attemptNumber]' : ''}',
      source: 'Network',
      metadata: <String, dynamic>{
        'method': method,
        'url': url,
        'errorType': error.runtimeType.toString(),
        'error': error.toString(),
      },
      stackTrace: stackTrace,
    );
  }

  /// ثبت دستی وضعیت اتصال به سرور (مثلاً بعد از تشخیص اتصال).
  void setConnectionStatus(
    ConnectionStatus status, {
    String? detail,
    String source = 'Network',
  }) {
    _setConnectionStatus(status, detail);
    log(
      'Server connection: ${status.label}${detail != null ? ' ($detail)' : ''}',
      level: status == ConnectionStatus.online
          ? LogLevel.info
          : (status == ConnectionStatus.serverError
              ? LogLevel.warning
              : LogLevel.debug),
      source: source,
    );
  }

  void _setConnectionStatus(ConnectionStatus status, String? detail) {
    _connectionStatus = status;
    _connectionDetail = detail;
  }

  static String _shortUrl(String url) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) return url;
    final String query = uri.query.isEmpty ? '' : '?${_truncate(uri.query, 60)}';
    return '${uri.host}${uri.path}$query';
  }

  static String _shortError(Object error) {
    final String text = error.toString();
    if (text.length <= 240) return text;
    return '${text.substring(0, 240)}...';
  }

  static String _truncate(String value, int max) {
    if (value.length <= max) return value;
    return '${value.substring(0, max)}... [truncated]';
  }

  static Map<String, String> _redactHeaders(Map<String, String> headers) {
    return headers.map((String key, String value) {
      final String lower = key.toLowerCase();
      if (lower == 'authorization' || lower.contains('secret')) {
        return MapEntry<String, String>(key, '***redacted***');
      }
      return MapEntry<String, String>(key, value);
    });
  }
  // ==================== خطاهای سراسری ====================

  /// نصب هندلرهای سراسری: خطاهای ویجت‌ها و خطاهای async ثبت‌نشده.
  /// باید یک بار در `main()` فراخوانی شود.
  void installGlobalErrorHandlers() {
    if (_isInstalled) return;
    _isInstalled = true;

    final FlutterExceptionHandler? previous = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      previous?.call(details);
      error(
        'FlutterError: ${details.exceptionAsString()}',
        source: 'Flutter',
        metadata: <String, dynamic>{
          'context': details.context?.toString(),
          'library': details.library,
        },
        stackTrace: details.stack,
      );
    };

    PlatformDispatcher.instance.onError = (Object err, StackTrace stack) {
      error('Uncaught async error: $err', source: 'Zone', stackTrace: stack);
      return true;
    };

    info('Logging service initialised', source: 'System',
        metadata: <String, dynamic>{
          'maxLogs': maxLogs,
          'platform': Platform.operatingSystem,
          'debugMode': kDebugMode,
        });
  }

  // ==================== کنترل نمایش ====================

  /// توقف/ادامه اسکرول خودکار (ثبت لاگ متوقف نمی‌شود).
  void setPaused(bool paused) {
    _isPaused = paused;
    if (!paused) _autoScroll = true;
    notifyListeners();
  }

  void setAutoScroll(bool enabled) {
    _autoScroll = enabled;
    notifyListeners();
  }

  void setMinLogLevel(LogLevel level) {
    _minLogLevel = level;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query.trim().toLowerCase();
    notifyListeners();
  }

  /// پاک کردن تمام لاگ‌ها.
  void clear() {
    _logs.clear();
    info('Logs cleared', source: 'System');
    notifyListeners();
  }

  // ==================== فیلتر و خروجی ====================

  List<LogEntry> getFilteredLogs([LogLevel? minLevel, String? query]) {
    final LogLevel level = minLevel ?? _minLogLevel;
    final String search = (query ?? _searchQuery).trim().toLowerCase();
    return _logs.where((LogEntry entry) {
      if (entry.level.index < level.index) return false;
      if (search.isEmpty) return true;
      return entry.message.toLowerCase().contains(search) ||
          entry.source.toLowerCase().contains(search) ||
          (entry.metadata?.toString().toLowerCase().contains(search) ?? false);
    }).toList();
  }

  /// لاگ‌های قابل نمایش با فیلترهای فعلی.
  List<LogEntry> get visibleLogs => getFilteredLogs();

  /// خروجی JSON معتبر.
  String exportToJson() {
    return const JsonEncoder.withIndent('  ')
        .convert(_logs.map((LogEntry e) => e.toJson()).toList());
  }

  /// خروجی متنی خوانا (شامل متادیتا).
  String exportToText() {
    final StringBuffer buffer = StringBuffer();
    buffer.writeln(
        '# Barcodify debug log - exported ${DateTime.now().toIso8601String()}');
    buffer.writeln('# entries: ${_logs.length}');
    buffer.writeln('# connection: $connectionSummary');
    buffer.writeln('-' * 60);
    for (final LogEntry entry in _logs) {
      buffer.writeln(entry.toDisplayString());
      if (entry.metadata != null && entry.metadata!.isNotEmpty) {
        buffer.writeln('      > ${entry.metadata}');
      }
    }
    return buffer.toString();
  }

  /// ذخیره لاگ‌ها در فایل و بازگرداندن آن (برای اشتراک‌گذاری/ارسال به پشتیبانی).
  Future<File> exportToFile() async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final String stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final File file =
        File('${dir.path}${Platform.pathSeparator}barcodify_log_$stamp.txt');
    await file.writeAsString(exportToText());
    info('Logs exported to ${file.path}', source: 'System');
    return file;
  }


}