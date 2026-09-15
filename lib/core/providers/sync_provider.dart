import 'package:flutter/foundation.dart';
import '../services/logging_service.dart';

/// Provider برای مدیریت وضعیت همگام‌سازی محصولات
/// این کلاس امکان اجرای همگام‌سازی در پس‌زمینه را فراهم می‌کند
class SyncProvider extends ChangeNotifier {
  static final SyncProvider _instance = SyncProvider._internal();
  factory SyncProvider() => _instance;
  SyncProvider._internal();

  bool _isSyncing = false;
  int _progress = 0;
  int _total = 0;
  String _currentStatus = '';
  DateTime? _lastSyncTime;
  SyncState _syncState = SyncState.idle;
  String? _lastError;

  // Getters
  bool get isSyncing => _isSyncing;
  int get progress => _progress;
  int get total => _total;
  String get currentStatus => _currentStatus;
  DateTime? get lastSyncTime => _lastSyncTime;
  SyncState get syncState => _syncState;
  String? get lastError => _lastError;
  double get progressPercent => _total > 0 ? _progress / _total : 0.0;

  /// شروع عملیات همگام‌سازی
  /// اگر همگام‌سازی در حال انجام باشد، خطا برمی‌گرداند
  Future<bool> startSync({
    required Future<void> Function(int progress, int total, String status) syncOperation,
  }) async {
    if (_isSyncing) {
      LoggingService().warning('Sync already in progress', source: 'SyncProvider');
      return false;
    }

    _isSyncing = true;
    _syncState = SyncState.syncing;
    _progress = 0;
    _total = 0;
    _currentStatus = 'Starting sync...';
    _lastError = null;
    notifyListeners();

    try {
      await syncOperation(_progress, _total, _currentStatus);
      
      _isSyncing = false;
      _syncState = SyncState.success;
      _lastSyncTime = DateTime.now();
      _currentStatus = 'Sync completed successfully';
      LoggingService().info('Sync completed', source: 'SyncProvider', metadata: {
        'progress': _progress,
        'total': _total,
      });
      notifyListeners();
      return true;
    } catch (e) {
      _isSyncing = false;
      _syncState = SyncState.failed;
      _lastError = e.toString();
      _currentStatus = 'Sync failed: $e';
      LoggingService().error('Sync failed: $e', source: 'SyncProvider');
      notifyListeners();
      return false;
    }
  }

  /// بروزرسانی پیشرفت همگام‌سازی
  void updateProgress(int progress, int total, String status) {
    _progress = progress;
    _total = total;
    _currentStatus = status;
    notifyListeners();
  }

  /// ریست کردن وضعیت همگام‌سازی
  void reset() {
    _isSyncing = false;
    _syncState = SyncState.idle;
    _progress = 0;
    _total = 0;
    _currentStatus = '';
    _lastError = null;
    notifyListeners();
  }

  /// پاک کردن خطای قبلی
  void clearError() {
    _lastError = null;
    if (_syncState == SyncState.failed) {
      _syncState = SyncState.idle;
    }
    notifyListeners();
  }
}

/// وضعیت‌های مختلف همگام‌سازی
enum SyncState {
  idle,       // هیچ عملیاتی در حال انجام نیست
  syncing,    // در حال همگام‌سازی
  success,    // همگام‌سازی با موفقیت انجام شد
  failed,     // همگام‌سازی با خطا مواجه شد
}

extension SyncStateExtension on SyncState {
  String get label {
    switch (this) {
      case SyncState.idle:
        return 'Idle';
      case SyncState.syncing:
        return 'Syncing';
      case SyncState.success:
        return 'Success';
      case SyncState.failed:
        return 'Failed';
    }
  }

  String get icon {
    switch (this) {
      case SyncState.idle:
        return '⏸️';
      case SyncState.syncing:
        return '🔄';
      case SyncState.success:
        return '✅';
      case SyncState.failed:
        return '❌';
    }
  }
}
