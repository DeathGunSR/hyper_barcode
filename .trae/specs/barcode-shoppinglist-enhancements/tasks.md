# نقشه پیاده‌سازی: بهبودهای اسکن بارکد، لیست خرید و عمومی

## دستورالعمل وضعیت
- Status: `pending` | `in_progress` | `blocked` | `completed` | `cancelled`
- وابستگی‌ها: Taskهایی که روی هم تکیه می‌کنند، به صورت ترتیبی اجرا شوند.
- اولویت‌ها: `high` (بلاکر یا الزام اصلی کاربر)، `medium` (بهبود مهم)، `low` (پالایش).

---

## Task 1: نمایش میزان پیشرفت همگام‌سازی WooCommerce در HomePage

- **شناسه**: T-01
- **وابستگی**: هیچ
- **اولویت**: high
- **زیرپوشش AC**: AC-BARCODE-1
- **توضیحات**:
  - `HomePage` (در `main.dart`) متغیرهای `_syncProgress`, `_syncTotalPages`, `_syncCurrentPage` و `_syncFetchedProducts` اضافه شوند.
  - در `_runBackgroundSync` هر شروع صفحه با `setState` مقدار `_syncCurrentPage = page` و درصد پیشرفت تخمینی `(page / estimatedPages) * 100` (با حدس تعداد کل صفحات بر اساس صفحه آخر) بروزرسانی شود.
  - در Container نوار همگام‌سازی (lines 306-342 `main.dart`)، در حالت `_isSyncing` علاوه بر `CircularProgressIndicator` کوچک، درصد یا «صفحه X از Y» نمایش داده شود.
  - استفاده از `SyncProvider` برای مشاهده وضعیت همگام‌سازی (اختیاری اما پیشنهادی) با شروع همگام‌سازی WooCommerce از طریق آن.
- **تست محلی (TR)**:
  - TR-T01-1 (**rule**): اجرای همگام‌سازی → UI درصد (یا صفحه X/Y) را به صورت لحظه‌ای تغییر می‌دهد و در پایان به 100% یا «اتمام» می‌رسد. منبع: بازرسی بصری از HomePage.
  - TR-T01-2 (**rule**): اگر همگام‌سازی در صفحه ۵ متوقف شود (تست دستی)، UI در همان درصد/صفحه متوقف نمی‌ماند و خطا را در SnackBar نشان می‌دهد (نشان‌دهنده پایان). منبع: شبیه‌سازی قطع شبکه.
- **Status**: pending
- **Completion Evidence**:

---

## Task 2: حذف گزینه «درباره» و فعال‌سازی تنظیمات قالب PDF در PopupMenu HomePage

- **شناسه**: T-02
- **وابستگی**: هیچ
- **اولویت**: high
- **زیرپوشش AC**: AC-BARCODE-2، پیش‌نیاز AC-BARCODE-3
- **توضیحات**:
  - `PopupMenuButton` در `HomePage.build` (AppBar actions, `main.dart` خط 288) گزینه `about` کاملاً حذف شود.
  - انتخاب گزینه `settings` دیالوگ `_showPdfTemplateSettings` را فراخوانی کند.
  - ساخت دیالوگ `_showPdfTemplateSettings` شامل: Slider یا TextField برای: `labelsPerRow`, `labelsPerColumn`, `labelWidthMm`, `labelHeightMm`, `marginTopMm/BottomMm/LeftMm/RightMm`, `gapHorizontalMm`, `gapVerticalMm`. SwitchListTile برای: «نمایش شماره بارکد متنی»، «نمایش قیمت روی جلد (در صورت تخفیف اجباری)».
  - ذخیره و بارگذاری مقادیر از SharedPreferences با کلید `pdf_label_template_v1`. مقادیر `LabelConfig` قبلاً در `main.dart` تعریف شده است؛ از همان مدل برای مقادیر استفاده شود و علاوه بر آن، فیلدهای `showBarcodeText`, `forceShowCoverPriceOnDiscount` اضافه گردند.
