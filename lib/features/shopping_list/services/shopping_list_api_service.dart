import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../../../core/services/logging_service.dart';
import '../../../core/services/network_client.dart';
import '../models/shopping_list_item.dart';

/// سرویس API برای همگام‌سازی چک‌لیست خرید با وردپرس.
///
/// نکات مهم نسبت به نسخه قبلی:
/// 1. تمام درخواست‌ها از [NetworkClient] عبور می‌کنند (timeout + retry + لاگ).
/// 2. `id` و `is_purchased` که REST API وردپرس به صورت **String** برمی‌گرداند
///    به صورت امن تبدیل می‌شوند (قبلا خطای type cast می‌داد و همگام‌سازی را
///    کاملا خراب می‌کرد).
/// 3. برای هر عملیات از `server_id` استفاده می‌شود، نه شناسه محلی.
class ShoppingListApiService {
  static final ShoppingListApiService _instance =
      ShoppingListApiService._internal();
  factory ShoppingListApiService() => _instance;
  ShoppingListApiService._internal();

  final NetworkClient _client = NetworkClient();
  final LoggingService _log = LoggingService();

  String get baseUrl => ApiConfig.wordpressBaseUrl;
  String get itemsEndpoint => ApiConfig.shoppingItemsEndpoint;
  String get usersEndpoint => ApiConfig.shoppingUsersEndpoint;
  String get syncEndpoint => ApiConfig.shoppingSyncEndpoint;

  Map<String, String> get _jsonHeaders => const <String, String>{
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'application/json',
      };

  // ==================== آیتم‌ها ====================

