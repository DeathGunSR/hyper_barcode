import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// مدل آیتم چک‌لیست خرید
class ShoppingListItem {
  final int? id;
  final String name;
  final String barcode;
  final List<String> tagIds; // Changed from single tag to multiple tags
  final bool isPurchased;
  final String addedBy; // نام کاربری اضافه‌کننده
  final DateTime createdAt;
  final DateTime? purchasedAt;

  ShoppingListItem({
    this.id,
    required this.name,
    required this.barcode,
    List<String>? tagIds, // Changed from single tag to multiple tags
    this.isPurchased = false,
    required this.addedBy,
    required this.createdAt,
    this.purchasedAt,
  }) : tagIds = tagIds ?? [];

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'barcode': barcode,
      'tag': json.encode(tagIds), // Store as JSON string
      'is_purchased': isPurchased ? 1 : 0,
      'added_by': addedBy,
      'created_at': createdAt.toIso8601String(),
      'purchased_at': purchasedAt?.toIso8601String(),
    };
  }

  factory ShoppingListItem.fromMap(Map<String, dynamic> map) {
    List<String> tagIds;
    final tagData = map['tag'];
    
    if (tagData == null || tagData == '') {
      tagIds = [];
    } else if (tagData is String) {
      // Try to parse as JSON (new format)
      try {
        tagIds = List<String>.from(json.decode(tagData));
      } catch (e) {
        // Old format - single tag ID
        tagIds = [tagData];
      }
    } else if (tagData is List) {
      tagIds = List<String>.from(tagData);
    } else {
      tagIds = [tagData.toString()];
    }

    return ShoppingListItem(
      id: map['id'],
      name: map['name'] ?? '',
      barcode: map['barcode'] ?? '',
      tagIds: tagIds,
      isPurchased: (map['is_purchased'] ?? 0) == 1,
      addedBy: map['added_by'] ?? '',
      createdAt: DateTime.parse(map['created_at']),
      purchasedAt: map['purchased_at'] != null 
          ? DateTime.parse(map['purchased_at']) 
          : null,
    );
  }

  ShoppingListItem copyWith({
    int? id,
    String? name,
    String? barcode,
    List<String>? tagIds,
    bool? isPurchased,
    String? addedBy,
    DateTime? createdAt,
    DateTime? purchasedAt,
  }) {
    return ShoppingListItem(
      id: id ?? this.id,
      name: name ?? this.name,
      barcode: barcode ?? this.barcode,
      tagIds: tagIds ?? this.tagIds,
      isPurchased: isPurchased ?? this.isPurchased,
      addedBy: addedBy ?? this.addedBy,
      createdAt: createdAt ?? this.createdAt,
      purchasedAt: purchasedAt ?? this.purchasedAt,
    );
  }
}

/// مدل تگ برای دسته‌بندی آیتم‌ها
class ShoppingListTag {
  final String id;
  final String nameFa;
  final String nameEn;
  final String colorHex;
  final bool isCustom; // آیا تگ سفارشی است

  const ShoppingListTag({
    required this.id,
    required this.nameFa,
    required this.nameEn,
    required this.colorHex,
    this.isCustom = false,
  });

  String getName(String locale) {
    return locale == 'fa' ? nameFa : nameEn;
  }

  ShoppingListTag copyWith({
    String? id,
    String? nameFa,
    String? nameEn,
    String? colorHex,
    bool? isCustom,
  }) {
    return ShoppingListTag(
      id: id ?? this.id,
      nameFa: nameFa ?? this.nameFa,
      nameEn: nameEn ?? this.nameEn,
      colorHex: colorHex ?? this.colorHex,
      isCustom: isCustom ?? this.isCustom,
    );
  }
}

