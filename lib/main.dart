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
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

// Import new structure
import 'providers/app_settings_provider.dart';
import 'pages/home_page.dart';
import 'pages/scanner_page.dart';
import 'pages/shopping_list_page.dart';
import 'pages/settings_page.dart';

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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize settings
  final prefs = await SharedPreferences.getInstance();
  final appSettings = AppSettings(prefs);
  await appSettings.loadSettings();

  runApp(BarcodifyApp(appSettings: appSettings));
}

class BarcodifyApp extends StatelessWidget {
  final AppSettings appSettings;

  const BarcodifyApp({super.key, required this.appSettings});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: appSettings,
      builder: (context, _) {
        return Consumer<AppSettings>(
          builder: (context, settings, child) {
            return MaterialApp(
              title: 'Barcodify',
              debugShowCheckedModeBanner: false,
              locale: settings.locale,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [
                Locale('fa', 'IR'),
                Locale('en', 'US'),
              ],
              themeMode: settings.themeMode,
              darkTheme: _buildDarkTheme(),
              theme: _buildLightTheme(),
              home: const HomePage(),
              routes: {
                '/scanner': (context) => const ScannerPage(),
                '/shopping-list': (context) => const ShoppingListPage(),
                '/settings': (context) => const SettingsPage(),
              },
            );
          },
        );
      },
    );
  }

  ThemeData _buildLightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6750A4),
        brightness: Brightness.light,
      ),
      fontFamily: 'Vazirmatn',
    );
  }

  ThemeData _buildDarkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFD0BCFF),
        brightness: Brightness.dark,
      ),
      fontFamily: 'Vazirmatn',
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

// Scanner page logic will be added in a separate file
// For now, we keep the core classes needed for PDF generation and scanning