  /// دریافت تمام آیتم‌ها از سرور.
  Future<List<ShoppingListItem>> fetchAllItems() async {
    final Uri uri = Uri.parse(itemsEndpoint);
    final http.Response response = await _client.get(
      uri,
      headers: const <String, String>{'Accept': 'application/json'},
    );

    if (response.statusCode != 200) {
      throw NetworkFailure(
        kind: NetworkFailureKind.http,
        url: itemsEndpoint,
        technical: 'GET items failed: HTTP ${response.statusCode}',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }

    final dynamic json = _client.decodeJson(response, itemsEndpoint);
    return parseItems(json);
  }

  /// تبدیل پاسخ سرور به لیست آیتم‌ها.
  ///
  /// یک آیتم خراب کل همگام‌سازی را متوقف نمی‌کند؛ فقط لاگ می‌شود.
  List<ShoppingListItem> parseItems(dynamic json) {
    if (json is! List) {
      throw NetworkFailure(
        kind: NetworkFailureKind.badResponse,
        url: itemsEndpoint,
        technical: 'Expected a JSON array but received ${json.runtimeType}',
      );
    }

    final List<ShoppingListItem> items = <ShoppingListItem>[];
    for (final dynamic entry in json) {
      if (entry is! Map) continue;
      try {
        items.add(
          ShoppingListItem.fromServerJson(Map<String, dynamic>.from(entry)),
        );
      } catch (e) {
        _log.warning(
          'Skipped malformed server item: $e',
          source: 'ShoppingListApi',
          metadata: <String, dynamic>{'item': entry.toString()},
        );
      }
    }
    return items;
  }

  /// ساخت آیتم جدید روی سرور و برگرداندن آیتم ساخته‌شده (همراه `serverId`).
  Future<ShoppingListItem?> createItem(ShoppingListItem item) async {
    final Uri uri = Uri.parse(itemsEndpoint);
    final http.Response response = await _client.postJson(
      uri,
      item.toServerJson(),
      headers: _jsonHeaders,
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw NetworkFailure(
        kind: NetworkFailureKind.http,
        url: itemsEndpoint,
        technical: 'POST item failed: HTTP ${response.statusCode}',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }

    final dynamic json = _client.decodeJson(response, itemsEndpoint);
    if (json is Map) {
      final ShoppingListItem created =
          ShoppingListItem.fromServerJson(Map<String, dynamic>.from(json));
      _log.debug('Server created item id=${created.serverId}',
          source: 'ShoppingListApi');
      return created;
    }
    return null;
  }

  /// بروزرسانی وضعیت خرید روی سرور (با `server_id`).
  Future<bool> updateItemStatus(
    int serverId,
    bool isPurchased, {
    DateTime? purchasedAt,
  }) async {
    final Uri uri = Uri.parse(ApiConfig.shoppingItemEndpoint(serverId));
    final http.Response response = await _client.putJson(
      uri,
      <String, dynamic>{
        'is_purchased': isPurchased ? 1 : 0,
        if (purchasedAt != null) 'purchased_at': purchasedAt.toIso8601String(),
      },
      headers: _jsonHeaders,
    );
    return response.statusCode == 200;
  }

  /// بروزرسانی تگ‌ها/نام/بارکد روی سرور.
  Future<bool> updateItemDetails(ShoppingListItem item) async {
    if (item.serverId == null) return false;
    final Uri uri = Uri.parse(ApiConfig.shoppingItemEndpoint(item.serverId!));
    final http.Response response = await _client.putJson(
      uri,
      <String, dynamic>{
        'name': item.name,
        'barcode': item.barcode,
        'tags': item.toServerJson()['tags'],
        'tag': item.tagIds.isEmpty ? 'other' : item.tagIds.first,
      },
      headers: _jsonHeaders,
    );
    return response.statusCode == 200;
  }

  /// حذف آیتم از سرور (با `server_id`).
  Future<bool> deleteItem(int serverId) async {
    final Uri uri = Uri.parse(ApiConfig.shoppingItemEndpoint(serverId));
    final http.Response response =
        await _client.delete(uri, headers: _jsonHeaders);
    return response.statusCode == 200;
  }

  // ==================== کاربران ====================

  Future<Map<String, dynamic>?> registerUser(
    String username,
    String phoneNumber,
  ) async {
    final Uri uri = Uri.parse(usersEndpoint);
    final http.Response response = await _client.postJson(
      uri,
      <String, dynamic>{
        'username': username,
        'phone_number': phoneNumber,
      },
      headers: _jsonHeaders,
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw NetworkFailure(
        kind: NetworkFailureKind.http,
        url: usersEndpoint,
        technical: 'POST user failed: HTTP ${response.statusCode}',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }

    final dynamic json = _client.decodeJson(response, usersEndpoint);
    return json is Map ? Map<String, dynamic>.from(json) : null;
  }

  Future<Map<String, dynamic>?> getUserByUsername(String username) async {
    final Uri uri =
        Uri.parse(ApiConfig.shoppingUserByUsernameEndpoint(username));
    final http.Response response = await _client.get(
      uri,
      headers: const <String, String>{'Accept': 'application/json'},
    );
    if (response.statusCode != 200) return null;
    final dynamic json = _client.decodeJson(response, uri.toString());
    if (json is List && json.isNotEmpty && json.first is Map) {
      return Map<String, dynamic>.from(json.first as Map);
    }
    return null;
  }

  // ==================== سلامت اتصال ====================

  /// بررسی سریع سلامت اتصال به سرور (بدون تلاش مجدد).
  Future<bool> checkConnection() async {
    try {
      final http.Response response = await _client.send(
        'GET',
        Uri.parse(itemsEndpoint),
        retry: false,
        timeout: ApiConfig.probeTimeout,
      );
      final bool ok = response.statusCode == 200;
      _log.setConnectionStatus(
        ok ? ConnectionStatus.online : ConnectionStatus.serverError,
        detail: 'HTTP ${response.statusCode}',
        source: 'ShoppingListApi',
      );
      return ok;
    } on NetworkFailure catch (e) {
      _log.setConnectionStatus(
        ConnectionStatus.offline,
        detail: e.kind.name,
        source: 'ShoppingListApi',
      );
      return false;
    }
  }
}