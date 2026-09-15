import 'package:flutter/foundation.dart';

/// سطح لاگ برای سیستم ثبت وقایع
enum LogLevel {
  debug,
  info,
  warning,
  error,
}

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

/// ورودی لاگ شامل تمام اطلاعات لازم
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

  String toDisplayString() {
    final timeStr = timestamp.toString().substring(11, 19); // HH:mm:ss
    return '[$timeStr] ${level.icon}[${level.label}] ($source): $message';
  }

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'level': level.name,
      'source': source,
      'message': message,
      if (metadata != null) 'metadata': metadata,
    };
  }
}

/// سرویس ثبت وقایع سراسری برنامه
/// این کلاس به صورت singleton طراحی شده و در کل برنامه قابل دسترسی است
class LoggingService extends ChangeNotifier {
  static final LoggingService _instance = LoggingService._internal();
  factory LoggingService() => _instance;
  LoggingService._internal();

  final List<LogEntry> _logs = [];
  static const int _maxLogs = 500;

  bool _isPaused = false;
  bool _autoScroll = true;
  LogLevel _minLogLevel = LogLevel.debug;

  // Getters
  List<LogEntry> get logs => List.unmodifiable(_logs);
  bool get isPaused => _isPaused;
  bool get autoScroll => _autoScroll;
  LogLevel get minLogLevel => _minLogLevel;

  /// ثبت یک ورودی لاگ جدید
  void log(
    String message, {
    LogLevel level = LogLevel.info,
    String source = 'App',
    Map<String, dynamic>? metadata,
  }) {
    if (_isPaused) return;
    if (level.index < _minLogLevel.index) return;

    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      source: source,
      message: message,
      metadata: metadata,
    );

    _logs.add(entry);

    // محدود کردن تعداد لاگ‌ها
    if (_logs.length > _maxLogs) {
      _logs.removeAt(0);
    }

    // چاپ در کنسول برای دیباگ
    if (kDebugMode) {
      print(entry.toDisplayString());
    }

    notifyListeners();
  }

  /// لاگ سطح دیباگ
  void debug(String message, {String source = 'App', Map<String, dynamic>? metadata}) {
    log(message, level: LogLevel.debug, source: source, metadata: metadata);
  }

  /// لاگ سطح اطلاعات
  void info(String message, {String source = 'App', Map<String, dynamic>? metadata}) {
    log(message, level: LogLevel.info, source: source, metadata: metadata);
  }

  /// لاگ سطح هشدار
  void warning(String message, {String source = 'App', Map<String, dynamic>? metadata}) {
    log(message, level: LogLevel.warning, source: source, metadata: metadata);
  }

  /// لاگ سطح خطا
  void error(String message, {String source = 'App', Map<String, dynamic>? metadata}) {
    log(message, level: LogLevel.error, source: source, metadata: metadata);
  }

  /// ثبت درخواست شبکه
  void logNetworkRequest({
    required String method,
    required String url,
    Map<String, String>? headers,
    dynamic body,
  }) {
    debug(
      'HTTP $method: $url',
      source: 'Network',
      metadata: {
        'method': method,
        'url': url,
        if (headers != null) 'headers': headers,
        if (body != null) 'body': body.toString(),
      },
    );
  }

  /// ثبت پاسخ شبکه
  void logNetworkResponse({
    required String method,
    required String url,
    required int statusCode,
    Duration? duration,
    String? responseBody,
  }) {
    final level = statusCode >= 200 && statusCode < 300 ? LogLevel.info : LogLevel.warning;
    log(
      'HTTP $method $statusCode: $url (${duration?.inMilliseconds}ms)',
      level: level,
      source: 'Network',
      metadata: {
        'method': method,
        'url': url,
        'statusCode': statusCode,
        'durationMs': duration?.inMilliseconds,
        if (responseBody != null && kDebugMode) 'response': responseBody.substring(0, responseBody.length.clamp(0, 200)),
      },
    );
  }

  /// ثبت خطای شبکه
  void logNetworkError({
    required String method,
    required String url,
    required Object error,
    StackTrace? stackTrace,
  }) {
    error(
      'HTTP $method FAILED: $url - $error',
      source: 'Network',
      metadata: {
        'method': method,
        'url': url,
        'error': error.toString(),
        if (stackTrace != null) 'stackTrace': stackTrace.toString(),
      },
    );
  }

  /// تنظیم وضعیت توقف لاگ
  void setPaused(bool paused) {
    _isPaused = paused;
    notifyListeners();
  }

  /// تنظیم اسکرول خودکار
  void setAutoScroll(bool enabled) {
    _autoScroll = enabled;
    notifyListeners();
  }

  /// تنظیم حداقل سطح لاگ
  void setMinLogLevel(LogLevel level) {
    _minLogLevel = level;
    notifyListeners();
  }

  /// پاک کردن تمام لاگ‌ها
  void clear() {
    _logs.clear();
    info('Logs cleared', source: 'System');
    notifyListeners();
  }

  /// فیلتر کردن لاگ‌ها بر اساس سطح
  List<LogEntry> getFilteredLogs([LogLevel? minLevel]) {
    final level = minLevel ?? _minLogLevel;
    return _logs.where((log) => log.level.index >= level.index).toList();
  }

  /// خروجی گرفتن از لاگ‌ها به فرمت JSON
  String exportToJson() {
    final jsonLogs = _logs.map((log) => log.toJson()).toList();
    return '[${jsonLogs.map((j) => '{${j.entries.map((e) => '"${e.key}":"${e.value}"').join(',')}').join(',')}]';
  }

  /// خروجی گرفتن از لاگ‌ها به فرمت متنی
  String exportToText() {
    return _logs.map((log) => log.toDisplayString()).join('\n');
  }
}
