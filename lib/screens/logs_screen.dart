import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'package:flutter/services.dart';
import '../services/connection_logger.dart';

/// Unified connection-log viewer: every protocol's Dart-side events plus the
/// native Psiphon service lines (`native: …`), newest at the bottom with
/// auto-scroll, protocol filter chips, and copy/clear actions.
///
/// The tail of the log survives restarts (persisted by [ConnectionLogger]), so
/// events from *before* a crash are still visible here afterwards.
class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key, this.initialProtocol});

  final String? initialProtocol;

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  final ScrollController _scrollController = ScrollController();
  late String _protocolFilter;
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    final logger = ConnectionLogger.instance;
    final initialProtocol = widget.initialProtocol;
    _protocolFilter = initialProtocol != null &&
            logger.entries.any((entry) => entry.protocol == initialProtocol)
        ? initialProtocol
        : 'all';
    logger.addListener(_onLogChanged);
    logger.loadPersisted();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    ConnectionLogger.instance.removeListener(_onLogChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onLogChanged() {
    if (!mounted) return;
    setState(() {});
    if (_autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    try {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final logger = ConnectionLogger.instance;
    final protocols = logger.protocols;
    final entries = logger.entries
        .where((e) => _protocolFilter == 'all' || e.protocol == _protocolFilter)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('Connection Logs'),
        actions: [
          IconButton(
            icon: Icon(
              _autoScroll ? Icons.arrow_downward : Icons.pause,
              color: _autoScroll ? Colors.green : null,
            ),
            tooltip: context.l10n.text(_autoScroll ? 'Auto-scroll ON' : 'Auto-scroll OFF'),
            onPressed: () => setState(() => _autoScroll = !_autoScroll),
          ),
          IconButton(
            icon: const Icon(Icons.copy_outlined),
            tooltip: context.l10n.text('Copy all'),
            onPressed: entries.isEmpty ? null : () => _copyAll(context, entries),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: context.l10n.text('Clear logs'),
            onPressed: entries.isEmpty
                ? null
                : () async {
                    await logger.clear();
                  },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Protocol filter chips.
            if (protocols.length > 1)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    _filterChip('all', 'All', isDark),
                    const SizedBox(width: 8),
                    for (final p in protocols) ...[
                      _filterChip(p, p, isDark),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            // Log lines.
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.article_outlined,
                            size: 64,
                            color: theme.disabledColor,
                          ),
                          const SizedBox(height: 16),
                          LocalizedText(
                            'No logs yet',
                            style: TextStyle(
                              fontSize: 16,
                              color: theme.disabledColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          LocalizedText(
                            'Connect to VPN to see logs',
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.disabledColor,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(12),
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final e = entries[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _levelDot(e.level),
                              const SizedBox(width: 8),
                              Expanded(
                                child: RichText(
                                  text: TextSpan(
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontFamily: 'monospace',
                                      color: theme.textTheme.bodyMedium?.color,
                                      height: 1.5,
                                    ),
                                    children: [
                                      TextSpan(
                                        text: '${e.timeStamp} ',
                                        style: TextStyle(
                                            color: theme.disabledColor),
                                      ),
                                      TextSpan(
                                        text: '[${e.protocol}] ',
                                        style: TextStyle(
                                          color: _protocolColor(
                                              e.protocol, isDark),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      TextSpan(text: e.message),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            // Footer hint.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: LocalizedText(
                '${entries.length} lines • log tail survives restarts',
                style: TextStyle(fontSize: 11, color: theme.disabledColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String value, String label, bool isDark) {
    final selected = _protocolFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() {
        _protocolFilter = value;
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }),
    );
  }

  Widget _levelDot(ConnectionLogLevel level) {
    final color = switch (level) {
      ConnectionLogLevel.success => Colors.green,
      ConnectionLogLevel.warning => Colors.orange,
      ConnectionLogLevel.error => Colors.red,
      ConnectionLogLevel.info => Colors.blue,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }

  Color _protocolColor(String protocol, bool isDark) {
    return switch (protocol) {
      'psiphon' => isDark ? Colors.tealAccent : Colors.teal.shade700,
      'xray' => isDark ? Colors.lightBlueAccent : Colors.blue.shade700,
      'sstp' => isDark ? Colors.amberAccent : Colors.orange.shade800,
      'openvpn' => isDark ? Colors.purpleAccent : Colors.purple.shade700,
      'proxy' => isDark ? Colors.pinkAccent : Colors.pink.shade700,
      _ => isDark ? Colors.grey.shade300 : Colors.grey.shade700,
    };
  }

  Future<void> _copyAll(
      BuildContext context, List<ConnectionLogEntry> entries) async {
    final buffer = StringBuffer();
    for (final e in entries) {
      buffer.writeln(
          '${e.timeStamp} [${e.protocol}] [${e.level.name}] ${e.message}');
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: LocalizedText('Copied ${entries.length} log lines to clipboard')),
      );
    }
  }
}
