/// تنظیمات مرکزی شبکه/API برنامه.
///
/// Central place for every host, endpoint, timeout and retry configuration.
/// هیچ آدرس یا کلیدی نباید به صورت پراکنده در برنامه تعریف شود.
class ApiConfig {
  ApiConfig._();

  // ==================== هاست‌ها / Hosts ====================

  /// آدرس سایت وردپرسی که هم API چک‌لیست و هم API ووکامرس روی آن است.
  static const String wordpressBaseUrl = 'https://ebimarket.ir';

  /// کلیدهای REST API ووکامرس (فقط خواندن).
  static const String wooCommerceConsumerKey =
      'ck_59df85eaad37b7c4f6bf77ba0707aca37dc42939';
  static const String wooCommerceConsumerSecret =
      'cs_71f8ba694ba54566be8209503145bdab47903e4e';

  // ==================== زمان‌های انتظار / Timeouts ====================

  /// زمان انتظار برای کل یک درخواست (اتصال + خواندن).
  static const Duration requestTimeout = Duration(seconds: 30);

  /// زمان انتظار برای بررسی‌های سریع (تشخیص اتصال، بررسی سلامت سرور).
  static const Duration probeTimeout = Duration(seconds: 12);

  // ==================== تلاش مجدد / Retry ====================

  /// حداکثر تعداد تلاش مجدد برای خطاهای موقت شبکه (۵xx، Timeout، قطعی).
  static const int maxRetries = 3;

  /// پایه تاخیر نمایی (exponential backoff) بین تلاش‌ها.
  static const Duration retryBaseDelay = Duration(milliseconds: 700);

  /// بلندترین تاخیر مجاز بین تلاش‌ها.
  static const Duration retryMaxDelay = Duration(seconds: 6);

  // ==================== اندپوینت‌های چک‌لیست خرید ====================

  /// ریشه REST وردپرس - برای تشخیص فعال بودن REST API.
  static String get wpRestRoot => '$wordpressBaseUrl/wp-json/';

  /// اندپوینت آیتم‌های چک‌لیست خرید.
  static String get shoppingItemsEndpoint =>
      '$wordpressBaseUrl/wp-json/bl/v1/items';

  /// اندپوینت کاربران چک‌لیست خرید.
  static String get shoppingUsersEndpoint =>
      '$wordpressBaseUrl/wp-json/bl/v1/users';

  /// اندپوینت همگام‌سازی چک‌لیست خرید.
  static String get shoppingSyncEndpoint =>
      '$wordpressBaseUrl/wp-json/bl/v1/sync';

  /// اندپوینت تگ‌های چک‌لیست خرید (ساختار درختی).
  /// اگر افزونه سرور این اندپوینت را هنوز پیاده‌سازی نکرده باشد،
  /// تگ‌ها فقط به صورت محلی در SharedPreferences ذخیره می‌شوند و خطا
  /// کل همگام‌سازی را متوقف نمی‌کنند (graceful fallback).
  static String get shoppingTagsEndpoint =>
      '$wordpressBaseUrl/wp-json/bl/v1/tags';

  static String shoppingItemEndpoint(int serverId) =>
      '$shoppingItemsEndpoint/$serverId';

  static String shoppingTagEndpoint(int serverId) =>
      '$shoppingTagsEndpoint/$serverId';

  static String shoppingUserByUsernameEndpoint(String username) =>
      '$shoppingUsersEndpoint?username=${Uri.encodeQueryComponent(username)}';

  // ==================== اندپوینتهای ووکامرس ====================

  /// اندپوینت محصولات ووکامرس.
  static String get wooCommerceProductsEndpoint =>
      '$wordpressBaseUrl/wp-json/wc/v3/products';

  static const int productsPerPage = 100;

  /// ساخت آدرس صفحه محصولات با احراز هویت کلیدها.
  ///
  /// ووکامرس اجازه می‌دهد کلیدها هم در query string و هم در هدر ارسال شوند.
  /// برای سازگاری حداکثری با نسخه‌های قدیمی‌تر، در query string ارسال می‌شوند
  /// و در صورت رد شدن، [NetworkClient] به صورت خودکار از هدر Basic استفاده می‌کند.
  static Uri wooProductsUri({
    required int page,
    int perPage = productsPerPage,
    required String fields,
  }) {
    return Uri.parse(wooCommerceProductsEndpoint).replace(
      queryParameters: <String, String>{
        'per_page': '$perPage',
        'page': '$page',
        'consumer_key': wooCommerceConsumerKey,
        'consumer_secret': wooCommerceConsumerSecret,
        '_fields': fields,
      },
    );
  }

  /// هدرهای احراز هویت ووکامرس (روش جایگزین در صورت رد شدن query string).
  static Map<String, String> get wooCommerceAuthHeaders => <String, String>{
        'Authorization':
            'Basic ${_base64Encode('$wooCommerceConsumerKey:$wooCommerceConsumerSecret')}',
        'Accept': 'application/json',
      };

  static String _base64Encode(String value) {
    // پیاده‌سازی کوچک و بدون وابستگی برای جلوگیری از import اضافه.
    const String chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    final List<int> bytes = value.codeUnits;
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < bytes.length; i += 3) {
      final int b0 = bytes[i];
      final int b1 = i + 1 < bytes.length ? bytes[i + 1] : -1;
      final int b2 = i + 2 < bytes.length ? bytes[i + 2] : -1;
      buffer.write(chars[b0 >> 2]);
      if (b1 == -1) {
        buffer.write(chars[(b0 & 0x03) << 4]);
        buffer.write('==');
        break;
      }
      buffer.write(chars[((b0 & 0x03) << 4) | (b1 >> 4)]);
      if (b2 == -1) {
        buffer.write(chars[(b1 & 0x0F) << 2]);
        buffer.write('=');
        break;
      }
      buffer.write(chars[((b1 & 0x0F) << 2) | (b2 >> 6)]);
      buffer.write(chars[b2 & 0x3F]);
    }
    return buffer.toString();
  }
}