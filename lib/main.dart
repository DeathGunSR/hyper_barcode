import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:excel/excel.dart' as excel_lib;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';

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

  Future<void> _exportToExcel() async {
    if (_barcodes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No barcodes to export')),
      );
      return;
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
    
    // Add header
    sheetObject.cell(excel_lib.CellIndex.indexByString('A1')).value = excel_lib.TextCellValue('Barcode');
    
    // Add barcodes in column A
    for (int i = 0; i < _barcodes.length; i++) {
      sheetObject.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1)).value = excel_lib.TextCellValue(_barcodes[i]);
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
    final filePath = '${directory.path}/barcodes_$timestamp.xlsx';
    
    // Save file
    final file = File(filePath);
    await file.writeAsBytes(excel.encode()!);

    // Share the file
    final result = await Share.shareXFiles(
      [XFile(filePath)],
      subject: 'Barcodes Export',
      text: 'Exported barcodes from Barcode Scanner App',
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
