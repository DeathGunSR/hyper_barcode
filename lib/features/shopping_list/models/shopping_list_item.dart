import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

// ==================== کمکیهای تبدیل امن نوع ====================

/// تبدیل امن به int.
///
/// بسیار مهم: REST API وردپرس (wpdb) مقادیر عددی را به صورت **String**
/// برمی‌گرداند (مثلا `"id":"2"` و `"is_purchased":"0"`). کد قبلی از
/// `as int?` استفاده می‌کرد که باعث خطای type cast و شکست کامل همگام‌سازی
/// می‌شد. این توابع هر دو حالت را پشتیبانی می‌کنند.
int? asIntOrNull(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is bool) return value ? 1 : 0;
  final String text = value.toString().trim();
  if (text.isEmpty) return null;
  return int.tryParse(text) ?? double.tryParse(text)?.toInt();
}

int asInt(dynamic value, {int fallback = 0}) =>
    asIntOrNull(value) ?? fallback;

/// تبدیل امن به bool ('1', 1, true, 'true', 'yes').
bool asBool(dynamic value) {
  if (value == null) return false;
  if (value is bool) return value;
  if (value is num) return value != 0;
  final String text = value.toString().trim().toLowerCase();
  return text == '1' || text == 'true' || text == 'yes' || text == 'on';
}

/// تبدیل امن به DateTime (هم ISO8601 و هم فرمت MySQL «YYYY-MM-DD HH:MM:SS»).
DateTime? asDateTimeOrNull(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  final String text = value.toString().trim();
  if (text.isEmpty) return null;
  return DateTime.tryParse(text) ??
      DateTime.tryParse(text.replaceFirst(' ', 'T'));
}

/// نرمال‌سازی لیست شناسه تگ‌ها: حذف خالی‌ها، trim و حذف تکراریها.
/// تعداد تگ‌ها هیچ محدودیتی ندارد (many-to-many بدون سقف).
List<String> normalizeTagIds(Iterable<dynamic>? raw) {
  if (raw == null) return <String>[];
  final List<String> result = <String>[];
  for (final dynamic item in raw) {
    if (item == null) continue;
    final String id = item.toString().trim();
    if (id.isEmpty) continue;
    if (!result.contains(id)) result.add(id);
  }
  return result;
}

/// تبدیل مقدار ستون `tags`/`tag` به لیست شناسه‌ها.
///
/// پشتیبانی از سه فرمت (سازگاری با داده‌های قبلی):
/// 1. JSON array: `["dairy","fruits"]`  (فرمت جدید)
/// 2. لیست واقعی (بعد از jsonDecode)
/// 3. تک مقدار رشته‌ای: `dairy`          (فرمت قدیمی، فقط یک تگ)
List<String> parseTagIdsFromValue(dynamic value) {
  if (value == null) return <String>[];
  if (value is List) return normalizeTagIds(value);

  final String text = value.toString().trim();
  if (text.isEmpty) return <String>[];

  if (text.startsWith('[')) {
    try {
      final dynamic decoded = json.decode(text);
      if (decoded is List) return normalizeTagIds(decoded);
    } catch (_) {
      // اگر JSON نبود، به عنوان متن ساده ادامه می‌دهیم.
    }
  }
  return normalizeTagIds(<String>[text]);
}

// ==================== مدل آیتم چک‌لیست خرید ====================

/// آیتم چک‌لیست خرید.
///
/// نکته مهم درباره شناسه‌ها:
/// - [id]: شناسه محلی (SQLite AUTOINCREMENT).
/// - [serverId]: شناسه همان آیتم روی سرور وردپرس. قبلا وجود نداشت و
///   برنامه شناسه محلی را به سرور می‌فرستاد که باعث بروزرسانی ردیف اشتباه
///   یا ساخت ردیف تکراری می‌شد.
class ShoppingListItem {
  final int? id;
  final int? serverId;
  final String name;
  final String barcode;

  /// لیست شناسه تگ‌ها - **بدون محدودیت تعداد** (رابطه چند‌به‌چند).
  final List<String> tagIds;

  final bool isPurchased;
  final String addedBy;
  final DateTime createdAt;
  final DateTime? purchasedAt;

  /// اگر true باشد یعنی این آیتم هنوز روی سرور ثبت/بروزرسانی نشده است.
  final bool pendingSync;

  ShoppingListItem({
    this.id,
    this.serverId,
    required this.name,
    required this.barcode,
    List<String>? tagIds,
    this.isPurchased = false,
    required this.addedBy,
    required this.createdAt,
    this.purchasedAt,
    this.pendingSync = true,
  }) : tagIds = normalizeTagIds(tagIds);

