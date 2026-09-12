import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/shopping_list_item.dart';

/// سرویس API برای همگام‌سازی چک‌لیست خرید با وردپرس
/// 
/// این سرویس با REST API سفارشی وردپرس ارتباط برقرار می‌کند.
/// جداول وردپرس باید با پیشوند bl_ (مخفف Barcode List) ایجاد شوند:
/// - bl_shopping_items
/// - bl_users
class ShoppingListApiService {
  static final ShoppingListApiService _instance = ShoppingListApiService._internal();
  factory ShoppingListApiService() => _instance;
  ShoppingListApiService._internal();

  // آدرس سایت وردپرسی
  final String baseUrl = 'https://ebimarket.ir';
  
  // اندپوینت‌های API سفارشی
  String get itemsEndpoint => '$baseUrl/wp-json/bl/v1/items';
  String get usersEndpoint => '$baseUrl/wp-json/bl/v1/users';
  String get syncEndpoint => '$baseUrl/wp-json/bl/v1/sync';

  /// دریافت تمام آیتم‌ها از سرور
  Future<List<ShoppingListItem>> fetchAllItems() async {
    try {
      final response = await http.get(Uri.parse(itemsEndpoint));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((item) => _parseServerItem(item)).toList();
      } else {
        throw Exception('Failed to load items: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching items: $e');
      rethrow;
    }
  }

  /// ارسال آیتم جدید به سرور
  Future<Map<String, dynamic>?> createItem(ShoppingListItem item) async {
    try {
      final response = await http.post(
        Uri.parse(itemsEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'name': item.name,
          'barcode': item.barcode,
          'tag': item.tag,
          'added_by': item.addedBy,
          'created_at': item.createdAt.toIso8601String(),
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to create item: ${response.statusCode}');
      }
    } catch (e) {
      print('Error creating item: $e');
      rethrow;
    }
  }

  /// بروزرسانی وضعیت خرید آیتم
  Future<bool> updateItemStatus(int itemId, bool isPurchased, String? purchasedAt) async {
    try {
      final response = await http.put(
        Uri.parse('$itemsEndpoint/$itemId'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'is_purchased': isPurchased ? 1 : 0,
          if (purchasedAt != null) 'purchased_at': purchasedAt,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Error updating item status: $e');
      return false;
    }
  }

  /// حذف آیتم از سرور
  Future<bool> deleteItem(int itemId) async {
    try {
      final response = await http.delete(
        Uri.parse('$itemsEndpoint/$itemId'),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Error deleting item: $e');
      return false;
    }
  }

  /// ثبت کاربر جدید در سرور
  Future<Map<String, dynamic>?> registerUser(String username, String phoneNumber) async {
    try {
      final response = await http.post(
        Uri.parse(usersEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'phone_number': phoneNumber,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to register user: ${response.statusCode}');
      }
    } catch (e) {
      print('Error registering user: $e');
      rethrow;
    }
  }

  /// دریافت اطلاعات کاربر
  Future<Map<String, dynamic>?> getUserByUsername(String username) async {
    try {
      final response = await http.get(
        Uri.parse('$usersEndpoint?username=$username'),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.isNotEmpty ? data.first as Map<String, dynamic> : null;
      } else {
        return null;
      }
    } catch (e) {
      print('Error getting user: $e');
      return null;
    }
  }

  /// همگام‌سازی کامل با سرور
  /// این متد آیتم‌های محلی تغییر کرده را به سرور می‌فرستد
  /// و آیتم‌های جدید سرور را دریافت می‌کند
  Future<Map<String, List<ShoppingListItem>>> syncWithServer(
    List<ShoppingListItem> localChanges,
    DateTime? lastSyncTime,
  ) async {
    try {
      // ارسال تغییرات محلی به سرور
      for (var item in localChanges) {
        if (item.id == null) {
          // آیتم جدید
          await createItem(item);
        } else {
          // بروزرسانی وضعیت
          await updateItemStatus(
            item.id!,
            item.isPurchased,
            item.purchasedAt?.toIso8601String(),
          );
        }
      }

      // دریافت آیتم‌های جدید از سرور
      final serverItems = await fetchAllItems();

      return {
        'server_items': serverItems,
      };
    } catch (e) {
      print('Error syncing with server: $e');
      rethrow;
    }
  }

  /// بررسی سلامت اتصال به API
  Future<bool> checkConnection() async {
    try {
      final response = await http.get(Uri.parse(itemsEndpoint));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  ShoppingListItem _parseServerItem(Map<String, dynamic> data) {
    return ShoppingListItem(
      id: data['id'] as int?,
      name: data['name'] ?? '',
      barcode: data['barcode'] ?? '',
      tag: data['tag'] ?? 'other',
      isPurchased: (data['is_purchased'] ?? 0) == 1,
      addedBy: data['added_by'] ?? '',
      createdAt: data['created_at'] != null 
          ? DateTime.parse(data['created_at']) 
          : DateTime.now(),
      purchasedAt: data['purchased_at'] != null 
          ? DateTime.parse(data['purchased_at']) 
          : null,
    );
  }
}
