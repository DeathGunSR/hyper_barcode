import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:excel/excel.dart' as excel_lib;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:io';
import 'dart:convert';

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

void main() {
  runApp(const BarcodeScannerApp());
}

class BarcodeScannerApp extends StatelessWidget {
  const BarcodeScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Barcode Scanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

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
      final path = join(databasesPath, 'products.db');
      
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
        // Parse pagination info from headers or assume large number
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
    setState(() {
      _barcodes.add(barcode);
    });
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
        const SnackBar(content: Text('No barcodes to fetch')),
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
        SnackBar(content: Text('Product info loaded: $foundCount/${_barcodes.length} barcodes matched')),
      );
    } catch (e) {
      AppLogger.log('Error fetching product info: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _exportToExcel({bool withProductInfo = false}) async {
    if (_barcodes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No barcodes to export')),
      );
      return;
    }

    AppLogger.log('Starting export. With product info: $withProductInfo');

    // If exporting with product info, use local database
    if (withProductInfo && _localProducts.isEmpty) {
      AppLogger.log('Loading products from local database');
      await _loadLocalProducts();
    }

    // Create Excel file
    var excel = excel_lib.Excel.createExcel();
    excel_lib.Sheet sheetObject = excel['Barcodes'];
    
    if (withProductInfo) {
      // Add headers for 4 columns
      sheetObject.cell(excel_lib.CellIndex.indexByString('A1')).value = excel_lib.TextCellValue('Barcode');
      sheetObject.cell(excel_lib.CellIndex.indexByString('B1')).value = excel_lib.TextCellValue('Product Name');
      sheetObject.cell(excel_lib.CellIndex.indexByString('C1')).value = excel_lib.TextCellValue('Cover Price');
      sheetObject.cell(excel_lib.CellIndex.indexByString('D1')).value = excel_lib.TextCellValue('Sale Price');
      
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
      
      // Add barcodes with product info
      for (int i = 0; i < _barcodes.length; i++) {
        final barcode = _barcodes[i];
        final product = barcodeToProduct[barcode];
        
        sheetObject.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1)).value = excel_lib.TextCellValue(barcode);
        sheetObject.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: i + 1)).value = excel_lib.TextCellValue(product?.name ?? '');
        sheetObject.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: i + 1)).value = excel_lib.TextCellValue(product?.coverPrice ?? '');
        sheetObject.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: i + 1)).value = excel_lib.TextCellValue(product?.salePrice ?? '');
      }
      AppLogger.log('Excel created with product info for ${_barcodes.length} items');
    } else {
      // Add header
      sheetObject.cell(excel_lib.CellIndex.indexByString('A1')).value = excel_lib.TextCellValue('Barcode');
      
      // Add barcodes in column A
      for (int i = 0; i < _barcodes.length; i++) {
        sheetObject.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1)).value = excel_lib.TextCellValue(_barcodes[i]);
      }
      AppLogger.log('Excel created with ${_barcodes.length} barcodes');
    }

    // Get app documents directory (no permission needed)
    final directory = await getApplicationDocumentsDirectory();
    
    // Generate filename with timestamp
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = withProductInfo ? 'products_$timestamp.xlsx' : 'barcodes_$timestamp.xlsx';
    final filePath = '${directory.path}/$fileName';
    
    AppLogger.log('Saving file to: $filePath');
    
    // Save file
    final file = File(filePath);
    await file.writeAsBytes(excel.encode()!);
    
    AppLogger.log('File saved successfully. Size: ${await file.length()} bytes');

    // Share the file
    AppLogger.log('Opening share dialog');
    final result = await Share.shareXFiles(
      [XFile(filePath)],
      subject: withProductInfo ? 'Products Export' : 'Barcodes Export',
      text: withProductInfo 
        ? 'Exported products from Barcode Scanner App' 
        : 'Exported barcodes from Barcode Scanner App',
    );

    if (result.status == ShareResultStatus.success) {
      AppLogger.log('File shared successfully');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File shared successfully')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Barcode Scanner'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          // Settings button
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Settings'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Storage Path:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        _storagePath,
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Files are saved in the app\'s documents directory.',
                        style: TextStyle(fontSize: 12),
                      ),
                      if (_lastSyncTime != null) ...[
                        const SizedBox(height: 16),
                        const Text(
                          'Last Sync:',
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
                        'Local Products:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_localProducts.length} products in database',
                        style: const TextStyle(fontSize: 12, color: Colors.blue),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
            tooltip: 'Settings',
          ),
          // Logs button
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('App Logs'),
                  content: SizedBox(
                    width: double.maxFinite,
                    height: 400,
                    child: AppLogger.getLogs().isEmpty
                        ? const Center(child: Text('No logs yet'))
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
                          const SnackBar(content: Text('Logs cleared')),
                        );
                      },
                      icon: const Icon(Icons.delete_sweep, color: Colors.red),
                      label: const Text('Clear Logs', style: TextStyle(color: Colors.red)),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
            tooltip: 'View Logs',
          ),
        ],
      ),
      body: Column(
        children: [
          // Barcode count display
          Container(
            padding: const EdgeInsets.all(16),
            width: double.infinity,
            color: Colors.blue.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total Barcodes:',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${_barcodes.length}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue),
                ),
                if (_barcodes.isNotEmpty)
                  ElevatedButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Scanned Barcodes'),
                          content: SizedBox(
                            width: double.maxFinite,
                            height: 400,
                            child: ListView.builder(
                              itemCount: _barcodes.length,
                              itemBuilder: (context, index) {
                                return ListTile(
                                  leading: CircleAvatar(
                                    child: Text('${index + 1}'),
                                  ),
                                  title: Text(_barcodes[index]),
                                  subtitle: const Text('Tap to copy'),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () {
                                      _removeBarcode(index);
                                      Navigator.pop(context);
                                    },
                                  ),
                                  onTap: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Copied: ${_barcodes[index]}')),
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
                                label: const Text('Delete All', style: TextStyle(color: Colors.red)),
                              ),
                            if (_barcodes.isNotEmpty)
                              ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _exportToExcel(withProductInfo: true);
                                },
                                icon: const Icon(Icons.cloud_upload),
                                label: const Text('Export with Product Info'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      );
                    },
                    icon: const Icon(Icons.list),
                    label: const Text('View List'),
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
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: MobileScanner(
                  onDetect: (capture) {
                    final List<Barcode> barcodes = capture.barcodes;
                    for (final barcode in barcodes) {
                      if (barcode.rawValue != null && !_barcodes.contains(barcode.rawValue)) {
                        _addBarcode(barcode.rawValue!);
                        AppLogger.log('Barcode scanned: ${barcode.rawValue}');
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Scanned: ${barcode.rawValue}'),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                        break;
                      }
                    }
                  },
                ),
              ),
            ),
          ),
          
          // Control buttons
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Info text
                  const Text(
                    'Camera is always scanning',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.green),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Point camera at barcodes to scan',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 20),
                  
                  // Register/Save button
                  ElevatedButton.icon(
                    onPressed: _barcodes.isEmpty 
                      ? null 
                      : () {
                          AppLogger.log('${_barcodes.length} barcodes registered');
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('${_barcodes.length} barcodes registered')),
                          );
                        },
                    icon: const Icon(Icons.save),
                    label: Text('Register (${_barcodes.length})'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Export button
                  ElevatedButton.icon(
                    onPressed: _barcodes.isEmpty ? null : _exportToExcel,
                    icon: const Icon(Icons.file_download),
                    label: const Text('Export to Excel & Share'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
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
                color: Colors.blue,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Text(
                    'تنظیمات محصولات',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_localProducts.length} محصول در دیتابیس',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
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
              title: const Text('بروزرسانی دیتابیس'),
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