- **تست محلی (TR)**:
  - TR-T02-1 (**rule**): PopupMenu در AppBar فقط یک گزینه «تنظیمات» دارد. منبع: اسکرین‌شات یا بازرسی بصری.
  - TR-T02-2 (**rule**): باز کردن تنظیمات و تغییر labelsPerRow از 3 به 4 و ذخیره → بستن و باز کردن مجدد تنظیمات → مقدار 4 نمایش داده می‌شود (پایداری در SharedPreferences). منبع: تست دستی با ۲ بار باز کردن دیالوگ.
  - TR-T02-3 (**rule**): همه فیلدهای الزامی FR-BARCODE-3 در دیالوگ وجود دارند. منبع: بازرسی بصری.
- **Status**: pending
- **Completion Evidence**:

---

## Task 3: رفع خطای Software caused connection abort با تلاش مجدد هوشمند

- **شناسه**: T-03
- **وابستگی**: هیچ
- **اولویت**: high
- **زیرپوشش AC**: AC-BARCODE-4
- **توضیحات**:
  - در `_runBackgroundSync` (در `main.dart`)، هر درخواست `http.get` داخل یک `try-catch` جداگانه با retry خودکار قرار بگیرد.
  - `NetworkClient.mapError` بررسی شود که `SocketException` با پیام «Software caused connection abort» به عنوان `NetworkFailureKind` قابل تلاش مجدد در نظر گرفته شود (اخیراً به عنوان `noInternet` طبقه‌بندی می‌شود که retryable است، درست است). اگر طبقه‌بندی دیگری لازم بود اضافه شود.
  - حداکثر ۳ تلاش برای هر صفحه با backoff تصاعدی ۱ ثانیه، ۲ ثانیه، ۴ ثانیه.
  - در صورت شکست نهایی صفحه: آن صفحه را ثبت کنید در لاگ (`AppLogger().error(...)`) و ادامه به صفحه بعدی (توقف کامل نداده شود). در پایان، تعداد صفحات دریافت‌نشده به کاربر در SnackBar نمایش داده شود.
  - متغیر `_syncFailedPages` (List<int>) اضافه شود تا در گزارش پایان استفاده گردد.
- **تست محلی (TR)**:
  - TR-T03-1 (**rule**): خطای شبیه‌سازی‌شده برای صفحه ۵ → حداقل ۲ تلاش مجدد انجام می‌شود (از روی لاگ قابل مشاهده). منبع: لاگ برنامه.
  - TR-T03-2 (**rule**): SnackBar پایان شامل «همگام‌سازی با خطا در X صفحه» است ولی بقیه صفحات ذخیره گردیده‌اند. منبع: SnackBar.
  - TR-T03-3 (**rule**): اگر همه تلاش‌ها موفق شوند، SnackBar موفقیت نمایش داده می‌شود. منبع: تست دستی با شبکه پایدار.
- **Status**: pending
- **Completion Evidence**:

---

## Task 4: بازطراحی قالب PDF لیبل قیمت (سیاه و سفید حرفه‌ای با تاکید UI)

- **شناسه**: T-04
- **وابستگی**: T-02 (برای خواندن مقادیر قالب)
- **اولویت**: high
- **زیرپوشش AC**: AC-BARCODE-5, AC-BARCODE-6, AC-BARCODE-7, AC-BARCODE-8, FR-BARCODE-5/6/7/8
- **توضیحات**:
  - تابع `_buildLabel` در `main.dart` کاملاً بازنویسی شود:
    - **بخش بالا (بارکد)**: `pw.Container` با `PdfColors.black` در کل عرض لیبل. متن بارکد با فونت سفید، Vazirmatn، درشت و `TextAlign.center` + `TextDirection.rtl`. شاید Icon بارکد بصری هم اضافه شود.
    - **بخش میانی (نام کالا)**: `pw.Padding` بزرگ‌تر. `pw.Text` با اندازه فونت 14-16، `fontWeight: bold`. حداکثر ۲ خط با `maxLines: 2` و در صورت نیاز ellipsis منطقی. `TextDirection.rtl` و `TextAlign.center`.
    - **بخش پایینی (قیمت‌ها)**: `pw.Row` با `MainAxisAlignment.spaceEvenly`. قیمت فروش برجسته‌تر (فونت 14-16 ضخیم). قیمت روی جلد فقط اگر `salePrice < coverPrice` نمایش داده شود و با `TextDecoration.lineThrough`. جداکننده `pw.Container` با عرض ۱ و رنگ خاکستری بین دو قیمت در صورت وجود. عنوان/برچسب قیمت هم اضافه شود (مثلاً «قیمت فروش» و «قیمت روی جلد»).
  - پالت رنگ: فقط `PdfColors.black` و `PdfColors.white`. حاشیه دور لیبل `PdfColors.black`.
  - مقادیر اندازه از `_labelConfig` (که از SharedPreferences بارگذاری می‌شود) خوانده شود.
  - `_loadPersianFont` در ابتدای `_exportToPdf` تضمین شود که فراخوانی شده باشد.
  - در `_exportToPdf` قبل از شروع ساخت PDF، مقادیر `_labelConfig` از پیش‌فرض به مقادیر ذخیره‌شده در SharedPreferences جایگزین شوند (در صورت وجود).
  - حذف رنگ‌های رنگی موجود در قالب قبلی (آبی، سبز و ...).
