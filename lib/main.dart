import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:collection' show HashMap, HashSet;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'features/menu/screens/menu_page.dart';
import 'features/shopping_list/providers/shopping_list_provider.dart';
import 'features/shopping_list/models/shopping_list_item.dart';
import 'core/services/app_logger.dart';
import 'core/widgets/debug_overlay.dart';
import 'dart:math' as math;

// Global font for Persian support in PDF
pw.Font? _persianFont;

Future<void> _loadPersianFont() async {
  if (_persianFont == null) {
    final ByteData fontData = await rootBundle.load('assets/fonts/Vazirmatn-Regular.ttf');
    _persianFont = pw.Font.ttf(fontData);
  }
}

// Helper function to shape Persian text (not needed with textDirection)
// String _shapeText(String text) {
//   return Intl.letters(text, locale: 'fa_IR');
// }

// Product model for local database
class LocalProduct {
  final int? id;
  final String sku;
  final String name;
  final String coverPrice;
  final String salePrice;
  final String mainBarcode;
  final String extraBarcodes;
  final double stockQuantity;
  final DateTime? lastSynced;

  LocalProduct({
    this.id,
    required this.sku,
    required this.name,
    required this.coverPrice,
    required this.salePrice,
    required this.mainBarcode,
    this.extraBarcodes = '',
    this.stockQuantity = 0,
    this.lastSynced,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sku': sku,
      'name': name,
      'cover_price': coverPrice,
      'sale_price': salePrice,
      'main_barcode': mainBarcode,
      'extra_barcodes': extraBarcodes,
      'stock_quantity': stockQuantity,
      'last_synced': lastSynced?.toIso8601String(),
    };
  }

  factory LocalProduct.fromMap(Map<String, dynamic> map) {
    return LocalProduct(
      id: map['id'],
      sku: map['sku'] ?? '',
      name: map['name'] ?? '',
      coverPrice: map['cover_price'] ?? '',
      salePrice: map['sale_price'] ?? '',
      mainBarcode: map['main_barcode'] ?? '',
      extraBarcodes: map['extra_barcodes'] ?? '',
      stockQuantity: map['stock_quantity'] ?? 0.0,
      lastSynced: map['last_synced'] != null ? DateTime.parse(map['last_synced']) : null,
    );
  }
}

class ScannedItem {
  final String barcode;
  final String name;
  final String coverPrice;
  final String salePrice;

  ScannedItem({
    required this.barcode,
    required this.name,
    required this.coverPrice,
    required this.salePrice,
  });
}

// Label configuration settings
class LabelConfig {
  int labelsPerRow;
  int labelsPerColumn;
  double labelWidthMm;
  double labelHeightMm;
  double marginTopMm;
  double marginBottomMm;
  double marginLeftMm;
  double marginRightMm;
  double gapHorizontalMm;
  double gapVerticalMm;
  bool showBarcodeText;
  bool forceShowCoverPriceOnDiscount;

  LabelConfig({
    this.labelsPerRow = 3,
    this.labelsPerColumn = 5,
    this.labelWidthMm = 70,
    this.labelHeightMm = 42,
    this.marginTopMm = 10,
    this.marginBottomMm = 10,
    this.marginLeftMm = 5,
    this.marginRightMm = 5,
    this.gapHorizontalMm = 5,
    this.gapVerticalMm = 5,
    this.showBarcodeText = true,
    this.forceShowCoverPriceOnDiscount = true,
  });

  int get labelsPerPage => labelsPerRow * labelsPerColumn;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'labelsPerRow': labelsPerRow,
        'labelsPerColumn': labelsPerColumn,
        'labelWidthMm': labelWidthMm,
        'labelHeightMm': labelHeightMm,
        'marginTopMm': marginTopMm,
        'marginBottomMm': marginBottomMm,
        'marginLeftMm': marginLeftMm,
        'marginRightMm': marginRightMm,
        'gapHorizontalMm': gapHorizontalMm,
        'gapVerticalMm': gapVerticalMm,
        'showBarcodeText': showBarcodeText,
        'forceShowCoverPriceOnDiscount': forceShowCoverPriceOnDiscount,
      };

  factory LabelConfig.fromJson(Map<String, dynamic> json) => LabelConfig(
        labelsPerRow: asIntFromJson(json['labelsPerRow'], 3),
        labelsPerColumn: asIntFromJson(json['labelsPerColumn'], 5),
        labelWidthMm: asDoubleFromJson(json['labelWidthMm'], 70),
        labelHeightMm: asDoubleFromJson(json['labelHeightMm'], 42),
        marginTopMm: asDoubleFromJson(json['marginTopMm'], 10),
        marginBottomMm: asDoubleFromJson(json['marginBottomMm'], 10),
        marginLeftMm: asDoubleFromJson(json['marginLeftMm'], 5),
        marginRightMm: asDoubleFromJson(json['marginRightMm'], 5),
        gapHorizontalMm: asDoubleFromJson(json['gapHorizontalMm'], 5),
        gapVerticalMm: asDoubleFromJson(json['gapVerticalMm'], 5),
        showBarcodeText: json['showBarcodeText'] == null ? true : asBoolFromJson(json['showBarcodeText']),
        forceShowCoverPriceOnDiscount: json['forceShowCoverPriceOnDiscount'] == null
            ? true
            : asBoolFromJson(json['forceShowCoverPriceOnDiscount']),
      );
}

int asIntFromJson(dynamic value, int fallback) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num) return value.toInt();
  final int? parsed = int.tryParse(value.toString());
  return parsed ?? fallback;
}

double asDoubleFromJson(dynamic value, double fallback) {
  if (value == null) return fallback;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  final double? parsed = double.tryParse(value.toString());
  return parsed ?? fallback;
}

bool asBoolFromJson(dynamic value) {
  if (value is bool) return value;
  if (value is int) return value != 0;
  final String s = value.toString().trim().toLowerCase();
  return s == 'true' || s == '1' || s == 'yes' || s == 'on';
}

const String _kLabelConfigPrefsKey = 'pdf_label_template_v1';

Future<LabelConfig> loadLabelConfig() async {
  try {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_kLabelConfigPrefsKey);
    if (raw == null || raw.isEmpty) return LabelConfig();
    final Map<String, dynamic> decoded =
        Map<String, dynamic>.from(json.decode(raw) as Map);
    return LabelConfig.fromJson(decoded);
  } catch (_) {
    return LabelConfig();
  }
}

Future<bool> saveLabelConfig(LabelConfig config) async {
  try {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.setString(_kLabelConfigPrefsKey, json.encode(config.toJson()));
  } catch (_) {
    return false;
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  ));
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ShoppingListProvider()),
        ChangeNotifierProvider(create: (_) => AppLogger()),
      ],
      child: const BarcodeScannerApp(),
    ),
  );
}

