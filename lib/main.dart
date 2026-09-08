import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// Logger class for debugging
class AppLogger {
  static final List<String> _logs = [];
  static final int _maxLogs = 200;

  static void log(String message) {
    final timestamp = DateTime.now().toString().substring(0, 19);
    final logEntry = '[$timestamp] $message';
    _logs.add(logEntry);
    if (_logs.length > _maxLogs) {
      _logs.removeAt(0);
    }
    print(logEntry);
  }

  static List<String> getLogs() => List.unmodifiable(_logs);

  static void clear() {
    _logs.clear();
    log('Logs cleared');
  }
}

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
  runApp(const BarcodeScannerApp());
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
        AppLocalizationsDelegate(_locale),
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
      home: HomePage(
        currentLocale: _locale,
        onLocaleChanged: updateLocale,
        themeMode: _themeMode,
        onThemeModeChanged: updateThemeMode,
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
  Map<String, ProductInfo> _productMap = {};
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
    AppLogger.log('App initialized');
    _initializeDatabase();
    _loadStoragePath();
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
          AppLogger.log('Database table created');
        },
      );
      
      AppLogger.log('Database initialized at: $path');
      await _loadLocalProducts();
    } catch (e) {
      AppLogger.log('Error initializing database: $e');
    }
  }

  Future<void> _loadStoragePath() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      setState(() {
        _storagePath = directory.path;
      });
      AppLogger.log('Storage path loaded: $_storagePath');
    } catch (e) {
      AppLogger.log('Error loading storage path: $e');
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
      AppLogger.log('Loaded ${_localProducts.length} products from local database');
    } catch (e) {
      AppLogger.log('Error loading local products: $e');
    }
  }

  Future<void> _syncProductsFromWooCommerce() async {
    if (_isSyncing) return;
    
    setState(() {
      _isSyncing = true;
    });

    AppLogger.log('Starting product sync from WooCommerce');

    try {
      int totalProducts = 0;
      int processedCount = 0;
      int newCount = 0;
      int updatedCount = 0;

      // Show progress dialog
      _showProgressDialog('در حال بروزرسانی...', 0, 0);

      // First, get total count
      final url = Uri.parse(
        '$_wooCommerceUrl/wp-json/wc/v3/products?per_page=1&page=1&consumer_key=$_consumerKey&consumer_secret=$_consumerSecret&_fields=id',
      );
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        totalProducts = 1000; // Estimate
      }

      List<LocalProduct> fetchedProducts = [];
      int page = 1;
      int perPage = 100;
      bool hasMorePages = true;

      while (hasMorePages) {
        AppLogger.log('Fetching products page $page');
        
        final url = Uri.parse(
          '$_wooCommerceUrl/wp-json/wc/v3/products?per_page=$perPage&page=$page&consumer_key=$_consumerKey&consumer_secret=$_consumerSecret&_fields=id,sku,regular_price,sale_price,name,meta_data,stock_quantity',
        );

        final response = await http.get(url);

        if (response.statusCode != 200) {
          AppLogger.log('Failed to fetch products page $page. Status: ${response.statusCode}');
          break;
        }

        final List<dynamic> products = json.decode(response.body);
        
        if (products.isEmpty) {
          hasMorePages = false;
          break;
        }

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

          fetchedProducts.add(LocalProduct(
            sku: sku,
            name: name,
            coverPrice: regularPrice,
            salePrice: salePrice.isNotEmpty ? salePrice : regularPrice,
            mainBarcode: mainBarcode,
            extraBarcodes: extraBarcodes,
            stockQuantity: double.tryParse(stockQuantity.toString()) ?? 0.0,
            lastSynced: DateTime.now(),
          ));

          processedCount++;
          
          // Update progress every 10 products
          if (processedCount % 10 == 0) {
            Navigator.pop(context); // Close previous dialog
            _showProgressDialog('در حال بروزرسانی...', processedCount, totalProducts);
          }
        }

        page++;
        totalProducts = processedCount + 100; // Update estimate
        await Future.delayed(const Duration(milliseconds: 300));
      }

      AppLogger.log('Fetched ${fetchedProducts.length} products from WooCommerce');

      // Insert or update in local database
      if (_database != null) {
        await _database!.transaction((txn) async {
          for (var product in fetchedProducts) {
            // Check if exists
            var existing = await txn.query(
              'products',
              where: 'sku = ?',
              whereArgs: [product.sku],
            );

            if (existing.isEmpty) {
              await txn.insert('products', product.toMap());
              newCount++;
            } else {
              await txn.update(
                'products',
                product.toMap(),
                where: 'sku = ?',
                whereArgs: [product.sku],
              );
              updatedCount++;
            }
          }
        });

        AppLogger.log('Database updated: $newCount new, $updatedCount updated');
      }

      Navigator.pop(context); // Close progress dialog
      
      setState(() {
        _lastSyncTime = DateTime.now();
      });

      await _loadLocalProducts();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('همگام‌سازی کامل شد: $newCount محصول جدید، $updatedCount محصول بروزرسانی شد'),
          duration: const Duration(seconds: 3),
        ),
      );

    } catch (e) {
      AppLogger.log('Error syncing products: $e');
      if (mounted) {
        Navigator.pop(context); // Close progress dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در همگام‌سازی: $e')),
        );
      }
    } finally {
      setState(() {
        _isSyncing = false;
      });
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
      setState(() {
        _barcodes.add(barcode);
      });
    }
  }

  void _removeBarcode(int index) {
    setState(() {
      _barcodes.removeAt(index);
    });
  }

  void _clearBarcodes() {
    setState(() {
      _barcodes.clear();
    });
  }

  Future<void> _fetchProductInfo() async {
    if (_barcodes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هیچ بارکدی برای دریافت اطلاعات وجود ندارد')),
      );
      return;
    }

    AppLogger.log('Fetching product info for ${_barcodes.length} barcodes');

    try {
      Map<String, ProductInfo> productMap = {};
      int page = 1;
      int perPage = 100;
      bool hasMorePages = true;

      // Fetch all products page by page
      while (hasMorePages) {
        AppLogger.log('Fetching products page $page');
        
        final url = Uri.parse(
          '$_wooCommerceUrl/wp-json/wc/v3/products?per_page=$perPage&page=$page&consumer_key=$_consumerKey&consumer_secret=$_consumerSecret&_fields=id,sku,regular_price,sale_price,name,meta_data',
        );

        AppLogger.log('API Request: $url');
        final response = await http.get(url);
        AppLogger.log('API Response Status: ${response.statusCode}');

        if (response.statusCode != 200) {
          AppLogger.log('Failed to fetch products page $page. Status: ${response.statusCode}');
          break;
        }

        final List<dynamic> products = json.decode(response.body);
        
        if (products.isEmpty) {
          hasMorePages = false;
          break;
        }

        AppLogger.log('Received ${products.length} products from page $page');

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
            AppLogger.log('Mapped SKU: $sku -> $name');
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
                AppLogger.log('Mapped Barcode: $trimmedBarcode -> $name');
              }
            }
          }
        }

        page++;
        // Small delay to avoid rate limiting
        await Future.delayed(const Duration(milliseconds: 500));
      }

      setState(() {
        _productMap = productMap;
      });

      AppLogger.log('Product info loading complete. Total products in map: ${productMap.length}');
      
      // Log how many scanned barcodes were found
      int foundCount = 0;
      for (var barcode in _barcodes) {
        if (productMap.containsKey(barcode)) {
          foundCount++;
        }
      }
      AppLogger.log('Found product info for $foundCount out of ${_barcodes.length} scanned barcodes');
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('اطلاعات محصول دریافت شد: $foundCount از ${_barcodes.length} بارکد')),
      );
    } catch (e) {
      AppLogger.log('Error fetching product info: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطا: $e')),
      );
    }
  }

  List<ScannedItem> _getScannedItemsWithProductInfo() {
    // Build a barcode to product map from local database
    Map<String, LocalProduct> barcodeToProduct = {};
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

    List<ScannedItem> items = [];
    Set<String> seenBarcodes = {};

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

    AppLogger.log('Generating PDF with ${items.length} items');

    try {
      final pdf = pw.Document();

      // Calculate how many pages we need
      final totalPages = (items.length / _labelConfig.labelsPerPage).ceil();

      for (int pageIndex = 0; pageIndex < totalPages; pageIndex++) {
        final startIndex = pageIndex * _labelConfig.labelsPerPage;
        final endIndex = (startIndex + _labelConfig.labelsPerPage).clamp(0, items.length);
        final pageItems = items.sublist(startIndex, endIndex);

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
                  children: List.generate(_labelConfig.labelsPerPage, (index) {
                    if (index < pageItems.length) {
                      final item = pageItems[index];
                      return _buildLabel(item);
                    } else {
                      // Empty placeholder
                      return pw.Container();
                    }
                  }),
                ),
              );
            },
          ),
        );
      }

      AppLogger.log('PDF generated with $totalPages pages');

      // Get app documents directory
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'labels_$timestamp.pdf';
      final filePath = '${directory.path}/$fileName';
      
      final file = File(filePath);
      await file.writeAsBytes(await pdf.save());

      AppLogger.log('PDF saved to: $filePath');

      // Share the PDF
      final result = await Share.shareXFiles(
        [XFile(filePath)],
        subject: 'لیبل قیمت محصولات',
        text: 'لیبل قیمت ${items.length} محصول',
      );

      if (result.status == ShareResultStatus.success) {
        AppLogger.log('PDF shared successfully');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فایل PDF با موفقیت به اشتراک گذاشته شد')),
        );
      }

    } catch (e) {
      AppLogger.log('Error generating PDF: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطا در تولید PDF: $e')),
      );
    }
  }

  pw.Widget _buildLabel(ScannedItem item) {
    return pw.Container(
      width: _labelConfig.labelWidthMm * PdfPageFormat.mm,
      height: _labelConfig.labelHeightMm * PdfPageFormat.mm,
      margin: pw.EdgeInsets.only(
        right: _labelConfig.gapHorizontalMm * PdfPageFormat.mm,
        bottom: _labelConfig.gapVerticalMm * PdfPageFormat.mm,
      ),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300, width: 1),
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Header with store name or title
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 3),
            decoration: pw.BoxDecoration(
              color: PdfColors.blueGrey700,
              borderRadius: const pw.BorderRadius.only(
                topLeft: pw.Radius.circular(4),
                topRight: pw.Radius.circular(4),
              ),
            ),
            child: pw.Text(
              'فروشگاه اینترنتی ebimarket.ir',
              style: pw.TextStyle(
                color: PdfColors.white,
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
              textAlign: pw.TextAlign.center,
            ),
          ),
          
          pw.SizedBox(height: 4),
          
          // Product name
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 4),
            child: pw.Text(
              item.name,
              style: const pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
              ),
              maxLines: 2,
              textAlign: pw.TextAlign.right,
            ),
          ),
          
          pw.SizedBox(height: 3),
          
          // Prices row
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
            children: [
              // Cover Price
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(
                      'قیمت رو جلد',
                      style: pw.TextStyle(
                        fontSize: 7,
                        color: PdfColors.grey600,
                      ),
                    ),
                    pw.Text(
                      '${item.coverPrice} تومان',
                      style: const pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.normal,
                        decoration: pw.TextDecoration.lineThrough,
                      ),
                    ),
                  ],
                ),
              ),
              
              // Sale Price (highlighted)
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(
                      'قیمت فروش',
                      style: pw.TextStyle(
                        fontSize: 7,
                        color: PdfColors.green700,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      '${item.salePrice} تومان',
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.red700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          pw.Spacer(),
          
          // Barcode at bottom
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 3),
            decoration: pw.BoxDecoration(
              border: pw.Border(
                top: pw.BorderSide(color: PdfColors.grey300, width: 1),
              ),
            ),
            child: pw.Column(
              children: [
                pw.Text(
                  item.barcode,
                  style: const pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
              ],
            ),
          ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('بارکد اسکنر حرفه‌ای'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        elevation: 2,
        actions: [
          // Label settings button
          IconButton(
            icon: const Icon(Icons.grid_on),
            onPressed: _showLabelSettings,
            tooltip: 'تنظیمات لیبل',
          ),
          // Settings button
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('تنظیمات'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'مسیر ذخیره‌سازی:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        _storagePath,
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'فایل‌ها در پوشه اسناد برنامه ذخیره می‌شوند.',
                        style: TextStyle(fontSize: 12),
                      ),
                      if (_lastSyncTime != null) ...[
                        const SizedBox(height: 16),
                        const Text(
                          'آخرین همگام‌سازی:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _lastSyncTime!.toString().substring(0, 19),
                          style: const TextStyle(fontSize: 12, color: Colors.green),
                        ),
                      ],
                      const SizedBox(height: 16),
                      const Text(
                        'محصولات محلی:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_localProducts.length} محصول در پایگاه داده',
                        style: const TextStyle(fontSize: 12, color: Colors.blue),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('بستن'),
                    ),
                  ],
                ),
              );
            },
            tooltip: 'تنظیمات',
          ),
          // Logs button
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('لاگ‌های برنامه'),
                  content: SizedBox(
                    width: double.maxFinite,
                    height: 400,
                    child: AppLogger.getLogs().isEmpty
                        ? const Center(child: Text('هنوز لاگی ثبت نشده'))
                        : ListView.builder(
                            itemCount: AppLogger.getLogs().length,
                            itemBuilder: (context, index) {
                              final logs = AppLogger.getLogs();
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: SelectableText(
                                  logs[logs.length - 1 - index],
                                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                                ),
                              );
                            },
                          ),
                  ),
                  actions: [
                    TextButton.icon(
                      onPressed: () {
                        AppLogger.clear();
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('لاگ‌ها پاک شدند')),
                        );
                      },
                      icon: const Icon(Icons.delete_sweep, color: Colors.red),
                      label: const Text('پاک کردن لاگ‌ها', style: TextStyle(color: Colors.red)),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('بستن'),
                    ),
                  ],
                ),
              );
            },
            tooltip: 'مشاهده لاگ‌ها',
          ),
        ],
      ),
      body: Column(
        children: [
          // Barcode count display with gradient
          Container(
            padding: const EdgeInsets.all(16),
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade50, Colors.blue.shade100],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'تعداد بارکدهای اسکن شده:',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    Text(
                      '${_barcodes.length}',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blue),
                    ),
                  ],
                ),
                if (_barcodes.isNotEmpty)
                  ElevatedButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('بارکدهای اسکن شده'),
                          content: SizedBox(
                            width: double.maxFinite,
                            height: 400,
                            child: ListView.builder(
                              itemCount: _barcodes.length,
                              itemBuilder: (context, index) {
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.blue,
                                    child: Text(
                                      '${index + 1}',
                                      style: const TextStyle(color: Colors.white, fontSize: 12),
                                    ),
                                  ),
                                  title: Text(_barcodes[index]),
                                  subtitle: const Text('برای کپی ضربه بزنید'),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () {
                                      _removeBarcode(index);
                                      Navigator.pop(context);
                                    },
                                  ),
                                  onTap: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('کپی شد: ${_barcodes[index]}')),
                                    );
                                    Navigator.pop(context);
                                  },
                                );
                              },
                            ),
                          ),
                          actions: [
                            if (_barcodes.isNotEmpty)
                              TextButton.icon(
                                onPressed: () {
                                  _clearBarcodes();
                                  Navigator.pop(context);
                                },
                                icon: const Icon(Icons.delete_forever, color: Colors.red),
                                label: const Text('حذف همه', style: TextStyle(color: Colors.red)),
                              ),
                            if (_barcodes.isNotEmpty)
                              ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _exportToPdf();
                                },
                                icon: const Icon(Icons.picture_as_pdf),
                                label: const Text('خروجی PDF'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('بستن'),
                            ),
                          ],
                        ),
                      );
                    },
                    icon: const Icon(Icons.list_alt),
                    label: const Text('مشاهده لیست'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
              ],
            ),
          ),
          
          // Camera preview area
          Expanded(
            flex: 3,
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.blue.shade300, width: 2),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  children: [
                    MobileScanner(
                      onDetect: (capture) {
                        final List<Barcode> barcodes = capture.barcodes;
                        for (final barcode in barcodes) {
                          if (barcode.rawValue != null && !_barcodes.contains(barcode.rawValue)) {
                            _addBarcode(barcode.rawValue!);
                            AppLogger.log('Barcode scanned: ${barcode.rawValue}');
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('اسکن شد: ${barcode.rawValue}'),
                                duration: const Duration(seconds: 1),
                                backgroundColor: Colors.green,
                              ),
                            );
                            break;
                          }
                        }
                      },
                    ),
                    // Scan overlay
                    Positioned.fill(
                      child: CustomPaint(
                        painter: ScanOverlayPainter(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // Control buttons
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Info text
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.qr_code_scanner, color: Colors.green.shade700, size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          'دوربین همیشه در حال اسکن است',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.green),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'دوربین را روی بارکد بگیرید',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 20),
                  
                  // Export to PDF button (primary action)
                  ElevatedButton.icon(
                    onPressed: _barcodes.isEmpty 
                      ? null 
                      : () {
                          _fetchProductInfo();
                          Future.delayed(const Duration(milliseconds: 500), () {
                            _exportToPdf();
                          });
                        },
                    icon: const Icon(Icons.picture_as_pdf, size: 24),
                    label: const Text('تولید و چاپ لیبل قیمت (PDF)'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 56),
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      elevation: 4,
                      shadowColor: Colors.red.withOpacity(0.4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Clear button
                  OutlinedButton.icon(
                    onPressed: _barcodes.isEmpty ? null : _clearBarcodes,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('پاک کردن بارکدها'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue.shade700, Colors.blue.shade900],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Icon(
                    Icons.inventory_2,
                    color: Colors.white,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'تنظیمات محصولات',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_localProducts.length} محصول در پایگاه داده',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 14,
                    ),
                  ),
                  if (_lastSyncTime != null)
                    Text(
                      'آخرین بروزرسانی: ${_lastSyncTime!.toString().substring(0, 16)}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.sync, color: Colors.blue),
              title: const Text('بروزرسانی پایگاه داده'),
              subtitle: Text(_isSyncing ? 'در حال پردازش...' : 'همگام‌سازی با سایت'),
              onTap: _isSyncing ? null : _syncProductsFromWooCommerce,
            ),
            ListTile(
              leading: const Icon(Icons.inventory, color: Colors.green),
              title: const Text('مشاهده محصولات'),
              subtitle: const Text('نمایش تمام محصولات'),
              onTap: () {
                Navigator.pop(context);
                _showProductsList();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.grid_on, color: Colors.orange),
              title: const Text('تنظیمات لیبل'),
              subtitle: const Text('چیدمان و اندازه لیبل‌ها'),
              onTap: () {
                Navigator.pop(context);
                _showLabelSettings();
              },
            ),
          ],
        ),
      ),
    );
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
