import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/providers/sync_provider.dart';
import '../../../core/services/logging_service.dart';
import '../../../core/services/network_client.dart';
import '../models/shopping_list_item.dart';
import '../services/shopping_list_api_service.dart';
import '../services/shopping_list_database_service.dart';

/// Provider چک‌لیست خرید.
///
/// مسئولیت‌ها:
/// - مدیریت آیتم‌ها، فیلترها و تگ‌ها (شامل تگ‌های سفارشی دائمی).
/// - همگام‌سازی **غیرمسدودکننده** با سرور با استفاده از [SyncProvider]
///   به عنوان منبع واحد وضعیت همگام‌سازی.
/// - نگاشت درست آیتم‌های محلی و سرور توسط `serverId`.
class ShoppingListProvider extends ChangeNotifier {
  ShoppingListProvider() {
    SyncProvider().addListener(_onSyncStateChanged);
  }

  final ShoppingListDatabaseService _dbService = ShoppingListDatabaseService();
  final ShoppingListApiService _apiService = ShoppingListApiService();
  final LoggingService _log = LoggingService();

  List<ShoppingListItem> _items = <ShoppingListItem>[];
  List<ShoppingListItem> _filteredItems = <ShoppingListItem>[];
  List<ShoppingListTag> _customTags = <ShoppingListTag>[];
  String? _username;
  bool _isLoading = false;
  bool _errorIsNetwork = false;
  String? _error;
  String _selectedLocale = 'fa';
  DateTime? _lastSyncTime;

  ShoppingListFilter _currentFilter = ShoppingListFilter.all;
  String? _selectedTag;
  bool _disposed = false;

  // ==================== Getters ====================

  List<ShoppingListItem> get items => _items;
  List<ShoppingListItem> get filteredItems => _filteredItems;
  String? get username => _username;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get errorIsNetwork => _errorIsNetwork;
  String get selectedLocale => _selectedLocale;
  ShoppingListFilter get currentFilter => _currentFilter;
  String? get selectedTag => _selectedTag;
  DateTime? get lastSyncTime => _lastSyncTime;
  bool get hasUser => _username != null;

  /// وضعیت همگام‌سازی از منبع واحد [SyncProvider] خوانده می‌شود.
  bool get isSyncing => SyncProvider().isSyncing;
  SyncState get syncState => SyncProvider().syncState;

  /// تگ‌های سفارشی ساخته‌شده توسط کاربر.
  List<ShoppingListTag> get customTags =>
      List<ShoppingListTag>.unmodifiable(_customTags);

  /// همه تگ‌ها = پیش‌فرض + سفارشی (بدون محدودیت تعداد).
  List<ShoppingListTag> get allTags =>
      DefaultTags.getAllTags(customTags: _customTags);

  ShoppingListTag? getTagById(String id) =>
      DefaultTags.getById(id, customTags: _customTags);

  String getTagColor(String tagId) =>
      getTagById(tagId)?.colorHex ?? '#BDBDBD';

  String getTagName(String tagId, String locale) =>
      getTagById(tagId)?.displayName(locale) ?? tagId;

