import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/shopping_list_item.dart';
import '../providers/shopping_list_provider.dart';

/// صفحه اصلی چک‌لیست خرید
class ShoppingListScreen extends StatefulWidget {
  final String currentLocale;

  const ShoppingListScreen({super.key, required this.currentLocale});

  @override
  State<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends State<ShoppingListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ShoppingListProvider>().initialize(widget.currentLocale);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ShoppingListProvider(),
      child: Consumer<ShoppingListProvider>(
        builder: (context, provider, child) {
          return Scaffold(
            appBar: AppBar(
              title: Text(
                widget.currentLocale == 'fa' 
                    ? 'چک‌لیست خرید مشترک' 
                    : 'Shared Shopping List',
              ),
              backgroundColor: Theme.of(context).colorScheme.inversePrimary,
              actions: [
                // دکمه همگام‌سازی
                IconButton(
                  icon: provider.isSyncing 
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  onPressed: () => provider.syncWithServer(),
                  tooltip: widget.currentLocale == 'fa' 
                      ? 'همگام‌سازی با سرور' 
                      : 'Sync with server',
                ),
                // دکمه تنظیمات کاربر
                IconButton(
                  icon: const Icon(Icons.person),
                  onPressed: () => _showUserSettings(context, provider),
                  tooltip: widget.currentLocale == 'fa' 
                      ? 'تنظیمات کاربر' 
                      : 'User settings',
                ),
              ],
            ),
            body: Column(
              children: [
                // نوار فیلتر تب‌ها
                _buildFilterTabs(context, provider),
                
                // نوار فیلتر تگ‌ها
                _buildTagFilterBar(context, provider),
                
                // لیست آیتم‌ها
                Expanded(
                  child: _buildItemList(context, provider),
                ),
              ],
            ),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () => _showAddItemDialog(context, provider),
              icon: const Icon(Icons.add),
              label: Text(
                widget.currentLocale == 'fa' ? 'افزودن آیتم' : 'Add Item',
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilterTabs(BuildContext context, ShoppingListProvider provider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          for (final filter in ShoppingListFilter.values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: FilterChip(
                  label: Text(filter.getLabel(provider.selectedLocale)),
                  selected: provider.currentFilter == filter,
                  onSelected: (selected) {
                    provider.setFilter(filter);
                  },
                  showCheckmark: false,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTagFilterBar(BuildContext context, ShoppingListProvider provider) {
    return SizedBox(
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: DefaultTags.tags.length + 1, // +1 for "All" option
        itemBuilder: (context, index) {
          if (index == 0) {
            // گزینه "همه تگ‌ها"
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                avatar: const CircleAvatar(
                  backgroundColor: Colors.grey,
                  child: Icon(Icons.all_inclusive, size: 18, color: Colors.white),
                ),
                label: Text(
                  provider.selectedLocale == 'fa' ? 'همه' : 'All',
                ),
                selected: provider.selectedTag == null,
                onSelected: (selected) {
                  provider.setTagFilter(null);
                },
              ),
            );
          }

          final tag = DefaultTags.tags[index - 1];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              avatar: CircleAvatar(
                backgroundColor: _hexToColor(tag.colorHex),
                child: const Icon(Icons.label, size: 18, color: Colors.white),
              ),
              label: Text(tag.getName(provider.selectedLocale)),
              selected: provider.selectedTag == tag.id,
              onSelected: (selected) {
                provider.setTagFilter(selected ? tag.id : null);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildItemList(BuildContext context, ShoppingListProvider provider) {
    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(provider.error!),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => provider.loadItems(),
              child: Text(
                provider.selectedLocale == 'fa' 
                    ? 'تلاش مجدد' 
                    : 'Try again',
              ),
            ),
          ],
        ),
      );
    }

    if (provider.filteredItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.shopping_cart_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              provider.selectedLocale == 'fa'
                  ? 'هیچ آیتمی یافت نشد'
                  : 'No items found',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: provider.filteredItems.length,
      itemBuilder: (context, index) {
        final item = provider.filteredItems[index];
        final tag = provider.getTagById(item.tag);
        final tagColor = _hexToColor(provider.getTagColor(item.tag));

        return Dismissible(
          key: Key(item.id.toString()),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            color: Colors.red,
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          onDismissed: (_) => provider.deleteItem(item.id!),
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: tagColor,
                child: Text(
                  tag?.getName(provider.selectedLocale).substring(0, 1) ?? '?',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              title: Text(
                item.name,
                style: TextStyle(
                  decoration: item.isPurchased 
                      ? TextDecoration.lineThrough 
                      : null,
                  color: item.isPurchased ? Colors.grey : null,
                ),
              ),
              subtitle: Text(
                '${item.addedBy} • ${_formatDate(item.createdAt, provider.selectedLocale)}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // نمایش بارکد اگر وجود دارد
                  if (item.barcode.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        item.barcode,
                        style: const TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  // چک‌باکس وضعیت خرید
                  Checkbox(
                    value: item.isPurchased,
                    onChanged: (value) {
                      provider.togglePurchaseStatus(item.id!, value ?? false);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showAddItemDialog(BuildContext context, ShoppingListProvider provider) {
    final nameController = TextEditingController();
    final barcodeController = TextEditingController();
    String selectedTag = 'other';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            provider.selectedLocale == 'fa' 
                ? 'افزودن آیتم جدید' 
                : 'Add New Item',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: provider.selectedLocale == 'fa' 
                        ? 'نام کالا' 
                        : 'Item name',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: barcodeController,
                  decoration: InputDecoration(
                    labelText: provider.selectedLocale == 'fa' 
                        ? 'بارکد (اختیاری)' 
                        : 'Barcode (optional)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    prefixIcon: const Icon(Icons.qr_code),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  provider.selectedLocale == 'fa' 
                      ? 'دسته‌بندی' 
                      : 'Category',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final tag in DefaultTags.tags)
                      ChoiceChip(
                        label: Text(tag.getName(provider.selectedLocale)),
                        selected: selectedTag == tag.id,
                        onSelected: (selected) {
                          if (selected) {
                            setDialogState(() {
                              selectedTag = tag.id;
                            });
                          }
                        },
                        avatar: CircleAvatar(
                          backgroundColor: _hexToColor(tag.colorHex),
                          child: const Icon(Icons.label, size: 16, color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                provider.selectedLocale == 'fa' ? 'انصراف' : 'Cancel',
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        provider.selectedLocale == 'fa' 
                            ? 'لطفاً نام کالا را وارد کنید' 
                            : 'Please enter item name',
                      ),
                    ),
                  );
                  return;
                }

                final username = provider.username ?? 'Unknown';
                final newItem = ShoppingListItem(
                  name: nameController.text.trim(),
                  barcode: barcodeController.text.trim(),
                  tag: selectedTag,
                  addedBy: username,
                  createdAt: DateTime.now(),
                );

                await provider.addItem(newItem);
                if (context.mounted) Navigator.pop(context);
              },
              child: Text(
                provider.selectedLocale == 'fa' ? 'افزودن' : 'Add',
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showUserSettings(BuildContext context, ShoppingListProvider provider) {
    final usernameController = TextEditingController(text: provider.username ?? '');
    final phoneController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          provider.selectedLocale == 'fa' 
              ? 'تنظیمات کاربر' 
              : 'User Settings',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: usernameController,
              decoration: InputDecoration(
                labelText: provider.selectedLocale == 'fa' 
                    ? 'نام کاربری' 
                    : 'Username',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: phoneController,
              decoration: InputDecoration(
                labelText: provider.selectedLocale == 'fa' 
                    ? 'شماره موبایل' 
                    : 'Mobile number',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.phone),
              ),
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              provider.selectedLocale == 'fa' ? 'انصراف' : 'Cancel',
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              if (usernameController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('نام کاربری الزامی است')),
                );
                return;
              }

              await provider.saveUser(
                usernameController.text.trim(),
                phoneController.text.trim(),
              );
              
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      provider.selectedLocale == 'fa' 
                          ? 'اطلاعات کاربر ذخیره شد' 
                          : 'User info saved',
                    ),
                  ),
                );
              }
            },
            child: Text(
              provider.selectedLocale == 'fa' ? 'ذخیره' : 'Save',
            ),
          ),
        ],
      ),
    );
  }

  Color _hexToColor(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }

  String _formatDate(DateTime date, String locale) {
    if (locale == 'fa') {
      // فرمت ساده فارسی
      return '${date.month}/${date.day}';
    } else {
      return '${date.month}/${date.day}';
    }
  }
}
