import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/connection_diagnostics.dart';
import '../services/logging_service.dart';
import 'sync_status_widget.dart';

/// میزبان «کنسول دیباگ» شناور.
///
/// این ویجت داخل `MaterialApp.builder` قرار می‌گیرد؛ بنابراین:
/// - در **همه** صفحات (اسکنر، چک‌لیست، تنظیمات و ...) دیده می‌شود و
///   با جابجایی بین صفحات از بین نمی‌رود.
/// - هیچ بخشی از UI را مسدود نمی‌کند (فقط ناحیه کوچک خودش را اشغال می‌کند).
class DebugOverlayHost extends StatefulWidget {
  final Widget child;

  const DebugOverlayHost({super.key, required this.child});

  @override
  State<DebugOverlayHost> createState() => _DebugOverlayHostState();
}

class _DebugOverlayHostState extends State<DebugOverlayHost> {
  final LoggingService _log = LoggingService();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  bool _panelOpen = false;
  bool _showDiagnostics = false;
  bool _runningDiagnostics = false;
  List<DiagnosticResult> _diagnostics = <DiagnosticResult>[];
  bool _lastAutoScroll = true;

  @override
  void initState() {
    super.initState();
    _log.addListener(_onLogsChanged);
  }

  @override
  void dispose() {
    _log.removeListener(_onLogsChanged);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onLogsChanged() {
    if (!mounted || !_panelOpen) return;
    if (!_log.autoScroll) return;
    if (!_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        // محتوای اصلی برنامه (Navigator).
        widget.child,

        // بنر وضعیت همگام‌سازی - غیرمسدودکننده و در همه صفحات.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: IgnorePointer(
              ignoring: false,
              child: SyncStatusBanner(
                onTap: () => setState(() => _panelOpen = true),
              ),
            ),
          ),
        ),

