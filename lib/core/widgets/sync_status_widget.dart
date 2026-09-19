import 'package:flutter/material.dart';

import '../providers/sync_provider.dart';

/// آیتم‌های نمایشی مشترک بین بنر و نشانگر.
class SyncVisuals {
  final Color color;
  final IconData icon;

  const SyncVisuals(this.color, this.icon);

  static SyncVisuals of(SyncState state) {
    switch (state) {
      case SyncState.syncing:
        return const SyncVisuals(Colors.blue, Icons.sync);
      case SyncState.success:
        return const SyncVisuals(Colors.green, Icons.check_circle);
      case SyncState.failed:
        return const SyncVisuals(Colors.red, Icons.error);
      case SyncState.alreadyInProgress:
        return const SyncVisuals(Colors.orange, Icons.hourglass_top);
      case SyncState.idle:
        return const SyncVisuals(Colors.grey, Icons.pause_circle_outline);
    }
  }
}

/// بنر غیرمسدودکننده وضعیت همگام‌سازی.
///
/// هیچ دیالوگی باز نمی‌کند و هیچ بخشی از UI را مسدود نمی‌کند؛ فقط یک نوار
/// کوچک نشان می‌دهد. چون در `MaterialApp.builder` قرار دارد (نگاه کنید به
/// `DebugOverlayHost`) در همه صفحات قابل مشاهده است.
class SyncStatusBanner extends StatelessWidget {
  final VoidCallback? onTap;

  const SyncStatusBanner({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final SyncProvider provider = SyncProvider();

    return ListenableBuilder(
      listenable: provider,
      builder: (BuildContext context, Widget? child) {
        if (!provider.bannerVisible || provider.syncState == SyncState.idle) {
          return const SizedBox.shrink();
        }

        final SyncVisuals visuals = SyncVisuals.of(provider.syncState);
        final bool syncing = provider.isSyncing;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: visuals.color.withOpacity(0.95),
                borderRadius: BorderRadius.circular(10),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withOpacity(0.18),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      if (syncing)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      else
                        Icon(visuals.icon, color: Colors.white, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${provider.syncState.labelFa} / '
                          '${provider.syncState.label}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      if (!syncing)
                        GestureDetector(
                          onTap: provider.dismissBanner,
                          child: const Padding(
                            padding: EdgeInsets.all(2),
                            child: Icon(Icons.close,
                                color: Colors.white, size: 16),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          provider.statusMessage,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (syncing && provider.total > 0) ...<Widget>[
                        const SizedBox(width: 8),
                        Text(
                          '${(provider.progressPercent * 100).toInt()}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (syncing) ...<Widget>[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: provider.total > 0
                            ? provider.progressPercent
                            : null,
                        minHeight: 4,
                        backgroundColor: Colors.white.withOpacity(0.3),
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// نشانگر کوچک وضعیت همگام‌سازی برای استفاده در AppBar / Drawer.
class SyncStatusIndicator extends StatelessWidget {
  final VoidCallback? onTap;
  final bool showWhenIdle;

  const SyncStatusIndicator({
    super.key,
    this.onTap,
    this.showWhenIdle = false,
  });

  @override
  Widget build(BuildContext context) {
    final SyncProvider provider = SyncProvider();

    return ListenableBuilder(
      listenable: provider,
      builder: (BuildContext context, Widget? child) {
        if (!showWhenIdle &&
            !provider.isSyncing &&
            provider.syncState == SyncState.idle) {
          return const SizedBox.shrink();
        }

        final SyncVisuals visuals = SyncVisuals.of(provider.syncState);

        return Tooltip(
          message: provider.statusMessage,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: visuals.color,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (provider.isSyncing)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  else
                    Icon(visuals.icon, size: 16, color: Colors.white),
                  if (provider.isSyncing) ...<Widget>[
                    const SizedBox(width: 6),
                    Text(
                      provider.total > 0
                          ? '${(provider.progressPercent * 100).toInt()}%'
                          : '...',
                      style:
                          const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// نمایش غیرمسدودکننده نتیجه همگام‌سازی با SnackBar.
void showSyncResultSnackBar(
  BuildContext context,
  SyncState state, {
  String? message,
  bool isRTL = true,
}) {
  final SyncVisuals visuals = SyncVisuals.of(state);
  final String text = message ??
      (state == SyncState.success
          ? (isRTL ? 'همگام‌سازی با موفقیت انجام شد' : 'Sync completed')
          : state == SyncState.alreadyInProgress
              ? (isRTL
                  ? 'همگام‌سازی از قبل در حال اجراست'
                  : 'A sync is already in progress')
              : (isRTL ? 'همگام‌سازی ناموفق بود' : 'Sync failed'));

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: <Widget>[
          Icon(visuals.icon, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
      backgroundColor: visuals.color,
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
    ),
  );
}