- **تست محلی (TR)**:
  - TR-T04-1 (**rule**): یک محصول بدون تخفیف → فقط قیمت فروش نمایش داده می‌شود؛ قیمت روی جلد حذف شده است. منبع: فایل PDF تولید‌شده.
  - TR-T04-2 (**rule**): محصول با تخفیف → هر دو قیمت نمایش داده می‌شوند و قیمت روی جلد با خط خورده است. منبع: فایل PDF.
  - TR-T04-3 (**rule**): نام فارسی کالا به صورت راست‌چین و با فونت Vazirmatn رندر می‌شود (نمایش صحیح حروف و لigationها). منبع: اسکرین‌شات از PDF.
  - TR-T04-4 (**rubric**): کیفیت بصری لیبل (0-5). معیارها: خوانایی نام کالا در نگاه اول (۲ نمره)، خوانایی قیمت فروش (۲ نمره)، چیدمان متعادل و تمیز (۱ نمره). **آستانه قبولی: ≥۴**. منبع: بازرسی بصری PDF.
  - TR-T04-5 (**rule**): سایز صفحه PDF A4 است. منبع: ویژگی‌های فایل یا preview.
- **Status**: pending
- **Completion Evidence**:

---

## Task 5: حذف تگ‌های پیش‌فرض ثابت و مهاجرت مدل تگ‌ها

- **شناسه**: T-05
- **وابستگی**: هیچ
- **اولویت**: high
- **زیرپوشش AC**: AC-SHOPPING-1, NFR-5, NFR-6, FR-SHOPPING-1, FR-SHOPPING-2
- **توضیحات**:
  - در مدل `shopping_list_item.dart`: کلاس `DefaultTags` **حذف** گردد.
  - مدل `ShoppingListTag` فیلدهای جدید: `String? parentId`, `int? serverId`, `bool pendingSync`. متدهای `toJson/fromJson/copyWith` بروزرسانی شوند. سازگاری با داده‌های قدیمی: اگر فیلدهای جدید نبودند، مقدار پیش‌فرض `null` یا `true` برگردد.
  - کلاس `CustomTagService` بروزرسانی شود: تگ‌ها در SharedPreferences با فیلدهای جدید serialize شوند. `createCustomTag` گزینه `parentId` دریافت کند. `findByName` همچنان در همه تگ‌های کاربران جستجو کند. `getAllTags/getTagById` به متدهای کمکی درون `ShoppingListProvider` منتقل شوند.
  - `ShoppingListProvider`:
    - getter `allTags` فیلتر `CustomTagService.loadCustomTags` شده از DefaultTags حذف شود → فقط تگ‌های سفارشی برگردانده شود.
    - متدهای کمکی `getTagById, getTagColor, getTagName` فقط روی `_customTags` جستجو کنند.
  - `shopping_list_screen.dart`: جاهای که از `DefaultTags` استفاده می‌کنند (مثل گزینه `other` در `selectedTagIds` پیش‌فرض) با تگ `custom_other` یا خالی جایگزین شوند. «همه» در فیلتر همچنان نمایش داده شود.
- **تست محلی (TR)**:
  - TR-T05-1 (**rule**): اولین اجرا یا پاک‌کردن داده‌ها → فهرست تگ‌ها خالی است (لبنیات، پروتئینی، و ... وجود ندارند). منبع: بازرسی از ShoppingListScreen tag filter bar.
  - TR-T05-2 (**rule**): ساخت یک تگ جدید با parentId=null → ذخیره و بازیابی موفق. fromJson/toJson شامل فیلدهای جدید می‌باشد. منبع: تست واحد دستی یا SharedPreferences.
  - TR-T05-3 (**rule**): داده‌های قبلی که تگ پیش‌فرض داشته‌اند، به درستی handle می‌شوند (exception نکنند). منبع: اجرای روی build قبلی با داده.
