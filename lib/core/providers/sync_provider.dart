import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/logging_service.dart';

/// وضعیت‌های همگام‌سازی.
enum SyncState {
  /// هیچ عملیاتی در حال انجام نیست.
  idle,

  /// در حال همگام‌سازی.
  syncing,

  /// همگام‌سازی با موفقیت تمام شد.
  success,

  /// همگام‌سازی با خطا مواجه شد.
  failed,

  /// درخواست همگام‌سازی جدید رد شد چون یکی در حال اجراست.
  alreadyInProgress,
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
      case SyncState.alreadyInProgress:
        return 'Already in progress';
    }
  }

  String get labelFa {
    switch (this) {
      case SyncState.idle:
        return 'بی‌کار';
      case SyncState.syncing:
        return 'در حال همگام‌سازی';
      case SyncState.success:
        return 'موفق';
      case SyncState.failed:
        return 'ناموفق';
      case SyncState.alreadyInProgress:
        return 'از قبل در حال اجرا';
    }
  }
}

/// Provider سراسری وضعیت همگام‌سازی.
///
/// این کلاس singleton است تا وضعیت همگام‌سازی «مستقل از صفحه» بماند؛
/// یعنی کاربر می‌تواند بین صفحات جابجا شود، اسکن کند یا به چک‌لیست
/// آیتم اضافه کند، در حالی که همگام‌سازی در پس‌زمینه ادامه دارد.
class SyncProvider extends ChangeNotifier {
  static final SyncProvider _instance = SyncProvider._internal();
  factory SyncProvider() => _instance;
  SyncProvider._internal();

  static const String _prefsLastSyncKey = 'sync_products_last_success';

  bool _isSyncing = false;
  int _progress = 0;
  int _total = 0;
  String _currentStatus = '';
  DateTime? _lastSyncTime;
  SyncState _syncState = SyncState.idle;
  String? _lastError;
  String? _lastSummary;
  int _lastNewCount = 0;
  int _lastUpdatedCount = 0;

  /// آیا بنر وضعیت باید نمایش داده شود (کاربر می‌تواند آن را ببندد).
  bool _bannerVisible = false;

  // ==================== Getters ====================

  bool get isSyncing => _isSyncing;
  int get progress => _progress;
  int get total => _total;
  String get currentStatus => _currentStatus;
  DateTime? get lastSyncTime => _lastSyncTime;
  SyncState get syncState => _syncState;
  String? get lastError => _lastError;
  String? get lastSummary => _lastSummary;
  int get lastNewCount => _lastNewCount;
  int get lastUpdatedCount => _lastUpdatedCount;
  bool get bannerVisible => _bannerVisible;
  double get progressPercent =>
      _total > 0 ? (_progress / _total).clamp(0.0, 1.0) : 0.0;

  /// پیام کوتاه وضعیت برای نمایش در بنر/اسنک‌بار.
  String get statusMessage {
    switch (_syncState) {
      case SyncState.syncing:
        if (_total > 0) {
          return '$_currentStatus ($_progress/$_total)';
        }
        return _currentStatus.isEmpty ? 'Syncing...' : _currentStatus;
      case SyncState.success:
        return _lastSummary ?? 'Sync completed successfully';
      case SyncState.failed:
        return 'Sync failed: ${_lastError ?? 'unknown error'}';
      case SyncState.alreadyInProgress:
        return 'A sync is already running';
      case SyncState.idle:
        return 'Idle';
    }
  }

  // ==================== وضعیت ذخیره‌شده ====================

