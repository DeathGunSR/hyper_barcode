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
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 320),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface.withOpacity(0.96),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildHeader(logger),
                            Flexible(
                              fit: FlexFit.loose,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 240),
                                child: _buildLogList(logger),
                              ),
                            ),
                          ],
                        ),
                      ),
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
                  bottom: MediaQuery.of(context).padding.bottom + 20,
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.bug_report, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Logs (${logger.logs.length})',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                ),
              ),
              _buildStatusIndicator(logger),
              const SizedBox(width: 4),
              InkWell(
                onTap: () => setState(() => _isMinimized = true),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.keyboard_arrow_up, size: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildHeaderIcon(Icons.filter_list, onTap: () => _showFilterDialog(logger)),
                _buildHeaderIcon(logger.isPaused ? Icons.play_arrow : Icons.pause,
                    onTap: () => logger.togglePause()),
                _buildHeaderIcon(
                    logger.autoScroll ? Icons.vertical_align_bottom : Icons.lock,
                    onTap: () => logger.toggleAutoScroll()),
                _buildHeaderIcon(Icons.delete_outline, onTap: () => logger.clearLogs()),
                _buildHeaderIcon(Icons.download, onTap: () => _exportLogs(logger)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderIcon(IconData icon, {required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Icon(icon, size: 18),
      ),
    );
  }

  Widget _buildStatusIndicator(AppLogger logger) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: logger.isServerConnected ? Colors.green : Colors.red,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        logger.isServerConnected ? Icons.cloud_done : Icons.cloud_off,
        size: 14,
        color: Colors.white,
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
      elevation: 0.5,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 22,
              child: Text(log.levelIcon, style: const TextStyle(fontSize: 14)),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        log.formattedTime,
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.grey.shade600,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          log.source,
                          style: const TextStyle(
                            fontSize: 9,
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    log.message,
                    style: const TextStyle(fontSize: 11),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    softWrap: true,
                  ),
                  if (log.error != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '! ${log.error}',
                      style: const TextStyle(fontSize: 9, color: Colors.red),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      softWrap: true,
                    ),
                  ],
                ],
              ),
            ),
          ],
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