- **Status**: pending
- **Completion Evidence**:

---

## Task 6: همگام‌سازی تگ‌ها با سرور (Upsert/Download)

- **شناسه**: T-06
- **وابستگی**: T-05
- **اولویت**: high
- **زیرپوشش AC**: AC-SHOPPING-3, FR-SHOPPING-2, FR-SHOPPING-3
- **توضیحات**:
  - اندپوینت سرور: یک اندپوینت برای تگ‌ها فرض می‌شود (مشابه آیتم‌ها) یا همان اندپوینت `bl/v1/tags`. سرور واقعی لزومی ندارد؛ منطق در `ShoppingListApiService` نوشته شود و در صورت عدم وجود اندپوینت خطا فقط لاگ گردد (مانند آیتم‌ها offline-friendly).
  - `ShoppingListApiService`: متدهای `createTag, updateTag, deleteTag, fetchAllTags`.
  - `ShoppingListDatabaseService`: جدول جدید `tags` در SQLite با ستون‌ها: id INTEGER PK, server_id INTEGER, name_fa, name_en, color_hex, parent_id, pending_sync INTEGER, created_at. همچنین متدهای `insertTag, updateTag, deleteTag, getAllTags, getPendingTags, upsertServerTag`.
  - Migration نسخه 1→2 دیتابیس لیست خرید. اگر ایجاد جدول در initialize امکان‌پذیر نباشد، از SharedPreferences به عنوان storage موقت برای تگ‌ها استفاده شود (به عنوان راه‌حل ایمن بدون شکستن موجود).
  - در `ShoppingListProvider`:
    - `_performSync` در مرحله جدید قبل از آیتم‌ها: آپلود تگ‌های معلق.
    - مرحله دانلود: `fetchAllTags` و `upsert` محلی.
    - بعد از هر `createTag/deleteTag` تگ pending علامت‌گذاری شود و `unawaited(_syncTags)` در پس‌زمینه اجرا شود.
- **تست محلی (TR)**:
  - TR-T06-1 (**rule**): ساخت یک تگ جدید روی دستگاه A → همگام‌سازی → دستگاه B بعد از همگام‌سازی همان تگ را مشاهده می‌کند (با mock/لاگ قابل تست). منبع: لاگ شبکه یا دو دستگاه.
  - TR-T06-2 (**rule**): در صورت قطع شبکه، تگ با `pendingSync=true` نگه داشته می‌شود و در همگام‌سازی بعدی ارسال می‌گردد. منبع: فیلد `pendingSync` در SharedPreferences/DB.
- **Status**: pending
- **Completion Evidence**:

---

## Task 7: اعتبارسنجی تگ تکراری و همگام‌سازی خودکار پس از هر تغییر

- **شناسه**: T-07
- **وابستگی**: T-06 (برای همگام‌سازی خودکار)
- **اولویت**: high
- **زیرپوشش AC**: AC-SHOPPING-2, AC-SHOPPING-4, FR-SHOPPING-4, FR-SHOPPING-5
- **توضیحات**:
  - `TagCreateStatus.duplicate` در حال حاضر با DefaultTags تطابق دارد؛ فقط به تگ‌های کاربری محدود شود. جستجو در `_customTags` انجام پذیرد.
  - `ShoppingListProvider`: در انتهای `addItem, togglePurchaseStatus, updateItemTags, deleteItem, createTag, deleteTag` (و `updateTag` اگر اضافه شد) خط `unawaited(syncWithServer())` برای همگام‌سازی پس‌زمینه اضافه شود (اگر از قبل در جریان نباشد).
  - در ShoppingListScreen به‌روزرسانی AppBar نشانگر همگام‌سازی در لحظه.
- **تست محلی (TR)**:
  - TR-T07-1 (**rule**): ساخت تگ با نام «میوه» و سپس تگ دوم با نام «میوه» (با فاصله اضافی یا حروف بزرگ) → پیام تکراری بودن نمایش داده می‌شود. منبع: SnackBar یا validationError در دیالوگ.
  - TR-T07-2 (**rule**): اضافه کردن آیتم جدید → `isSyncing` در عرض ۱ ثانیه true می‌شود و بعد از پایان به حالت اول برمی‌گردد. منبع: نشانگر همگام‌سازی در AppBar.