  /// آخرین زمان موفق همگام‌سازی را از حافظه می‌خواند (بعد از ری‌استارت اپ).
  Future<void> loadPersistedState() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_prefsLastSyncKey);
      if (raw != null) {
        _lastSyncTime = DateTime.tryParse(raw);
        notifyListeners();
      }
    } catch (e) {
      LoggingService().warning('Failed to load persisted sync state: $e',
          source: 'SyncProvider');
    }
  }

  Future<void> _persistLastSyncTime(DateTime time) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsLastSyncKey, time.toIso8601String());
    } catch (e) {
      LoggingService().warning('Failed to persist sync time: $e',
          source: 'SyncProvider');
    }
  }

  // ==================== اجرای همگام‌سازی ====================

  /// شروع عملیات همگام‌سازی در پس‌زمینه.
  ///
  /// خروجی:
  /// - [SyncState.alreadyInProgress] اگر از قبل یکی در حال اجراست
  ///   (عملیات قبلی دست‌نخورده ادامه می‌یابد و کار تکراری انجام نمی‌شود).
  /// - [SyncState.success] یا [SyncState.failed] پس از پایان کار.
  ///
  /// این متد هرگز UI را مسدود نمی‌کند و هیچ دیالوگی باز نمی‌کند.
  Future<SyncState> startSync({
    required Future<void> Function(int progress, int total, String status)
        syncOperation,
  }) async {
    if (_isSyncing) {
      LoggingService().warning(
        'Sync request rejected - a sync is already in progress',
        source: 'SyncProvider',
      );
      _syncState = SyncState.alreadyInProgress;
      notifyListeners();
      return SyncState.alreadyInProgress;
    }

    _isSyncing = true;
    _syncState = SyncState.syncing;
    _progress = 0;
    _total = 0;
    _currentStatus = 'Starting sync...';
    _lastError = null;
    _lastSummary = null;
    _bannerVisible = true;
    LoggingService().info('Sync started', source: 'SyncProvider');
    notifyListeners();

    try {
      await syncOperation(_progress, _total, _currentStatus);

      _isSyncing = false;
      _syncState = SyncState.success;
      _lastSyncTime = DateTime.now();
      _bannerVisible = true;
      _lastSummary ??= 'Sync completed successfully';
      LoggingService().info(
        'Sync completed successfully',
        source: 'SyncProvider',
        metadata: <String, dynamic>{
          'new': _lastNewCount,
          'updated': _lastUpdatedCount,
          'total': _total,
        },
      );
      await _persistLastSyncTime(_lastSyncTime!);
      notifyListeners();
      return SyncState.success;
    } catch (e, stack) {
      _isSyncing = false;
      _syncState = SyncState.failed;
      _lastError = e.toString();
      _bannerVisible = true;
      LoggingService().error(
        'Sync failed',
        source: 'SyncProvider',
        exception: e,
        stackTrace: stack,
      );
      notifyListeners();
      return SyncState.failed;
    }
  }

  /// بروزرسانی پیشرفت از داخل عملیات همگام‌سازی.
  void updateProgress(int progress, int total, String status) {
    _progress = progress;
    _total = total;
    _currentStatus = status;
    notifyListeners();
  }

  /// اعلام خلاصه نتیجه (تعداد جدید/بروزرسانی‌شده).
  void reportSummary({
    required int newCount,
    required int updatedCount,
    String? message,
  }) {
    _lastNewCount = newCount;
    _lastUpdatedCount = updatedCount;
    _lastSummary =
        message ?? 'Sync completed: $newCount new, $updatedCount updated';
    notifyListeners();
  }

  /// اعلام خطا از بیرون (وقتی provider دیگری شکست را تشخیص می‌دهد).
  void reportFailure(Object error, {String? summary}) {
    _isSyncing = false;
    _syncState = SyncState.failed;
    _lastError = error.toString();
    _lastSummary = summary;
    _bannerVisible = true;
    notifyListeners();
  }

  /// ریست کامل وضعیت.
  void reset() {
    _isSyncing = false;
    _syncState = SyncState.idle;
    _progress = 0;
    _total = 0;
    _currentStatus = '';
    _lastError = null;
    _lastSummary = null;
    _bannerVisible = false;
    notifyListeners();
  }

  /// پنهان کردن بنر بدون پاک کردن نتیجه.
  void dismissBanner() {
    _bannerVisible = false;
    notifyListeners();
  }

  /// پاک کردن خطای قبلی.
  void clearError() {
    _lastError = null;
    if (_syncState == SyncState.failed ||
        _syncState == SyncState.alreadyInProgress) {
      _syncState = _isSyncing ? SyncState.syncing : SyncState.idle;
      if (!_isSyncing) _bannerVisible = false;
    }
    notifyListeners();
  }
}