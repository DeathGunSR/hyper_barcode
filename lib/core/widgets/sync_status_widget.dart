import 'package:flutter/material.dart';
import '../providers/sync_provider.dart';

/// ویجت نمایش وضعیت همگام‌سازی به صورت غیرمسدودکننده
/// این ویجت می‌تواند به صورت snackbar یا banner نمایش داده شود
class SyncStatusWidget extends StatelessWidget {
  final VoidCallback? onTap;
  final VoidCallback? onDismiss;

  const SyncStatusWidget({
    super.key,
    this.onTap,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final syncProvider = SyncProvider();
    final state = syncProvider.syncState;

    // اگر در حالت idle هستیم، چیزی نمایش نده
    if (state == SyncState.idle && !syncProvider.isSyncing) {
      return const SizedBox.shrink();
    }

    Color backgroundColor;
    IconData icon;
    String message;

    switch (state) {
      case SyncState.syncing:
        backgroundColor = Colors.blue;
        icon = Icons.sync;
        message = '${syncProvider.currentStatus} (${syncProvider.progress}/${syncProvider.total})';
        break;
      case SyncState.success:
        backgroundColor = Colors.green;
        icon = Icons.check_circle;
        message = 'Sync completed at ${syncProvider.lastSyncTime?.toString().substring(11, 16) ?? 'unknown time'}';
        break;
      case SyncState.failed:
        backgroundColor = Colors.red;
        icon = Icons.error;
        message = 'Sync failed: ${syncProvider.lastError ?? 'Unknown error'}';
        break;
      case SyncState.idle:
        return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    state == SyncState.syncing ? 'Syncing...' : state.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  if (state == SyncState.syncing) ...[
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: syncProvider.progressPercent,
                      backgroundColor: Colors.white.withOpacity(0.3),
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (state != SyncState.syncing && onDismiss != null)
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 20),
                onPressed: onDismiss,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
          ],
        ),
      ),
    );
  }
}

/// ویجت کوچک نمایش وضعیت همگام‌سازی برای استفاده در AppBar
class SyncStatusIndicator extends StatelessWidget {
  final VoidCallback? onTap;

  const SyncStatusIndicator({
    super.key,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final syncProvider = SyncProvider();

    if (!syncProvider.isSyncing && syncProvider.syncState == SyncState.idle) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: syncProvider.syncState == SyncState.failed
              ? Colors.red
              : syncProvider.syncState == SyncState.success
                  ? Colors.green
                  : Colors.blue,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (syncProvider.isSyncing)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            else
              Icon(
                syncProvider.syncState.icon,
                size: 16,
                color: Colors.white,
              ),
            if (syncProvider.isSyncing) ...[
              const SizedBox(width: 8),
              Text(
                '${(syncProvider.progressPercent * 100).toInt()}%',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
