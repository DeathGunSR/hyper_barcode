import 'package:flutter/material.dart';
import '../../../main.dart';

/// صفحه منوی اصلی برنامه Barcodify
class MenuPage extends StatefulWidget {
  final String currentLocale;
  final Function(String) onLocaleChanged;
  final ThemeMode themeMode;
  final Function(ThemeMode) onThemeModeChanged;

  const MenuPage({
    super.key,
    required this.currentLocale,
    required this.onLocaleChanged,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> {
  @override
  Widget build(BuildContext context) {
    final isRTL = widget.currentLocale == 'fa';
    
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.currentLocale == 'fa' ? 'بارکدیفای' : 'Barcodify',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Text(
              widget.currentLocale == 'fa' 
                ? 'تولیدکننده حرفه‌ای لیبل قیمت' 
                : 'Professional Price Label Generator',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _showQuickSettings(context),
            tooltip: widget.currentLocale == 'fa' ? 'تنظیمات' : 'Settings',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              
              Card(
                elevation: 4,
                shadowColor: Colors.blue.withOpacity(0.3),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.blue.shade50, Colors.blue.shade100],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: isRTL ? CrossAxisAlignment.right : CrossAxisAlignment.left,
                          children: [
                            Text(
                              widget.currentLocale == 'fa' 
                                ? 'به بارکدیفای خوش آمدید' 
                                : 'Welcome to Barcodify',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade900,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.currentLocale == 'fa'
                                ? 'یکی از گزینه‌های زیر را انتخاب کنید'
                                : 'Select one of the options below',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.blue.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.qr_code_scanner, size: 48, color: Colors.blue.shade400),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 32),
              
              Expanded(
                child: ListView(
                  children: [
                    _buildMenuCard(
                      icon: Icons.qr_code_scanner,
                      title: widget.currentLocale == 'fa' ? 'بارکد خوان' : 'Barcode Scanner',
                      subtitle: widget.currentLocale == 'fa'
                          ? 'اسکن بارکد و تولید لیبل قیمت'
                          : 'Scan barcodes and generate price labels',
                      color: Colors.green,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => BarcodeScannerWidget(
                              currentLocale: widget.currentLocale,
                            ),
                          ),
                        );
                      },
                    ),
                    
                    const SizedBox(height: 16),
                    
                    _buildMenuCard(
                      icon: Icons.shopping_cart,
                      title: widget.currentLocale == 'fa' ? 'چک‌لیست خرید مشترک' : 'Shared Shopping List',
                      subtitle: widget.currentLocale == 'fa'
                          ? 'مدیریت لیست خرید با همگام‌سازی آنلاین'
                          : 'Manage shopping lists with online sync',
                      color: Colors.orange,
                      onTap: () {
                        _navigateToShoppingList(context);
                      },
                    ),
                    
                    const SizedBox(height: 16),
                    
                    _buildMenuCard(
                      icon: Icons.settings,
                      title: widget.currentLocale == 'fa' ? 'تنظیمات' : 'Settings',
                      subtitle: widget.currentLocale == 'fa'
                          ? 'شخصی‌سازی ظاهر و رفتار برنامه'
                          : 'Customize app appearance and behavior',
                      color: Colors.purple,
                      onTap: () {
                        _showFullSettings(context);
                      },
                    ),
                  ],
                ),
              ),
              
              Center(
                child: Text(
                  widget.currentLocale == 'fa' ? 'نسخه ۱.۰.۰' : 'Version 1.0.0',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isRTL = widget.currentLocale == 'fa';
    
    return Card(
      elevation: 3,
      shadowColor: color.withOpacity(0.3),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: isRTL ? CrossAxisAlignment.right : CrossAxisAlignment.left,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              Icon(isRTL ? Icons.arrow_back : Icons.arrow_forward, color: color),
            ],
          ),
        ),
      ),
    );
  }

  void _showQuickSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.currentLocale == 'fa' ? 'تنظیمات سریع' : 'Quick Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: const Icon(Icons.language),
              title: Text(widget.currentLocale == 'fa' ? 'زبان' : 'Language'),
              trailing: Text(widget.currentLocale == 'fa' ? 'فارسی' : 'English'),
              onTap: () {
                Navigator.pop(context);
                widget.onLocaleChanged(widget.currentLocale == 'fa' ? 'en' : 'fa');
              },
            ),
            ListTile(
              leading: Icon(widget.themeMode == ThemeMode.dark ? Icons.dark_mode : Icons.light_mode),
              title: Text(widget.currentLocale == 'fa' ? 'حالت تم' : 'Theme Mode'),
              trailing: Text(
                widget.themeMode == ThemeMode.system
                  ? (widget.currentLocale == 'fa' ? 'سیستم' : 'System')
                  : widget.themeMode == ThemeMode.light
                    ? (widget.currentLocale == 'fa' ? 'روشن' : 'Light')
                    : (widget.currentLocale == 'fa' ? 'تیره' : 'Dark'),
              ),
              onTap: () {
                Navigator.pop(context);
                ThemeMode newMode;
                switch (widget.themeMode) {
                  case ThemeMode.system: newMode = ThemeMode.light; break;
                  case ThemeMode.light: newMode = ThemeMode.dark; break;
                  case ThemeMode.dark: newMode = ThemeMode.system; break;
                }
                widget.onThemeModeChanged(newMode);
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(widget.currentLocale == 'fa' ? 'بستن' : 'Close')),
        ],
      ),
    );
  }

  void _showFullSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => SettingsDialog(
        currentLocale: widget.currentLocale,
        onLocaleChanged: widget.onLocaleChanged,
        themeMode: widget.themeMode,
        onThemeModeChanged: widget.onThemeModeChanged,
      ),
    );
  }

  void _navigateToShoppingList(BuildContext context) {
    // Navigation to shopping list will be implemented
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(widget.currentLocale == 'fa' ? 'به زودی' : 'Coming soon')),
    );
  }
}