  bool get isOnServer => serverId != null;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'server_id': serverId,
      'name': name,
      'barcode': barcode,
      // ستون قدیمی برای سازگاری با نسخه‌های قبلی دیتابیس.
      'tag': tagIds.isEmpty ? '' : tagIds.first,
      // ستون جدید: آرایه JSON از تگ‌ها (بدون محدودیت).
      'tags': json.encode(tagIds),
      'is_purchased': isPurchased ? 1 : 0,
      'added_by': addedBy,
      'created_at': createdAt.toIso8601String(),
      'purchased_at': purchasedAt?.toIso8601String(),
      'pending_sync': pendingSync ? 1 : 0,
    };
  }

  /// ساخت مدل از ردیف دیتابیس محلی.
  factory ShoppingListItem.fromMap(Map<String, dynamic> map) {
    final List<String> tagIds = map.containsKey('tags')
        ? parseTagIdsFromValue(map['tags'])
        : parseTagIdsFromValue(map['tag']);

    return ShoppingListItem(
      id: asIntOrNull(map['id']),
      serverId: asIntOrNull(map['server_id']),
      name: map['name']?.toString() ?? '',
      barcode: map['barcode']?.toString() ?? '',
      tagIds: tagIds,
      isPurchased: asBool(map['is_purchased']),
      addedBy: map['added_by']?.toString() ?? '',
      createdAt: asDateTimeOrNull(map['created_at']) ?? DateTime.now(),
      purchasedAt: asDateTimeOrNull(map['purchased_at']),
      pendingSync: map.containsKey('pending_sync')
          ? asBool(map['pending_sync'])
          : true,
    );
  }

  /// ساخت مدل از پاسخ REST API وردپرس (برای آیتم‌های سرور).
  ///
  /// `serverId` از `id` سرور پر می‌شود و `id` محلی خالی می‌ماند تا در
  /// دیتابیس محلی به عنوان ردیف جدید درج شود.
  factory ShoppingListItem.fromServerJson(Map<String, dynamic> data) {
    return ShoppingListItem(
      id: null,
      serverId: asIntOrNull(data['id']),
      name: data['name']?.toString() ?? '',
      barcode: data['barcode']?.toString() ?? '',
      tagIds: data.containsKey('tags')
          ? parseTagIdsFromValue(data['tags'])
          : parseTagIdsFromValue(data['tag']),
      isPurchased: asBool(data['is_purchased']),
      addedBy: data['added_by']?.toString() ?? '',
      createdAt: asDateTimeOrNull(data['created_at']) ?? DateTime.now(),
      purchasedAt: asDateTimeOrNull(data['purchased_at']),
      pendingSync: false,
    );
  }

  /// بدنه JSON برای ارسال به سرور (بدون شناسه محلی).
  Map<String, dynamic> toServerJson() {
    return <String, dynamic>{
      'name': name,
      'barcode': barcode,
      // `tags` آرایه JSON است؛ `tag` برای سازگاری با افزونه‌های قدیمی.
      'tags': json.encode(tagIds),
      'tag': tagIds.isEmpty ? 'other' : tagIds.first,
      'added_by': addedBy,
      'created_at': createdAt.toIso8601String(),
    };
  }

  ShoppingListItem copyWith({
    int? id,
    int? serverId,
    bool clearServerId = false,
    String? name,
    String? barcode,
    List<String>? tagIds,
    bool? isPurchased,
    String? addedBy,
    DateTime? createdAt,
    DateTime? purchasedAt,
    bool clearPurchasedAt = false,
    bool? pendingSync,
  }) {
    return ShoppingListItem(
      id: id ?? this.id,
      serverId: clearServerId ? null : (serverId ?? this.serverId),
      name: name ?? this.name,
      barcode: barcode ?? this.barcode,
      tagIds: tagIds ?? this.tagIds,
      isPurchased: isPurchased ?? this.isPurchased,
      addedBy: addedBy ?? this.addedBy,
      createdAt: createdAt ?? this.createdAt,
      purchasedAt: clearPurchasedAt ? null : (purchasedAt ?? this.purchasedAt),
      pendingSync: pendingSync ?? this.pendingSync,
    );
  }
  
  /// بررسی اینکه آیا آیتم تگ خاصی دارد
  bool hasTag(String tagId) => tagIds.contains(tagId);
  
  /// افزودن تگ
  ShoppingListItem addTag(String tagId) {
    if (!tagIds.contains(tagId)) {
      return copyWith(tagIds: [...tagIds, tagId]);
    }
    return this;
  }
  
  /// حذف تگ
  ShoppingListItem removeTag(String tagId) {
    if (tagIds.contains(tagId)) {
      return copyWith(tagIds: tagIds.where((t) => t != tagId).toList());
    }
    return this;
  }
}

