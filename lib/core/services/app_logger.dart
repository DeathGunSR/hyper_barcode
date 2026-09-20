import 'dart:async';
import 'package:flutter/foundation.dart';

enum LogLevel { debug, info, warning, error }

class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String source;
  final String message;
  final dynamic error;
  final StackTrace? stackTrace;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.source,
    required this.message,
    this.error,
    this.stackTrace,
  });

  String get formattedTime =>
      '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';

  String get levelIcon {
    switch (level) {
      case LogLevel.debug:
        return '🐞';
      case LogLevel.info:
        return 'ℹ️';
      case LogLevel.warning:
        return '⚠️';
      case LogLevel.error:
        return '❌';
    }
  }

  @override
  String toString() {
    var text = '[$formattedTime] [$source] $message';
    if (error != null) text += '\nError: $error';
    if (stackTrace != null) text += '\n$stackTrace';
    return text;
  }
}

class AppLogger extends ChangeNotifier {
  static final AppLogger _instance = AppLogger._internal();
  factory AppLogger() => _instance;
  AppLogger._internal();

  final List<LogEntry> _logs = [];
  final int _maxLogs = 500; // حداکثر تعداد لاگ در حافظه
  
  bool _isPaused = false;
  bool _autoScroll = true;
  LogLevel _filterLevel = LogLevel.debug;
  
  // وضعیت اتصال به سرور
  bool _isServerConnected = false;
  String _lastServerError = '';
  DateTime? _lastSyncTime;

  bool get isPaused => _isPaused;
  bool get autoScroll => _autoScroll;
  LogLevel get filterLevel => _filterLevel;
  bool get isServerConnected => _isServerConnected;
  String get lastServerError => _lastServerError;
  DateTime? get lastSyncTime => _lastSyncTime;

  List<LogEntry> get logs {
    if (_filterLevel == LogLevel.debug) return _logs;
    return _logs.where((log) => log.level.index >= _filterLevel.index).toList();
  }

  void log(String message, {String source = 'App', LogLevel level = LogLevel.info, dynamic error, StackTrace? stackTrace}) {
    if (_isPaused) return;

    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      source: source,
      message: message,
      error: error,
      stackTrace: stackTrace,
    );

    _logs.add(entry);
    if (_logs.length > _maxLogs) {
      _logs.removeAt(0);
    }

    // چاپ در کنسول دیباگ
    if (kDebugMode) {
      print(entry.toString());
    }

    notifyListeners();
  }

  void debug(String message, {String source = 'App'}) => log(message, source: source, level: LogLevel.debug);
  void info(String message, {String source = 'App'}) => log(message, source: source, level: LogLevel.info);
  void warning(String message, {String source = 'App'}) => log(message, source: source, level: LogLevel.warning);
  void error(String message, {String source = 'App', dynamic ex, StackTrace? stackTrace}) {
    log(message, source: source, level: LogLevel.error, error: ex, stackTrace: stackTrace);
  }

  void updateServerStatus(bool isConnected, {String errorMessage = ''}) {
    _isServerConnected = isConnected;
    _lastServerError = errorMessage;
    if (isConnected) {
      _lastSyncTime = DateTime.now();
      info('Server connection successful', source: 'Network');
    } else {
      error('Server connection failed: $errorMessage', source: 'Network');
    }
    notifyListeners();
  }

  void setFilterLevel(LogLevel level) {
    _filterLevel = level;
    notifyListeners();
  }

  void togglePause() {
    _isPaused = !_isPaused;
    notifyListeners();
  }

  void toggleAutoScroll() {
    _autoScroll = !_autoScroll;
    notifyListeners();
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  String exportLogs() {
    final buffer = StringBuffer();
    buffer.writeln('=== Barcodify Debug Logs ===');
    buffer.writeln('Generated: ${DateTime.now()}');
    buffer.writeln('Server Connected: $_isServerConnected');
    buffer.writeln('===========================');
    for (var log in _logs) {
      buffer.writeln(log.toString());
      buffer.writeln('---------------------------');
    }
    return buffer.toString();
  }
}