/// تگ‌های پیش‌فرض
class DefaultTags {
  static const List<ShoppingListTag> tags = [
    ShoppingListTag(id: 'dairy', nameFa: 'لبنیات', nameEn: 'Dairy', colorHex: '#FFB74D'),
    ShoppingListTag(id: 'protein', nameFa: 'پروتئینی', nameEn: 'Protein', colorHex: '#E57373'),
    ShoppingListTag(id: 'grains', nameFa: 'غلات', nameEn: 'Grains', colorHex: '#FFF176'),
    ShoppingListTag(id: 'vegetables', nameFa: 'سبزیجات', nameEn: 'Vegetables', colorHex: '#81C784'),
    ShoppingListTag(id: 'fruits', nameFa: 'میوه‌ها', nameEn: 'Fruits', colorHex: '#AED581'),
    ShoppingListTag(id: 'snacks', nameFa: 'تنقلات', nameEn: 'Snacks', colorHex: '#FFD54F'),
    ShoppingListTag(id: 'beverages', nameFa: 'نوشیدنی‌ها', nameEn: 'Beverages', colorHex: '#4DB6AC'),
    ShoppingListTag(id: 'household', nameFa: 'خانگی', nameEn: 'Household', colorHex: '#90CAF9'),
    ShoppingListTag(id: 'personal_care', nameFa: 'بهداشتی', nameEn: 'Personal Care', colorHex: '#CE93D8'),
    ShoppingListTag(id: 'other', nameFa: 'سایر', nameEn: 'Other', colorHex: '#BDBDBD'),
  ];

  static ShoppingListTag? getById(String id, {List<ShoppingListTag>? customTags}) {
    // First check default tags
    try {
      return tags.firstWhere((tag) => tag.id == id);
    } catch (e) {
      // Then check custom tags
      if (customTags != null) {
        try {
          return customTags.firstWhere((tag) => tag.id == id);
        } catch (e) {
          return null;
        }
      }
      return null;
    }
  }

  static List<ShoppingListTag> getAllTags({List<ShoppingListTag>? customTags}) {
    if (customTags == null || customTags.isEmpty) {
      return tags;
    }
    return [...tags, ...customTags];
  }
}

/// فیلتر برای نمایش آیتم‌ها
enum ShoppingListFilter {
  all,
  purchased,
  pending,
}

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

/// سرویس مدیریت تگ‌های سفارشی
class CustomTagService {
  static const String _prefsKey = 'custom_shopping_tags';

  /// دریافت تگ‌های سفارشی از SharedPreferences
  static Future<List<ShoppingListTag>> loadCustomTags() async {
    final prefs = await SharedPreferences.getInstance();
    final tagsJson = prefs.getString(_prefsKey);
    
    if (tagsJson == null || tagsJson.isEmpty) {
      return [];
    }

    try {
      final List<dynamic> decoded = json.decode(tagsJson);
      return decoded.map((item) => ShoppingListTag(
        id: item['id'] as String,
        nameFa: item['nameFa'] as String,
        nameEn: item['nameEn'] as String,
        colorHex: item['colorHex'] as String,
        isCustom: true,
      )).toList();
    } catch (e) {
      print('Error loading custom tags: $e');
      return [];
    }
  }

  /// ذخیره تگ‌های سفارشی در SharedPreferences
  static Future<void> saveCustomTags(List<ShoppingListTag> tags) async {
    final prefs = await SharedPreferences.getInstance();
    final tagsJson = json.encode(tags.map((tag) => {
      'id': tag.id,
      'nameFa': tag.nameFa,
      'nameEn': tag.nameEn,
      'colorHex': tag.colorHex,
    }).toList());
    await prefs.setString(_prefsKey, tagsJson);
  }

  /// افزودن تگ سفارشی جدید
  static Future<ShoppingListTag?> createCustomTag({
    required String nameFa,
    required String nameEn,
    required String colorHex,
  }) async {
    // Validate name
    if (nameFa.trim().isEmpty && nameEn.trim().isEmpty) {
      return null;
    }

    // Generate unique ID
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final id = 'custom_$timestamp';

    final newTag = ShoppingListTag(
      id: id,
      nameFa: nameFa.trim(),
      nameEn: nameEn.trim(),
      colorHex: colorHex,
      isCustom: true,
    );

    // Load existing tags, add new one, and save
    final existingTags = await loadCustomTags();
    existingTags.add(newTag);
    await saveCustomTags(existingTags);

    return newTag;
  }

  /// حذف تگ سفارشی
  static Future<void> deleteCustomTag(String tagId) async {
    final existingTags = await loadCustomTags();
    existingTags.removeWhere((tag) => tag.id == tagId);
    await saveCustomTags(existingTags);
  }
}