// ==================== مدل تگ ====================

/// تگ برای دسته‌بندی آیتم‌ها.
class ShoppingListTag {
  final String id;
  final String nameFa;
  final String nameEn;
  final String colorHex;

  /// شناسه تگ والد (برای ساختار درختی).
  /// اگر `null` یعنی تگ در سطح ریشه است.
  final String? parentId;

  /// شناسه این تگ روی سرور وردپرس (برای همگام‌سازی).
  final int? serverId;

  /// اگر true یعنی تگ هنوز روی سرور ثبت/بروزرسانی نشده است.
  final bool pendingSync;

  const ShoppingListTag({
    required this.id,
    required this.nameFa,
    required this.nameEn,
    required this.colorHex,
    this.isCustom = true,
    this.parentId,
    this.serverId,
    this.pendingSync = true,
  });

  /// آیا این تگ توسط کاربر ساخته شده است (همیشه true، زیرا تگ‌های پیش‌فرض حذف شده‌اند).
  final bool isCustom;

  String getName(String locale) => locale == 'fa' ? nameFa : nameEn;

  /// نام برای نمایش، با پشتیبانی از تگ‌هایی که فقط یک نام دارند.
  String displayName(String locale) {
    final String primary = getName(locale).trim();
    if (primary.isNotEmpty) return primary;
    final String fallback = locale == 'fa' ? nameEn : nameFa;
    if (fallback.trim().isNotEmpty) return fallback.trim();
    return id;
  }

  /// عمق درختی تگ (برای indent در UI).
  int depth(List<ShoppingListTag> allTags) {
    int d = 0;
    String? cur = parentId;
    final Set<String> seen = <String>{};
    while (cur != null) {
      if (seen.contains(cur)) break;
      seen.add(cur);
      d++;
      final ShoppingListTag? p = _findTagById(allTags, cur);
      cur = p?.parentId;
    }
    return d;
  }

  /// لیست تگ‌های فرزند مستقیم.
  List<ShoppingListTag> children(List<ShoppingListTag> allTags) {
    return allTags.where((ShoppingListTag t) => t.parentId == id).toList();
  }

  static ShoppingListTag? _findTagById(List<ShoppingListTag> allTags, String id) {
    for (final ShoppingListTag t in allTags) {
      if (t.id == id) return t;
    }
    return null;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'nameFa': nameFa,
        'nameEn': nameEn,
        'colorHex': colorHex,
        'isCustom': isCustom,
        'parentId': parentId,
        'serverId': serverId,
        'pendingSync': pendingSync,
      };

  factory ShoppingListTag.fromJson(Map<String, dynamic> json) {
    final String nameFa = json['nameFa']?.toString() ?? '';
    final String nameEn = json['nameEn']?.toString() ?? '';
    final String? parentIdRaw = json['parentId']?.toString();
    return ShoppingListTag(
      id: json['id']?.toString() ?? '',
      nameFa: nameFa.isNotEmpty ? nameFa : nameEn,
      nameEn: nameEn.isNotEmpty ? nameEn : nameFa,
      colorHex: json['colorHex']?.toString() ?? '#BDBDBD',
      isCustom: json['isCustom'] == null ? true : asBool(json['isCustom']),
      parentId: (parentIdRaw != null && parentIdRaw.trim().isNotEmpty) ? parentIdRaw : null,
      serverId: (json['serverId'] == null || json['serverId'] == '')
          ? null
          : asIntOrNull(json['serverId']),
      pendingSync: json['pendingSync'] == null ? true : asBool(json['pendingSync']),
    );
  }