class BarcodeScannerApp extends StatefulWidget {
  const BarcodeScannerApp({super.key});

  @override
  State<BarcodeScannerApp> createState() => _BarcodeScannerAppState();
}

class _BarcodeScannerAppState extends State<BarcodeScannerApp> {
  String _locale = 'fa';
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _locale = prefs.getString('locale') ?? 'fa';
      final themeIndex = prefs.getInt('theme_mode') ?? 0;
      _themeMode = ThemeMode.values[themeIndex];
    });
  }

  Future<void> _saveSettings(String locale, ThemeMode themeMode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('locale', locale);
    await prefs.setInt('theme_mode', themeMode.index);
  }

  void updateLocale(String locale) {
    setState(() => _locale = locale);
    _saveSettings(_locale, _themeMode);
  }

  void updateThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
    _saveSettings(_locale, _themeMode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: _locale == 'fa' ? 'بارکد اسکنر' : 'Barcode Scanner',
      debugShowCheckedModeBanner: false,
      locale: Locale(_locale),
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('fa'),
        Locale('en'),
      ],
      themeMode: _themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'Vazirmatn',
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: 'Vazirmatn',
      ),
      home: DebugOverlay(
        child: MenuPage(
        currentLocale: _locale,
        onLocaleChanged: updateLocale,
        themeMode: _themeMode,
        onThemeModeChanged: updateThemeMode,
      ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final String currentLocale;
  final Function(String) onLocaleChanged;
  final ThemeMode themeMode;
  final Function(ThemeMode) onThemeModeChanged;

  const HomePage({
    super.key,
    required this.currentLocale,
    required this.onLocaleChanged,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<String> _barcodes = [];
  Map<String, ProductInfo> _productMap = HashMap<String, ProductInfo>();
  String _storagePath = 'Application Documents Directory';
  Database? _database;
  List<LocalProduct> _localProducts = [];
  bool _isSyncing = false;
  DateTime? _lastSyncTime;

  int _syncCurrentPage = 0;
  int _syncEstimatedPages = 1;
  int _syncFetchedProducts = 0;
  final List<int> _syncFailedPages = <int>[];

  // Label configuration
  LabelConfig _labelConfig = LabelConfig();
  bool _showUniqueOnly = true;

  // WooCommerce API configuration
  final String _wooCommerceUrl = 'https://ebimarket.ir';
  final String _consumerKey = 'ck_59df85eaad37b7c4f6bf77ba0707aca37dc42939';
  final String _consumerSecret = 'cs_71f8ba694ba54566be8209503145bdab47903e4e';

  @override
  void initState() {
    super.initState();
    AppLogger().info('App initialized');
    _initializeDatabase();
    _loadStoragePath();
    _initLabelConfig();
  }

  Future<void> _initLabelConfig() async {
    final LabelConfig stored = await loadLabelConfig();
    if (mounted) {
      setState(() {
        _labelConfig = stored;
      });
    }
  }

  double get _syncProgressPercent {
    if (_syncEstimatedPages <= 0) return 0;
    final double p = _syncCurrentPage / _syncEstimatedPages;
    if (p < 0) return 0;
    if (p > 1) return 1;
    return p;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.currentLocale == 'fa' ? 'بارکد اسکنر' : 'Barcode Scanner'),
        actions: [
          IconButton(
            icon: const Icon(Icons.list),
            onPressed: _showProductsList,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'settings') {
                _showPdfTemplateSettings();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'settings', child: Text('تنظیمات')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        left: false,
        right: false,
        child: Column(
          children: [
            // Sync status bar
            Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 8,
                left: 16,
                right: 16,
                bottom: 12,
              ),
              color: Colors.blue.shade50,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        _isSyncing ? Icons.sync : Icons.cloud_done,
                        size: 20,
                        color: _isSyncing ? Colors.orange : Colors.green,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _isSyncing
                              ? 'در حال همگام‌سازی... صفحه $_syncCurrentPage از ~$_syncEstimatedPages | $_syncFetchedProducts محصول'
                              : (_lastSyncTime != null
                                  ? 'آخرین همگام‌سازی: ${_formatDateTime(_lastSyncTime!)}'
                                  : 'بدون همگام‌سازی'),
                          style: TextStyle(
                            fontSize: 12,
                            color: _isSyncing ? Colors.orange : Colors.grey.shade700,
                          ),
                        ),
                      ),
                      if (!_isSyncing)
                        TextButton.icon(
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('همگام‌سازی'),
                          onPressed: _syncProductsFromWooCommerce,
                          style: TextButton.styleFrom(
                            minimumSize: const Size(0, 32),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                        ),
                    ],
                  ),
                  if (_isSyncing) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: _syncProgressPercent > 0 ? _syncProgressPercent : null,
                        minHeight: 5,
                        backgroundColor: Colors.blue.shade100,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade600),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Spacer(),
                        Text(
                          '${(_syncProgressPercent * 100).toInt()}%',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (_syncFailedPages.isNotEmpty && !_isSyncing)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'صفحات دریافت‌نشده: ${_syncFailedPages.join(", ")}',
                        style: const TextStyle(fontSize: 11, color: Colors.redAccent),
                      ),
                    ),
                ],
              ),
            ),
            
            // Main content
            Expanded(
              child: MobileScanner(
                onDetect: (capture) {
                  final List<Barcode> barcodes = capture.barcodes;
                  for (final barcode in barcodes) {
                    if (barcode.rawValue != null) {
                      _addBarcode(barcode.rawValue!);
                    }
                  }
                },
                controller: MobileScannerController(
                  facing: CameraFacing.back,
                ),
              ),
            ),
            
            // Bottom controls
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.currentLocale == 'fa'
                              ? '${_barcodes.length} بارکد اسکن شده'
                              : '${_barcodes.length} barcodes scanned',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.delete_outline),
                        label: Text(widget.currentLocale == 'fa' ? 'پاک کردن' : 'Clear'),
                        onPressed: _barcodes.isEmpty ? null : _clearBarcodes,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.info_outline),
                          label: Text(widget.currentLocale == 'fa' ? 'دریافت اطلاعات' : 'Fetch Info'),
                          onPressed: _barcodes.isEmpty ? null : _fetchProductInfo,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.print),
                          label: Text(widget.currentLocale == 'fa' ? 'چاپ لیبل' : 'Print Labels'),
                          onPressed: _barcodes.isEmpty ? null : _printLabels,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _initializeDatabase() async {
    try {
      final databasesPath = await getDatabasesPath();
      final path = p.join(databasesPath, 'products.db');
      
      _database = await openDatabase(
        path,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE products (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              sku TEXT UNIQUE NOT NULL,
              name TEXT NOT NULL,
              cover_price TEXT NOT NULL,
              sale_price TEXT NOT NULL,
              main_barcode TEXT NOT NULL,
              extra_barcodes TEXT DEFAULT '',
              stock_quantity REAL DEFAULT 0,
              last_synced TEXT
            )
          ''');
          AppLogger().info('Database table created');
        },
      );
      
      AppLogger().info('Database initialized at: $path');
      await _loadLocalProducts();
    } catch (e) {
      AppLogger().info('Error initializing database: $e');
    }
  }

  Future<void> _loadStoragePath() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      setState(() {
        _storagePath = directory.path;
      });
      AppLogger().info('Storage path loaded: $_storagePath');
    } catch (e) {
      AppLogger().info('Error loading storage path: $e');
    }
  }

  Future<void> _loadLocalProducts() async {
    if (_database == null) return;
    
    try {
      final List<Map<String, dynamic>> maps = await _database!.query('products');
      setState(() {
        _localProducts = List.generate(maps.length, (i) {
          return LocalProduct.fromMap(maps[i]);
        });
      });
      AppLogger().info('Loaded ${_localProducts.length} products from local database');
    } catch (e) {
      AppLogger().info('Error loading local products: $e');
    }
  }

  Future<void> _syncProductsFromWooCommerce() async {
    if (_isSyncing) {
      AppLogger().warning('Sync already in progress');
      return;
    }

    setState(() {
      _isSyncing = true;
      _syncCurrentPage = 0;
      _syncEstimatedPages = 1;
      _syncFetchedProducts = 0;
      _syncFailedPages.clear();
    });

    AppLogger().info('Starting product sync from WooCommerce (background)');

    // Start sync as a background task without blocking UI
    _runBackgroundSync();
  }

  Future<http.Response> _fetchWooPageWithRetry(int page, int perPage, {int maxAttempts = 5, String? fields}) async {
    http.Client client = http.Client();
    Object? lastError;
    final String fieldsParam = fields ?? 'id,sku,regular_price,sale_price,name,meta_data,stock_quantity';
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final url = Uri.parse(
          '$_wooCommerceUrl/wp-json/wc/v3/products?per_page=$perPage&page=$page&consumer_key=$_consumerKey&consumer_secret=$_consumerSecret&_fields=$fieldsParam',
        );
        final response = await client.get(url, headers: {
          'Connection': 'keep-alive',
          'Accept-Encoding': 'gzip, deflate',
        }).timeout(Duration(seconds: attempt == 1 ? 45 : 60 + attempt * 15));
        if (response.statusCode == 200 || response.statusCode >= 500) {
          client.close();
          return response;
        }
        if (attempt >= maxAttempts) {
          client.close();
          return response;
        }
        lastError = Exception('HTTP ${response.statusCode}');
      } on TimeoutException catch (e) {
        lastError = e;
        AppLogger().warning('Page $page timeout (attempt $attempt/$maxAttempts)');
      } on SocketException catch (e) {
        lastError = e;
        final String msg = e.toString().toLowerCase();
        final bool connectionAbort = msg.contains('connection abort') ||
            msg.contains('connection reset') ||
            msg.contains('connection refused') ||
            msg.contains('no route to host') ||
            msg.contains('timed out') ||
            msg.contains('software caused');
        if (connectionAbort) {
          AppLogger().warning('Page $page SocketException abort (attempt $attempt/$maxAttempts): ${e.message}');
        } else {
          AppLogger().warning('Page $page network error (attempt $attempt/$maxAttempts): ${e.message}');
        }
      } on http.ClientException catch (e) {
        lastError = e;
        final String msg = e.message.toLowerCase();
        final bool retryable = msg.contains('abort') ||
            msg.contains('reset') ||
            msg.contains('timed out') ||
            msg.contains('timeout') ||
            msg.contains('closed before full body') ||
            msg.contains('software caused') ||
            msg.contains('connection');
        AppLogger().warning(
            'Page $page ClientException (attempt $attempt/$maxAttempts): ${e.message}');
        if (!retryable && attempt >= maxAttempts) {
          break;
        }
      } catch (e) {
        lastError = e;
        AppLogger().warning('Page $page error (attempt $attempt/$maxAttempts): $e');
      }
      if (attempt < maxAttempts) {
        final int delayMs = 1500 * math.pow(2, attempt - 1).toInt() + math.Random().nextInt(1000);
        await Future.delayed(Duration(milliseconds: delayMs));
        if (attempt >= 2) {
          client.close();
          client = http.Client();
        }
      }
    }
    client.close();
    throw lastError ?? Exception('Unknown error fetching page $page');
  }

  Future<void> _runBackgroundSync() async {
    try {
      int totalProducts = 0;
      int processedCount = 0;
      int newCount = 0;
      int updatedCount = 0;

      AppLogger().info('Background sync started');

      // Pre-allocate list with estimated capacity to reduce reallocations
      List<LocalProduct> fetchedProducts = List<LocalProduct>.empty(growable: true);
      int page = 1;
      const int perPage = 50;
      bool hasMorePages = true;
      bool haveEstimated = false;

      // Bootstrap with an optimistic guess for progress
      setState(() {
        _syncEstimatedPages = 30;
      });

      while (hasMorePages) {
        AppLogger().info('Fetching products page $page');

        setState(() {
          _syncCurrentPage = page;
          if (!haveEstimated) {
            _syncEstimatedPages = math.max(_syncEstimatedPages, page + 10);
          }
        });

        List<dynamic> products;
        try {
          final response = await _fetchWooPageWithRetry(page, perPage);
          if (response.statusCode != 200) {
            AppLogger().warning(
                'Failed to fetch products page $page. Status: ${response.statusCode}');
            if (!mounted) break;
            setState(() {
              _syncFailedPages.add(page);
            });
            // If we hit rate-limit / server-error, break loop but save what we have
            if (response.statusCode >= 500 || response.statusCode == 429) {
              AppLogger().error('Stopping loop early due to HTTP ${response.statusCode}',
                  source: 'Sync');
              break;
            }
            page++;
            continue;
          }
          products = json.decode(response.body) as List<dynamic>;
        } catch (e) {
          AppLogger().error('Page $page failed after retries: $e',
              source: 'Sync');
          if (mounted) {
            setState(() {
              _syncFailedPages.add(page);
            });
          }
          // Continue to next page to not lose entire progress
          page++;
          if (page > 200) {
            hasMorePages = false;
          }
          // Wait a bit longer after failure before continuing
          await Future.delayed(const Duration(milliseconds: 600));
          continue;
        }

        if (products.isEmpty) {
          // We reached the final page, set our final estimate for progress bar
          if (mounted) {
            setState(() {
              _syncEstimatedPages = math.max(page - 1, 1);
              _syncCurrentPage = math.max(page - 1, 1);
            });
          }
          hasMorePages = false;
          break;
        }

        haveEstimated = true;

        // Estimate total: current page is known, WooCommerce X-WP-Total header usually gives
        // total count; but we estimate by doubling remaining if page is still full.
        final int remainingEstimate = products.length == perPage ? 10 : 0;
        if (mounted) {
          setState(() {
            _syncEstimatedPages = page + remainingEstimate;
          });
        }

        // Pre-allocate temporary list for this page
        final List<LocalProduct> pageProducts = List<LocalProduct>.filled(
          products.length,
          LocalProduct(sku: '', name: '', coverPrice: '', salePrice: '', mainBarcode: ''),
          growable: false,
        );

        int validIndex = 0;
        for (var product in products) {
          final sku = product['sku']?.toString() ?? '';
          if (sku.isEmpty) continue;

          final name = product['name']?.toString() ?? 'Unknown';
          final regularPrice = product['regular_price']?.toString() ?? '0';
          final salePrice = product['sale_price']?.toString() ?? '';
          final stockQuantity = product['stock_quantity'] ?? 0.0;

          // Extract barcodes from meta_data
          String allBarcodes = '';
          String mainBarcode = '';
          String extraBarcodes = '';

          if (product['meta_data'] != null) {
            for (var meta in product['meta_data']) {
              if (meta['key'] == '_holoo_barcodes') {
                allBarcodes = meta['value']?.toString() ?? '';
                break;
              }
            }
          }

          // Parse barcodes
          if (allBarcodes.isNotEmpty) {
            final barcodeList = allBarcodes.split(',').map((b) => b.trim()).where((b) => b.isNotEmpty).toList();
            if (barcodeList.isNotEmpty) {
              mainBarcode = barcodeList.first;
              extraBarcodes = barcodeList.skip(1).join(',');
            }
          }

          pageProducts[validIndex++] = LocalProduct(
            sku: sku,
            name: name,
            coverPrice: regularPrice,
            salePrice: salePrice.isNotEmpty ? salePrice : regularPrice,
            mainBarcode: mainBarcode,
            extraBarcodes: extraBarcodes,
            stockQuantity: double.tryParse(stockQuantity.toString()) ?? 0.0,
            lastSynced: DateTime.now(),
          );

          processedCount++;
        }

        // Add only valid products
        fetchedProducts.addAll(pageProducts.take(validIndex));

        // Update live progress in UI
        if (mounted) {
          setState(() {
            _syncFetchedProducts = fetchedProducts.length;
          });
        }

        page++;
        totalProducts = processedCount + perPage; // Update estimate
        // Reduced delay with jitter to avoid lockstep patterns
        final int delayMs = 150 + math.Random().nextInt(100);
        await Future.delayed(Duration(milliseconds: delayMs));
      }

      AppLogger().info('Fetched ${fetchedProducts.length} products from WooCommerce');

      // Insert or update in local database with batch optimization
      if (_database != null) {
        await _database!.transaction((txn) async {
          // Use batch operations for better performance
          final Batch batch = txn.batch();

          for (var product in fetchedProducts) {
            // Check if exists
            var existing = await txn.query(
              'products',
              where: 'sku = ?',
              whereArgs: [product.sku],
            );

            if (existing.isEmpty) {
              batch.insert('products', product.toMap());
              newCount++;
            } else {
              batch.update(
                'products',
                product.toMap(),
                where: 'sku = ?',
                whereArgs: [product.sku],
              );
              updatedCount++;
            }
          }

          // Execute all operations in one commit
          await batch.commit(noResult: true);
        });

        AppLogger().info('Database updated: $newCount new, $updatedCount updated');
      }

      setState(() {
        _lastSyncTime = DateTime.now();
        _isSyncing = false;
        if (_syncEstimatedPages < _syncCurrentPage) {
          _syncEstimatedPages = math.max(_syncCurrentPage, 1);
        }
      });

      await _loadLocalProducts();

      // Show success notification
      if (mounted) {
        if (_syncFailedPages.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                        'همگام‌سازی کامل شد: $newCount محصول جدید، $updatedCount محصول بروزرسانی شد'),
                  ),
                ],
              ),
              duration: const Duration(seconds: 4),
              backgroundColor: Colors.green.shade700,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.warning, color: Colors.yellow),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                        'همگام‌سازی با خطا: ${_syncFailedPages.length} صفحه دریافت نشد (صفحه ${_syncFailedPages.join(",")}). $newCount محصول جدید، $updatedCount محصول بروزرسانی شد'),
                  ),
                ],
              ),
              duration: const Duration(seconds: 6),
              backgroundColor: Colors.orange.shade800,
            ),
          );
        }
      }

      AppLogger().info('Sync completed successfully');
    } catch (e) {
      AppLogger().error('Error syncing products: $e', source: 'Sync');
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.red),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('خطا در همگام‌سازی: ${e.toString()}'),
                ),
              ],
            ),
            duration: const Duration(seconds: 4),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  void _showProgressDialog(String message, int current, int total) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('در حال پردازش...'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: total > 0 ? current / total : null,
            ),
            const SizedBox(height: 8),
            Text('$current از $total'),
          ],
        ),
      ),
    );
  }

  void _addBarcode(String barcode) {
    if (!_barcodes.contains(barcode)) {
      _barcodes.add(barcode);
      setState(() {});
    }
  }

  void _removeBarcode(int index) {
    _barcodes.removeAt(index);
    setState(() {});
  }

  void _clearBarcodes() {
    _barcodes.clear();
    setState(() {});
  }

  Future<void> _fetchProductInfo() async {
    if (_barcodes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هیچ بارکدی برای دریافت اطلاعات وجود ندارد')),
      );
      return;
    }

    if (_localProducts.isNotEmpty) {
      AppLogger().info('Using local database (${_localProducts.length} items) for product info');
      int foundLocal = 0;
      final Map<String, ProductInfo> localMap = HashMap<String, ProductInfo>();
      for (final barcode in _barcodes) {
        for (final product in _localProducts) {
          final barcodes = <String>[product.sku, product.mainBarcode];
          if (product.extraBarcodes.isNotEmpty) {
            barcodes.addAll(product.extraBarcodes.split(',').map((e) => e.trim()));
          }
          if (barcodes.contains(barcode)) {
            localMap[barcode] = ProductInfo(
              name: product.name,
              coverPrice: product.coverPrice,
              salePrice: product.salePrice,
            );
            foundLocal++;
            break;
          }
        }
      }
      if (foundLocal == _barcodes.length) {
        setState(() {
          _productMap = localMap;
        });
        AppLogger().info('All $_barcodes.length barcodes found locally');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('اطلاعات محصول از حافظه محلی دریافت شد: $foundLocal بارکد')),
        );
        return;
      }
    }

    AppLogger().info('Fetching product info for ${_barcodes.length} barcodes from API');
    final List<int> failedPages = <int>[];

    try {
      final Map<String, ProductInfo> productMap = HashMap<String, ProductInfo>();
      int page = 1;
      const int perPage = 50;
      bool hasMorePages = true;
      int totalFetched = 0;

      while (hasMorePages) {
        AppLogger().info('Fetching products page $page');
        List<dynamic> products;
        try {
          final response = await _fetchWooPageWithRetry(
            page,
            perPage,
            maxAttempts: 4,
            fields: 'id,sku,regular_price,sale_price,name,meta_data',
          );
          if (response.statusCode != 200) {
            AppLogger().warning('Failed to fetch products page $page. Status: ${response.statusCode}');
            failedPages.add(page);
            if (response.statusCode == 429 || response.statusCode >= 500) {
              AppLogger().warning('Stopping fetch loop due to HTTP ${response.statusCode}');
              break;
            }
            page++;
            await Future.delayed(const Duration(milliseconds: 800));
            continue;
          }
          products = json.decode(response.body) as List<dynamic>;
        } catch (e) {
          AppLogger().error('Page $page fetch failed: $e', source: 'FetchInfo');
          failedPages.add(page);
          page++;
          if (page > 150) {
            hasMorePages = false;
          }
          await Future.delayed(const Duration(milliseconds: 1200));
          continue;
        }

        if (products.isEmpty) {
          hasMorePages = false;
          break;
        }

        AppLogger().info('Received ${products.length} products from page $page');
        totalFetched += products.length;

        for (var product in products) {
          final sku = product['sku']?.toString() ?? '';
          final name = product['name']?.toString() ?? 'Unknown';
          final regularPrice = product['regular_price']?.toString() ?? '0';
          final salePrice = product['sale_price']?.toString() ?? '';

          String allBarcodes = '';
          if (product['meta_data'] != null) {
            for (var meta in product['meta_data']) {
              if (meta['key'] == '_holoo_barcodes') {
                allBarcodes = meta['value']?.toString() ?? '';
                break;
              }
            }
          }

          final finalSale = salePrice.isNotEmpty ? salePrice : regularPrice;

          if (sku.isNotEmpty) {
            productMap[sku] = ProductInfo(
              name: name,
              coverPrice: regularPrice,
              salePrice: finalSale,
            );
          }

          if (allBarcodes.isNotEmpty) {
            final barcodeList = allBarcodes.split(',');
            for (var barcode in barcodeList) {
              final trimmedBarcode = barcode.trim();
              if (trimmedBarcode.isNotEmpty) {
                productMap[trimmedBarcode] = ProductInfo(
                  name: name,
                  coverPrice: regularPrice,
                  salePrice: finalSale,
                );
              }
            }
          }
        }

        page++;
        final int delayMs = 200 + math.Random().nextInt(200);
        await Future.delayed(Duration(milliseconds: delayMs));
      }

      setState(() {
        _productMap = productMap;
      });

      AppLogger().info('Product info loading complete. Total: $totalFetched products, ${productMap.length} unique keys');

      int foundCount = 0;
      for (var barcode in _barcodes) {
        if (productMap.containsKey(barcode)) {
          foundCount++;
        }
      }
      AppLogger().info('Found product info for $foundCount out of ${_barcodes.length} scanned barcodes');

      final message = StringBuffer('اطلاعات محصول دریافت شد: $foundCount از ${_barcodes.length} بارکد');
      if (failedPages.isNotEmpty) {
        message.write(' (${failedPages.length} صفحه ناموفق)');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message.toString()),
            backgroundColor: failedPages.isEmpty ? Colors.green.shade700 : Colors.orange.shade800,
            duration: Duration(seconds: failedPages.isEmpty ? 3 : 6),
          ),
        );
      }
    } catch (e) {
      AppLogger().error('Error fetching product info: $e', source: 'FetchInfo');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در دریافت اطلاعات: ${e.runtimeType}'),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  List<ScannedItem> _getScannedItemsWithProductInfo() {
    // Build a barcode to product map from local database with pre-allocation
    Map<String, LocalProduct> barcodeToProduct = HashMap<String, LocalProduct>();
    for (var product in _localProducts) {
      // Map by SKU
      barcodeToProduct[product.sku] = product;
      // Map by main barcode
      if (product.mainBarcode.isNotEmpty) {
        barcodeToProduct[product.mainBarcode] = product;
      }
      // Map by extra barcodes
      if (product.extraBarcodes.isNotEmpty) {
        final extraBars = product.extraBarcodes.split(',');
        for (var bar in extraBars) {
          barcodeToProduct[bar.trim()] = product;
        }
      }
    }

    List<ScannedItem> items = List<ScannedItem>.empty(growable: true);
    Set<String> seenBarcodes = HashSet<String>();

    for (var barcode in _barcodes) {
      // Skip duplicates if unique only is enabled
      if (_showUniqueOnly && seenBarcodes.contains(barcode)) {
        continue;
      }
      seenBarcodes.add(barcode);

      final product = barcodeToProduct[barcode];
      if (product != null) {
        items.add(ScannedItem(
          barcode: barcode,
          name: product.name,
          coverPrice: product.coverPrice,
          salePrice: product.salePrice,
        ));
      } else {
        // Use product map from API if available
        final apiProduct = _productMap[barcode];
        if (apiProduct != null) {
          items.add(ScannedItem(
            barcode: barcode,
            name: apiProduct.name,
            coverPrice: apiProduct.coverPrice,
            salePrice: apiProduct.salePrice,
          ));
        } else {
          // Fallback to barcode only
          items.add(ScannedItem(
            barcode: barcode,
            name: 'محصول نامشخص',
            coverPrice: '0',
            salePrice: '0',
          ));
        }
      }
    }

    return items;
  }

  Future<void> _exportToPdf() async {
    final items = _getScannedItemsWithProductInfo();
    
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هیچ محصولی برای چاپ وجود ندارد')),
      );
      return;
    }

    AppLogger().info('Generating PDF with ${items.length} items');

    try {
      // Load Persian font before generating PDF
      await _loadPersianFont();
      
      final pdf = pw.Document();

      // Calculate how many pages we need
      final totalPages = (items.length / _labelConfig.labelsPerPage).ceil();

      // Pre-build label widgets to avoid rebuilding on each page
      final List<pw.Widget> allLabels = List<pw.Widget>.generate(items.length, (index) {
        return _buildLabel(items[index]);
      });

      for (int pageIndex = 0; pageIndex < totalPages; pageIndex++) {
        final startIndex = pageIndex * _labelConfig.labelsPerPage;
        final endIndex = (startIndex + _labelConfig.labelsPerPage).clamp(0, items.length);
        
        // Use pre-built labels
        final pageLabels = allLabels.sublist(startIndex, endIndex);
        // Add placeholders for remaining slots
        final remainingSlots = _labelConfig.labelsPerPage - pageLabels.length;
        if (remainingSlots > 0) {
          pageLabels.addAll(List<pw.Widget>.filled(remainingSlots, pw.Container()));
        }

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            build: (pw.Context context) {
              return pw.Container(
                padding: pw.EdgeInsets.only(
                  top: _labelConfig.marginTopMm * PdfPageFormat.mm,
                  bottom: _labelConfig.marginBottomMm * PdfPageFormat.mm,
                  left: _labelConfig.marginLeftMm * PdfPageFormat.mm,
                  right: _labelConfig.marginRightMm * PdfPageFormat.mm,
                ),
                child: pw.GridView(
                  crossAxisCount: _labelConfig.labelsPerRow,
                  children: pageLabels,
                ),
              );
            },
          ),
        );
      }

      AppLogger().info('PDF generated with $totalPages pages');

      // Get app documents directory
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'labels_$timestamp.pdf';
      final filePath = '${directory.path}/$fileName';
      
      final file = File(filePath);
      await file.writeAsBytes(await pdf.save());

      AppLogger().info('PDF saved to: $filePath');

      // Share the PDF
      final result = await Share.shareXFiles(
        [XFile(filePath)],
        subject: 'لیبل قیمت محصولات',
        text: 'لیبل قیمت ${items.length} محصول',
      );

      if (result.status == ShareResultStatus.success) {
        AppLogger().info('PDF shared successfully');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فایل PDF با موفقیت به اشتراک گذاشته شد')),
        );
      }

    } catch (e) {
      AppLogger().info('Error generating PDF: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطا در تولید PDF: $e')),
      );
    }
  }

  pw.Widget _buildLabel(ScannedItem item) {
    final pw.Font? font = _persianFont;

    // Parse numeric prices for accurate comparison
    final double? coverPriceVal = double.tryParse(item.coverPrice);
    final double? salePriceVal = double.tryParse(item.salePrice.isNotEmpty && item.salePrice != '0'
        ? item.salePrice
        : item.coverPrice);
    final String salePriceDisplay =
        (salePriceVal != null && item.salePrice.isNotEmpty && item.salePrice != '0')
            ? item.salePrice
            : item.coverPrice;

    final bool hasDiscount = _labelConfig.forceShowCoverPriceOnDiscount &&
        coverPriceVal != null &&
        salePriceVal != null &&
        salePriceVal < coverPriceVal;

    final String displaySalePrice = salePriceDisplay;
    final String displayCoverPrice = item.coverPrice;

    return pw.Container(
      width: _labelConfig.labelWidthMm * PdfPageFormat.mm,
      height: _labelConfig.labelHeightMm * PdfPageFormat.mm,
      margin: pw.EdgeInsets.only(
        right: _labelConfig.gapHorizontalMm * PdfPageFormat.mm,
        bottom: _labelConfig.gapVerticalMm * PdfPageFormat.mm,
      ),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: PdfColors.black, width: 1.2),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: <pw.Widget>[
          // ============ بخش بالا: شماره بارکد روی پس‌زمینه سیاه ============
          if (_labelConfig.showBarcodeText)
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 6),
              decoration: const pw.BoxDecoration(
                color: PdfColors.black,
                borderRadius: pw.BorderRadius.only(
                  topLeft: pw.Radius.circular(3),
                  topRight: pw.Radius.circular(3),
                ),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: <pw.Widget>[
                  pw.Svg(svg: _kBarcodeIconSvg, width: 14, height: 10),
                  pw.SizedBox(width: 6),
                  pw.Flexible(
                    child: pw.Text(
                      item.barcode.isNotEmpty ? item.barcode : '—',
                      style: pw.TextStyle(
                        font: font,
                        color: PdfColors.white,
                        fontSize: 10.5,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                      textAlign: pw.TextAlign.center,
                      textDirection: pw.TextDirection.rtl,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ),

          // ============ بخش میانی: نام کالا (بزرگ‌ترین فونت) ============
          pw.Expanded(
            child: pw.Container(
              alignment: pw.Alignment.center,
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: pw.Text(
                item.name,
                style: pw.TextStyle(
                  font: font,
                  fontSize: 15.5,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.black,
                ),
                maxLines: 3,
                textAlign: pw.TextAlign.center,
                textDirection: pw.TextDirection.rtl,
              ),
            ),
          ),

          // خط جداکننده نازک بین نام و قیمت‌ها
          pw.Container(
            margin: const pw.EdgeInsets.symmetric(horizontal: 10),
            height: 0.5,
            color: PdfColors.grey500,
          ),
          pw.SizedBox(height: 3),

          // ============ بخش پایینی: قیمت‌ها (تاکید بر قیمت فروش) ============
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: hasDiscount
                ? pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: <pw.Widget>[
                      // قیمت روی جلد با خط خورده
                      pw.Expanded(
                        child: pw.Column(
                          mainAxisAlignment: pw.MainAxisAlignment.center,
                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                          children: <pw.Widget>[
                            pw.Text(
                              'قیمت روی جلد',
                              style: pw.TextStyle(
                                font: font,
                                fontSize: 7.5,
                                color: PdfColors.grey700,
                              ),
                              textAlign: pw.TextAlign.center,
                              textDirection: pw.TextDirection.rtl,
                            ),
                            pw.SizedBox(height: 1.5),
                            pw.Text(
                              '$displayCoverPrice تومان',
                              style: pw.TextStyle(
                                font: font,
                                fontSize: 10,
                                decoration: pw.TextDecoration.lineThrough,
                                decorationThickness: 1.2,
                                color: PdfColors.grey600,
                              ),
                              textAlign: pw.TextAlign.center,
                              textDirection: pw.TextDirection.rtl,
                              maxLines: 1,
                            ),
                          ],
                        ),
                      ),
                      // جداکننده عمودی
                      pw.Container(
                        width: 0.8,
                        height: 28,
                        color: PdfColors.black,
                        margin: const pw.EdgeInsets.symmetric(horizontal: 2),
                      ),
                      // قیمت فروش برجسته
                      pw.Expanded(
                        flex: 2,
                        child: pw.Column(
                          mainAxisAlignment: pw.MainAxisAlignment.center,
                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                          children: <pw.Widget>[
                            pw.Text(
                              'قیمت فروش',
                              style: pw.TextStyle(
                                font: font,
                                fontSize: 8.5,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.black,
                              ),
                              textAlign: pw.TextAlign.center,
                              textDirection: pw.TextDirection.rtl,
                            ),
                            pw.SizedBox(height: 1),
                            pw.Text(
                              '$displaySalePrice تومان',
                              style: pw.TextStyle(
                                font: font,
                                fontSize: 15.5,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.black,
                              ),
                              textAlign: pw.TextAlign.center,
                              textDirection: pw.TextDirection.rtl,
                              maxLines: 1,
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: <pw.Widget>[
                      pw.Text(
                        'قیمت',
                        style: pw.TextStyle(
                          font: font,
                          fontSize: 8.5,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.black,
                        ),
                        textAlign: pw.TextAlign.center,
                        textDirection: pw.TextDirection.rtl,
                      ),
                      pw.SizedBox(height: 1),
                      pw.Text(
                        '$displaySalePrice تومان',
                        style: pw.TextStyle(
                          font: font,
                          fontSize: 17,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.black,
                        ),
                        textAlign: pw.TextAlign.center,
                        textDirection: pw.TextDirection.rtl,
                        maxLines: 1,
                      ),
                    ],
                  ),
          ),
          pw.SizedBox(height: 2),
        ],
      ),
    );
  }

  static const String _kBarcodeIconSvg =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 12" fill="#FFFFFF"><path d="M1 0h1v12H1zM3.5 0h1v12h-1zM6 0h.5v12H6zM8 0h2v12H8zM11.5 0h.5v12h-.5zM13.5 0h1v12h-1zM15.5 0h.5v12h-.5zM17.5 0h1.5v12h-1.5zM20.5 0h.5v12h-.5zM22.5 0h1v12h-1z"/></svg>';

  Future<void> _showPdfTemplateSettings() async {
    // Make a working copy so that if user cancels, we don't have partial changes
    final LabelConfig tmpConfig = LabelConfig.fromJson(_labelConfig.toJson());
    final bool tmpShowUniqueOnly = _showUniqueOnly;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('تنظیمات قالب PDF لیبل'),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'چیدمان لیبل‌ها در هر صفحه A4',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 16),
              
              // Labels per row
              Row(
                children: [
                  const Text('تعداد ستون: '),
                  Expanded(
                    child: Slider(
                      value: tmpConfig.labelsPerRow.toDouble(),
                      min: 1,
                      max: 5,
                      divisions: 4,
                      label: tmpConfig.labelsPerRow.toString(),
                      onChanged: (value) {
                        setDialogState(() {
                          tmpConfig.labelsPerRow = value.toInt();
                        });
                      },
                    ),
                  ),
                  Text('${tmpConfig.labelsPerRow}'),
                ],
              ),
              
              // Labels per column
              Row(
                children: [
                  const Text('تعداد ردیف: '),
                  Expanded(
                    child: Slider(
                      value: tmpConfig.labelsPerColumn.toDouble(),
                      min: 1,
                      max: 7,
                      divisions: 6,
                      label: tmpConfig.labelsPerColumn.toString(),
                      onChanged: (value) {
                        setDialogState(() {
                          tmpConfig.labelsPerColumn = value.toInt();
                        });
                      },
                    ),
                  ),
                  Text('${tmpConfig.labelsPerColumn}'),
                ],
              ),
              
              const Divider(),
              Text(
                'مجموع لیبل در هر صفحه: ${tmpConfig.labelsPerPage}',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
              ),
              
              const SizedBox(height: 16),
              const Text(
                'اندازه لیبل (میلی‌متر)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 16),
              
              // Label width
              Row(
                children: [
                  const Text('عرض: ', style: TextStyle(fontSize: 12)),
                  Expanded(
                    child: Slider(
                      value: tmpConfig.labelWidthMm,
                      min: 40,
                      max: 100,
                      divisions: 12,
                      label: '${tmpConfig.labelWidthMm.toInt()} mm',
                      onChanged: (value) {
                        setDialogState(() {
                          tmpConfig.labelWidthMm = value;
                        });
                      },
                    ),
                  ),
                  Text('${tmpConfig.labelWidthMm.toInt()} mm', style: const TextStyle(fontSize: 12)),
                ],
              ),
              
              // Label height
              Row(
                children: [
                  const Text('ارتفاع: ', style: TextStyle(fontSize: 12)),
                  Expanded(
                    child: Slider(
                      value: tmpConfig.labelHeightMm,
                      min: 25,
                      max: 60,
                      divisions: 7,
                      label: '${tmpConfig.labelHeightMm.toInt()} mm',
                      onChanged: (value) {
                        setDialogState(() {
                          tmpConfig.labelHeightMm = value;
                        });
                      },
                    ),
                  ),
                  Text('${tmpConfig.labelHeightMm.toInt()} mm', style: const TextStyle(fontSize: 12)),
                ],
              ),
              
              const SizedBox(height: 16),
              const Text(
                'حاشیه‌ها و فاصله‌ها (میلی‌متر)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              
              // Margins
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildMarginField(setDialogState, 'بالا', () => tmpConfig.marginTopMm, (v) => tmpConfig.marginTopMm = v),
                  _buildMarginField(setDialogState, 'پایین', () => tmpConfig.marginBottomMm, (v) => tmpConfig.marginBottomMm = v),
                  _buildMarginField(setDialogState, 'چپ', () => tmpConfig.marginLeftMm, (v) => tmpConfig.marginLeftMm = v),
                  _buildMarginField(setDialogState, 'راست', () => tmpConfig.marginRightMm, (v) => tmpConfig.marginRightMm = v),
                  _buildMarginField(setDialogState, 'فاصله افقی', () => tmpConfig.gapHorizontalMm, (v) => tmpConfig.gapHorizontalMm = v),
                  _buildMarginField(setDialogState, 'فاصله عمودی', () => tmpConfig.gapVerticalMm, (v) => tmpConfig.gapVerticalMm = v),
                ],
              ),
              
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              const Text(
                'گزینه‌های نمایش لیبل',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('نمایش شماره بارکد متنی'),
                subtitle: const Text('در نوار بالای لیبل'),
                value: tmpConfig.showBarcodeText,
                onChanged: (value) {
                  setDialogState(() {
                    tmpConfig.showBarcodeText = value;
                  });
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('نمایش قیمت روی جلد در صورت تخفیف'),
                subtitle: const Text('فقط وقتی قیمت فروش کمتر باشد'),
                value: tmpConfig.forceShowCoverPriceOnDiscount,
                onChanged: (value) {
                  setDialogState(() {
                    tmpConfig.forceShowCoverPriceOnDiscount = value;
                  });
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('فقط محصولات یکتا'),
                subtitle: const Text('حذف بارکدهای تکراری هنگام چاپ'),
                value: tmpShowUniqueOnly,
                onChanged: (value) {
                  // Modify the actual state since showUniqueOnly isn't in LabelConfig
                  _showUniqueOnly = value;
                  setDialogState(() {});
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                setDialogState(() {
                  final LabelConfig reset = LabelConfig();
                  tmpConfig.labelsPerRow = reset.labelsPerRow;
                  tmpConfig.labelsPerColumn = reset.labelsPerColumn;
                  tmpConfig.labelWidthMm = reset.labelWidthMm;
                  tmpConfig.labelHeightMm = reset.labelHeightMm;
                  tmpConfig.marginTopMm = reset.marginTopMm;
                  tmpConfig.marginBottomMm = reset.marginBottomMm;
                  tmpConfig.marginLeftMm = reset.marginLeftMm;
                  tmpConfig.marginRightMm = reset.marginRightMm;
                  tmpConfig.gapHorizontalMm = reset.gapHorizontalMm;
                  tmpConfig.gapVerticalMm = reset.gapVerticalMm;
                  tmpConfig.showBarcodeText = reset.showBarcodeText;
                  tmpConfig.forceShowCoverPriceOnDiscount = reset.forceShowCoverPriceOnDiscount;
                });
              },
              child: const Text('بازنشانی'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('انصراف'),
            ),
            ElevatedButton(
              onPressed: () async {
                final bool ok = await saveLabelConfig(tmpConfig);
                if (mounted) {
                  setState(() {
                    _labelConfig = tmpConfig;
                  });
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(ok ? 'تنظیمات ذخیره شد' : 'خطا در ذخیره تنظیمات'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
              child: const Text('ذخیره'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMarginField(
    StateSetter setDialogState,
    String label,
    double Function() getValue,
    void Function(double) setValue,
  ) {
    return SizedBox(
      width: 100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11)),
          Row(
            children: [
              Expanded(
                child: TextField(
                  keyboardType: TextInputType.number,
                  controller: TextEditingController(text: getValue().toInt().toString()),
                  onChanged: (value) {
                    final num = double.tryParse(value);
                    if (num != null) {
                      setValue(num);
                      setDialogState(() {});
                    }
                  },
                  style: const TextStyle(fontSize: 11),
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    isDense: true,
                  ),
                ),
              ),
              const Text(' mm', style: TextStyle(fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }


  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inMinutes < 1) {
      return 'همین الان';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes} دقیقه پیش';
    } else if (difference.inDays < 1) {
      return '${difference.inHours} ساعت پیش';
    } else {
      final month = dateTime.month.toString().padLeft(2, '0');
      final day = dateTime.day.toString().padLeft(2, '0');
      final hour = dateTime.hour.toString().padLeft(2, '0');
      final minute = dateTime.minute.toString().padLeft(2, '0');
      return '${dateTime.year}/$month/$day $hour:$minute';
    }
  }

  void _printLabels() {
    _fetchProductInfo();
    Future.delayed(const Duration(milliseconds: 500), () {
      _exportToPdf();
    });
  }

  void _showProductsList() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProductsListPage(products: _localProducts),
      ),
    );
  }
}

// Custom painter for scan overlay
class ScanOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..style = PaintingStyle.fill;

    final centerRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width * 0.7,
      height: size.height * 0.4,
    );

    // Draw semi-transparent overlay
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
    
    // Clear center rectangle
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
        Path()..addRRect(RRect.fromRectAndRadius(centerRect, const Radius.circular(12))),
      ),
      Paint()..blendMode = BlendMode.clear,
    );

    // Draw corner markers
    final markerPaint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    const markerLength = 30.0;
    
    // Top-left
    canvas.drawLine(
      Offset(centerRect.left, centerRect.top + markerLength),
      Offset(centerRect.left, centerRect.top),
      markerPaint,
    );
    canvas.drawLine(
      Offset(centerRect.left, centerRect.top),
      Offset(centerRect.left + markerLength, centerRect.top),
      markerPaint,
    );

    // Top-right
    canvas.drawLine(
      Offset(centerRect.right - markerLength, centerRect.top),
      Offset(centerRect.right, centerRect.top),
      markerPaint,
    );
    canvas.drawLine(
      Offset(centerRect.right, centerRect.top),
      Offset(centerRect.right, centerRect.top + markerLength),
      markerPaint,
    );

    // Bottom-left
    canvas.drawLine(
      Offset(centerRect.left, centerRect.bottom - markerLength),
      Offset(centerRect.left, centerRect.bottom),
      markerPaint,
    );
    canvas.drawLine(
      Offset(centerRect.left, centerRect.bottom),
      Offset(centerRect.left + markerLength, centerRect.bottom),
      markerPaint,
    );

    // Bottom-right
    canvas.drawLine(
      Offset(centerRect.right - markerLength, centerRect.bottom),
      Offset(centerRect.right, centerRect.bottom),
      markerPaint,
    );
    canvas.drawLine(
      Offset(centerRect.right, centerRect.bottom - markerLength),
      Offset(centerRect.right, centerRect.bottom),
      markerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ProductsListPage extends StatefulWidget {
  final List<LocalProduct> products;

  const ProductsListPage({super.key, required this.products});

  @override
  State<ProductsListPage> createState() => _ProductsListPageState();
}

class _ProductsListPageState extends State<ProductsListPage> {
  late List<LocalProduct> _filteredProducts;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filteredProducts = widget.products;
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    setState(() {
      final query = _searchController.text.toLowerCase();
      _filteredProducts = widget.products.where((product) {
        return product.name.toLowerCase().contains(query) ||
               product.sku.toLowerCase().contains(query) ||
               product.mainBarcode.contains(query);
      }).toList();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('محصولات'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        left: false,
        right: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'جستجو بر اساس نام، بارکد یا کد محصول',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                ),
              ),
            ),
            Expanded(
              child: _filteredProducts.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'محصولی یافت نشد',
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.of(context).padding.bottom + 16,
                      ),
                      itemCount: _filteredProducts.length,
                      itemBuilder: (context, index) {
                        final product = _filteredProducts[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          child: ExpansionTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.blue,
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            title: Text(
                              product.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text('کد: ${product.sku}'),
                            trailing: Text(
                              '${product.salePrice} تومان',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildInfoRow('بارکد اصلی', product.mainBarcode),
                                    if (product.extraBarcodes.isNotEmpty)
                                      _buildInfoRow('بارکدهای اضافی', product.extraBarcodes),
                                    _buildInfoRow('قیمت روی جلد', '${product.coverPrice} تومان'),
                                    _buildInfoRow('قیمت فروش', '${product.salePrice} تومان'),
                                    _buildInfoRow('موجودی', product.stockQuantity.toString()),
                                    if (product.lastSynced != null)
                                      _buildInfoRow(
                                        'آخرین بروزرسانی',
                                        product.lastSynced!.toString().substring(0, 16),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class ProductInfo {
  final String name;
  final String coverPrice;
  final String salePrice;

  ProductInfo({
    required this.name,
    required this.coverPrice,
    required this.salePrice,
  });
}
