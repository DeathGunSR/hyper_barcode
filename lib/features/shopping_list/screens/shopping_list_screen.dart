import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/sync_provider.dart';
import '../../../core/widgets/sync_status_widget.dart';
import '../models/shopping_list_item.dart';
import '../providers/shopping_list_provider.dart';

/// صفحه اصلی چک‌لیست خرید.
///
/// نکته: [ShoppingListProvider] در ریشه برنامه (`MultiProvider` در
/// `main.dart`) فراهم شده است؛ بنابراین `context.read` در `initState` بدون
/// خطای ProviderNotFoundException کار می‌کند.
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
      if (!mounted) return;
      context
          .read<ShoppingListProvider>()
          .initialize(widget.currentLocale);
    });
  }

  bool get _isFa => widget.currentLocale == 'fa';
  
  Color _hexToColor(String hexString) => Color(hexColorToArgb32(hexString));

  @override
  Widget build(BuildContext context) {
    return Consumer<ShoppingListProvider>(
      builder: (BuildContext context, ShoppingListProvider provider, _) {
        // T-08: اگر کاربر هنوز نام کاربری وارد نکرده، دیالوگ مودال اجباری نشان بده.
        if (!provider.hasUser) {
          _showMandatoryLoginDialog(context, provider);
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(
              _isFa ? 'چک‌لیست خرید مشترک' : 'Shared Shopping List',
            ),
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            actions: <Widget>[
              // دکمه همگام‌سازی: غیرمسدودکننده و با نمایش وضعیت.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: SyncStatusIndicator(
                  showWhenIdle: true,
                  onTap: () => _startSync(context, provider),
                ),
              ),
              // مدیریت تگ‌های سفارشی
              IconButton(
                icon: const Icon(Icons.local_offer),
                onPressed: provider.hasUser
                    ? () => _showTagManager(context, provider)
                    : null,
              ),
              // تنظیمات کاربر
              IconButton(
                icon: const Icon(Icons.person),
                onPressed: provider.hasUser
                    ? () => _showUserSettings(context, provider)
                    : null,
              ),
            ],
          ),
          // T-10: SafeArea برای edge-to-edge — نوار ناوبری با دکمه‌های خانه/برگشت.
          body: SafeArea(
            top: false,
            bottom: true,
            left: false,
            right: false,
            child: Column(
              children: <Widget>[
                _buildFilterTabs(context, provider),
                _buildTagFilterBar(context, provider),
                Expanded(child: _buildItemList(context, provider)),
              ],
            ),
          ),
          floatingActionButton: Padding(
            // T-10: padding از پایین برای جلوگیری از قرار گرفتن زیر دکمه‌های سیستم.
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).padding.bottom + 8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                FloatingActionButton.small(
                  heroTag: 'addCustomTagFab',
                  onPressed: provider.hasUser
                      ? () => _showCreateTagDialog(context, provider)
                      : null,
                  backgroundColor: Colors.purple,
                  child: const Icon(Icons.new_label, color: Colors.white),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.extended(
                  heroTag: 'addItemFab',
                  onPressed: provider.hasUser
                      ? () => _showAddItemDialog(context, provider)
                      : null,
                  icon: const Icon(Icons.add),
                  label: Text(_isFa ? 'افزودن آیتم' : 'Add Item'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// T-08: دیالوگ ورود اجباری نام کاربری — قابل انصراف نیست.
  ///
  /// - با [WillPopScope] دکمه برگشت سیستم مسدود می‌شود.
  /// - روی backdrop click بسته نمی‌شود (barrierDismissible=false).
  /// - نام کاربری فقط باید خالی نباشد؛ پس از ذخیره دیالوگ بسته می‌شود.
  bool _loginDialogShown = false;
  void _showMandatoryLoginDialog(
      BuildContext context, ShoppingListProvider provider) {
    if (_loginDialogShown) return;
    _loginDialogShown = true;
    final TextEditingController nameController = TextEditingController();
    String? error;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          return StatefulBuilder(
            builder: (BuildContext ctx, StateSetter setD) {
              return WillPopScope(
                onWillPop: () async => false,
                child: AlertDialog(
                  title: Text(_isFa ? 'خوش آمدید' : 'Welcome'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(_isFa
                          ? 'لطفاً برای ادامه نام خود را وارد کنید (بدون نیاز به رمز عبور).'
                          : 'Please enter your name to continue (no password required).'),
                      const SizedBox(height: 12),
                      TextField(
                        controller: nameController,
                        autofocus: true,
                        onChanged: (_) => setD(() => error = null),
                        decoration: InputDecoration(
                          labelText: _isFa ? 'نام کاربری' : 'Username',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          prefixIcon: const Icon(Icons.person_outline),
                          errorText: error,
                        ),
                      ),
                    ],
                  ),
                  actions: <Widget>[
                    ElevatedButton.icon(
                      onPressed: () {
                        final String username = nameController.text.trim();
                        if (username.isEmpty) {
                          setD(() =>
                              error = _isFa ? 'نام الزامی است' : 'Name is required');
                          return;
                        }
                        provider.setUserName(username);
                        _loginDialogShown = false;
                        Navigator.pop(dialogContext);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(_isFa
                                  ? 'سلام «$username»، خوش آمدید!'
                                  : 'Hi «$username», welcome!'),
                              backgroundColor: Colors.green,
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.login),
                      label: Text(_isFa ? 'ورود' : 'Enter'),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ).then((_) => _loginDialogShown = false);
    });
  }

  /// شروع همگام‌سازی غیرمسدودکننده + نمایش نتیجه با SnackBar.
  Future<void> _startSync(
      BuildContext context, ShoppingListProvider provider) async {
    final SyncState result = await provider.syncWithServer();
    if (!mounted) return;

    if (result == SyncState.success) {
      showSyncResultSnackBar(
        context,
        result,
        isRTL: _isFa,
        message: SyncProvider().lastSummary ??
            (_isFa ? 'همگام‌سازی کامل شد' : 'Sync completed'),
      );
    } else {
      showSyncResultSnackBar(context, result, isRTL: _isFa);
    }
  }

  // ==================== مدیریت تگ‌ها ====================

  void _showTagManager(
      BuildContext context, ShoppingListProvider provider) {
    final List<ShoppingListTag> allTags = provider.allTags;
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(_isFa ? 'مدیریت تگ‌ها' : 'Manage Tags'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              // T-09: نمایش تگ‌ها بصورت indented بر اساس عمق درختی.
              for (final ShoppingListTag tag in allTags)
                Padding(
                  padding: EdgeInsets.only(
                    left: tag.depth(allTags) * 16.0,
                    right: 0,
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _hexToColor(tag.colorHex),
                      child: const Icon(
                        Icons.label,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    title: Text(tag.displayName(provider.selectedLocale)),
                    subtitle: tag.parentId != null
                        ? Text(
                            _isFa
                                ? 'زیرمجموعه: «${provider.getTagById(tag.parentId!)?.displayName(provider.selectedLocale) ?? '-'}»'
                                : 'Child of: "${provider.getTagById(tag.parentId!)?.displayName(provider.selectedLocale) ?? '-'}"',
                            style: const TextStyle(fontSize: 11),
                          )
                        : Text(
                            _isFa ? 'سطح ریشه' : 'Root level',
                            style: const TextStyle(fontSize: 11),
                          ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () =>
                          _confirmDeleteTag(context, provider, tag),
                    ),
                  ),
                ),
              if (allTags.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: Text(
                      _isFa
                          ? 'هنوز تگی ساخته نشده. از دکمه + بنفش پایین صفحه استفاده کنید.'
                          : 'No tags yet. Use the purple + FAB at the bottom.',
                      style: TextStyle(color: Colors.grey.shade600),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_isFa ? 'بستن' : 'Close'),
          ),
        ],
      ),
    );
  }

  void _showUserSettings(
      BuildContext context, ShoppingListProvider provider) {
    final TextEditingController nameController =
        TextEditingController(text: provider.currentUserName);
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(_isFa ? 'تنظیمات کاربر' : 'User Settings'),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(
            labelText: _isFa ? 'نام شما' : 'Your name',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_isFa ? 'انصراف' : 'Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              provider.setUserName(nameController.text.trim());
              Navigator.pop(dialogContext);
            },
            child: Text(_isFa ? 'ذخیره' : 'Save'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteTag(BuildContext context, ShoppingListProvider provider,
      ShoppingListTag tag) {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(_isFa ? 'حذف تگ' : 'Delete Tag'),
        content: Text(_isFa
            ? 'آیا مطمئن هستید که می‌خواهید تگ «${tag.nameFa}» را حذف کنید؟'
            : 'Are you sure you want to delete the tag \"${tag.nameEn}\"?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_isFa ? 'انصراف' : 'Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              provider.deleteTag(tag.id);
              Navigator.pop(dialogContext);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(_isFa ? 'حذف' : 'Delete'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date, String locale) {
    if (locale == 'fa') {
      return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
    }
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  // ==================== نوار فیلتر وضعیت ====================

  Widget _buildFilterTabs(
      BuildContext context, ShoppingListProvider provider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: <Widget>[
          for (final ShoppingListFilter filter in ShoppingListFilter.values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: FilterChip(
                  label: Text(filter.getLabel(provider.selectedLocale)),
                  selected: provider.currentFilter == filter,
                  onSelected: (_) => provider.setFilter(filter),
                  showCheckmark: false,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ==================== نوار فیلتر تگ‌ها ====================

  Widget _buildTagFilterBar(
      BuildContext context, ShoppingListProvider provider) {
    final List<ShoppingListTag> tags = provider.allTags;

    return SizedBox(
      height: 54,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: tags.length + 1, // +1 برای گزینه «همه»
        itemBuilder: (BuildContext context, int index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                avatar: const CircleAvatar(
                  backgroundColor: Colors.grey,
                  child:
                      Icon(Icons.all_inclusive, size: 18, color: Colors.white),
                ),
                label: Text(provider.selectedLocale == 'fa' ? 'همه' : 'All'),
                selected: provider.selectedTag == null,
                onSelected: (_) => provider.setTagFilter(null),
              ),
            );
          }

          final ShoppingListTag tag = tags[index - 1];
          final bool selected = provider.selectedTag == tag.id;
          // T-09: indent بصری برای نمایش سطح درختی تگ در فیلتر افقی.
          // چون افقی است، از padding کوچک بالا استفاده می‌کنیم تا نشانه‌ای از عمق باشد.
          final double visualTopIndent = tag.depth(tags) * 3.0;

          return Padding(
            padding: EdgeInsets.only(right: 8, top: visualTopIndent),
            child: GestureDetector(
              // نگه‌داشتن روی تگ → حذف آن.
              onLongPress: () => _confirmDeleteTag(context, provider, tag),
              child: FilterChip(
                avatar: CircleAvatar(
                  backgroundColor: _hexToColor(tag.colorHex),
                  child: const Icon(
                    Icons.label,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
                label: Text(tag.displayName(provider.selectedLocale)),
                selected: selected,
                onSelected: (_) =>
                    provider.setTagFilter(selected ? null : tag.id),
              ),
            ),
          );
        },
      ),
    );
  }

  // ==================== لیست آیتم‌ها ====================

  Widget _buildItemList(BuildContext context, ShoppingListProvider provider) {
    if (provider.isLoading && provider.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.filteredItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.shopping_cart_outlined,
                size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              _isFa ? 'هیچ آیتمی یافت نشد' : 'No items found',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      itemCount: provider.filteredItems.length,
      itemBuilder: (BuildContext context, int index) {
        final ShoppingListItem item = provider.filteredItems[index];
        return _buildItemTile(context, provider, item);
      },
    );
  }

  Widget _buildItemTile(
    BuildContext context,
    ShoppingListProvider provider,
    ShoppingListItem item,
  ) {
    final List<ShoppingListTag> itemTags = item.tagIds
        .map((String id) => provider.getTagById(id))
        .whereType<ShoppingListTag>()
        .toList();

    final Color leadingColor = itemTags.isEmpty
        ? Colors.grey
        : _hexToColor(itemTags.first.colorHex);

    return Dismissible(
      key: ValueKey<String>('item_${item.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) {
        // T-08: حذف آیتم همراه با SnackBar Undo (رویکرد استاندارد Flutter).
        final ShoppingListItem removedItem = item.copyWith();
        provider.deleteItem(item.id!);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isFa
                ? 'آیتم «${removedItem.name}» حذف شد'
                : 'Item "${removedItem.name}" deleted'),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: _isFa ? 'بازگردانی' : 'UNDO',
              textColor: Colors.yellowAccent,
              onPressed: () {
                // کاربر Undo زد → آیتم را دوباره اضافه کن.
                provider.addItem(removedItem.copyWith(
                  id: null,
                  serverId: null,
                  pendingSync: true,
                  isPurchased: false,
                  purchasedAt: null,
                  clearPurchasedAt: true,
                  createdAt: DateTime.now(),
                ));
              },
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              CircleAvatar(
                backgroundColor: leadingColor,
                child: Text(
                  itemTags.isEmpty
                      ? '?'
                      : itemTags.first
                          .displayName(provider.selectedLocale)
                          .substring(0, 1),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        decoration: item.isPurchased
                            ? TextDecoration.lineThrough
                            : null,
                        color: item.isPurchased ? Colors.grey : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${item.addedBy} • '
                      '${_formatDate(item.createdAt, provider.selectedLocale)}'
                      '${item.pendingSync ? ' • pending' : ''}',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade600),
                    ),
                    // نمایش «همه» تگهای آیتم (چند‌به‌چند، بدون محدودیت).
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: <Widget>[
                        for (final ShoppingListTag tag in itemTags)
                          _buildSmallTagChip(
                            tag: tag,
                            locale: provider.selectedLocale,
                            onRemove: () =>
                                provider.toggleTagOnItem(item.id!, tag.id),
                          ),
                        _buildAddTagChip(context, provider, item),
                      ],
                    ),
                    if (item.barcode.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        item.barcode,
                        style: const TextStyle(
                            fontSize: 10, fontFamily: 'monospace'),
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                children: <Widget>[
                  Checkbox(
                    value: item.isPurchased,
                    onChanged: (bool? value) => provider
                        .togglePurchaseStatus(item.id!, value ?? false),
                  ),
                  InkWell(
                    onTap: () => _showEditItemDialog(context, provider, item),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.edit, size: 18, color: Colors.blueGrey),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSmallTagChip({
    required ShoppingListTag tag,
    required String locale,
    required VoidCallback onRemove,
  }) {
    return Chip(
      label: Text(
        tag.displayName(locale),
        style: const TextStyle(fontSize: 10, color: Colors.white),
      ),
      backgroundColor: _hexToColor(tag.colorHex),
      deleteIcon: const Icon(Icons.close, size: 12, color: Colors.white),
      onDeleted: onRemove,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: EdgeInsets.zero,
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  Widget _buildAddTagChip(
    BuildContext context,
    ShoppingListProvider provider,
    ShoppingListItem item,
  ) {
    return ActionChip(
      avatar: const Icon(Icons.add, size: 12),
      label: const Text('tag', style: TextStyle(fontSize: 10)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onPressed: () => _showEditTagsDialog(context, provider, item),
    );
  }

  // ==================== افزودن آیتم جدید ====================

  void _showAddItemDialog(
      BuildContext context, ShoppingListProvider provider) {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController barcodeController = TextEditingController();
    List<String> selectedTagIds = <String>['other'];

    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) =>
            AlertDialog(
          title: Text(_isFa ? 'افزودن آیتم جدید' : 'Add New Item'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: _isFa ? 'نام کالا' : 'Item name',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: barcodeController,
                  decoration: InputDecoration(
                    labelText: _isFa ? 'بارکد (اختیاری)' : 'Barcode (optional)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    prefixIcon: const Icon(Icons.qr_code),
                  ),
                ),
                const SizedBox(height: 16),
                _buildMultiTagSelector(
                  provider: provider,
                  selectedTagIds: selectedTagIds,
                  setDialogState: setDialogState,
                  onChanged: (List<String> updated) =>
                      selectedTagIds = updated,
                  onRequestCreateTag: () => _showCreateTagDialog(
                    context,
                    provider,
                    onCreated: (ShoppingListTag tag) {
                      selectedTagIds = <String>[...selectedTagIds, tag.id];
                      setDialogState(() {});
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(_isFa ? 'انصراف' : 'Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(_isFa
                          ? 'لطفاً نام کالا را وارد کنید'
                          : 'Please enter item name'),
                    ),
                  );
                  return;
                }

                final ShoppingListItem newItem = ShoppingListItem(
                  name: nameController.text.trim(),
                  barcode: barcodeController.text.trim(),
                  tagIds: selectedTagIds,
                  addedBy: provider.username ?? 'Unknown',
                  createdAt: DateTime.now(),
                );

                await provider.addItem(newItem);
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(_isFa
                        ? 'آیتم اضافه شد (در حال ارسال به سرور)'
                        : 'Item added (uploading in background)'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              child: Text(_isFa ? 'افزودن' : 'Add'),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== ویرایش آیتم ====================

  Future<void> _showEditItemDialog(
    BuildContext context,
    ShoppingListProvider provider,
    ShoppingListItem item,
  ) async {
    final TextEditingController nameController =
        TextEditingController(text: item.name);
    final TextEditingController barcodeController =
        TextEditingController(text: item.barcode);

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) =>
            AlertDialog(
          title: Text(_isFa ? 'ویرایش آیتم' : 'Edit Item'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: _isFa ? 'نام کالا' : 'Item name',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: barcodeController,
                  decoration: InputDecoration(
                    labelText: _isFa ? 'بارکد (اختیاری)' : 'Barcode (optional)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    prefixIcon: const Icon(Icons.qr_code),
                  ),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () {
                    Navigator.pop(dialogContext);
                    _showEditTagsDialog(context, provider, item);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade400),
                    ),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.label_outline, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _isFa
                                ? 'مدیریت تگ‌های این آیتم'
                                : 'Manage tags for this item',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade800,
                            ),
                          ),
                        ),
                        const Icon(Icons.chevron_right, size: 18),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(_isFa ? 'انصراف' : 'Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(_isFa
                          ? 'لطفاً نام کالا را وارد کنید'
                          : 'Please enter item name'),
                    ),
                  );
                  return;
                }

                await provider.updateItemDetails(
                  item.id!,
                  name: nameController.text.trim(),
                  barcode: barcodeController.text.trim(),
                );
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(_isFa
                        ? 'آیتم بروزرسانی شد (در حال ارسال به سرور)'
                        : 'Item updated (uploading in background)'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              child: Text(_isFa ? 'ذخیره' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  /// انتخابگر تگ چندگانه - **بدون محدودیت تعداد**.
  Widget _buildMultiTagSelector({
    required ShoppingListProvider provider,
    required List<String> selectedTagIds,
    required StateSetter setDialogState,
    required ValueChanged<List<String>> onChanged,
    required VoidCallback onRequestCreateTag,
  }) {
    final List<ShoppingListTag> tags = provider.allTags;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                _isFa
                    ? 'تگ‌ها (هر تعداد بخواهید)'
                    : 'Tags (as many as you want)',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            TextButton.icon(
              onPressed: onRequestCreateTag,
              icon: const Icon(Icons.add, size: 16),
              label: Text(_isFa ? 'تگ جدید' : 'New tag'),
            ),
          ],
        ),
        Text(
          _isFa
              ? '${selectedTagIds.length} تگ انتخاب شده (بدون محدودیت)'
              : '${selectedTagIds.length} selected (no limit)',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        if (tags.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              _isFa
                  ? 'هنوز تگی وجود ندارد. از دکمه «تگ جدید» استفاده کنید.'
                  : 'No tags yet. Use the "New tag" button.',
              style: TextStyle(color: Colors.grey.shade600, fontStyle: FontStyle.italic),
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            // T-09: نمایش Wrap بصورت indent نشانه‌دار از طریق padding چپ.
            for (final ShoppingListTag tag in tags)
              Padding(
                padding: EdgeInsets.only(
                  left: tag.depth(tags) * 10.0,
                ),
                child: FilterChip(
                  label: Text(tag.displayName(provider.selectedLocale)),
                  selected: selectedTagIds.contains(tag.id),
                  onSelected: (bool isSelected) {
                    final List<String> updated =
                        List<String>.from(selectedTagIds);
                    if (isSelected) {
                      if (!updated.contains(tag.id)) updated.add(tag.id);
                    } else {
                      updated.remove(tag.id);
                    }
                    setDialogState(() => onChanged(updated));
                  },
                  avatar: CircleAvatar(
                    backgroundColor: _hexToColor(tag.colorHex),
                    child: const Icon(
                      Icons.label,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // ==================== ویرایش تگ‌های یک آیتم ====================

  void _showEditTagsDialog(
    BuildContext context,
    ShoppingListProvider provider,
    ShoppingListItem item,
  ) {
    List<String> selected = List<String>.from(item.tagIds);

    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) =>
            AlertDialog(
          title: Text(_isFa ? 'تگ‌های «${item.name}»' : 'Tags for "${item.name}"'),
          content: SingleChildScrollView(
            child: _buildMultiTagSelector(
              provider: provider,
              selectedTagIds: selected,
              setDialogState: setDialogState,
              onChanged: (List<String> updated) => selected = updated,
              onRequestCreateTag: () => _showCreateTagDialog(
                context,
                provider,
                onCreated: (ShoppingListTag tag) {
                  selected = <String>[...selected, tag.id];
                  setDialogState(() {});
                },
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(_isFa ? 'انصراف' : 'Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                await provider.updateItemTags(item.id!, selected);
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(_isFa
                        ? 'تگ‌ها ذخیره شد'
                        : 'Tags saved'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              child: Text(_isFa ? 'ذخیره' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== ساخت تگ سفارشی جدید ====================

  Future<void> _showCreateTagDialog(
    BuildContext context,
    ShoppingListProvider provider, {
    ValueChanged<ShoppingListTag>? onCreated,
  }) async {
    final TextEditingController nameController = TextEditingController();
    String selectedColor = CustomTagService.colorPalette.first;
    String? selectedParentId;
    String? validationError;

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) {
          final List<ShoppingListTag> tags = provider.allTags;
          return AlertDialog(
            title: Text(_isFa ? 'ساخت تگ جدید' : 'Create New Tag'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  TextField(
                    controller: nameController,
                    onChanged: (_) => setDialogState(() => validationError = null),
                    decoration: InputDecoration(
                      labelText: _isFa ? 'نام تگ' : 'Tag name',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      errorText: validationError,
                      prefixIcon: const Icon(Icons.label_outline),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _isFa ? 'تگ والد (ساختار درختی)' : 'Parent Tag (Tree)',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        value: selectedParentId,
                        isExpanded: true,
                        hint: Text(_isFa ? 'بدون والد (سطح ریشه)' : 'No parent (Root)'),
                        items: <DropdownMenuItem<String?>>[
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text(_isFa ? '— سطح ریشه —' : '— Root level —'),
                          ),
                          for (final ShoppingListTag t in tags)
                            DropdownMenuItem<String?>(
                              value: t.id,
                              child: Padding(
                                padding: EdgeInsets.only(
                                  left: t.depth(tags) * 16.0,
                                  right: _isFa ? t.depth(tags) * 16.0 : 0,
                                ),
                                child: Row(
                                  children: <Widget>[
                                    CircleAvatar(
                                      radius: 9,
                                      backgroundColor: _hexToColor(t.colorHex),
                                      child: const Icon(
                                        Icons.label,
                                        size: 10,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        t.displayName(provider.selectedLocale),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                        onChanged: (String? newValue) {
                          setDialogState(() => selectedParentId = newValue);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _isFa ? 'رنگ تگ' : 'Tag color',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final String hex in CustomTagService.colorPalette)
                        GestureDetector(
                          onTap: () =>
                              setDialogState(() => selectedColor = hex),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: _hexToColor(hex),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: selectedColor == hex
                                    ? Colors.black
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                            child: selectedColor == hex
                                ? const Icon(Icons.check,
                                    size: 16, color: Colors.white)
                                : null,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _hexToColor(selectedColor).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: <Widget>[
                        CircleAvatar(
                          backgroundColor: _hexToColor(selectedColor),
                          radius: 12,
                          child: const Icon(Icons.star,
                              size: 12, color: Colors.white),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                nameController.text.trim().isEmpty
                                    ? (_isFa ? 'پیش‌نمایش تگ' : 'Tag preview')
                                    : nameController.text.trim(),
                                style: const TextStyle(fontSize: 12),
                              ),
                              if (selectedParentId != null)
                                Text(
                                  _isFa
                                      ? 'زیرمجموعه: ${provider.getTagById(selectedParentId!)?.displayName(provider.selectedLocale) ?? '—'}'
                                      : 'Child of: ${provider.getTagById(selectedParentId!)?.displayName(provider.selectedLocale) ?? '—'}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(_isFa ? 'انصراف' : 'Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final String name = nameController.text.trim();

                  if (name.isEmpty) {
                    setDialogState(() => validationError =
                        _isFa ? 'نام تگ الزامی است' : 'Tag name is required');
                    return;
                  }

                  final TagCreateResult result = await provider.createTag(
                    nameFa: name,
                    nameEn: name,
                    colorHex: selectedColor,
                    parentId: selectedParentId,
                  );

                  if (!dialogContext.mounted) return;

                  if (result.status == TagCreateStatus.duplicate) {
                    setDialogState(() => validationError = _isFa
                        ? 'این نام تگ از قبل وجود دارد'
                        : 'This tag name already exists');
                    if (result.tag != null) onCreated?.call(result.tag!);
                    return;
                  }

                  if (result.status != TagCreateStatus.created) {
                    setDialogState(() => validationError = result.messageFa);
                    return;
                  }

                  Navigator.pop(dialogContext);
                  if (result.tag != null) onCreated?.call(result.tag!);

                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(_isFa
                          ? 'تگ «${result.tag?.nameFa ?? name}» ذخیره شد'
                          : 'Tag "${result.tag?.nameEn ?? name}" saved'),
                      duration: const Duration(seconds: 2),
                      backgroundColor: Colors.green,
                    ),
                  );
                },
                child: Text(_isFa ? 'ساخت تگ' : 'Create'),
              ),
            ],
          );
        },
      ),
    );
  }
}