import 'package:flutter/foundation.dart';
import '../models/shopping_list_item.dart';
import '../services/shopping_list_database_service.dart';
import '../services/shopping_list_api_service.dart';

/// Provider برای مدیریت وضعیت چک‌لیست خرید
class ShoppingListProvider extends ChangeNotifier {
  final ShoppingListDatabaseService _dbService = ShoppingListDatabaseService();
  final ShoppingListApiService _apiService = ShoppingListApiService();

  List<ShoppingListItem> _items = [];
  List<ShoppingListItem> _filteredItems = [];
  String? _username;
  bool _isLoading = false;
  bool _isSyncing = false;
  String? _error;
  String _selectedLocale = 'fa';
  
  ShoppingListFilter _currentFilter = ShoppingListFilter.all;
  String? _selectedTag;

  // Getters
  List<ShoppingListItem> get items => _items;
  List<ShoppingListItem> get filteredItems => _filteredItems;
  String? get username => _username;
  bool get isLoading => _isLoading;
  bool get isSyncing => _isSyncing;
  String? get error => _error;
  String get selectedLocale => _selectedLocale;
  ShoppingListFilter get currentFilter => _currentFilter;
  String? get selectedTag => _selectedTag;
  bool get hasUser => _username != null;

  /// مقداردهی اولیه و بارگذاری داده‌ها
  Future<void> initialize(String locale) async {
    _selectedLocale = locale;
    await _loadUsername();
    await loadItems();
  }

  /// تنظیم لوکالیشن
  void setLocale(String locale) {
    _selectedLocale = locale;
    notifyListeners();
  }

  /// بارگذاری نام کاربری از دیتابیس محلی
  Future<void> _loadUsername() async {
    try {
      _username = await _dbService.getUsername();
      notifyListeners();
    } catch (e) {
      _error = 'خطا در بارگذاری اطلاعات کاربر';
      notifyListeners();
    }
  }

  /// ذخیره اطلاعات کاربر محلی
  Future<bool> saveUser(String username, String phoneNumber) async {
    try {
      await _dbService.saveLocalUser(username, phoneNumber);
      
      // تلاش برای ثبت در سرور
      try {
        await _apiService.registerUser(username, phoneNumber);
      } catch (e) {
        // اگر سرور در دسترس نبود، فقط locally ذخیره شود
        print('Server registration failed, saved locally only: $e');
      }
      
      _username = username;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'خطا در ذخیره اطلاعات کاربر';
      notifyListeners();
      return false;
    }
  }

  /// بارگذاری آیتم‌ها از دیتابیس محلی
  Future<void> loadItems() async {
    _isLoading = true;
    notifyListeners();

    try {
      _items = await _dbService.getAllItems();
      _applyFilters();
      _error = null;
    } catch (e) {
      _error = 'خطا در بارگذاری آیتم‌ها';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// افزودن آیتم جدید
  Future<bool> addItem(ShoppingListItem item) async {
    try {
      final itemId = await _dbService.insertItem(item);
      _items.insert(0, item.copyWith(id: itemId));
      _applyFilters();
      
      // ارسال به سرور در پس‌زمینه (بدون مسدود کردن UI)
      _syncItemToServerAsync(item);
      
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'خطا در افزودن آیتم';
      notifyListeners();
      return false;
    }
  }

  /// بروزرسانی وضعیت خرید
  Future<void> togglePurchaseStatus(int id, bool isPurchased) async {
    try {
      await _dbService.updateItemPurchaseStatus(id, isPurchased);
      
      final index = _items.indexWhere((item) => item.id == id);
      if (index != -1) {
        _items[index] = _items[index].copyWith(
          isPurchased: isPurchased,
          purchasedAt: isPurchased ? DateTime.now() : null,
        );
        _applyFilters();
      }
      
      // بروزرسانی در سرور
      final item = _items[index];
      _apiService.updateItemStatus(id, isPurchased, item.purchasedAt?.toIso8601String());
      
      notifyListeners();
    } catch (e) {
      _error = 'خطا در بروزرسانی وضعیت';
      notifyListeners();
    }
  }

  /// حذف آیتم
  Future<void> deleteItem(int id) async {
    try {
      await _dbService.deleteItem(id);
      _items.removeWhere((item) => item.id == id);
      _applyFilters();
      
      // حذف از سرور
      _apiService.deleteItem(id);
      
      notifyListeners();
    } catch (e) {
      _error = 'خطا در حذف آیتم';
      notifyListeners();
    }
  }

  /// اعمال فیلترها
  void setFilter(ShoppingListFilter filter) {
    _currentFilter = filter;
    _applyFilters();
    notifyListeners();
  }

  /// فیلتر بر اساس تگ
  void setTagFilter(String? tag) {
    _selectedTag = tag;
    _applyFilters();
    notifyListeners();
  }

  void _applyFilters() {
    _filteredItems = _items.where((item) {
      // فیلتر وضعیت خرید
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

      // فیلتر تگ - پشتیبانی از چندین تگ
      bool matchesTag = _selectedTag == null || item.tagIds.contains(_selectedTag);

      return matchesFilter && matchesTag;
    }).toList();
  }

  /// همگام‌سازی با سرور
  Future<void> syncWithServer() async {
    if (_isSyncing) return;

    _isSyncing = true;
    _error = null;
    notifyListeners();

    try {
      // دریافت آیتم‌های تغییر کرده از آخرین همگام‌سازی
      // (در یک پیاده‌سازی کامل، باید lastSyncTime را ذخیره کرد)
      final localChanges = await _dbService.getItemsForSync(null);
      
      // همگام‌سازی با سرور
      final result = await _apiService.syncWithServer(localChanges, null);
      
      // بروزرسانی آیتم‌های محلی با داده‌های سرور
      if (result.containsKey('server_items')) {
        final serverItemsData = result['server_items'] as List<dynamic>;
        final serverItems = serverItemsData
            .whereType<Map<String, dynamic>>()
            .map((itemMap) => ShoppingListItem.fromMap(itemMap))
            .toList();
        await _dbService.syncItemsFromServer(serverItems);
        await loadItems();
      }
    } catch (e) {
      _error = 'خطا در همگام‌سازی با سرور';
      print('Sync error: $e');
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// همگام‌سازی خودکار هنگام اتصال به اینترنت
  Future<void> autoSync() async {
    if (await _apiService.checkConnection()) {
      await syncWithServer();
    }
  }

  /// پاک کردن همه آیتم‌ها
  Future<void> clearAllItems() async {
    try {
      await _dbService.clearAllItems();
      _items.clear();
      _filteredItems.clear();
      notifyListeners();
    } catch (e) {
      _error = 'خطا در پاک کردن آیتم‌ها';
      notifyListeners();
    }
  }

  /// دریافت تگ بر اساس ID
  ShoppingListTag? getTagById(String id) {
    return DefaultTags.getById(id);
  }

  /// دریافت رنگ تگ
  String getTagColor(String tagId) {
    final tag = DefaultTags.getById(tagId);
    return tag?.colorHex ?? '#BDBDBD';
  }

  /// همگام‌سازی آیتم با سرور به صورت Async (بدون مسدود کردن UI)
  Future<void> _syncItemToServerAsync(ShoppingListItem item) async {
    try {
      await _apiService.createItem(item);
    } catch (e) {
      print('Background sync failed: $e');
      // خطا در پس‌زمینه رخ داده و کاربر را آزار نمی‌دهد
    }
  }
}
