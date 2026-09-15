import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/shopping_list_item.dart';

/// سرویس دیتابیس محلی برای چک‌لیست خرید
class ShoppingListDatabaseService {
  static final ShoppingListDatabaseService _instance = ShoppingListDatabaseService._internal();
  factory ShoppingListDatabaseService() => _instance;
  ShoppingListDatabaseService._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = p.join(databasesPath, 'shopping_list.db');

    return await openDatabase(
      path,
      version: 2, // Incremented for tag migration
      onCreate: (db, version) async {
        // جدول آیتم‌های چک‌لیست خرید
        await db.execute('''
          CREATE TABLE shopping_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            barcode TEXT NOT NULL,
            tag TEXT NOT NULL,
            is_purchased INTEGER DEFAULT 0,
            added_by TEXT NOT NULL,
            created_at TEXT NOT NULL,
            purchased_at TEXT
          )
        ''');

        // جدول کاربران محلی
        await db.execute('''
          CREATE TABLE local_users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT UNIQUE NOT NULL,
            phone_number TEXT,
            created_at TEXT NOT NULL
          )
        ''');

        print('Shopping list database initialized at: $path');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Migration from version 1 to 2 - no schema changes needed
        // The tag field already stores JSON for multiple tags
        print('Database upgraded from $oldVersion to $newVersion');
      },
    );
  }

  // ==================== عملیات CRUD برای آیتم‌ها ====================

  Future<int> insertItem(ShoppingListItem item) async {
    final db = await database;
    return await db.insert('shopping_items', item.toMap());
  }

  Future<List<ShoppingListItem>> getAllItems() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'shopping_items',
      orderBy: 'created_at DESC',
    );
    return List.generate(maps.length, (i) => ShoppingListItem.fromMap(maps[i]));
  }

  Future<List<ShoppingListItem>> getItemsByFilter(ShoppingListFilter filter) async {
    final db = await database;
    String? whereClause;
    
    switch (filter) {
      case ShoppingListFilter.purchased:
        whereClause = 'is_purchased = 1';
        break;
      case ShoppingListFilter.pending:
        whereClause = 'is_purchased = 0';
        break;
      case ShoppingListFilter.all:
      default:
        whereClause = null;
    }

    final List<Map<String, dynamic>> maps = await db.query(
      'shopping_items',
      where: whereClause,
      orderBy: 'created_at DESC',
    );
    return List.generate(maps.length, (i) => ShoppingListItem.fromMap(maps[i]));
  }

  Future<List<ShoppingListItem>> getItemsByTag(String tag) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'shopping_items',
      where: 'tag = ?',
      whereArgs: [tag],
      orderBy: 'created_at DESC',
    );
    return List.generate(maps.length, (i) => ShoppingListItem.fromMap(maps[i]));
  }

  Future<int> updateItem(ShoppingListItem item) async {
    final db = await database;
    return await db.update(
      'shopping_items',
      item.toMap(),
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  Future<int> deleteItem(int id) async {
    final db = await database;
    return await db.delete(
      'shopping_items',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateItemPurchaseStatus(int id, bool isPurchased) async {
    final db = await database;
    await db.update(
      'shopping_items',
      {
        'is_purchased': isPurchased ? 1 : 0,
        'purchased_at': isPurchased ? DateTime.now().toIso8601String() : null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> getItemCount() async {
    final db = await database;
    return Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM shopping_items'),
    ) ?? 0;
  }

  Future<void> clearAllItems() async {
    final db = await database;
    await db.delete('shopping_items');
  }

  // ==================== عملیات مربوط به کاربر محلی ====================

  Future<int> saveLocalUser(String username, String phoneNumber) async {
    final db = await database;
    return await db.insert(
      'local_users',
      {
        'username': username,
        'phone_number': phoneNumber,
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getLocalUser() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'local_users',
      limit: 1,
      orderBy: 'id DESC',
    );
    return maps.isNotEmpty ? maps.first : null;
  }

  Future<String?> getUsername() async {
    final user = await getLocalUser();
    return user?['username'] as String?;
  }

  Future<bool> hasUser() async {
    final user = await getLocalUser();
    return user != null;
  }

  // ==================== همگام‌سازی ====================

  Future<List<ShoppingListItem>> getItemsForSync(DateTime? lastSyncTime) async {
    final db = await database;
    String? whereClause;
    List<dynamic>? whereArgs;

    if (lastSyncTime != null) {
      whereClause = 'created_at > ? OR (purchased_at IS NOT NULL AND purchased_at > ?)';
      whereArgs = [lastSyncTime.toIso8601String(), lastSyncTime.toIso8601String()];
    }

    final List<Map<String, dynamic>> maps = await db.query(
      'shopping_items',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'created_at DESC',
    );
    return List.generate(maps.length, (i) => ShoppingListItem.fromMap(maps[i]));
  }

  Future<void> syncItemsFromServer(List<ShoppingListItem> items) async {
    final db = await database;
    await db.transaction((txn) async {
      for (var item in items) {
        if (item.id != null) {
          await txn.insert(
            'shopping_items',
            item.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}
