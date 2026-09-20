import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../../core/services/logging_service.dart';
import '../models/shopping_list_item.dart';

/// سرویس دیتابیس محلی برای چک‌لیست خرید.
///
/// نسخه ۳ اسکیمای دیتابیس شامل:
/// - `server_id`: شناسه همان آیتم روی سرور (برای جلوگیری از بروزرسانی
///   ردیف اشتباه یا ساخت ردیف تکراری).
/// - `tags`: آرایه JSON از تگ‌ها (چند‌به‌چند، بدون محدودیت تعداد).
/// - `pending_sync`: آیا این آیتم باید به سرور فرستاده شود.
class ShoppingListDatabaseService {
  static final ShoppingListDatabaseService _instance =
      ShoppingListDatabaseService._internal();
  factory ShoppingListDatabaseService() => _instance;
  ShoppingListDatabaseService._internal();

  static const int schemaVersion = 3;
  static const String itemsTable = 'shopping_items';
  static const String usersTable = 'local_users';

  Database? _database;
  final LoggingService _log = LoggingService();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final String databasesPath = await getDatabasesPath();
    final String path = p.join(databasesPath, 'shopping_list.db');

    return openDatabase(
      path,
      version: schemaVersion,
      onCreate: (Database db, int version) async {
        await db.execute('''
          CREATE TABLE $itemsTable (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            server_id INTEGER,
            name TEXT NOT NULL,
            barcode TEXT NOT NULL DEFAULT '',
            tag TEXT NOT NULL DEFAULT '',
            tags TEXT NOT NULL DEFAULT '[]',
            is_purchased INTEGER NOT NULL DEFAULT 0,
            added_by TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            purchased_at TEXT,
            pending_sync INTEGER NOT NULL DEFAULT 1
          )
        ''');

        await db.execute('''
          CREATE TABLE $usersTable (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT UNIQUE NOT NULL,
            phone_number TEXT,
            created_at TEXT NOT NULL
          )
        ''');

        await _createIndexes(db);
        _log.info('Shopping list database created at: $path',
            source: 'ShoppingListDB');
      },
      onUpgrade: (Database db, int oldVersion, int newVersion) async {
        _log.info(
          'Upgrading shopping list database $oldVersion -> $newVersion',
          source: 'ShoppingListDB',
        );

        if (oldVersion < 3) {
          await _addColumnIfMissing(db, 'server_id', 'INTEGER');
          await _addColumnIfMissing(db, 'tags', "TEXT NOT NULL DEFAULT '[]'");
          await _addColumnIfMissing(
              db, 'pending_sync', 'INTEGER NOT NULL DEFAULT 1');
          await _createIndexes(db);
          await _migrateSingleTagToTagArray(db);
        }
      },
    );
  }

  Future<void> _addColumnIfMissing(
      Database db, String column, String definition) async {
    try {
      final List<Map<String, Object?>> info =
          await db.rawQuery('PRAGMA table_info($itemsTable)');
      final bool exists =
          info.any((Map<String, Object?> row) => row['name'] == column);
      if (!exists) {
        await db.execute(
            'ALTER TABLE $itemsTable ADD COLUMN $column $definition');
      }
    } catch (e) {
      _log.error('Failed to add column $column',
          source: 'ShoppingListDB', exception: e);
    }
  }

  Future<void> _createIndexes(Database db) async {
    try {
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_items_server_id '
        'ON $itemsTable(server_id)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_items_pending_sync '
        'ON $itemsTable(pending_sync)',
      );
    } catch (e) {
      _log.warning('Failed to create indexes: $e', source: 'ShoppingListDB');
    }
  }

  /// مهاجرت داده‌های قدیمی: ستون `tag` (تک تگ) → ستون `tags` (آرایه JSON).
  Future<void> _migrateSingleTagToTagArray(Database db) async {
    try {
      final List<Map<String, Object?>> rows = await db.query(
        itemsTable,
        columns: <String>['id', 'tag', 'tags'],
      );
      for (final Map<String, Object?> row in rows) {
        final List<String> current = parseTagIdsFromValue(row['tags']);
        if (current.isNotEmpty) continue;
        final List<String> legacy = parseTagIdsFromValue(row['tag']);
        if (legacy.isEmpty) continue;
        await db.update(
          itemsTable,
          <String, Object?>{'tags': json.encode(legacy)},
          where: 'id = ?',
          whereArgs: <Object?>[row['id']],
        );
      }
      _log.info('Tag migration completed (${rows.length} rows scanned)',
          source: 'ShoppingListDB');
    } catch (e) {
      _log.error('Tag migration failed',
          source: 'ShoppingListDB', exception: e);
    }
  }

  // ==================== عملیات CRUD آیتم‌ها ====================

  Future<int> insertItem(ShoppingListItem item) async {
    final Database db = await database;
    return db.insert(itemsTable, item.toMap());
  }

  Future<List<ShoppingListItem>> getAllItems() async {
    final Database db = await database;
    final List<Map<String, Object?>> maps = await db.query(
      itemsTable,
      orderBy: 'created_at DESC',
    );
    return _mapRows(maps);
  }

  Future<List<ShoppingListItem>> getItemsByFilter(
      ShoppingListFilter filter) async {
    final Database db = await database;
    String? whereClause;
    switch (filter) {
      case ShoppingListFilter.purchased:
        whereClause = 'is_purchased = 1';
        break;
      case ShoppingListFilter.pending:
        whereClause = 'is_purchased = 0';
        break;
      case ShoppingListFilter.all:
        whereClause = null;
        break;
    }
    final List<Map<String, Object?>> maps = await db.query(
      itemsTable,
      where: whereClause,
      orderBy: 'created_at DESC',
    );
    return _mapRows(maps);
  }

  /// آیتمهای دارای یک تگ مشخص (پشتیبانی از چند‌به‌چند).
  Future<List<ShoppingListItem>> getItemsByTag(String tagId) async {
    final Database db = await database;
    final List<Map<String, Object?>> maps = await db.query(
      itemsTable,
      where: '(tags LIKE ? OR tag = ?)',
      whereArgs: <Object?>['%"$tagId"%', tagId],
      orderBy: 'created_at DESC',
    );
    return _mapRows(maps);
  }

  Future<ShoppingListItem?> getItemByServerId(int serverId) async {
    final Database db = await database;
    final List<Map<String, Object?>> maps = await db.query(
      itemsTable,
      where: 'server_id = ?',
      whereArgs: <Object?>[serverId],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return ShoppingListItem.fromMap(Map<String, dynamic>.from(maps.first));
  }

  Future<int> updateItem(ShoppingListItem item) async {
    final Database db = await database;
    return db.update(
      itemsTable,
      item.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[item.id],
    );
  }

  Future<int> deleteItem(int id) async {
    final Database db = await database;
    return db.delete(itemsTable, where: 'id = ?', whereArgs: <Object?>[id]);
  }

  Future<void> updateItemPurchaseStatus(int id, bool isPurchased) async {
    final Database db = await database;
    await db.update(
      itemsTable,
      <String, Object?>{
        'is_purchased': isPurchased ? 1 : 0,
        'purchased_at': isPurchased ? DateTime.now().toIso8601String() : null,
        'pending_sync': 1,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// بروزرسانی تگ‌های یک آیتم (بدون محدودیت تعداد).
  Future<void> updateItemTags(int id, List<String> tagIds) async {
    final Database db = await database;
    final List<String> normalized = normalizeTagIds(tagIds);
    await db.update(
      itemsTable,
      <String, Object?>{
        'tags': json.encode(normalized),
        'tag': normalized.isEmpty ? '' : normalized.first,
        'pending_sync': 1,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<int> getItemCount() async {
    final Database db = await database;
    return Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $itemsTable'),
        ) ??
        0;
  }

  Future<void> clearAllItems() async {
    final Database db = await database;
    await db.delete(itemsTable);
  }

  List<ShoppingListItem> _mapRows(List<Map<String, Object?>> maps) {
    return maps
        .map((Map<String, Object?> row) =>
            ShoppingListItem.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  // ==================== عملیات کاربر محلی ====================

  Future<int> saveLocalUser(String username, String phoneNumber) async {
    final Database db = await database;
    return db.insert(
      usersTable,
      <String, Object?>{
        'username': username,
        'phone_number': phoneNumber,
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getLocalUser() async {
    final Database db = await database;
    final List<Map<String, Object?>> maps = await db.query(
      usersTable,
      limit: 1,
      orderBy: 'id DESC',
    );
    return maps.isEmpty ? null : Map<String, dynamic>.from(maps.first);
  }

  Future<String?> getUsername() async {
    final Map<String, dynamic>? user = await getLocalUser();
    return user?['username'] as String?;
  }

  Future<bool> hasUser() async {
    final Map<String, dynamic>? user = await getLocalUser();
    return user != null;
  }

  // ==================== همگام‌سازی ====================

  /// آیتم‌هایی که هنوز روی سرور ثبت/بروزرسانی نشده‌اند.
  ///
  /// فقط این آیتم‌ها به سرور فرستاده می‌شوند (نه همه آیتم‌ها)، بنابراین
  /// ردیف تکراری ساخته نمی‌شود و ترافیک هم کمتر است.
  Future<List<ShoppingListItem>> getPendingItemsForSync() async {
    final Database db = await database;
    final List<Map<String, Object?>> maps = await db.query(
      itemsTable,
      where: 'pending_sync = 1',
      orderBy: 'created_at ASC',
    );
    return _mapRows(maps);
  }

  /// سازگاری با کد قبلی: آیتم‌های تغییرکرده از یک زمان مشخص.
  Future<List<ShoppingListItem>> getItemsForSync(DateTime? lastSyncTime) async {
    if (lastSyncTime == null) return getPendingItemsForSync();
    final Database db = await database;
    final List<Map<String, Object?>> maps = await db.query(
      itemsTable,
      where: 'created_at > ? OR (purchased_at IS NOT NULL AND purchased_at > ?)',
      whereArgs: <Object?>[
        lastSyncTime.toIso8601String(),
        lastSyncTime.toIso8601String(),
      ],
      orderBy: 'created_at DESC',
    );
    return _mapRows(maps);
  }

  /// ثبت موفق روی سرور: ذخیره `server_id` و پاک کردن پرچم pending.
  Future<void> markSynced(int localId, int serverId) async {
    final Database db = await database;
    await db.update(
      itemsTable,
      <String, Object?>{'server_id': serverId, 'pending_sync': 0},
      where: 'id = ?',
      whereArgs: <Object?>[localId],
    );
  }

  /// درج/بروزرسانی آیتمی که از سرور آمده است.
  ///
  /// کلید تطبیق `server_id` است؛ بنابراین هیچ‌گاه ردیف محلی (با کلید
  /// اصلی AUTOINCREMENT) بازنویسی یا حذف نمی‌شود - این همان باگ نسخه
  /// قبلی بود که از `ConflictAlgorithm.replace` روی کلید اصلی استفاده
  /// می‌کرد.
  Future<void> upsertItemFromServer(ShoppingListItem item) async {
    if (item.serverId == null) return;
    final Database db = await database;

    final List<Map<String, Object?>> existing = await db.query(
      itemsTable,
      columns: <String>['id'],
      where: 'server_id = ?',
      whereArgs: <Object?>[item.serverId],
      limit: 1,
    );

    if (existing.isEmpty) {
      // `item.id` برای آیتم‌های سرور همیشه null است (از `fromServerJson`)،
      // بنابراین INSERT ردیف جدید می‌سازد و کلید اصلی محلی دست‌نخورده می‌ماند.
      await db.insert(itemsTable, item.copyWith(pendingSync: false).toMap());
      return;
    }

    final Object? localId = existing.first['id'];
    await db.update(
      itemsTable,
      <String, Object?>{
        'name': item.name,
        'barcode': item.barcode,
        'tag': item.tagIds.isEmpty ? '' : item.tagIds.first,
        'tags': json.encode(item.tagIds),
        'is_purchased': item.isPurchased ? 1 : 0,
        'added_by': item.addedBy,
        'purchased_at': item.purchasedAt?.toIso8601String(),
        'server_id': item.serverId,
        'pending_sync': 0,
      },
      where: 'id = ?',
      whereArgs: <Object?>[localId],
    );
  }

  /// همگام‌سازی گروهی آیتم‌های سرور در یک تراکنش.
  Future<void> syncItemsFromServer(List<ShoppingListItem> items) async {
    for (final ShoppingListItem item in items) {
      await upsertItemFromServer(item);
    }
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

}