  void _onSyncStateChanged() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    SyncProvider().removeListener(_onSyncStateChanged);
    super.dispose();
  }

  // ==================== مقداردهی اولیه ====================

  Future<void> initialize(String locale) async {
    _selectedLocale = locale;
    await loadCustomTags();
    await _loadUsername();
    await loadItems();
    // آخرین زمان همگام‌سازی از حافظه دائمی.
    await SyncProvider().loadPersistedState();
    _lastSyncTime = SyncProvider().lastSyncTime;
  }

  void setLocale(String locale) {
    _selectedLocale = locale;
    notifyListeners();
  }

  /// بارگذاری تگ‌های سفارشی ذخیره‌شده (بعد از ری‌استارت اپ باقی می‌مانند).
  Future<void> loadCustomTags() async {
    try {
      _customTags = await CustomTagService.loadCustomTags();
      _log.info('Loaded ${_customTags.length} custom tags',
          source: 'ShoppingListProvider');
      notifyListeners();
    } catch (e) {
      _log.warning('Failed to load custom tags: $e',
          source: 'ShoppingListProvider');
    }
  }

  // ==================== تگ‌های سفارشی ====================

  /// ساخت تگ سفارشی جدید (با اعتبارسنجی و مدیریت نام تکراری).
  Future<TagCreateResult> createTag({
    required String nameFa,
    required String nameEn,
    required String colorHex,
  }) async {
    final TagCreateResult result = await CustomTagService.createCustomTag(
      nameFa: nameFa,
      nameEn: nameEn,
      colorHex: colorHex,
      existingCustomTags: _customTags,
    );

    switch (result.status) {
      case TagCreateStatus.created:
        _customTags = await CustomTagService.loadCustomTags();
        _log.info(
          'Custom tag created: ${result.tag?.id} (${result.tag?.nameEn})',
          source: 'ShoppingListProvider',
        );
        notifyListeners();
        break;
      case TagCreateStatus.duplicate:
        _log.info('Duplicate tag name rejected: $nameFa',
            source: 'ShoppingListProvider');
        break;
      case TagCreateStatus.invalidEmptyName:
      case TagCreateStatus.storageError:
        _log.warning('Custom tag creation failed: ${result.message}',
            source: 'ShoppingListProvider');
        break;
    }
    return result;
  }

  /// حذف تگ سفارشی (تگ‌های پیش‌فرض قابل حذف نیستند).
  Future<bool> deleteTag(String tagId) async {
    final ShoppingListTag? tag = getTagById(tagId);
    if (tag == null || !tag.isCustom) return false;

    final bool ok = await CustomTagService.deleteCustomTag(tagId);
    if (!ok) return false;

    _customTags = await CustomTagService.loadCustomTags();

    // حذف تگ از همه آیتم‌های محلی تا ارجاع بی‌اعتبار باقی نماند.
    for (final ShoppingListItem item in List<ShoppingListItem>.from(_items)) {
      if (item.id == null || !item.tagIds.contains(tagId)) continue;
      final List<String> updated = item.tagIds
          .where((String id) => id != tagId)
          .toList();
      await _dbService.updateItemTags(item.id!, updated);
    }

    if (_selectedTag == tagId) _selectedTag = null;
    await loadItems();
    _log.info('Custom tag deleted: $tagId', source: 'ShoppingListProvider');
    return true;
  }

  // ==================== کاربر محلی ====================

  Future<void> _loadUsername() async {
    try {
      _username = await _dbService.getUsername();
      notifyListeners();
    } catch (e) {
      _setError('خطا در بارگذاری اطلاعات کاربر', isNetwork: false);
    }
  }

  Future<bool> saveUser(String username, String phoneNumber) async {
    try {
      await _dbService.saveLocalUser(username, phoneNumber);

      // ثبت در سرور (اگر ممکن نبود، فقط محلی ذخیره می‌شود).
      try {
        await _apiService.registerUser(username, phoneNumber);
        _log.info('User registered on server: $username',
            source: 'ShoppingListProvider');
      } on NetworkFailure catch (e) {
        _log.warning(
          'Server registration failed, saved locally only: ${e.message}',
          source: 'ShoppingListProvider',
          metadata: <String, dynamic>{'kind': e.kind.name},
        );
      }

      _username = username;
      notifyListeners();
      return true;
    } catch (e) {
      _setError('خطا در ذخیره اطلاعات کاربر', isNetwork: false);
      return false;
    }
  }

  // ==================== بارگذاری آیتم‌ها ====================

  Future<void> loadItems() async {
    _isLoading = true;
    _notify();
    try {
      _items = await _dbService.getAllItems();
      _applyFilters();
      _error = null;
      _errorIsNetwork = false;
    } catch (e, stack) {
      _log.error('Failed to load items', source: 'ShoppingListProvider',
          exception: e, stackTrace: stack);
      _setError('خطا در بارگذاری آیتم‌ها', isNetwork: false);
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  void _setError(String message, {required bool isNetwork}) {
    _error = message;
    _errorIsNetwork = isNetwork;
    _notify();
  }

  // ==================== عملیات روی آیتم‌ها ====================

  /// افزودن آیتم جدید (فورا محلی ذخیره می‌شود؛ ارسال به سرور در پس‌زمینه).
  Future<bool> addItem(ShoppingListItem item) async {
    try {
      final int newId = await _dbService.insertItem(item);
      _items.insert(0, item.copyWith(id: newId));
      _applyFilters();
      _error = null;
      _notify();

      // ارسال به سرور بدون مسدود کردن UI و بدون بستن هیچ دیالوگی.
      unawaited(_pushSingleItem(item.copyWith(id: newId)));

      return true;
    } catch (e, stack) {
      _log.error('Failed to add item', source: 'ShoppingListProvider',
          exception: e, stackTrace: stack);
      _setError('خطا در افزودن آیتم', isNetwork: false);
      return false;
    }
  }

  /// بروزرسانی وضعیت خرید.
  Future<void> togglePurchaseStatus(int id, bool isPurchased) async {
    try {
      await _dbService.updateItemPurchaseStatus(id, isPurchased);

      final int index = _items.indexWhere((ShoppingListItem i) => i.id == id);
      if (index == -1) {
        await loadItems();
        return;
      }

      final ShoppingListItem updated = _items[index].copyWith(
        isPurchased: isPurchased,
        purchasedAt: isPurchased ? DateTime.now() : null,
        clearPurchasedAt: !isPurchased,
        pendingSync: true,
      );
      _items[index] = updated;
      _applyFilters();
      _notify();

      unawaited(_pushSingleItem(updated));
    } catch (e, stack) {
      _log.error('Failed to update purchase status',
          source: 'ShoppingListProvider', exception: e, stackTrace: stack);
      _setError('خطا در بروزرسانی وضعیت', isNetwork: false);
    }
  }

  /// تنظیم کامل تگ‌های یک آیتم (پشتیبانی از چندین تگ، بدون محدودیت).
  Future<bool> updateItemTags(int itemId, List<String> tagIds) async {
    try {
      final List<String> normalized = normalizeTagIds(tagIds);
      await _dbService.updateItemTags(itemId, normalized);

      final int index =
          _items.indexWhere((ShoppingListItem i) => i.id == itemId);
      if (index != -1) {
        _items[index] = _items[index].copyWith(
          tagIds: normalized,
          pendingSync: true,
        );
        _applyFilters();
        _notify();
        unawaited(_pushSingleItem(_items[index]));
      }
      return true;
    } catch (e, stack) {
      _log.error('Failed to update item tags',
          source: 'ShoppingListProvider', exception: e, stackTrace: stack);
      return false;
    }
  }

  /// افزودن/حذف یک تگ از آیتم (برای رابط کاربری چند‌تگی).
  Future<bool> toggleTagOnItem(int itemId, String tagId) async {
    final int index =
        _items.indexWhere((ShoppingListItem i) => i.id == itemId);
    if (index == -1) return false;

    final List<String> current = List<String>.from(_items[index].tagIds);
    if (current.contains(tagId)) {
      current.remove(tagId);
    } else {
      current.add(tagId);
    }
    return updateItemTags(itemId, current);
  }

  /// حذف آیتم.
  Future<void> deleteItem(int id) async {
    try {
      final int index =
          _items.indexWhere((ShoppingListItem item) => item.id == id);
      final ShoppingListItem? removed = index == -1 ? null : _items[index];

      await _dbService.deleteItem(id);
      _items.removeWhere((ShoppingListItem item) => item.id == id);
      _applyFilters();
      _notify();

      if (removed?.serverId != null) {
        try {
          await _apiService.deleteItem(removed!.serverId!);
        } on NetworkFailure catch (e) {
          _log.warning(
            'Failed to delete item on server (will stay only locally): '
            '${e.message}',
            source: 'ShoppingListProvider',
          );
        }
      }
    } catch (e, stack) {
      _log.error('Failed to delete item', source: 'ShoppingListProvider',
          exception: e, stackTrace: stack);
      _setError('خطا در حذف آیتم', isNetwork: false);
    }
  }

  /// پاک کردن همه آیتمها.
  Future<void> clearAllItems() async {
    try {
      await _dbService.clearAllItems();
      _items.clear();
      _filteredItems.clear();
      _notify();
    } catch (e) {
      _setError('خطا در پاک کردن آیتم‌ها', isNetwork: false);
    }
  }

  // ==================== فیلترها ====================

  void setFilter(ShoppingListFilter filter) {
    _currentFilter = filter;
    _applyFilters();
    _notify();
  }

  void setTagFilter(String? tag) {
    _selectedTag = tag;
    _applyFilters();
    _notify();
  }

  void _applyFilters() {
    _filteredItems = _items.where((ShoppingListItem item) {
      bool matchesFilter = true;
      switch (_currentFilter) {
        case ShoppingListFilter.purchased:
          matchesFilter = item.isPurchased;
          break;
        case ShoppingListFilter.pending:
          matchesFilter = !item.isPurchased;
          break;
        case ShoppingListFilter.all:
          matchesFilter = true;
          break;
      }

      // فیلتر تگ با پشتیبانی از چندین تگ روی هر آیتم.
      final bool matchesTag =
          _selectedTag == null || item.tagIds.contains(_selectedTag);

      return matchesFilter && matchesTag;
    }).toList();
  }

  // ==================== همگام‌سازی ====================

  /// همگام‌سازی کامل با سرور - **غیرمسدودکننده**.
  ///
  /// وضعیت از [SyncProvider] خوانده می‌شود؛ بنابراین:
  /// - درخواست تکراری هنگام اجرا رد می‌شود ([SyncState.alreadyInProgress]).
  /// - کاربر می‌تواند همزمان اسکن کند، آیتم اضافه کند یا صفحه عوض کند.
  Future<SyncState> syncWithServer() {
    return SyncProvider().startSync(syncOperation: _performSync);
  }

  /// همگام‌سازی خودکار (فقط اگر سرور در دسترس باشد).
  Future<void> autoSync() async {
    if (await _apiService.checkConnection()) {
      await syncWithServer();
    }
  }

  /// بدنه واقعی همگام‌سازی: ابتدا ارسال آیتم‌های معلق، سپس دریافت آیتم‌ها.
  Future<void> _performSync(
    int progress,
    int total,
    String status,
  ) async {
    final SyncProvider sync = SyncProvider();

    // ---------- مرحله ۱: ارسال تغییرات محلی ----------
    final List<ShoppingListItem> pending =
        await _dbService.getPendingItemsForSync();
    final int totalSteps = pending.length + 1;

    sync.updateProgress(
      0,
      totalSteps,
      'Uploading ${pending.length} pending item(s)...',
    );
    _log.info('Sync: ${pending.length} pending item(s) to upload',
        source: 'ShoppingListProvider');

    int uploaded = 0;
    int failedUploads = 0;

    for (int i = 0; i < pending.length; i++) {
      final ShoppingListItem item = pending[i];
      try {
        if (item.serverId == null) {
          final ShoppingListItem? created = await _apiService.createItem(item);
          if (created?.serverId != null && item.id != null) {
            await _dbService.markSynced(item.id!, created!.serverId!);
          } else if (item.id != null) {
            // سرور شناسه برنگرداند؛ آیتم را «همگام‌شده» علامت نمی‌زنیم تا
            // در همگام‌سازی بعدی دوباره تلاش شود.
            failedUploads++;
          }
        } else {
          await _apiService.updateItemStatus(
            item.serverId!,
            item.isPurchased,
            purchasedAt: item.purchasedAt,
          );
          await _apiService.updateItemDetails(item);
          if (item.id != null) {
            await _dbService.markSynced(item.id!, item.serverId!);
          }
        }
        uploaded++;
      } on NetworkFailure catch (e) {
        failedUploads++;
        _log.warning(
          'Sync upload failed for item "${item.name}": ${e.message}',
          source: 'ShoppingListProvider',
          metadata: <String, dynamic>{
            'kind': e.kind.name,
            'detail': e.technical,
          },
        );
      }

      sync.updateProgress(
        i + 1,
        totalSteps,
        'Uploading ${i + 1}/${pending.length}...',
      );
    }

    // ---------- مرحله ۲: دریافت آیتم‌های سرور ----------
    sync.updateProgress(pending.length, totalSteps,
        'Downloading items from server...');
    final List<ShoppingListItem> serverItems =
        await _apiService.fetchAllItems();
    for (final ShoppingListItem item in serverItems) {
      await _dbService.upsertItemFromServer(item);
    }

    // ---------- مرحله ۳: بازخوانی از دیتابیس ----------
    _lastSyncTime = DateTime.now();
    await loadItems();

    sync.reportSummary(
      newCount: serverItems.length,
      updatedCount: uploaded,
      message: failedUploads == 0
          ? 'Synced: ${serverItems.length} from server, $uploaded uploaded'
          : 'Synced with $failedUploads upload failure(s): '
              '${serverItems.length} from server, $uploaded uploaded',
    );
    _log.info(
      'Sync finished: server=${serverItems.length}, uploaded=$uploaded, '
      'failed=$failedUploads',
      source: 'ShoppingListProvider',
    );
  }

  /// ارسال یک آیتم به سرور در پس‌زمینه (بدون مسدود کردن UI).
  ///
  /// اگر شبکه در دسترس نباشد، خطا فقط لاگ می‌شود و آیتم با
  /// `pending_sync = 1` باقی می‌ماند تا در همگام‌سازی بعدی فرستاده شود.
  Future<void> _pushSingleItem(ShoppingListItem item) async {
    if (item.id == null) return;
    try {
      if (item.serverId == null) {
        final ShoppingListItem? created = await _apiService.createItem(item);
        if (created?.serverId != null) {
          await _dbService.markSynced(item.id!, created!.serverId!);
          _log.debug(
            'Item "${item.name}" pushed to server (id=${created.serverId})',
            source: 'ShoppingListProvider',
          );
        }
      } else {
        await _apiService.updateItemStatus(
          item.serverId!,
          item.isPurchased,
          purchasedAt: item.purchasedAt,
        );
        await _apiService.updateItemDetails(item);
        await _dbService.markSynced(item.id!, item.serverId!);
      }
    } on NetworkFailure catch (e) {
      _log.warning(
        'Background push failed for "${item.name}" (kept pending): '
        '${e.message}',
        source: 'ShoppingListProvider',
        metadata: <String, dynamic>{'kind': e.kind.name},
      );
    }
  }
}