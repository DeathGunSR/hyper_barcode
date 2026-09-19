import 'package:flutter/material.dart';

/// مدل آیتم چک‌لیست خرید
class ShoppingListItem {
  final int? id;
  final String name;
  final String barcode;
  final List<String> tags; // تغییر از String tag به List<String> tags
  final bool isPurchased;
  final String addedBy; // نام کاربری اضافه‌کننده
  final DateTime createdAt;
  final DateTime? purchasedAt;

  ShoppingListItem({
    this.id,
    required this.name,
    required this.barcode,
    List<String>? tags, // تغییر یافته
    this.isPurchased = false,
    required this.addedBy,
    required this.createdAt,
    this.purchasedAt,
  }) : tags = tags ?? ['other']; // مقدار پیش‌فرض

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'barcode': barcode,
      'tags': tags.join(','), // ذخیره به صورت رشته CSV
      'is_purchased': isPurchased ? 1 : 0,
      'added_by': addedBy,
      'created_at': createdAt.toIso8601String(),
      'purchased_at': purchasedAt?.toIso8601String(),
    };
  }

  factory ShoppingListItem.fromMap(Map<String, dynamic> map) {
    String tagsData = map['tags'] ?? map['tag'] ?? 'other'; // پشتیبانی از فیلد قدیمی
    List<String> tagsList = tagsData.split(',').where((t) => t.trim().isNotEmpty).toList();
    if (tagsList.isEmpty) tagsList = ['other'];
    
    return ShoppingListItem(
      id: map['id'],
      name: map['name'] ?? '',
      barcode: map['barcode'] ?? '',
      tags: tagsList,
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
    List<String>? tags,
    bool? isPurchased,
    String? addedBy,
    DateTime? createdAt,
    DateTime? purchasedAt,
  }) {
    return ShoppingListItem(
      id: id ?? this.id,
      name: name ?? this.name,
      barcode: barcode ?? this.barcode,
      tags: tags ?? List.from(this.tags),
      isPurchased: isPurchased ?? this.isPurchased,
      addedBy: addedBy ?? this.addedBy,
      createdAt: createdAt ?? this.createdAt,
      purchasedAt: purchasedAt ?? this.purchasedAt,
    );
  }
  
  /// بررسی اینکه آیا آیتم تگ خاصی دارد
  bool hasTag(String tagId) => tags.contains(tagId);
  
  /// افزودن تگ
  ShoppingListItem addTag(String tagId) {
    if (!tags.contains(tagId)) {
      return copyWith(tags: [...tags, tagId]);
    }
    return this;
  }
  
  /// حذف تگ
  ShoppingListItem removeTag(String tagId) {
    if (tags.contains(tagId)) {
      return copyWith(tags: tags.where((t) => t != tagId).toList());
    }
    return this;
  }
}

/// مدل تگ برای دسته‌بندی آیتم‌ها
class ShoppingListTag {
  final String id;
  final String nameFa;
  final String nameEn;
  final String colorHex;
  final bool isCustom;

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
}

/// تگ‌های پیش‌فرض
class DefaultTags {
  static const List<ShoppingListTag> _defaultTags = [
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

  static List<ShoppingListTag> get tags => _defaultTags;

  static ShoppingListTag? getById(String id) {
    try {
      return _defaultTags.firstWhere((tag) => tag.id == id);
    } catch (e) {
      return null;
    }
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