        // پنل لاگ.
        if (_panelOpen)
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: _buildPanel(context),
          ),

        // دکمه همیشه‌در‌دسترس دیباگ.
        Positioned(
          left: 12,
          bottom: 12,
          child: SafeArea(child: _buildPill()),
        ),
      ],
    );
  }

  // ==================== دکمه شناور ====================

  Widget _buildPill() {
    return ListenableBuilder(
      listenable: _log,
      builder: (BuildContext context, Widget? child) {
        final int errors = _log.errorCount;
        return FloatingActionButton.small(
          heroTag: 'debugConsolePill',
          onPressed: () => setState(() => _panelOpen = !_panelOpen),
          backgroundColor:
              errors > 0 ? Colors.red.shade700 : Colors.blueGrey.shade800,
          tooltip: 'Debug console (${_log.totalCount} logs, $errors errors)',
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              const Icon(Icons.bug_report, color: Colors.white, size: 20),
              if (errors > 0)
                Positioned(
                  right: -6,
                  top: -6,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Colors.yellow,
                      shape: BoxShape.circle,
                    ),
                    constraints:
                        const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      errors > 99 ? '99+' : '$errors',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ==================== پنل لاگ ====================

  Widget _buildPanel(BuildContext context) {
    final double height = MediaQuery.of(context).size.height * 0.52;
    return Material(
      elevation: 12,
      borderRadius: BorderRadius.circular(12),
      color: const Color(0xF21B1B1B),
      child: SizedBox(
        height: height,
        child: Column(
          children: <Widget>[
            _buildPanelHeader(context),
            _buildFilterBar(),
            if (_showDiagnostics) _buildDiagnosticsSection(),
            const Divider(height: 1, color: Colors.white24),
            Expanded(child: _buildLogList()),
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildPanelHeader(BuildContext context) {
    return ListenableBuilder(
      listenable: _log,
      builder: (BuildContext context, Widget? child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: const BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Row(
            children: <Widget>[
              const Icon(Icons.terminal, color: Colors.greenAccent, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Debug console',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _log.connectionSummary,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'Run connection diagnostics',
                icon: const Icon(Icons.health_and_safety,
                    color: Colors.lightBlueAccent, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                onPressed: _runningDiagnostics ? null : _runDiagnostics,
              ),
              IconButton(
                tooltip: 'Minimize',
                icon: const Icon(Icons.keyboard_arrow_down,
                    color: Colors.white, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                onPressed: () => setState(() => _panelOpen = false),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterBar() {
    return ListenableBuilder(
      listenable: _log,
      builder: (BuildContext context, Widget? child) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  for (final LogLevel level in LogLevel.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: ChoiceChip(
                        label: Text(
                          level.label,
                          style: TextStyle(
                            fontSize: 10,
                            color: _log.minLogLevel == level
                                ? Colors.black
                                : Colors.white70,
                          ),
                        ),
                        selected: _log.minLogLevel == level,
                        selectedColor: _levelColor(level),
                        backgroundColor: Colors.white12,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => _log.setMinLogLevel(level),
                      ),
                    ),
                  const Spacer(),
                  IconButton(
                    tooltip: _log.isPaused
                        ? 'Resume auto-scroll'
                        : 'Pause auto-scroll (logging continues)',
                    icon: Icon(
                      _log.isPaused ? Icons.play_arrow : Icons.pause,
                      color:
                          _log.isPaused ? Colors.orangeAccent : Colors.white70,
                      size: 18,
                    ),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 30, minHeight: 30),
                    onPressed: () => _log.setPaused(!_log.isPaused),
                  ),
                  IconButton(
                    tooltip: _log.autoScroll
                        ? 'Auto-scroll: on'
                        : 'Auto-scroll: off',
                    icon: Icon(
                      _log.autoScroll
                          ? Icons.vertical_align_bottom
                          : Icons.vertical_align_center,
                      color: _log.autoScroll
                          ? Colors.greenAccent
                          : Colors.white38,
                      size: 18,
                    ),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 30, minHeight: 30),
                    onPressed: () => _log.setAutoScroll(!_log.autoScroll),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 32,
                child: TextField(
                  controller: _searchController,
                  onChanged: _log.setSearchQuery,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Filter logs (text or source)...',
                    hintStyle:
                        const TextStyle(color: Colors.white38, fontSize: 11),
                    prefixIcon: const Icon(Icons.search,
                        color: Colors.white38, size: 16),
                    filled: true,
                    fillColor: Colors.white10,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ==================== بخش تشخیص اتصال ====================

  Widget _buildDiagnosticsSection() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 170),
      color: Colors.white10,
      child: _runningDiagnostics
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text('Running connection diagnostics...',
                      style: TextStyle(color: Colors.white, fontSize: 12)),
                ],
              ),
            )
          : ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              itemCount: _diagnostics.length,
              itemBuilder: (BuildContext context, int index) {
                final DiagnosticResult result = _diagnostics[index];
                final Color color = result.skipped
                    ? Colors.grey
                    : (result.ok ? Colors.greenAccent : Colors.redAccent);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              result.statusLabel,
                              style: TextStyle(
                                color: color,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              result.title,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 11),
                            ),
                          ),
                          Text(
                            '${result.duration.inMilliseconds}ms',
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 9),
                          ),
                        ],
                      ),
                      if (!result.ok && !result.skipped) ...<Widget>[
                        Padding(
                          padding: const EdgeInsets.only(left: 4, top: 2),
                          child: SelectableText(
                            result.detail,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        if (result.hint != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 4, top: 2),
                            child: SelectableText(
                              result.hint!,
                              style: const TextStyle(
                                color: Colors.orangeAccent,
                                fontSize: 10,
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                );
              },
            ),
    );
  }

  void _runDiagnostics() async {
    setState(() {
      _showDiagnostics = true;
      _runningDiagnostics = true;
      _diagnostics = <DiagnosticResult>[];
    });

    final List<DiagnosticResult> results = await ConnectionDiagnostics.run(
      onProgress: (DiagnosticResult result) {
        if (!mounted) return;
        setState(() => _diagnostics = <DiagnosticResult>[
              ..._diagnostics,
              result,
            ]);
      },
    );

    if (!mounted) return;
    setState(() {
      _diagnostics = results;
      _runningDiagnostics = false;
    });

    final bool allOk = results.every(
      (DiagnosticResult r) => r.ok || r.skipped,
    );
    _log.setConnectionStatus(
      allOk ? ConnectionStatus.online : ConnectionStatus.offline,
      detail: '${results.where((DiagnosticResult r) => r.ok).length}/'
          '${results.length} checks passed',
      source: 'Diagnostics',
    );
  }

  // ==================== لیست لاگ‌ها ====================

  Widget _buildLogList() {
    return ListenableBuilder(
      listenable: _log,
      builder: (BuildContext context, Widget? child) {
        final List<LogEntry> entries = _log.visibleLogs;
        if (entries.isEmpty) {
          return const Center(
            child: Text(
              'No logs match the current filter',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          );
        }

        // پس از هر رندر به انتهای لیست می‌رویم تا آخرین لاگ دیده شود.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_log.autoScroll) return;
          if (_scrollController.hasClients) {
            _scrollController
                .jumpTo(_scrollController.position.maxScrollExtent);
          }
        });

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          itemCount: entries.length,
          itemBuilder: (BuildContext context, int index) =>
              _buildLogTile(entries[index]),
        );
      },
    );
  }

  Widget _buildLogTile(LogEntry entry) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                entry.timeString,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: _levelColor(entry.level).withOpacity(0.25),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  entry.level.label,
                  style: TextStyle(
                    color: _levelColor(entry.level),
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  entry.source,
                  style: const TextStyle(
                      color: Colors.lightBlueAccent, fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: SelectableText(
              entry.message,
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
          if (entry.metadata != null && entry.metadata!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: SelectableText(
                entry.metadata.toString(),
                style: TextStyle(
                  color: Colors.green.shade300,
                  fontSize: 9,
                  fontFamily: 'monospace',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color _levelColor(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return Colors.purpleAccent;
      case LogLevel.info:
        return Colors.lightBlueAccent;
      case LogLevel.warning:
        return Colors.orangeAccent;
      case LogLevel.error:
        return Colors.redAccent;
    }
  }

  // ==================== نوار پایین: پاک کردن / خروجی ====================

  Widget _buildFooter(BuildContext context) {
    return ListenableBuilder(
      listenable: _log,
      builder: (BuildContext context, Widget? child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: const BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '${_log.visibleLogs.length}/${_log.totalCount} shown | '
                  '${_log.errorCount} errors | ${_log.warningCount} warnings',
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'Clear logs',
                icon: const Icon(Icons.delete_sweep,
                    color: Colors.redAccent, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                onPressed: _log.clear,
              ),
              IconButton(
                tooltip: 'Copy logs to clipboard',
                icon: const Icon(Icons.copy_all,
                    color: Colors.white70, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                onPressed: _copyLogs,
              ),
              IconButton(
                tooltip: 'Save logs to file and share',
                icon: const Icon(Icons.save_alt,
                    color: Colors.greenAccent, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                onPressed: _saveLogs,
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _copyLogs() async {
    await Clipboard.setData(ClipboardData(text: _log.exportToText()));
    _log.info('Logs copied to clipboard', source: 'System');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Logs copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _saveLogs() async {
    try {
      final File file = await _log.exportToFile();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Log saved to ${file.path}'),
          duration: const Duration(seconds: 4),
        ),
      );
      await Share.shareXFiles(
        <XFile>[XFile(file.path)],
        subject: 'Barcodify debug log',
      );
    } catch (e, stack) {
      _log.error(
        'Failed to export logs',
        source: 'System',
        exception: e,
        stackTrace: stack,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to export logs: $e')),
      );
    }
  }
}