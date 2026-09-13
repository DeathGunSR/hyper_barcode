# Barcodify Shopping List - WordPress Plugin

## توضیحات / Description

این پلاگین وردپرس یک REST API برای همگام‌سازی چک‌لیست خرید مشترک در اپلیکیشن Barcodify فراهم می‌کند.

This WordPress plugin provides a REST API for synchronizing shared shopping lists in the Barcodify mobile application.

## نصب / Installation

1. پوشه `barcodify-shopping-list` را در `/wp-content/plugins/` آپلود کنید
   Upload the `barcodify-shopping-list` folder to `/wp-content/plugins/`

2. پلاگین را از بخش "افزونه‌ها" در وردپرس فعال کنید
   Activate the plugin from the "Plugins" section in WordPress

3. جداول دیتابیس به صورت خودکار با پیشوند `bl_` ساخته می‌شوند
   Database tables will be automatically created with `bl_` prefix

## جداول دیتابیس / Database Tables

پلاگین دو جدول سفارشی ایجاد می‌کند:

The plugin creates two custom tables:

### `wp_bl_shopping_items`
- `id`: شناسه یکتا
- `name`: نام کالا
- `barcode`: بارکد
- `tag`: دسته‌بندی
- `is_purchased`: وضعیت خرید (0/1)
- `added_by`: اضافه‌کننده
- `created_at`: تاریخ ایجاد
- `purchased_at`: تاریخ خرید
- `synced_at`: تاریخ آخرین همگام‌سازی

### `wp_bl_users`
- `id`: شناسه یکتا
- `username`: نام کاربری
- `phone_number`: شماره موبایل
- `created_at`: تاریخ ایجاد
- `last_sync`: آخرین همگام‌سازی
- `is_active`: وضعیت فعال بودن

## اندپوینت‌های REST API

### آیتم‌ها / Items

#### دریافت همه آیتم‌ها
```
GET https://ebimarket.ir/wp-json/bl/v1/items
```

#### افزودن آیتم جدید
```
POST https://ebimarket.ir/wp-json/bl/v1/items
Content-Type: application/json

{
  "name": "شیر",
  "barcode": "6261234567890",
  "tag": "dairy",
  "added_by": "ali"
}
```

#### بروزرسانی وضعیت خرید
```
PUT https://ebimarket.ir/wp-json/bl/v1/items/{id}
Content-Type: application/json

{
  "is_purchased": 1,
  "purchased_at": "2024-01-15T10:30:00"
}
```

#### حذف آیتم
```
DELETE https://ebimarket.ir/wp-json/bl/v1/items/{id}
```

### کاربران / Users

#### دریافت کاربران
```
GET https://ebimarket.ir/wp-json/bl/v1/users
GET https://ebimarket.ir/wp-json/bl/v1/users?username=ali
```

#### ثبت کاربر جدید
```
POST https://ebimarket.ir/wp-json/bl/v1/users
Content-Type: application/json

{
  "username": "ali",
  "phone_number": "09123456789"
}
```

### همگام‌سازی / Sync

```
POST https://ebimarket.ir/wp-json/bl/v1/sync
```

## صفحات مدیریت / Admin Pages

پس از فعال‌سازی، یک منوی جدید به نام "Shopping List" به پیشخوان وردپرس اضافه می‌شود که شامل:
- آمار کلی آیتم‌ها و کاربران
- لیست اندپوینت‌های API
- اطلاعات جداول دیتابیس

After activation, a new "Shopping List" menu will be added to WordPress admin dashboard including:
- Overall statistics of items and users
- List of API endpoints
- Database table information

## امنیت / Security

در حال حاضر دسترسی به API عمومی است. برای محیط تولید، توصیه می‌شود:

Currently, API access is public. For production, it's recommended to:

1. احراز هویت با توکن JWT یا OAuth اضافه کنید
   Add JWT or OAuth authentication

2. محدودیت نرخ درخواست (Rate Limiting) اعمال کنید
   Implement rate limiting

3. فقط به کاربران ثبت‌نام شده اجازه دسترسی دهید
   Restrict access to registered users only

## سازگاری / Compatibility

- WordPress 5.0+
- PHP 7.4+
- MySQL 5.7+ / MariaDB 10.3+

## مجوز / License

GPL v2 or later
