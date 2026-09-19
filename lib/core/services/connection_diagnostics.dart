import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'logging_service.dart';
import 'network_client.dart';

/// نتیجه یک بررسی تشخیصی.
class DiagnosticResult {
  final String title;
  final bool ok;
  final bool skipped;
  final String detail;
  final String? hint;
  final Duration duration;
  final int? statusCode;

  const DiagnosticResult({
    required this.title,
    required this.ok,
    required this.detail,
    required this.duration,
    this.skipped = false,
    this.hint,
    this.statusCode,
  });

  String get statusLabel {
    if (skipped) return 'SKIP';
    return ok ? 'PASS' : 'FAIL';
  }
}

/// تشخیص گام‌به‌گام علت قطع ارتباط با سرور.
///
/// این کلاس دقیقا همان مسیرهایی را تست می‌کند که برنامه استفاده می‌کند؛
/// بنابراین هر جا مشکل باشد، همان مرحله FAIL می‌شود و راهنمای رفع مشکل
/// هم نمایش داده می‌شود.
class ConnectionDiagnostics {
  ConnectionDiagnostics._();

  static final NetworkClient _client = NetworkClient();
  static final LoggingService _log = LoggingService();

  /// اجرای تمام بررسی‌ها. [onProgress] بعد از هر بررسی صدا زده می‌شود.
  static Future<List<DiagnosticResult>> run({
    void Function(DiagnosticResult result)? onProgress,
  }) async {
    final List<DiagnosticResult> results = <DiagnosticResult>[];
    _log.info('Connection diagnostics started', source: 'Diagnostics');

    void add(DiagnosticResult result) {
      results.add(result);
      onProgress?.call(result);
      _log.log(
        '${result.statusLabel} ${result.title}: ${result.detail}',
        level: result.ok ? LogLevel.info : LogLevel.warning,
        source: 'Diagnostics',
      );
    }

    // 1) دسترسی شبکه: ریشه REST وردپرس.
    final DiagnosticResult reach = await _checkHostReachable();
    add(reach);

    // اگر اصلا دسترسی شبکه نداریم، بقیه بررسی‌ها بی‌معنی است.
    if (!reach.ok) {
      for (final String title in const <String>[
        'WordPress REST API',
        'Shopping list plugin (bl/v1/items)',
        'WooCommerce API keys',
      ]) {
        add(DiagnosticResult(
          title: title,
          ok: false,
          skipped: true,
          detail: 'به دلیل خطای بالا اجرا نشد.',
          duration: Duration.zero,
        ));
      }
      return results;
    }

    // 2) فعال بودن REST API وردپرس.
    add(await _checkWpRestApi());

    // 3) افزونه چک‌لیست خرید + ساختار پاسخ.
    add(await _checkShoppingItems());

    // 4) اعتبار کلیدهای ووکامرس.
    add(await _checkWooCommerce());

    _log.info(
      'Connection diagnostics finished: '
      '${results.where((DiagnosticResult r) => r.ok).length}/${results.length} passed',
      source: 'Diagnostics',
    );
    return results;
  }

  static Future<DiagnosticResult> _checkHostReachable() async {
    final DateTime started = DateTime.now();
    const String title = 'Network access to server';
    try {
      final http.Response response = await _client.send(
        'GET',
        Uri.parse(ApiConfig.wpRestRoot),
        retry: false,
        timeout: ApiConfig.probeTimeout,
      );
      final Duration elapsed = DateTime.now().difference(started);
      final bool ok = response.statusCode >= 200 && response.statusCode < 500;
      return DiagnosticResult(
        title: title,
        ok: ok,
        statusCode: response.statusCode,
        detail: ok
            ? '${ApiConfig.wordpressBaseUrl} reachable, HTTP '
                '${response.statusCode} (${elapsed.inMilliseconds}ms)'
            : 'Host returned HTTP ${response.statusCode}',
        hint: ok ? null : 'بررسی کنید دامنه در دسترس و DNS درست باشد.',
        duration: elapsed,
      );
    } on NetworkFailure catch (e) {
      _log.setConnectionStatus(
        ConnectionStatus.offline,
        detail: e.kind.name,
        source: 'Diagnostics',
      );
      return DiagnosticResult(
        title: title,
        ok: false,
        detail: '${e.kind.name}: ${e.technical}',
        hint: e.hint,
        duration: DateTime.now().difference(started),
      );
    }
  }

