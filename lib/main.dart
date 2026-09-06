import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:excel/excel.dart' as excel_lib;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:convert';

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
  bool _isScanning = false;
  bool _isLoadingProducts = false;
  Map<String, ProductInfo> _productMap = {};

  // WooCommerce API configuration
  final String _wooCommerceUrl = 'https://ebimarket.ir';
  final String _consumerKey = 'ck_59df85eaad37b7c4f6bf77ba0707aca37dc42939';
  final String _consumerSecret = 'cs_71f8ba694ba54566be8209503145bdab47903e4e';

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

    setState(() {
      _isLoadingProducts = true;
    });

    try {
      final url = Uri.parse(
        '$_wooCommerceUrl/wp-json/wc/v3/products?per_page=100&consumer_key=$_consumerKey&consumer_secret=$_consumerSecret&_fields=id,sku,regular_price,sale_price,name,meta_data',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final List<dynamic> products = json.decode(response.body);
        Map<String, ProductInfo> productMap = {};

        for (var product in products) {
          final sku = product['sku']?.toString() ?? '';
          final name = product['name']?.toString() ?? '';
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

          // Also use SKU as a barcode
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

        setState(() {
          _productMap = productMap;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Product info loaded for ${productMap.length} items')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to fetch product information')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() {
        _isLoadingProducts = false;
      });
    }
  }

  Future<void> _exportToExcel({bool withProductInfo = false}) async {
    if (_barcodes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No barcodes to export')),
      );
      return;
    }

    // If exporting with product info, fetch it first
    if (withProductInfo && _productMap.isEmpty) {
      await _fetchProductInfo();
    }

    // Request storage permission
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      status = await Permission.storage.request();
      if (!status.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Storage permission denied')),
        );
        return;
      }
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
      
      // Add barcodes with product info
      for (int i = 0; i < _barcodes.length; i++) {
        final barcode = _barcodes[i];
        final product = _productMap[barcode];
        
        sheetObject.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1)).value = excel_lib.TextCellValue(barcode);
        sheetObject.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: i + 1)).value = excel_lib.TextCellValue(product?.name ?? '');
        sheetObject.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: i + 1)).value = excel_lib.TextCellValue(product?.coverPrice ?? '');
        sheetObject.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: i + 1)).value = excel_lib.TextCellValue(product?.salePrice ?? '');
      }
    } else {
      // Add header
      sheetObject.cell(excel_lib.CellIndex.indexByString('A1')).value = excel_lib.TextCellValue('Barcode');
      
      // Add barcodes in column A
      for (int i = 0; i < _barcodes.length; i++) {
        sheetObject.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1)).value = excel_lib.TextCellValue(_barcodes[i]);
      }
    }

    // Get save directory
    Directory? directory;
    if (Platform.isAndroid) {
      directory = await getExternalStorageDirectory();
    } else {
      directory = await getApplicationDocumentsDirectory();
    }

    if (directory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not access storage')),
      );
      return;
    }

    // Generate filename with timestamp
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = withProductInfo ? 'products_$timestamp.xlsx' : 'barcodes_$timestamp.xlsx';
    final filePath = '${directory.path}/$fileName';
    
    // Save file
    final file = File(filePath);
    await file.writeAsBytes(excel.encode()!);

    // Share the file
    final result = await Share.shareXFiles(
      [XFile(filePath)],
      subject: withProductInfo ? 'Products Export' : 'Barcodes Export',
      text: withProductInfo 
        ? 'Exported products from Barcode Scanner App' 
        : 'Exported barcodes from Barcode Scanner App',
    );

    if (result.status == ShareResultStatus.success) {
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
                                icon: const Icon(Icons.delete_all, color: Colors.red),
                                label: const Text('Delete All', style: TextStyle(color: Colors.red)),
                              ),
                            if (_barcodes.isNotEmpty && !_isLoadingProducts)
                              ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _exportToExcel(withProductInfo: true);
                                },
                                icon: _isLoadingProducts 
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
                                  : const Icon(Icons.cloud_upload),
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
                  // Scan button (shutter-style)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _isScanning = !_isScanning;
                      });
                      if (!_isScanning) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Scanning paused')),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Scanning active - point camera at barcodes')),
                        );
                      }
                    },
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isScanning ? Colors.green : Colors.red,
                        border: Border.all(color: Colors.white, width: 4),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Icon(
                        _isScanning ? Icons.camera_alt : Icons.camera_alt_outlined,
                        size: 40,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _isScanning ? 'Scanning Active' : 'Tap to Start Scanning',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 20),
                  
                  // Register/Save button
                  ElevatedButton.icon(
                    onPressed: _barcodes.isEmpty 
                      ? null 
                      : () {
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
    );
  }
}