  ShoppingListTag copyWith({
    String? id,
    String? nameFa,
    String? nameEn,
    String? colorHex,
    bool? isCustom,
    Object? clearParentId = const _None(),
    String? parentId,
    Object? clearServerId = const _None(),
    int? serverId,
    bool? pendingSync,
  }) {
    return ShoppingListTag(
      id: id ?? this.id,
      nameFa: nameFa ?? this.nameFa,
      nameEn: nameEn ?? this.nameEn,
      colorHex: colorHex ?? this.colorHex,
      isCustom: isCustom ?? this.isCustom,
      parentId: clearParentId is! _None ? null : (parentId ?? this.parentId),
      serverId: clearServerId is! _None ? null : (serverId ?? this.serverId),
      pendingSync: pendingSync ?? this.pendingSync,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ShoppingListTag && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Sentinel برای تشخیص «پاک کردن مقدار null».
class _None {
  const _None();
}

/// کمکی‌ها برای جستجوی تگ‌ها (فقط شامل تگ‌های کاربر، چون تگ‌های پیش‌فرض حذف شده‌اند).
class TagQueries {
  static ShoppingListTag? getById(String id, {required List<ShoppingListTag> tags}) {
    for (final ShoppingListTag tag in tags) {
      if (tag.id == id) return tag;
    }
    return null;
  }

  static ShoppingListTag? findByName(
    String name, {
    required List<ShoppingListTag> tags,
  }) {
    final String needle = name.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final ShoppingListTag tag in tags) {
      if (tag.nameFa.trim().toLowerCase() == needle ||
          tag.nameEn.trim().toLowerCase() == needle) {
        return tag;
      }
    }
    return null;
  }
}

// ==================== سرویس تگ‌های سفارشی ====================

/// وضعیت نتیجه ساخت تگ جدید.
enum TagCreateStatus {
  /// تگ ساخته شد.
  created,

  /// نام تکراری بود؛ [TagCreateResult.tag] همان تگ موجود است.
  duplicate,

  /// نام خالی/نامعتبر بود.
  invalidEmptyName,

  /// خطای ذخیره‌سازی.
  storageError,
}

/// نتیجه ساخت تگ سفارشی.
class TagCreateResult {
  final TagCreateStatus status;
  final ShoppingListTag? tag;
  final String message;
  final String messageFa;

  const TagCreateResult({
    required this.status,
    required this.message,
    required this.messageFa,
    this.tag,
  });

  bool get isSuccess => status == TagCreateStatus.created;
  bool get isDuplicate => status == TagCreateStatus.duplicate;
}

/// مدیریت تگ‌های سفارشی: ساخت، ذخیره دائمی، ویرایش و حذف.
///
/// تگ‌ها در `SharedPreferences` ذخیره می‌شوند و بعد از ری‌استارت اپ باقی
/// می‌مانند.
class CustomTagService {
  static const String _prefsKey = 'custom_shopping_tags';

  /// پالت رنگ پیشنهادی برای تگ‌های جدید.
  static const List<String> colorPalette = <String>[
    '#EF5350', '#EC407A', '#AB47BC', '#7E57C2', '#5C6BC0',
    '#42A5F5', '#29B6F6', '#26C6DA', '#26A69A', '#66BB6A',
    '#9CCC65', '#D4E157', '#FFEE58', '#FFCA28', '#FFA726',
    '#FF7043', '#8D6E63', '#78909C', '#BDBDBD', '#263238',
  ];

  /// بارگذاری تگ‌های سفارشی از حافظه.
  static Future<List<ShoppingListTag>> loadCustomTags() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? tagsJson = prefs.getString(_prefsKey);
      if (tagsJson == null || tagsJson.isEmpty) return <ShoppingListTag>[];

      final dynamic decoded = json.decode(tagsJson);
      if (decoded is! List) return <ShoppingListTag>[];

      final List<ShoppingListTag> result = <ShoppingListTag>[];
      for (final dynamic item in decoded) {
        if (item is Map) {
          final ShoppingListTag tag =
              ShoppingListTag.fromJson(Map<String, dynamic>.from(item));
          if (tag.id.isNotEmpty &&
              !result.any((ShoppingListTag t) => t.id == tag.id)) {
            result.add(tag.copyWith(isCustom: true));
          }
        }
      }
      return result;
    } catch (e) {
      // ignore: avoid_print
      print('Error loading custom tags: $e');
      return <ShoppingListTag>[];
    }
  }

