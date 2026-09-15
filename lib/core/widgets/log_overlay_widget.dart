import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/logging_service.dart';

/// ویجت نمایش لاگ‌ها به صورت overlay شناور
/// این ویجت به کاربر اجازه می‌دهد در حین کار با برنامه، لاگ‌ها را مشاهده کند
class LogOverlayWidget extends StatefulWidget {
  final bool isVisible;
  final VoidCallback? onToggleVisibility;

  const LogOverlayWidget({
    super.key,
    this.isVisible = true,
    this.onToggleVisibility,
  });

  @override
  State<LogOverlayWidget> createState() => _LogOverlayWidgetState();
}

class _LogOverlayWidgetState extends State<LogOverlayWidget> {
  final LoggingService _loggingService = LoggingService();
  final ScrollController _scrollController = ScrollController();
  bool _isExpanded = false;
  LogLevel? _filterLevel;

  @override
  void initState() {
    super.initState();
    _loggingService.addListener(_onLogsChanged);
  }

  @override
  void dispose() {
    _loggingService.removeListener(_onLogsChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onLogsChanged() {
    if (mounted && _loggingService.autoScroll && _scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible) return const SizedBox.shrink();

    return Positioned(
      bottom: 16,
      right: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          // دکمه اصلی برای باز/بستن لاگ
          if (!_isExpanded)
            FloatingActionButton.small(
              heroTag: 'logToggle',
              mini: true,
              onPressed: () {
                setState(() => _isExpanded = true);
              },
              backgroundColor: _getLogLevelColor(LogLevel.error),
              child: const Icon(Icons.bug_report, color: Colors.white),
            ),

          // پنل نمایش لاگ‌ها
          if (_isExpanded) ...[
            Container(
              width: MediaQuery.of(context).size.width - 48,
              height: 300,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.85),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // هدر پنل لاگ
                  _buildHeader(),
                  // فیلتر سطح لاگ
                  _buildFilterBar(),
                  // لیست لاگ‌ها
                  Expanded(
                    child: _buildLogList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          const Icon(Icons.bug_report, size: 20, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Debug Logs (${_loggingService.logs.length})',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.clear_all, size: 20, color: Colors.white),
            onPressed: () => _loggingService.clear(),
            tooltip: 'Clear logs',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          IconButton(
            icon: const Icon(Icons.file_download, size: 20, color: Colors.white),
            onPressed: () => _exportLogs(),
            tooltip: 'Export logs',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          IconButton(
            icon: Icon(
              _loggingService.isPaused ? Icons.play_arrow : Icons.pause,
              size: 20,
              color: Colors.white,
            ),
            onPressed: () {
              _loggingService.setPaused(!_loggingService.isPaused);
            },
            tooltip: _loggingService.isPaused ? 'Resume logging' : 'Pause logging',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20, color: Colors.white),
            onPressed: () {
              setState(() => _isExpanded = false);
            },
            tooltip: 'Close',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          const Text(
            'Filter:',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(width: 4),
          ...LogLevel.values.map((level) => Padding(
            padding: const EdgeInsets.only(right: 4),
            child: FilterChip(
              label: Text(
                level.icon + level.label,
                style: const TextStyle(fontSize: 10, color: Colors.white),
              ),
              selected: _filterLevel == level,
              onSelected: (selected) {
                setState(() {
                  _filterLevel = selected ? level : null;
                });
              },
              backgroundColor: Colors.grey.shade800,
              selectedColor: _getLogLevelColor(level).withOpacity(0.5),
              checkmarkColor: Colors.white,
              labelStyle: const TextStyle(color: Colors.white),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildLogList() {
    final logs = _filterLevel != null
        ? _loggingService.getFilteredLogs(_filterLevel)
        : _loggingService.logs;

    if (logs.isEmpty) {
      return const Center(
        child: Text(
          'No logs to display',
          style: TextStyle(color: Colors.white54, fontSize: 14),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(8),
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final log = logs[index];
        return _buildLogEntry(log);
      },
    );
  }

  Widget _buildLogEntry(LogEntry log) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _getLogLevelColor(log.level).withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: _getLogLevelColor(log.level).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                log.level.icon,
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(width: 4),
              Text(
                '[${log.timestamp.toString().substring(11, 19)}]',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _getLogLevelColor(log.level),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  log.level.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  log.source,
                  style: const TextStyle(
                    color: Colors.blueAccent,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            log.message,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
            ),
          ),
          if (log.metadata != null && log.metadata!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                log.metadata.toString(),
                style: TextStyle(
                  color: Colors.green.shade300,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _getLogLevelColor(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return Colors.purple;
      case LogLevel.info:
        return Colors.blue;
      case LogLevel.warning:
        return Colors.orange;
      case LogLevel.error:
        return Colors.red;
    }
  }

  Future<void> _exportLogs() async {
    final textLogs = _loggingService.exportToText();
    await Clipboard.setData(ClipboardData(text: textLogs));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Logs copied to clipboard'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }
}