  static Future<DiagnosticResult> _checkWpRestApi() async {
    final DateTime started = DateTime.now();
    const String title = 'WordPress REST API';
    try {
      final dynamic json = await _client.getJson(
        Uri.parse(ApiConfig.wpRestRoot),
      );
      final Duration elapsed = DateTime.now().difference(started);
      final String siteName = (json is Map && json['name'] != null)
          ? json['name'].toString()
          : '(unknown)';
      return DiagnosticResult(
        title: title,
        ok: true,
        statusCode: 200,
        detail: 'REST API active. Site: $siteName',
        duration: elapsed,
      );
    } on NetworkFailure catch (e) {
      return DiagnosticResult(
        title: title,
        ok: false,
        detail: '${e.kind.name}: ${e.technical}',
        hint: e.hint,
        statusCode: e.statusCode,
        duration: DateTime.now().difference(started),
      );
    }
  }
  static Future<DiagnosticResult> _checkShoppingItems() async {
    final DateTime started = DateTime.now();
    const String title = 'Shopping list plugin (bl/v1/items)';
    try {
      final http.Response response = await _client.get(
        Uri.parse(ApiConfig.shoppingItemsEndpoint),
        headers: const <String, String>{'Accept': 'application/json'},
      );
      final Duration elapsed = DateTime.now().difference(started);

      if (response.statusCode != 200) {
        final String preview = response.body.length > 180
            ? response.body.substring(0, 180)
            : response.body;
        final NetworkFailure failure = NetworkFailure(
          kind: NetworkFailureKind.http,
          url: ApiConfig.shoppingItemsEndpoint,
          technical: 'HTTP ${response.statusCode}: $preview',
          statusCode: response.statusCode,
        );
        return DiagnosticResult(
          title: title,
          ok: false,
          statusCode: response.statusCode,
          detail: failure.technical,
          hint: failure.hint,
          duration: elapsed,
        );
      }

      final dynamic json =
          _client.decodeJson(response, ApiConfig.shoppingItemsEndpoint);
      if (json is! List) {
        return DiagnosticResult(
          title: title,
          ok: false,
          statusCode: 200,
          detail: 'Expected a JSON array, got ${json.runtimeType}',
          hint: 'پاسخ سرور ساختار مورد انتظار را ندارد.',
          duration: elapsed,
        );
      }

      // بررسی نوع داده‌ها: id و is_purchased ممکن است String باشند
      // (همین موضوع قبلا باعث خطای type cast می‌شد).
      final String typeInfo;
      if (json.isEmpty) {
        typeInfo = 'empty list (no items yet)';
      } else {
        final dynamic first = json.first;
        typeInfo = 'items=${json.length}, '
            'id=${first is Map ? first['id'].runtimeType : '?'}, '
            'is_purchased=${first is Map ? first['is_purchased'].runtimeType : '?'}';
      }

      return DiagnosticResult(
        title: title,
        ok: true,
        statusCode: 200,
        detail: 'HTTP 200 ($typeInfo)',
        duration: elapsed,
      );
    } on NetworkFailure catch (e) {
      return DiagnosticResult(
        title: title,
        ok: false,
        detail: '${e.kind.name}: ${e.technical}',
        hint: e.hint,
        statusCode: e.statusCode,
        duration: DateTime.now().difference(started),
      );
    }
  }

  static Future<DiagnosticResult> _checkWooCommerce() async {
    final DateTime started = DateTime.now();
    const String title = 'WooCommerce API keys';
    final Uri uri = ApiConfig.wooProductsUri(
      page: 1,
      perPage: 1,
      fields: 'id,sku,name',
    );
    try {
      final http.Response response = await _client.send(
        'GET',
        uri,
        retry: false,
        timeout: ApiConfig.probeTimeout,
      );
      final Duration elapsed = DateTime.now().difference(started);

      if (response.statusCode == 200) {
        final dynamic json = _client.decodeJson(response, uri.toString());
        final int count = json is List ? json.length : -1;
        return DiagnosticResult(
          title: title,
          ok: count >= 0,
          statusCode: 200,
          detail: 'HTTP 200, sample products returned: $count',
          duration: elapsed,
        );
      }

      final String preview = response.body.length > 180
          ? response.body.substring(0, 180)
          : response.body;
      final NetworkFailure failure = NetworkFailure(
        kind: NetworkFailureKind.http,
        url: uri.toString(),
        technical: 'HTTP ${response.statusCode}: $preview',
        statusCode: response.statusCode,
      );
      return DiagnosticResult(
        title: title,
        ok: false,
        statusCode: response.statusCode,
        detail: failure.technical,
        hint: failure.hint,
        duration: elapsed,
      );
    } on NetworkFailure catch (e) {
      return DiagnosticResult(
        title: title,
        ok: false,
        detail: '${e.kind.name}: ${e.technical}',
        hint: e.hint,
        statusCode: e.statusCode,
        duration: DateTime.now().difference(started),
      );
    }
  }

}