  /// ذخیره دائمی تگ‌های سفارشی.
  static Future<bool> saveCustomTags(List<ShoppingListTag> tags) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String tagsJson = json.encode(
        tags
            .map((ShoppingListTag tag) => tag.copyWith(isCustom: true).toJson())
            .toList(),
      );
      return await prefs.setString(_prefsKey, tagsJson);
    } catch (e) {
      // ignore: avoid_print
      print('Error saving custom tags: $e');
      return false;
    }
  }

  /// ساخت تگ سفارشی جدید.
  ///
  /// اعتبارسنجی:
  /// - نام خالی مجاز نیست ([TagCreateStatus.invalidEmptyName]).
  /// - نام تکراری به صورت «معمولی» مدیریت می‌شود: به جای ساخت تگ جدید،
  ///   تگ موجود برگردانده می‌شود ([TagCreateStatus.duplicate]).
  /// - [parentId] شناسه تگ والد برای ساختار درختی است (اختیاری).
  static Future<TagCreateResult> createCustomTag({
    required String nameFa,
    required String nameEn,
    required String colorHex,
    List<ShoppingListTag>? existingCustomTags,
    String? parentId,
  }) async {
    final String fa = nameFa.trim();
    final String en = nameEn.trim();
    final String displayName = fa.isNotEmpty ? fa : en;

    if (displayName.isEmpty) {
      return const TagCreateResult(
        status: TagCreateStatus.invalidEmptyName,
        message: 'Tag name cannot be empty',
        messageFa: 'نام تگ نمی‌تواند خالی باشد',
      );
    }

    final List<ShoppingListTag> existing =
        existingCustomTags ?? await loadCustomTags();

    // مدیریت تکراری بودن نام (فقط روی تگ‌های کاربر ساخته‌شده).
    final ShoppingListTag? duplicate = TagQueries.findByName(
      displayName,
      tags: existing,
    );
    if (duplicate != null) {
      return TagCreateResult(
        status: TagCreateStatus.duplicate,
        tag: duplicate,
        message: 'Tag "${duplicate.displayName('en')}" already exists',
        messageFa: 'تگ «${duplicate.displayName('fa')}» از قبل وجود دارد',
      );
    }

    final ShoppingListTag newTag = ShoppingListTag(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      nameFa: fa.isNotEmpty ? fa : en,
      nameEn: en.isNotEmpty ? en : fa,
      colorHex: normalizeHexColor(colorHex),
      isCustom: true,
      parentId: parentId,
      pendingSync: true,
    );

    final bool saved =
        await saveCustomTags(<ShoppingListTag>[...existing, newTag]);
    if (!saved) {
      return const TagCreateResult(
        status: TagCreateStatus.storageError,
        message: 'Failed to save the new tag',
        messageFa: 'ذخیره تگ جدید ناموفق بود',
      );
    }

    return TagCreateResult(
      status: TagCreateStatus.created,
      tag: newTag,
      message: 'Tag created',
      messageFa: 'تگ ساخته شد',
    );
  }

  /// ویرایش یک تگ سفارشی (نام/رنگ).
  static Future<bool> updateCustomTag(ShoppingListTag tag) async {
    final List<ShoppingListTag> existing = await loadCustomTags();
    final int index =
        existing.indexWhere((ShoppingListTag t) => t.id == tag.id);
    if (index == -1) return false;
    existing[index] = tag.copyWith(isCustom: true);
    return saveCustomTags(existing);
  }

  /// حذف یک تگ سفارشی.
  static Future<bool> deleteCustomTag(String tagId) async {
    final List<ShoppingListTag> existing = await loadCustomTags();
    existing.removeWhere((ShoppingListTag t) => t.id == tagId);
    return saveCustomTags(existing);
  }
}

/// نرمال‌سازی رنگ به فرمت `#RRGGBB` (مقدار نامعتبر → خاکستری پیش‌فرض).
String normalizeHexColor(String colorHex) {
  String value = colorHex.trim().toUpperCase();
  if (value.startsWith('#')) value = value.substring(1);
  if (value.length == 8) value = value.substring(2); // حذف کانال آلفا
  if (value.length != 6) return '#BDBDBD';
  if (int.tryParse(value, radix: 16) == null) return '#BDBDBD';
  return '#$value';
}

/// تبدیل `#RRGGBB` به مقدار ARGB برای استفاده در ویجت‌ها.
int hexColorToArgb32(String colorHex) {
  final String normalized = normalizeHexColor(colorHex);
  return int.parse('FF${normalized.substring(1)}', radix: 16);
}

// ==================== فیلتر نمایش ====================

/// فیلتر نمایش آیتم‌ها بر اساس وضعیت خرید.
enum ShoppingListFilter { all, purchased, pending }

extension ShoppingListFilterExtension on ShoppingListFilter {
  String getLabel(String locale) {
    switch (this) {
      case ShoppingListFilter.all:
        return locale == 'fa' ? 'همه' : 'All';
      case ShoppingListFilter.purchased:
        return locale == 'fa' ? 'خریداری شده' : 'Purchased';
      case ShoppingListFilter.pending:
        return locale == 'fa' ? 'در انتظار' : 'Pending';
    }
  }
}