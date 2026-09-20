import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/services/app_logger.dart';

class DebugOverlay extends StatefulWidget {
  final Widget child;

  const DebugOverlay({Key? key, required this.child}) : super(key: key);

  @override
  State<DebugOverlay> createState() => _DebugOverlayState();
}

class _DebugOverlayState extends State<DebugOverlay> {
  bool _isVisible = false;
  bool _isMinimized = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppLogger>(
      builder: (context, logger, _) {
        return SizedBox.expand(
          child: Stack(
            fit: StackFit.expand,
            children: [
              widget.child,
              if (_isVisible && !_isMinimized)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 10,
                  right: 10,
                  left: 10,
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 300),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface.withOpacity(0.95),
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
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildHeader(logger),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 240),
                          child: _buildLogList(logger),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_isVisible && _isMinimized)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 10,
                  right: 10,
                  child: _buildMinimizedButton(logger),
                ),
              if (!_isVisible)
                Positioned(
                  bottom: 20,
                  right: 20,
                  child: FloatingActionButton.small(
                    heroTag: 'debug_fab',
                    onPressed: () => setState(() => _isVisible = true),
                    backgroundColor: logger.isServerConnected
                        ? Colors.green
                        : logger.lastServerError.isNotEmpty
                            ? Colors.red
                            : Colors.orange,
                    child: const Icon(Icons.bug_report, size: 20),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(AppLogger logger) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.bug_report, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Debug Logs - ${logger.logs.length} entries',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          _buildStatusIndicator(logger),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.filter_list, size: 20),
            onPressed: () => _showFilterDialog(logger),
          ),
          IconButton(
            icon: Icon(logger.isPaused ? Icons.play_arrow : Icons.pause, size: 20),
            onPressed: () => logger.togglePause(),
          ),
          IconButton(
            icon: Icon(logger.autoScroll ? Icons.vertical_align_bottom : Icons.lock, size: 20),
            onPressed: () => logger.toggleAutoScroll(),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: () => logger.clearLogs(),
          ),
          IconButton(
            icon: const Icon(Icons.download, size: 20),
            onPressed: () => _exportLogs(logger),
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_up, size: 20),
            onPressed: () => setState(() => _isMinimized = true),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(AppLogger logger) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: logger.isServerConnected ? Colors.green : Colors.red,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            logger.isServerConnected ? Icons.cloud_done : Icons.cloud_off,
            size: 14,
            color: Colors.white,
          ),
          const SizedBox(width: 4),
          Text(
            logger.isServerConnected ? 'Connected' : 'Disconnected',
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildMinimizedButton(AppLogger logger) {
    return GestureDetector(
      onTap: () => setState(() => _isMinimized = false),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: logger.isServerConnected ? Colors.green : Colors.red,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              logger.isServerConnected ? Icons.cloud_done : Icons.cloud_off,
              color: Colors.white,
              size: 24,
            ),
            const SizedBox(height: 2),
            Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildLogList(AppLogger logger) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(8),
      itemCount: logger.logs.length,
      itemBuilder: (context, index) {
        final log = logger.logs[index];
        return _buildLogTile(log);
      },
    );
  }

  Widget _buildLogTile(LogEntry log) {
    Color bgColor;
    switch (log.level) {
      case LogLevel.debug:
        bgColor = Colors.grey.shade200;
        break;
      case LogLevel.info:
        bgColor = Colors.blue.shade50;
        break;
      case LogLevel.warning:
        bgColor = Colors.orange.shade50;
        break;
      case LogLevel.error:
        bgColor = Colors.red.shade50;
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      color: bgColor,
      child: ListTile(
        dense: true,
        leading: Text(log.levelIcon, style: const TextStyle(fontSize: 16)),
        title: Text(
          '[${log.formattedTime}] ${log.message}',
          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: log.error != null
            ? Text(
                'Error: ${log.error}',
                style: const TextStyle(fontSize: 10, color: Colors.red, fontFamily: 'monospace'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              )
            : null,
        trailing: Text(
          log.source,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
        ),
      ),
    );
  }

  void _showFilterDialog(AppLogger logger) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filter Log Level'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: LogLevel.values.map((level) {
            return RadioListTile<LogLevel>(
              title: Text(_getLevelName(level)),
              value: level,
              groupValue: logger.filterLevel,
              onChanged: (value) {
                logger.setFilterLevel(value!);
                Navigator.pop(context);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  String _getLevelName(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return 'Debug (All)';
      case LogLevel.info:
        return 'Info & Above';
      case LogLevel.warning:
        return 'Warning & Above';
      case LogLevel.error:
        return 'Error Only';
    }
  }

  Future<void> _exportLogs(AppLogger logger) async {
    try {
      final logsText = logger.exportLogs();
      await Clipboard.setData(ClipboardData(text: logsText));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Logs copied to clipboard')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to export logs: $e')),
      );
    }
  }
}