- **Status**: pending
- **Completion Evidence**:

---

## Task 8: صفحه ورود اجباری نام کاربری برای لیست خرید + تضمین حذف آیتم

- **شناسه**: T-08
- **وابستگی**: هیچ
- **اولویت**: high
- **زیرپوشش AC**: AC-SHOPPING-5, AC-SHOPPING-6, FR-SHOPPING-6, FR-SHOPPING-7
- **توضیحات**:
  - `ShoppingListScreen.build`: در ابتدای build، اگر `!provider.hasUser` یک `Stack` بازگرداند که `child` اصلی در پس‌زمینه + یک `AlertDialog` بامحور (Center) به صورت مودال non-dismissible نمایش دهد (با `barrierDismissible: false`). اگر نام کاربری وارد و ذخیره شد، دیالوگ برداشته می‌شود و صفحه واقعی نمایش داده می‌شود.
  - در دیالوگ: TextField برای نام کاربری + دکمه «ورود». روی تماس با دکمه برگشت سیستم: Navigator pop نشود (گرفتن با `WillPopScope`).
  - حذف آیتم: `Dismissible` فعلاً وجود دارد (line 370). فقط `SnackBar` بهینه شود (با undo اختصاری در صورت تمایل)، یا حداقل پیام «آیتم [نام] حذف شد + دکمه بازگشت».
- **تست محلی (TR)**:
  - TR-T08-1 (**rule**): پاک‌کردن داده‌ها و ورود مجدد به ShoppingListScreen → دیالوگ ورود نمایش داده می‌شود و بدون واردکردن نام نمی‌توان از آن خارج شد. منبع: تست دستی.
  - TR-T08-2 (**rule**): وارد کردن نام "علی" → دفعات بعدی بدون دیالوگ وارد می‌شود. منبع: بستن و باز کردن اپ.
  - TR-T08-3 (**rule**): کشیدن آیتم به سمت چپ → آیتم حذف می‌شود و SnackBar با پیام "آیتم حذف شد" ظاهر می‌شود. منبع: تست دستی.
- **Status**: pending
- **Completion Evidence**:

---

## Task 9: پشتیبانی از تگ‌های درختی (Parent/Child) در UI و مدل

- **شناسه**: T-09
- **وابستگی**: T-05
- **اولویت**: medium
- **زیرپوشش AC**: AC-SHOPPING-7, FR-SHOPPING-8, FR-SHOPPING-9
- **توضیحات**:
  - دیالوگ ساخت تگ جدید: یک DropdownButton «تگ والد (اختیاری)» با لیست همه تگ‌ها اضافه شود (پیش‌فرض: هیچکدام → parentId=null).
  - صفحه مدیریت تگ‌ها: `ListView` با indent بر اساس عمق. محاسبه عمق با تابع recursive: `depth = 1 + depth(parent)`.
  - `_buildMultiTagSelector` در ShoppingListScreen: تگ‌ها با indent نمایش داده شوند (`Padding(left: depth * 12)`).
  - در مدل تگ: متد کمکی `List<ShoppingListTag> children(List<ShoppingListTag> allTags)` برگرداند.
- **تست محلی (TR)**:
  - TR-T09-1 (**rule**): ساخت ۳ تگ: canapes (parent=null), cold-canapes (parent=canapes), mini-cold-canapes (parent=cold-canapes). مدیریت تگ‌ها هر سه را با indent ۰، ۱۲، ۲۴ نمایش می‌دهد. منبع: بازرسی از مدیریت تگ‌ها.
  - TR-T09-2 (**rule**): Dropdown «تگ والد» در دیالوگ ساخت تگ وجود دارد و قابل انتخاب است. منبع: دیالوگ ساخت تگ.
- **Status**: pending
- **Completion Evidence**:

---

## Task 10: فعال‌سازی Full Screen Edge-to-Edge و اصلاح SafeArea در تمام صفحات

