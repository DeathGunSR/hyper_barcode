# نقشه پیاده‌سازی: بهبودهای بارکد اسکنر، لیست خرید و پنل وردپرس (نسخه 2)

## دستورالعمل وضعیت
- Status: `pending` | `in_progress` | `blocked` | `completed` | `cancelled`
- وابستگی‌ها: Taskهایی که روی هم تکیه می‌کنند، به صورت ترتیبی اجرا شوند.
- اولویت‌ها: `high` (بلاکر یا الزام اصلی کاربر)، `medium` (بهبود مهم)، `low` (پالایش).

---

## بخش ۱: بارکد اسکنر (main.dart)

---

## Task V2-BAR-1: اطمینان از مشکی بودن کامل «قیمت روی جلد» در لیبل PDF

- **شناسه**: T-V2-BAR-1
- **وابستگی**: هیچ
- **اولویت**: high
- **زیرپوشش AC**: AC-BAR-V2-1, FR-BAR-V2-1
- **توضیحات عملی**:
  1. باز کردن تابع `_buildLabel` در `lib/main.dart` (خط 1618 به بعد).
  2. بررسی تمام موارد استفاده از رنگ در ستون «قیمت روی جلد» (خطوط 1743-1773):
     - عنوان «قیمت روی جلد» (خط 1749): اطمینان از `PdfColors.black`.
     - مقدار عددی قیمت روی جلد (خط 1761-1767): اطمینان از `PdfColors.black` برای `color` در `TextStyle`.
  3. بررسی ستون «قیمت فروش» نیز برای اطمینان از اینکه هر دو از یک رنگ مشکی استفاده می‌کنند.
  4. در صورت وجود هر رنگ دیگری (مثل `PdfColors.grey` یا مقادیر هگز غیر #000000)، جایگزین با `PdfColors.black` شود.
  5. حذف هر تغییری که باعث رنگی غیرمشکی برای قیمت روی جلد می‌شد (مثل opacity کمتر از 1 یا color متفاوت).
- **تست محلی (TR)**:
  - TR-TV2BAR1-1 (**rule**): تولید PDF برای محصول با تخفیف → باز کردن خروجی با PDF viewer → بررسی بصری اینکه هر دو قیمت (روی جلد با خط خورده و فروش) رنگ مشکی یکدست دارند. منبع: خروجی PDF.
  - TR-TV2BAR1-2 (**rule**): در کد، تمام `TextStyle`های مربوط به قیمت روی جلد دارای `color: PdfColors.black` هستند. منبع: grep روی `_buildLabel`.
- **Status**: pending
- **Completion Evidence**:

---

## Task V2-BAR-2: بهبود صدای شاتر و لرزش پس از اسکن بارکد

- **شناسه**: T-V2-BAR-2
- **وابستگی**: هیچ
- **اولویت**: high
- **زیرپوشش AC**: AC-BAR-V2-2, FR-BAR-V2-2
- **توضیحات عملی**:
  1. باز کردن تابع `_addBarcode` در `lib/main.dart` (خط 1195 به بعد).
  2. جایگزینی یا بهبود `HapticFeedback.mediumImpact()` و `SystemSound.play(SystemSoundType.click)` فعلی:
     - (الف) افزودن `HapticFeedback.heavyImpact()` (قوی‌تر) به همراه یا به جای mediumImpact.
     - (ب) افزودن `HapticFeedback.vibrate()` برای لرزش طولانی‌تر (اختیاری، اگر سازگار بود).
  3. اگر `SystemSoundType.click` کافی نیست، بررسی سطوح دیگر SystemSound (مثل `alert` یا `preferredSound`) یا ترکیب چند صدای پشت سر هم.
  4. **توجه**: تا حد امکان از افزودن پکیج جدید (مانند audioplayers) اجتناب شود. فقط اگر روش‌های داخلی Flutter ناکافی بودند، سپس پکیج اضافه گردد (با تأیید قبلی).
- **تست محلی (TR)**:
  - TR-TV2BAR2-1 (**rule**): اسکن بارکد روی دستگاه واقعی یا emulator → لرزش واضح‌تر و قوی‌تر از قبل حس شود. منبع: تست دستی.
  - TR-TV2BAR2-2 (**rule**): صدای قابل شنیدن پس از هر اسکن پخش شود (حتی اگر صدای سیستم در حالت متوسط باشد). منبع: تست دستی.
- **Status**: pending
- **Completion Evidence**:

---

## Task V2-BAR-3: بهبود افکت تصویری فلش پس از اسکن (Animation)

- **شناسه**: T-V2-BAR-3
- **وابستگی**: هیچ
- **اولویت**: high
- **زیرپوشش AC**: AC-BAR-V2-3, FR-BAR-V2-3
- **توضیحات عملی**:
  1. باز کردن بخش Stack در `HomePage.build` که `MobileScanner` و `_showScanFlash` را در بر می‌گیرد (خطوط 513-539 main.dart).
  2. جایگزینی Container ساده `_showScanFlash` با یک انیمیشن حرفه‌ای‌تر:
     - **گزینه ۱ (پیشنهادی)**: استفاده از `AnimatedOpacity` + `AnimatedContainer` برای fade-in و fade-out نرم Overlay سفید با مدت زمان ۱۲۰ میلی‌ثانیه ورود + ۱۵۰ میلی‌ثانیه خروج.
     - **گزینه ۲**: ترکیب Overlay سفید + یک آیکون `Icons.check_circle` (سبز رنگ) در مرکز کادر اسکن که با `ScaleTransition` از ۰ به ۱ و سپس محو می‌شود.
  3. در `_addBarcode` تابع، مکانیزم `setState + Future.delayed 150ms` فعلی با یک `AnimationController` بهتر شود (اگر Complex نباشد همچنان Future.delayed با چند مرحله‌ای کار می‌کند).
  4. مدت زمان کل افکت: ۳۰۰-۴۰۰ میلی‌ثانیه.
- **تست محلی (TR)**:
  - TR-TV2BAR3-1 (**rule**): اسکن بارکد → افکت بصری واضح نمایش داده شود (فلش سفید سریع یا تیک سبز) و پس از حداکثر ۴۰۰ میلی‌ثانیه کاملاً ناپدید شود. منبع: تست دستی روی دستگاه.
  - TR-TV2BAR3-2 (**rule**): در طول افکت، اپ هنگ نمی‌کند و اسکن بعدی بلافاصله بعد از اتمام افکت ممکن است. منبع: تست دستی با اسکن سریال چند بارکد.
- **Status**: pending
- **Completion Evidence**:

---

## Task V2-BAR-4: بهبود حذف موردی بارکد (SnackBar Undo)

- **شناسه**: T-V2-BAR-4
- **وابستگی**: هیچ
- **اولویت**: medium
- **زیرپوشش AC**: AC-BAR-V2-4, FR-BAR-V2-4
- **توضیحات عملی**:
  1. باز کردن تابع `_removeBarcode` در `main.dart` (خط 1214) و محل فراخوانی آن در `InkWell` دکمه X (خط 693-705).
  2. پس از حذف، یک `SnackBar` با محتوای «بارکد [xxxx] حذف شد» + دکمه `UNDO` (بازگردانی) نمایش داده شود.
  3. پیاده‌سازی منطق Undo: نگه داشتن کپی از `_barcodes[index]` قبل از حذف و در صورت کلیک UNDO، در همان index دوباره `insert` شود. همچنین `_selectedBarcodeIndices` را در صورت نیاز به‌روز رسانی کند.
- **تست محلی (TR)**:
  - TR-TV2BAR4-1 (**rule**): کلیک روی X یک بارکد → SnackBar با پیام + دکمه UNDO ظاهر شود. منبع: تست دستی.
  - TR-TV2BAR4-2 (**rule**): کلیک روی UNDO → بارکد در همان موقعیت قبلی به لیست بازگردد. منبع: تست دستی.
- **Status**: pending
- **Completion Evidence**:

---

## Task V2-BAR-5: بهبود حذف گروهی بارکد + دیالوگ تأیید

- **شناسه**: T-V2-BAR-5
- **وابستگی**: هیچ
- **اولویت**: high
- **زیرپوشش AC**: AC-BAR-V2-5, FR-BAR-V2-5
- **توضیحات عملی**:
  1. باز کردن تابع `_deleteSelectedBarcodes` در `main.dart` (خط 1251) و محل فراخوانی آن (خط 581).
  2. قبل از حذف واقعی در `_deleteSelectedBarcodes`، یک `showDialog` با AlertDialog نمایش دهد:
     - عنوان: «حذف گروهی بارکدها».
     - محتوا: «آیا از حذف [N] بارکد انتخاب‌شده مطمئن هستید؟ این عملیات قابل بازگشت نیست.»
     - دکمه‌های انصراف (TextButton) + حذف (ElevatedButton با backgroundColor=Colors.red).
  3. فقط در صورت تأیید کاربر، عملیات حذف انجام شود و سپس SnackBar پیام «[N] بارکد با موفقیت حذف شد» نمایش داده شود.
  4. اطمینان از اینکه حالت `_isBarcodeSelectionMode` و `_selectedBarcodeIndices` پس از حذف به درستی ریست می‌شوند.
- **تست محلی (TR)**:
  - TR-TV2BAR5-1 (**rule**): Long Press روی کارت بارکد → انتخاب ۳ آیتم → کلیک Delete → دیالوگ تأیید با عدد ۳ نمایش داده شود. منبع: تست دستی.
  - TR-TV2BAR5-2 (**rule**): Cancel در دیالوگ → هیچ کدام از بارکدها حذف نشوند. منبع: تست دستی.
  - TR-TV2BAR5-3 (**rule**): Confirm در دیالوگ → هر ۳ آیتم از لیست حذف شوند + SnackBar موفقیت ظاهر شود. منبع: تست دستی.
- **Status**: pending
- **Completion Evidence**:

---

## بخش ۲: لیست خرید (Shopping List)

---

## Task V2-SHOP-1: Persistent Login (عدم نمایش دیالوگ نام کاربری در دفعات بعدی)

- **شناسه**: T-V2-SHOP-1
- **وابستگی**: هیچ
- **اولویت**: high
- **زیرپوشش AC**: AC-SHOP-V2-1, FR-SHOP-V2-1
- **توضیحات عملی**:
  1. باز کردن `shopping_list_screen.dart` (خط 70-75) و بررسی منطق `_showMandatoryLoginDialog`.
  2. بررسی اینکه `provider.hasUser` و `provider.username` به درستی از `ShoppingListDatabaseService.getUsername()` (در ShoppingListProvider `_loadUsername` خط 193) بارگذاری می‌شوند.
  3. اطمینان از اینکه:
     - اگر `provider.username != null && provider.username.trim().isNotEmpty` → دیالوگ اصلاً نمایش داده نشود.
     - فقط در صورتی که username null یا خالی باشد، دیالوگ اجباری نمایش داده شود.
  4. بررسی `ShoppingListDatabaseService.saveLocalUser` (خط 291) و `setUserName` در provider (خط 229): تأیید اینکه نام کاربری با `ConflictAlgorithm.replace` به صورت دائمی در SQLite ذخیره می‌گردد.
  5. اگر باگ در شارژ شدن username در initialize وجود داشت، برطرف شود.
- **تست محلی (TR)**:
  - TR-TV2SHOP1-1 (**rule**): پاک کردن داده‌های اپ → ورود به ShoppingListScreen → دیالوگ نام کاربری ظاهر شود → وارد کردن «علی» → ذخیره. منبع: تست دستی.
  - TR-TV2SHOP1-2 (**rule**): بستن کامل اپ → باز کردن مجدد → ورود به ShoppingListScreen → دیالوگ نام کاربری اصلاً نمایش داده نشود و مستقیماً لیست خرید دیده شود. منبع: تست دستی.
- **Status**: pending
- **Completion Evidence**:

---

## Task V2-SHOP-2: Auto-Sync دوره‌ای (Polling شبیه Inbox) + سینک آنی بعد از add/delete

- **شناسه**: T-V2-SHOP-2
- **وابستگی**: T-V2-SHOP-1 (اختیاری، بدون وابستگی مستقیم)
- **اولویت**: high
- **زیرپوشش AC**: AC-SHOP-V2-2, AC-SHOP-V2-3, FR-SHOP-V2-2, FR-SHOP-V2-3
- **توضیحات عملی**:
  1. باز کردن `shopping_list_screen.dart` در `initState` (خط 31-55): بازه `Timer.periodic` فعلی (۳۰ ثانیه) را به **۲۰ ثانیه** تغییر دهید (یا ۱۵ ثانیه، مطابق فرض Q2).
  2. باز کردن `shopping_list_provider.dart`:
     - بررسی `addItem` (خط 271): اطمینان از اینکه انتهای تابع `unawaited(syncWithServer())` فراخوانی شده باشد.
     - بررسی `deleteItem` (خط 398): همین بررسی و اضافه کردن `unawaited(syncWithServer())` در صورت نداشتن.
     - بررسی `togglePurchaseStatus`, `updateItemTags`, `updateItemDetails`, `createTag`, `deleteTag`: اطمینان از سینک آنی در انتهای همه آن‌ها.
  3. اطمینان از اینکه دکمه Sync در AppBar همچنان برای سینک دستی (اضطراری) باقی می‌ماند.
- **تست محلی (TR)**:
  - TR-TV2SHOP2-1 (**rule**): افزودن آیتم جدید در دستگاه A → فوراً `isSyncing` در نشانگر AppBar true شود (دور ۱-۲ ثانیه). منبع: تست دستی + نشانگر همگام‌سازی.
  - TR-TV2SHOP2-2 (**rule**): بدون هیچ فعالیتی در اپ، هر ۲۰ ثانیه یکبار سینک در پس‌زمینه اجرا شود (از طریق لاگ `LoggingService` قابل مشاهده است). منبع: لاگ برنامه.
  - TR-TV2SHOP2-3 (**rule**): حذف یک آیتم → سینک آنی آغاز گردد. منبع: نشانگر همگام‌سازی + لاگ.
- **Status**: pending
- **Completion Evidence**:

---

## Task V2-SHOP-3: Bulk Delete (حذف گروهی کالاها) در لیست خرید + دیالوگ تأیید

- **شناسه**: T-V2-SHOP-3
- **وابستگی**: هیچ
- **اولویت**: high
- **زیرپوشش AC**: AC-SHOP-V2-4, FR-SHOP-V2-4
- **توضیحات عملی**:
  1. باز کردن `shopping_list_screen.dart` و متغیرهای `_selectedItemIds` و `_isItemSelectionMode` (خط 27-28) - این‌ها فعلاً وجود دارند، باید اطمینان از کامل بودن منطق.
  2. بررسی بخش AppBar actions (خط 91-125): اطمینان از اینکه در حالت انتخاب، سه دکمه Select All / Delete Selected / Exit Mode نمایش داده می‌شوند.
  3. بررسی `_showBulkDeleteConfirm` (اگر در کد هست یا باید ساخته شود):
     - ساخت دیالوگ تأیید: «آیا از حذف [N] آیتم انتخاب‌شده مطمئن هستید؟» + دکمه Cancel / Delete (قرمز).
  4. پس از تأیید: iter روی `_selectedItemIds` و فراخوانی `provider.deleteItem(id)` برای هر کدام (یا در صورت وجود متد bulk در provider استفاده از آن). سینک آنی خودکار از طریق `deleteItem` انجام می‌شود.
  5. ورود به حالت انتخاب: Long Press روی یک آیتم ListTile → فعال شدن `_isItemSelectionMode`. همچنین می‌توان یک Checkbox یا نماد انتخاب در گوشه هر آیتم هنگام حالت انتخاب اضافه کرد.
- **تست محلی (TR)**:
  - TR-TV2SHOP3-1 (**rule**): Long Press روی یک آیتم → ورود به حالت انتخاب (آیکون Close و Delete در AppBar ظاهر شود). منبع: تست دستی.
  - TR-TV2SHOP3-2 (**rule**): انتخاب ۲ آیتم → کلیک Delete → دیالوگ تأیید با عدد ۲ ظاهر شود. منبع: تست دستی.
  - TR-TV2SHOP3-3 (**rule**): تأیید → هر دو آیتم از لیست حذف شوند + SnackBar «۲ آیتم حذف شد» نمایش داده شود + سینک آنی آغاز گردد. منبع: تست دستی + نشانگر سینک.
- **Status**: pending
- **Completion Evidence**:

---

## Task V2-SHOP-4: جلوگیری از تگ تکراری (Case-insensitive + Trim)

- **شناسه**: T-V2-SHOP-4
- **وابستگی**: هیچ
- **اولویت**: high
- **زیرپوشش AC**: AC-SHOP-V2-5, FR-SHOP-V2-5
- **توضیحات عملی**:
  1. باز کردن `CustomTagService.createCustomTag` (در مدل یا مربوطه) و `ShoppingListProvider.createTag` (خط 125).
  2. در جایی که مقایسه «تکراری بودن» انجام می‌شود (TagCreateStatus.duplicate check):
     - نرمال‌سازی `nameFa` ورودی: `.trim().toLowerCase()`
     - نرمال‌سازی `nameEn` ورودی: `.trim().toLowerCase()`
     - مقایسه با تگ‌های موجود در `_customTags` با **نرمال‌سازی مشابه** اسم‌ها (case + فاصله).
     - تطبیق به صورت OR: اگر `nameFa_normalized` با هر کدام از تگ‌های موجود همخوانی داشت **یا** `nameEn_normalized` همخوانی داشت → تکراری بود.
  3. در صورت تشخیص تکراری: `TagCreateStatus.duplicate` برگردانده شود و در Screen به کاربر پیام «نام تگ تکراری است» نمایش داده شود.
- **تست محلی (TR)**:
  - TR-TV2SHOP4-1 (**rule**): ساخت تگ با نام فارسی «میوه» → تلاش برای ساخت تگ دوم با نام «میوه» (با فاصله قبل/بعد یا حروف بزرگ/کوچک) → پیام تکراری. منبع: تست دستی.
  - TR-TV2SHOP4-2 (**rule**): ساخت تگ با نام انگلیسی «Fruit» → تلاش برای «FRUIT» یا « fruit » → پیام تکراری. منبع: تست دستی.
- **Status**: pending
- **Completion Evidence**:

---

## Task V2-SHOP-5: جلوگیری از افزودن آیتم (کالا) تکراری به لیست خرید

- **شناسه**: T-V2-SHOP-5
- **وابستگی**: هیچ
- **اولویت**: high
- **زیرپوشش AC**: AC-SHOP-V2-6, FR-SHOP-V2-6
- **توضیحات عملی**:
  1. باز کردن `ShoppingListProvider.addItem` (خط 271).
  2. قبل از `insertItem` (خط 273)، یک بررسی تکراری بودن اضافه کنید:
     - نرمال‌سازی نام آیتم جدید: `item.name.trim().toLowerCase()`
     - نرمال‌سازی بارکد (اگر خالی نباشد): `item.barcode.trim()`
     - جستجو در `_items` برای تطبیق:
       - **اگر بارکد آیتم جدید خالی نبود**: تطبیق بر اساس (`barcode_normalized == item_i.barcode.trim()` **AND** `name_normalized == item_i.name.trim().toLowerCase()`).
       - **اگر بارکد خالی بود**: تطبیق بر اساس (`name_normalized == item_i.name.trim().toLowerCase()` **AND** `added_by == item.addedBy` (همان کاربر)).
  3. اگر تطبیقی پیدا شد → `addItem` بدون درج، `false` برگرداند.
  4. در `shopping_list_screen.dart` تابع `_showAddItemDialog` (خط 741): بعد از فراخوانی `await provider.addItem(newItem)` بررسی شود که اگر `false` برگشت، `SnackBar` با پیام «این کالا قبلاً در لیست خرید وجود دارد» نمایش داده شود.
- **تست محلی (TR)**:
  - TR-TV2SHOP5-1 (**rule**): افزودن آیتم «شیر» با بارکد خالی توسط کاربر «علی» → تلاش برای افزودن دوباره «شیر» (یا « شیر » یا «شیر» با حروف بزرگ) توسط همان کاربر → پیام کالای تکراری + عدم ذخیره آیتم دوم. منبع: تست دستی.
  - TR-TV2SHOP5-2 (**rule**): افزودن آیتم «شکلات» با بارکد «123456» → تلاش برای افزودن آیتمی با نام «شکلات» و بارکد «123456» (حتی اگر کاربر متفاوت باشد) → پیام تکراری. منبع: تست دستی.
- **Status**: pending
- **Completion Evidence**:

---

## بخش ۳: پنل مدیریت وردپرس (barcodify-shopping-list.php)

---

## Task V2-WP-1: توسعه ساختار منوی چندصفحه‌ای در WP Admin + داشبورد

- **شناسه**: T-V2-WP-1
- **وابستگی**: هیچ
- **اولویت**: high
- **زیرپوشش AC**: AC-WP-1, AC-WP-2, FR-WP-1, FR-WP-2
- **توضیحات عملی**:
  1. باز کردن `wordpress-plugin/barcodify-shopping-list.php`.
  2. در تابع `bl_shopping_list_add_admin_menu` (خط 350)، جایگزینی `add_menu_page` تک‌صفحه‌ای با ساختار چندصفحه‌ای:
     - `add_menu_page` والد با عنوان «مدیریت لیست خرید» (وظیفه داشبورد).
     - `add_submenu_page` سه بار: (۱) داشبورد (همون والد), (۲) کاربران, (۳) لیست خرید.
  3. ساخت سه تابع جداگانه برای هر صفحه:
     - `bl_admin_page_dashboard()`: کارت‌های آمار + جدول آخرین آیتم‌ها.
     - `bl_admin_page_users()`: جدول مدیریت کاربران.
     - `bl_admin_page_items()`: جدول مدیریت لیست خرید.
  4. برای داشبورد:
     - ۴ کارت با `class="card"` یا `div` با استایل dashbord stats:
       - کل کاربران: `$wpdb->get_var("SELECT COUNT(*) FROM $table_users")`
       - کل آیتم‌ها: `$wpdb->get_var("SELECT COUNT(*) FROM $items_table")`
       - خریداری‌شده: `COUNT WHERE is_purchased = 1`
       - در انتظار خرید: `COUNT WHERE is_purchased = 0`
     - جدول «آخرین ۱۰ آیتم»: SELECT * ORDER BY created_at DESC LIMIT 10 با ستون‌های نام کالا، کاربر، تاریخ.
- **تست محلی (TR)**:
  - TR-TV2WP1-1 (**rule**): فعال کردن پلاگین در وردپرس → در منوی چپ سه زیرمنوی داشبورد/کاربران/لیست خرید زیر منوی اصلی ظاهر شود. منبع: WP Admin.
  - TR-TV2WP1-2 (**rule**): صفحه داشبورد شامل ۴ کارت آمار رنگی و جدول آخرین ۱۰ آیتم باشد. منبع: اسکرین‌شات یا بازرسی مستقیم.
- **Status**: pending
- **Completion Evidence**:

---

## Task V2-WP-2: صفحه مدیریت کاربران (جدول + جستجو + Bulk Actions)

- **شناسه**: T-V2-WP-2
- **وابستگی**: T-V2-WP-1
- **اولویت**: high
- **زیرپوشش AC**: AC-WP-3, FR-WP-3
- **توضیحات عملی**:
  1. ساخت تابع `bl_admin_page_users()`.
  2. ساخت HTML form با جعبه جستجو `<input type="search" name="s_user">` + دکمه Apply.
  3. بررسی پارامتر GET `s_user` و `WHERE username LIKE %s` در query.
  4. ساخت جدول HTML با کلاس‌های `wp-list-table widefat fixed striped` و ستون‌های:
     - CB (checkbox برای انتخاب گروهی)
     - ID
     - نام کاربری (Username)
     - شماره تلفن (Phone Number)
     - تاریخ عضویت (Created At)
     - آخرین سینک (Last Sync)
     - وضعیت فعال/غیرفعال (با بلیط رنگی یا badge)
     - عملیات: ویرایش/حذف (اختیاری، حداقل حذف)
  5. Bulk Actions: Dropdown بالای جدول با گزینه‌های «فعال کردن»، «غیرفعال کردن»، «حذف کاربر».
  6. **Security**: برای حذف/فعال/غیرفعال: `wp_nonce_field` + `check_admin_referer('bl_bulk_users')` + `current_user_can('manage_bl_shopping_list')`.
  7. Handle POST برای Bulk: گرفتن `$wpdb->query` یا delete با `IN (...)` روی آرایه ID.
- **تست محلی (TR)**:
  - TR-TV2WP2-1 (**rule**): باز کردن صفحه «کاربران» → جدول با تمام ستون‌های بالا نمایش داده شود و ردیف‌ها با striped background نمایش داده شوند. منبع: WP Admin.
  - TR-TV2WP2-2 (**rule**): جستجو برای نام کاربری خاص (مثلاً «علی») → فقط ردیف‌های مشابه نمایش داده شوند. منبع: تست دستی.
  - TR-TV2WP2-3 (**rule**): انتخاب چند کاربر → انتخاب «حذف» → Apply → تأیید → کاربران حذف شوند و پیام notice-success نمایش داده شود. منبع: تست دستی.
- **Status**: pending
- **Completion Evidence**:

---

## Task V2-WP-3: صفحه مدیریت لیست خرید (جدول + جستجو + فیلترها)

- **شناسه**: T-V2-WP-3
- **وابستگی**: T-V2-WP-1
- **اولویت**: high
- **زیرپوشش AC**: AC-WP-4, FR-WP-4
- **توضیحات عملی**:
  1. ساخت تابع `bl_admin_page_items()`.
  2. بخش فیلترها:
     - جستجو بر اساس نام کالا یا بارکد: input search + دکمه Apply.
     - Dropdown فیلتر کاربر (لیست همه کاربران از bl_users).
     - Dropdown فیلتر وضعیت خریداری‌شده: همه / خریداری‌شده / در انتظار.
     - Dropdown فیلتر تگ (گزینه‌های تگ‌های منحصر به فرد از bl_shopping_items).
  3. ساخت جدول HTML با کلاس‌های wp-list-table و ستون‌های:
     - CB (checkbox)
     - ID
     - نام کالا (Name) با امکان quick edit حذف.
     - بارکد (Barcode)
     - تگ (Tag) با رنگ بندی ساده
     - وضعیت (Purchased / Pending) با بلیط رنگی (سبز/نارنجی).
     - افزوده توسط (Added by: نام کاربری)
     - تاریخ ایجاد (Created at)
     - تاریخ خریداری (Purchased at, در صورت خریداری‌شده)
     - عملیات: «حذف» (link با hover)
  4. Query دیتابیس با فیلترهای اعمال‌شده + LIMIT + pagination (برای لیست‌های طولانی).
- **تست محلی (TR)**:
  - TR-TV2WP3-1 (**rule**): باز کردن صفحه «لیست خرید» → جدول شامل تمام ستون‌های بالا، با striped و تناوب رنگ، نمایش داده شود. منبع: WP Admin.
  - TR-TV2WP3-2 (**rule**): جستجو نام کالای خاص → فقط ردیف‌های متناظر نمایش داده شوند. منبع: تست دستی.
  - TR-TV2WP3-3 (**rule**): فیلتر «خریداری‌شده» → فقط ردیف‌های خریداری‌شده نمایش داده شوند. منبع: تست دستی.
- **Status**: pending
- **Completion Evidence**:

---

## Task V2-WP-4: حذف تکی و گروهی (Bulk Delete) آیتم‌های لیست خرید در WP Admin

- **شناسه**: T-V2-WP-4
- **وابستگی**: T-V2-WP-3
- **اولویت**: high
- **زیرپوشش AC**: AC-WP-5, AC-WP-6, FR-WP-5, FR-WP-6
- **توضیحات عملی**:
  1. در صفحه لیست خرید:
     - **حذف تکی**: هر ردیف در ستون عملیات، لینک `<a class="submitdelete deletion">حذف</a>` دارد. href شامل `?page=...&action=delete_item&id=X` و `wp_create_nonce('bl_delete_item_' . $id)` باشد.
     - هنگام load صفحه، بررسی `$_GET['action'] == 'delete_item'` و `id` → `check_admin_referer` → `$wpdb->delete(...)` → `admin_notice` موفقیت.
  2. **Bulk Delete**:
     - Dropdown Bulk Actions بالای جدول شامل گزینه «حذف» باشد.
     - فرم action به همین صفحه (PHP_SELF) و method POST.
     - بررسی `$_POST['action'] == 'bulk_delete'` یا `$_POST['action2']` → `check_admin_referer('bl_bulk_items')` → گرفتن آرایه `item_ids` از $_POST → `$wpdb->query(DELETE ... WHERE id IN (...))` با `implode(',', array_map('intval', $ids))`.
     - نمایش admin_notice با تعداد آیتم‌های حذف‌شده.
  3. **Security**: تمام عملیات حذف فقط با nonce معتبر + capability `manage_bl_shopping_list` + sanitize ورودی‌ها انجام شود.
- **تست محلی (TR)**:
  - TR-TV2WP4-1 (**rule**): کلیک روی لینک «حذف» در یک ردیف → نمایش تأیید (confirm javascript ساده) → تایید → ردیف حذف شود و پیام «۱ آیتم حذف شد» به رنگ سبز ظاهر شود. منبع: تست دستی.
  - TR-TV2WP4-2 (**rule**): انتخاب ۳ آیتم با checkbox → انتخاب «حذف» از Bulk → Apply → تأیید → ۳ ردیف حذف شوند و پیام «۳ آیتم با موفقیت حذف شد» نمایش داده شود. منبع: تست دستی.
  - TR-TV2WP4-3 (**rule**): تلاش حذف بدون nonce (URL مستقیم) → خطای security یا عدم انجام عملیات. منبع: تست دستی.
- **Status**: pending
- **Completion Evidence**:

---

## Task V2-WP-5: بهبود UI/UX و Security کامل پنل (Nonce, Capability, Noticeها)

- **شناسه**: T-V2-WP-5
- **وابستگی**: T-V2-WP-1, T-V2-WP-2, T-V2-WP-3, T-V2-WP-4
- **اولویت**: medium
- **زیرپوشش AC**: AC-WP-7, FR-WP-7, FR-WP-8
- **توضیحات عملی**:
  1. **Security Audit**:
     - در تمام صفحات، ابتدا `!current_user_can('manage_bl_shopping_list')` → `wp_die(__('You do not have sufficient permissions to access this page.'))`.
     - تمام فرم‌ها دارای `wp_nonce_field('bl_action_name')` هستند و در handle POST `check_admin_referer('bl_action_name')` فراخوانی می‌شود.
     - تمام ورودی‌های GET/POST با `sanitize_text_field`, `intval`, `esc_sql` sanitize می‌شوند.
     - خروجی‌ها در HTML با `esc_html`, `esc_attr`, `esc_url` escape می‌شوند.
  2. **Noticeها**:
     - پس از هر عملیات موفق: `<div class="notice notice-success is-dismissible"><p>پیام موفقیت</p></div>`.
     - پس از خطا: `<div class="notice notice-error is-dismissible"><p>پیام خطا</p></div>`.
     - استفاده از `admin_notices` action یا مستقیم در صفحه.
  3. **UI Polish**:
     - دکمه‌ها: کلاس‌های `button-primary`, `button-secondary`, `button-link-delete`.
     - ردیف‌های جدول: `$alternate = '';` و در هر ردیف `$alternate = ($alternate === '' ? ' alternate' : '');` + کلاس `class="row-actions"` برای عملیات hover.
     - بلیط وضعیت (badge): `<span class="dashicons dashicons-yes" style="color:#46b450;"></span>` برای خریداری‌شده و clock برای pending.
     - Pagination: برای لیست‌های بیش از 50 ردیف (LIMIT با OFFSET و لینک‌های صفحه‌بندی).
- **تست محلی (TR)**:
  - TR-TV2WP5-1 (**rule**): ورود با کاربر با نقش subscriber → تلاش دسترسی مستقیم به page=bl-... → پیام عدم دسترسی نمایش داده شود. منبع: تست دستی با دو کاربر.
  - TR-TV2WP5-2 (**rubric**): کیفیت UI پنل (0-5). معیارها: هماهنگی با WP Admin (۱ نمره)، کلاس‌های button/list-table/notice صحیح (۱ نمره)، تناوب رنگ ردیف‌ها + cursor pointer روی ردیف (۱ نمره)، بلیط رنگی وضعیت خریداری‌شده (۱ نمره)، noticeهای colored برای موفقیت/خطا (۱ نمره). **آستانه قبولی: ≥۴**. منبع: اسکرین‌شات از تمام سه صفحه.
- **Status**: pending
- **Completion Evidence**:

---

## بخش ۴: اصلاحات نهایی و ساخت

---

## Task V2-FINAL-1: اجرای flutter analyze و اصلاح لینت‌ها

- **شناسه**: T-V2-FINAL-1
- **وابستگی**: تمام تسک‌های Flutter (V2-BAR*, V2-SHOP*)
- **اولویت**: high
- **زیرپوشش AC**: همه ACهای بخش A و B
- **توضیحات عملی**:
  1. اجرای `flutter pub get` → `flutter analyze` در ریشه پروژه.
  2. برطرف کردن تمام خطاها و warningهای جدی (مثل unused import, missing const, undefined method).
  3. اطمینان از اینکه خطای analyzer در سطح Project صفر باشد.
- **تست محلی (TR)**:
  - TR-TV2FIN1-1 (**rule**): خروجی `flutter analyze` بدون خطای `error` باشد (warningها در صورت ضرورت می‌توانند باقی بمانند ولی حداقل شوند). منبع: خروجی ترمینال.
- **Status**: pending
- **Completion Evidence**:

---

## Task V2-FINAL-2: اجرای flutter build apk (debug) و تأیید موفقیت آمیز بودن بیلد

- **شناسه**: T-V2-FINAL-2
- **وابستگی**: T-V2-FINAL-1
- **اولویت**: high
- **زیرپوشش AC**: همه ACها
- **توضیحات عملی**:
  1. اجرای `flutter build apk --debug` از ریشه پروژه.
  2. بررسی موفقیت‌آمیز بودن Build. در صورت خطا:
     - ردیابی خطا → اعمال اصلاح → بیلد مجدد.
  3. تأیید اینکه فایل APK در `build/app/outputs/flutter-apk/` تولید شده است.
- **تست محلی (TR)**:
  - TR-TV2FIN2-1 (**rule**): دستور `flutter build apk --debug` با exit code 0 خاتمه یابد و فایل app-debug.apk تولید شود. منبع: خروجی ترمینال + وجود فایل خروجی.
- **Status**: pending
- **Completion Evidence**:
