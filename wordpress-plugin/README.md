# Barcodify Shopping List - WordPress Plugin

## توضیحات / Description

این پلاگین وردپرس یک REST API برای همگام‌سازی چک‌لیست خرید مشترک در اپلیکیشن Barcodify فراهم می‌کند.

This WordPress plugin provides a REST API for synchronizing shared shopping lists in the Barcodify mobile application.

> **v3.1.0 — API v2 hardened (Phase 1.1).** Every change-log row now stores an
> **immutable snapshot** of the resource at event time (`payload_json`), so a sync
> response is never rebuilt from current state — the historical order
> `Milk → Milk 2 → DELETE → Milk 3` is delivered exactly. Idempotent creates use a
> **durable operation id** (the item row carries it, plus a queryable
> `GET /barcodify/v2/operations/{key}`), and the initial backfill is
> **restart-safe and checkpointed**.
> The complete contract lives in [`docs/API_V2.md`](../docs/API_V2.md).
> API v1 (`bl/v1`) below stays as the legacy/compatibility layer for the current Flutter client.

## نصب / Installation

1. پوشه `barcodify-shopping-list` را در `/wp-content/plugins/` آپلود کنید
   Upload the `barcodify-shopping-list` folder to `/wp-content/plugins/`

2. پلاگین را از بخش "افزونه‌ها" در وردپرس فعال کنید
   Activate the plugin from the "Plugins" section in WordPress

3. جداول دیتابیس به صورت خودکار با پیشوند `bl_` ساخته می‌شوند
   Database tables will be automatically created with `bl_` prefix

4. مهاجرت اسکیمای نسخه ۵ و backfill به‌صورت خودکار و قابل‌ازسرگیری اجرا می‌شود
   The schema-v5 migration and the resumable backfill run automatically

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
> v1 delete is a **soft delete** (tombstone) since v3.0.0 and v1 reads exclude
> tombstoned rows — a server-side compatibility mitigation, not a full fix.
> See `docs/API_V2.md` §13.

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

### v2 (barcodify/v2) — سینک جدید

```
GET  /wp-json/barcodify/v2/products/sync?cursor=0&limit=200
GET  /wp-json/barcodify/v2/items/sync?cursor=0&limit=200
POST /wp-json/barcodify/v2/items            (Idempotency-Key)
GET  /wp-json/barcodify/v2/operations/{key}
GET  /wp-json/barcodify/v2/backfill/status
```

Full contract: [`docs/API_V2.md`](../docs/API_V2.md).

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
   Implement rate limiting (v2 already ships a per-IP limiter — see `docs/API_V2.md` §15.3)
3. فقط به کاربران ثبت‌نام شده اجازه دسترسی دهید
   Restrict access to registered users only

> **⚠ Production gate:** v2 is currently **public and rate-limited only**. It is
> **not production-secure against catalog scraping**. Authentication is a
> prerequisite before production deployment (`docs/API_V2.md` §15.4).
>
> **⚠ Never embed WooCommerce consumer key/secret in the mobile app.** The
> client must not carry store credentials; rotate any key that has ever shipped.

## جداول نسخه ۳ / Tables (v3.0.0)

به جداول قبلی، این جداول اضافه می‌شوند:

- `bl_shopping_items` (扩展): `updated_at`, `revision`, `deleted_at` (tombstone), `tags_json`
- `bl_tags` — تگ‌های سلسله‌مراتبی (parent_id، revision، tombstone)
- `bl_item_tags` — رابطه چند‌به‌چند آیتم/تگ
- `bl_product_changes` — change log محصولات (منبع cursor سینک محصولات)
- `bl_item_changes` — change log آیتم‌ها (منبع cursor سینک لیست خرید)
- `bl_idempotency` — کلیدهای Idempotency-Key برای createهای تکراری‌ناپذیر

## تغییرات نسخه ۳.۱.۰ / Phase 1.1 changes (schema v5)

- `bl_product_changes.payload_json` و `bl_item_changes.payload_json` — snapshot
  غیرقابل‌تغییر هر event؛ endpoint سینک فقط از همین snapshot پاسخ می‌سازد
  (docs §4.2)
- `bl_shopping_items.client_operation_id` (UNIQUE) — نشانه‌ی دائمی عملیات کلاینت؛
  retry با همان کلید هرگز آیتم دوم نمی‌سازد (docs §8.3)
- `bl_idempotency`: ستون‌های `status`, `resource_type`, `resource_id`,
  `updated_at_gmt` + نگه‌داشت ۹۰ روزه (به‌جای ۴۸ ساعت) و endpoint وضعیت عملیات
- backfill محصولات/آیتم‌ها: دسته‌ای، checkpoint‌دار، idempotent و قابل‌ازسرگیری
  (`bl_v2_backfill_products`, `bl_v2_backfill_items`) + `GET /barcodify/v2/backfill/status`
- خطاهای v2 (از جمله 429) همیشه در envelope قرارداد برمی‌گردند و
  `Retry-After` واقعی دارند

مهاجرت خودکار و idempotent است (`bl_shopping_list_db_version` → 5) و داده‌های قبلی حفظ می‌شوند.

## تست‌ها / Tests

بدون نیاز به WordPress (فقط PHP + PHPUnit):

Without WordPress (PHP + PHPUnit only):

```bash
cd wordpress-plugin
php tests/tools/phpunit-9.phar --testsuite pure   # یا: phpunit --testsuite pure
php tests/tools/real-source-check.php             # اجرای کد واقعی پلاگین بدون وردپرس
php tests/tools/static-contract-check.php         # اعتبارسنجی استاتیک suiteهای integration
```

`tests/tools/phpunit-9.phar` یک PHPUnit 9.6 همراه است تا اجرا به نصب global
وابسته نباشد؛ اگر PHPUnit نصب دارید، همان `phpunit` کافی است.

تست‌های integration به bootstrap وردپرس نیاز دارند:

Integration tests need a WordPress bootstrap:

```bash
export WP_TESTS_DIR=/tmp/wordpress-tests-lib
BARCODIFY_TEST_INTEGRATION=1 phpunit --testsuite integration
```

بدون آن، suiteهای integration به‌صورت خودکار skip می‌شوند و تست‌های pure اجرا می‌شوند.

Without it, the integration suites self-skip with a clear message while the pure suite runs.

## سازگاری / Compatibility

- WordPress 5.0+
- PHP 7.4+
- MySQL 5.7+ / MariaDB 10.3+

## مجوز / License

GPL v2 or later