- **شناسه**: T-10
- **وابستگی**: هیچ
- **اولویت**: high
- **زیرپوشش AC**: AC-GENERAL-1, FR-GENERAL-1, FR-GENERAL-2
- **توضیحات**:
  - در `main.dart` در تابع `main()` یا داخل `initState` BarcodeScannerApp:
    ```dart
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarIconBrightness: Brightness.dark,
    ));
    ```
  - MenuPage: `body` در حال حاضر `SafeArea` دارد (line 55). حذف `SafeArea` خارجی شود و SafeArea فقط `top: true` + درون padding اعمال گردد؛ یا SafeArea با `top: true, bottom: true` نگه داشته شود ولی background رنگی دورترین Container باشد (برای کشیدن زیر نوار سیستم).
  - HomePage: `Scaffold` body → تمام Column در `SafeArea` با `bottom: true, top: true` قرار گیرد.
  - ShoppingListScreen: `Scaffold` body در `SafeArea` با `bottom: true` قرار گیرد (AppBar از top محافظت می‌کند).
  - ProductsListPage: مشابه بالا.
  - FloatingActionButton در ShoppingListScreen و Debug Overlay FAB: padding `MediaQuery.of(context).padding.bottom` به اضافه شود تا در بالای navigation bar نمایش داده شوند.
- **تست محلی (TR)**:
  - TR-T10-1 (**rule**): اجرای برنامه روی دستگاه با ناوبری سه‌دکمه‌ای → پس‌زمینه (gradient یا AppBar رنگی) در زیر نوار سیستم دیده می‌شود ولی دکمه‌ها/متن‌های قابل تعامل در ناحیه امن باقی می‌مانند. منبع: اسکرین‌شات.
  - TR-T10-2 (**rule**): هیچ بخشی از UI «hidden» زیر نوار پایینی سیستم نمی‌رود (کاربر می‌تواند روی همه دکمه‌ها کلیک کند). منبع: تست دستی.
- **Status**: pending
- **Completion Evidence**:

---

## Task 11: رفع overflow در Debug Overlay و Debug Overlay Host

- **شناسه**: T-11
- **وابستگی**: هیچ
- **اولویت**: high
- **زیرپوشش AC**: AC-GENERAL-2, AC-GENERAL-3, FR-GENERAL-3, FR-GENERAL-4, FR-GENERAL-5
- **توضیحات**:
  - `debug_overlay.dart`:
    - `_buildHeader` Row داخل Container: فیلتر تگ‌ها را Wrap کنید. اگر Row زیاد است، Row اولیه را در `SingleChildScrollView` با `scrollDirection: Axis.horizontal` بپیچید یا به جای Row → `Wrap` با `spacing: 4`.
    - Header Container خودش محدودیت عرض و ارتفاع ندارد → Wrap داخل `ConstrainedBox` یا `LayoutBuilder` برای حداکثر عرض صفحه بگردد.
    - DebugOverlay حالا درون MaterialApp قرار دارد → tooltip به صورت مجدد می‌تواند فعال باشد (اگر خطای No Overlay نداد). اما مطمئن شویم که IconButton ها overflow در Row نکنند.
  - `debug_overlay_host.dart`:
    - پراپرتی‌های tooltip روی IconButton ها حذف شوند (در صورت وجود: lines 115, 205, 213, 259, 274, 278, 599, 607, 615 را بررسی کنید).
    - Rowهای `_buildPanelHeader`, `_buildFilterBar`: Actionهای IconButton انتهای Row با `Wrap` یا `SingleChildScrollView` افقی مدیریت شوند.
    - `_buildPanel` ارتفاع ثابت `0.52 * screenHeight` دارد → برای صفحات کوچک ممکن است overflow در ردیف‌ها ایجاد کند. مطمئن شویم که `Column` داخلی کاملاً `Expanded` برای لیست و `mainAxisSize: MainAxisSize.min` برای header/footer استفاده کرده است.
- **تست محلی (TR)**:
  - TR-T11-1 (**rule**): کلیک روی FAB Debug در گوشه → پنل Debug Overlay باز می‌شود و بدون No Overlay/Overflow نمایش داده می‌شود. منبع: تست دستی.
  - TR-T11-2 (**rule**): کلیک روی FAB پایین-چپ در DebugOverlayHost → پنل سیاه رنگ بدون overflow باز می‌شود؛ حتی در صفحه کوچک. منبع: تست دستی در اندازه صفحه مختلف.
- **Status**: pending
- **Completion Evidence**:
