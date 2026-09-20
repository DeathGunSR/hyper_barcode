import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
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
  });

  int get labelsPerPage => labelsPerRow * labelsPerColumn;
}

void main() {
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
    return DebugOverlay(
      child: MaterialApp(
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
        home: MenuPage(
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
                // Show settings
              } else if (value == 'about') {
                // Show about
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'settings', child: Text('تنظیمات')),
              const PopupMenuItem(value: 'about', child: Text('درباره')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Sync status bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.blue.shade50,
            child: Row(
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
                        ? 'در حال همگام‌سازی...'
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
    });

    AppLogger().info('Starting product sync from WooCommerce (background)');
    
    // Start sync as a background task without blocking UI
    _runBackgroundSync();
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
      const int perPage = 100;
      bool hasMorePages = true;

      while (hasMorePages) {
        AppLogger().info('Fetching products page $page');
        
        final url = Uri.parse(
          '$_wooCommerceUrl/wp-json/wc/v3/products?per_page=$perPage&page=$page&consumer_key=$_consumerKey&consumer_secret=$_consumerSecret&_fields=id,sku,regular_price,sale_price,name,meta_data,stock_quantity',
        );

        final response = await http.get(url);

        if (response.statusCode != 200) {
          AppLogger().info('Failed to fetch products page $page. Status: ${response.statusCode}');
          break;
        }

        final List<dynamic> products = json.decode(response.body);
        
        if (products.isEmpty) {
          hasMorePages = false;
          break;
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

        page++;
        totalProducts = processedCount + 100; // Update estimate
        // Reduced delay for better performance
        await Future.delayed(const Duration(milliseconds: 200));
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
      });

      await _loadLocalProducts();

      // Show success notification
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('همگام‌سازی کامل شد: $newCount محصول جدید، $updatedCount محصول بروزرسانی شد'),
                ),
              ],
            ),
            duration: const Duration(seconds: 4),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }

      AppLogger().info('Sync completed successfully');

    } catch (e) {
      AppLogger().info('Error syncing products: $e');
      setState(() {
        _isSyncing = false;
      });
      
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

    AppLogger().info('Fetching product info for ${_barcodes.length} barcodes');

    try {
      // Pre-allocate map with estimated capacity
      Map<String, ProductInfo> productMap = HashMap<String, ProductInfo>();
      int page = 1;
      const int perPage = 100;
      bool hasMorePages = true;

      // Fetch all products page by page
      while (hasMorePages) {
        AppLogger().info('Fetching products page $page');
        
        final url = Uri.parse(
          '$_wooCommerceUrl/wp-json/wc/v3/products?per_page=$perPage&page=$page&consumer_key=$_consumerKey&consumer_secret=$_consumerSecret&_fields=id,sku,regular_price,sale_price,name,meta_data',
        );

        AppLogger().info('API Request: $url');
        final response = await http.get(url);
        AppLogger().info('API Response Status: ${response.statusCode}');

        if (response.statusCode != 200) {
          AppLogger().info('Failed to fetch products page $page. Status: ${response.statusCode}');
          break;
        }

        final List<dynamic> products = json.decode(response.body);
        
        if (products.isEmpty) {
          hasMorePages = false;
          break;
        }

        AppLogger().info('Received ${products.length} products from page $page');

        for (var product in products) {
          final sku = product['sku']?.toString() ?? '';
          final name = product['name']?.toString() ?? 'Unknown';
          final regularPrice = product['regular_price']?.toString() ?? '0';
          final salePrice = product['sale_price']?.toString() ?? '';

          // Extract barcodes from meta_data
          String allBarcodes = '';
          if (product['meta_data'] != null) {
            for (var meta in product['meta_data']) {
              if (meta['key'] == '_holoo_barcodes') {
                allBarcodes = meta['value']?.toString() ?? '';
                break;
              }
            }
          }

          // Map SKU to product info
          if (sku.isNotEmpty) {
            productMap[sku] = ProductInfo(
              name: name,
              coverPrice: regularPrice,
              salePrice: salePrice.isNotEmpty ? salePrice : regularPrice,
            );
          }

          // Map all barcodes (comma-separated) to this product
          if (allBarcodes.isNotEmpty) {
            final barcodeList = allBarcodes.split(',');
            for (var barcode in barcodeList) {
              final trimmedBarcode = barcode.trim();
              if (trimmedBarcode.isNotEmpty) {
                productMap[trimmedBarcode] = ProductInfo(
                  name: name,
                  coverPrice: regularPrice,
                  salePrice: salePrice.isNotEmpty ? salePrice : regularPrice,
                );
              }
            }
          }
        }

        page++;
        // Reduced delay for better performance
        await Future.delayed(const Duration(milliseconds: 300));
      }

      setState(() {
        _productMap = productMap;
      });

      AppLogger().info('Product info loading complete. Total products in map: ${productMap.length}');
      
      // Log how many scanned barcodes were found
      int foundCount = 0;
      for (var barcode in _barcodes) {
        if (productMap.containsKey(barcode)) {
          foundCount++;
        }
      }
      AppLogger().info('Found product info for $foundCount out of ${_barcodes.length} scanned barcodes');
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('اطلاعات محصول دریافت شد: $foundCount از ${_barcodes.length} بارکد')),
      );
    } catch (e) {
      AppLogger().info('Error fetching product info: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطا: $e')),
      );
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
    
    return pw.Container(
      width: _labelConfig.labelWidthMm * PdfPageFormat.mm,
      height: _labelConfig.labelHeightMm * PdfPageFormat.mm,
      margin: pw.EdgeInsets.only(
        right: _labelConfig.gapHorizontalMm * PdfPageFormat.mm,
        bottom: _labelConfig.gapVerticalMm * PdfPageFormat.mm,
      ),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 1),
        borderRadius: pw.BorderRadius.circular(3),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          // Barcode section with black background at top
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 6),
            decoration: const pw.BoxDecoration(
              color: PdfColors.black,
              borderRadius: pw.BorderRadius.only(
                topLeft: pw.Radius.circular(2),
                topRight: pw.Radius.circular(2),
              ),
            ),
            child: pw.Column(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Text(
                  item.barcode,
                  style: pw.TextStyle(
                    font: font,
                    color: PdfColors.white,
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  textAlign: pw.TextAlign.center,
                  textDirection: pw.TextDirection.rtl,
                ),
              ],
            ),
          ),
          
          pw.SizedBox(height: 5),
          
          // Product name - bold and clear
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 5),
            child: pw.Text(
              item.name,
              style: pw.TextStyle(
                font: font,
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black,
              ),
              maxLines: 2,
              textAlign: pw.TextAlign.center,
              textDirection: pw.TextDirection.rtl,
            ),
          ),
          
          pw.Spacer(),
          
          // Prices row with clear distinction
          pw.Builder(
            builder: (pw.Context context) {
              // بررسی وجود قیمت فروش فوق‌العاده
              final bool hasDiscount = item.salePrice.isNotEmpty && 
                                       item.salePrice != '0' &&
                                       item.salePrice != item.coverPrice;
              
              return pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                children: [
                  if (hasDiscount) ...[
                    // Cover Price (crossed out) - only show if there's a discount
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.center,
                        children: [
                          pw.Text(
                            'قیمت رو جلد',
                            style: pw.TextStyle(
                              font: font,
                              fontSize: 8,
                              color: PdfColors.grey700,
                            ),
                            textDirection: pw.TextDirection.rtl,
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            '${item.coverPrice} تومان',
                            style: pw.TextStyle(
                              font: font,
                              fontSize: 10,
                              fontWeight: pw.FontWeight.normal,
                              decoration: pw.TextDecoration.lineThrough,
                              color: PdfColors.grey600,
                            ),
                            textDirection: pw.TextDirection.rtl,
                          ),
                        ],
                      ),
                    ),
                    
                    pw.Container(
                      width: 1,
                      height: 30,
                      color: PdfColors.grey400,
                    ),
                  ],
                  
                  // Sale Price or Regular Price (highlighted)
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text(
                          hasDiscount ? 'قیمت فروش' : 'قیمت',
                          style: pw.TextStyle(
                            font: font,
                            fontSize: 9,
                            color: PdfColors.black,
                            fontWeight: pw.FontWeight.bold,
                          ),
                          textDirection: pw.TextDirection.rtl,
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          '${hasDiscount ? item.salePrice : item.coverPrice} تومان',
                          style: pw.TextStyle(
                            font: font,
                            fontSize: hasDiscount ? 14 : 16,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.black,
                          ),
                          textDirection: pw.TextDirection.rtl,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          
          pw.SizedBox(height: 3),
        ],
      ),
    );
  }

  void _showLabelSettings() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('تنظیمات لیبل'),
          content: SingleChildScrollView(
            child: Column(
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
                        value: _labelConfig.labelsPerRow.toDouble(),
                        min: 1,
                        max: 5,
                        divisions: 4,
                        label: _labelConfig.labelsPerRow.toString(),
                        onChanged: (value) {
                          setDialogState(() {
                            _labelConfig.labelsPerRow = value.toInt();
                          });
                        },
                      ),
                    ),
                    Text('${_labelConfig.labelsPerRow}'),
                  ],
                ),
                
                // Labels per column
                Row(
                  children: [
                    const Text('تعداد ردیف: '),
                    Expanded(
                      child: Slider(
                        value: _labelConfig.labelsPerColumn.toDouble(),
                        min: 1,
                        max: 7,
                        divisions: 6,
                        label: _labelConfig.labelsPerColumn.toString(),
                        onChanged: (value) {
                          setDialogState(() {
                            _labelConfig.labelsPerColumn = value.toInt();
                          });
                        },
                      ),
                    ),
                    Text('${_labelConfig.labelsPerColumn}'),
                  ],
                ),
                
                const Divider(),
                Text(
                  'مجموع لیبل در هر صفحه: ${_labelConfig.labelsPerPage}',
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
                        value: _labelConfig.labelWidthMm,
                        min: 40,
                        max: 100,
                        divisions: 12,
                        label: '${_labelConfig.labelWidthMm.toInt()} mm',
                        onChanged: (value) {
                          setDialogState(() {
                            _labelConfig.labelWidthMm = value;
                          });
                        },
                      ),
                    ),
                    Text('${_labelConfig.labelWidthMm.toInt()} mm', style: const TextStyle(fontSize: 12)),
                  ],
                ),
                
                // Label height
                Row(
                  children: [
                    const Text('ارتفاع: ', style: TextStyle(fontSize: 12)),
                    Expanded(
                      child: Slider(
                        value: _labelConfig.labelHeightMm,
                        min: 25,
                        max: 60,
                        divisions: 7,
                        label: '${_labelConfig.labelHeightMm.toInt()} mm',
                        onChanged: (value) {
                          setDialogState(() {
                            _labelConfig.labelHeightMm = value;
                          });
                        },
                      ),
                    ),
                    Text('${_labelConfig.labelHeightMm.toInt()} mm', style: const TextStyle(fontSize: 12)),
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
                    _buildMarginField(setDialogState, 'بالا', () => _labelConfig.marginTopMm, (v) => _labelConfig.marginTopMm = v),
                    _buildMarginField(setDialogState, 'پایین', () => _labelConfig.marginBottomMm, (v) => _labelConfig.marginBottomMm = v),
                    _buildMarginField(setDialogState, 'چپ', () => _labelConfig.marginLeftMm, (v) => _labelConfig.marginLeftMm = v),
                    _buildMarginField(setDialogState, 'راست', () => _labelConfig.marginRightMm, (v) => _labelConfig.marginRightMm = v),
                    _buildMarginField(setDialogState, 'فاصله افقی', () => _labelConfig.gapHorizontalMm, (v) => _labelConfig.gapHorizontalMm = v),
                    _buildMarginField(setDialogState, 'فاصله عمودی', () => _labelConfig.gapVerticalMm, (v) => _labelConfig.gapVerticalMm = v),
                  ],
                ),
                
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('فقط محصولات یکتا'),
                  subtitle: const Text('حذف بارکدهای تکراری'),
                  value: _showUniqueOnly,
                  onChanged: (value) {
                    setDialogState(() {
                      _showUniqueOnly = value;
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setDialogState(() {
                  _labelConfig = LabelConfig();
                });
              },
              child: const Text('بازنشانی'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('انصراف'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {});
                Navigator.pop(context);
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
      body: Column(
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
