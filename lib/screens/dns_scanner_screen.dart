import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/dns_scanner_service.dart';

/// Advanced DNS Scanner for the Slow DNS protocol.
///
/// Probes a large curated list of public DNS resolvers (plus any custom IPs the
/// user enters) concurrently using a real DNS query + TCP/53 probe, then ranks
/// them fastest-first. The user can copy an IP or return it to the Slow DNS
/// config form as the tunnel's Name Server.
class DnsScannerScreen extends StatefulWidget {
  /// Optional domain to resolve while probing (e.g. a tunnel domain).
  final String? probeDomain;

  const DnsScannerScreen({super.key, this.probeDomain});

  @override
  State<DnsScannerScreen> createState() => _DnsScannerScreenState();
}

class _DnsScannerScreenState extends State<DnsScannerScreen> {
  final _scanner = DnsScannerService();
  final _customController = TextEditingController();
  final _domainController = TextEditingController();

  bool _scanning = false;
  double _progress = 0;
  List<DnsScanResult> _results = [];
  int _testedCount = 0;
  int _totalCount = 0;

  static const Color _accent = Colors.orange;

  @override
  void initState() {
    super.initState();
    _domainController.text = widget.probeDomain?.trim().isNotEmpty == true
        ? widget.probeDomain!.trim()
        : 'google.com';
    // Auto-start a scan of the default list as soon as the screen opens.
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScan());
  }

  @override
  void dispose() {
    _customController.dispose();
    _domainController.dispose();
    super.dispose();
  }

  List<String> _parseCustom() {
    final text = _customController.text.trim();
    if (text.isEmpty) return [];
    return text
        .split(RegExp(r'[\s,;\n]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Future<void> _startScan() async {
    if (_scanning) return;

    final custom = _parseCustom();
    final targets = <String>[
      ...custom,
      ...DnsScannerService.defaultServers,
    ];
    // De-dupe while preserving order.
    final seen = <String>{};
    final unique = targets.where((e) => seen.add(e)).toList();

    setState(() {
      _scanning = true;
      _progress = 0;
      _results = [];
      _testedCount = 0;
      _totalCount = unique.length;
    });

    // Indeterminate-ish progress feedback (native runs concurrently and returns
    // all at once, so we animate the bar while awaiting).
    _animateProgress();

    final domain = _domainController.text.trim().isEmpty
        ? 'google.com'
        : _domainController.text.trim();

    final results =
        await _scanner.scan(servers: unique, domain: domain);

    if (!mounted) return;
    setState(() {
      _results = results;
      _testedCount = results.length;
      _scanning = false;
      _progress = 1;
    });
  }

  Future<void> _animateProgress() async {
    // Smoothly fill towards 90% while the native scan runs.
    while (_scanning && _progress < 0.9) {
      await Future.delayed(const Duration(milliseconds: 120));
      if (!mounted || !_scanning) return;
      setState(() => _progress = (_progress + 0.03).clamp(0, 0.9));
    }
  }

  Color _latencyColor(int ms) {
    if (ms < 0) return Colors.grey;
    if (ms < 80) return Colors.green;
    if (ms < 200) return Colors.lightGreen;
    if (ms < 400) return Colors.orange;
    return Colors.redAccent;
  }

  String _ms(int v) => v < 0 ? '—' : '$v ms';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reachable = _results.where((r) => r.reachable).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('DNS Scanner'),
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Rescan',
            onPressed: _scanning ? null : _startScan,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          // ---- Controls ----
          Container(
            color: _accent.withValues(alpha: 0.08),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _customController,
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Custom DNS IPs (optional)',
                    hintText: 'e.g. 1.1.1.1, 9.9.9.9 — space/comma separated',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.dns_outlined),
                    filled: true,
                    fillColor: isDark ? Colors.white10 : Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _domainController,
                        decoration: InputDecoration(
                          labelText: 'Probe domain',
                          isDense: true,
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.travel_explore),
                          filled: true,
                          fillColor: isDark ? Colors.white10 : Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _scanning ? null : _startScan,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: Colors.white,
                        ),
                        icon: _scanning
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.radar),
                        label: Text(_scanning ? 'Scanning' : 'Scan'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ---- Progress / summary ----
          if (_scanning)
            LinearProgressIndicator(
              value: _progress,
              color: _accent,
              backgroundColor: _accent.withValues(alpha: 0.15),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Icon(
                  _scanning ? Icons.radar : Icons.check_circle,
                  size: 18,
                  color: _accent,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _scanning
                        ? 'Scanning $_totalCount resolvers…'
                        : _results.isEmpty
                            ? 'No results yet'
                            : '$reachable of $_testedCount reachable · sorted fastest first',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // ---- Results ----
          Expanded(
            child: _results.isEmpty && !_scanning
                ? Center(
                    child: Text(
                      'Tap Scan to find the best DNS resolvers',
                      style: TextStyle(
                          color: isDark ? Colors.white54 : Colors.black45),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _results.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final r = _results[index];
                      return _buildResultTile(r, index, isDark);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultTile(DnsScanResult r, int index, bool isDark) {
    final best = r.bestMs;
    final rank = index + 1;
    final isTop = index == 0 && r.reachable;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isTop ? _accent : Colors.transparent,
          width: 2,
        ),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: r.reachable
              ? _latencyColor(best).withValues(alpha: 0.18)
              : Colors.grey.withValues(alpha: 0.15),
          child: r.reachable
              ? Text('$rank',
                  style: TextStyle(
                      color: _latencyColor(best),
                      fontWeight: FontWeight.bold))
              : const Icon(Icons.close, color: Colors.grey, size: 20),
        ),
        title: Row(
          children: [
            Text(
              r.ip,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 15),
            ),
            if (r.name != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  r.name!,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              _chip('UDP', r.udpMs, isDark),
              const SizedBox(width: 8),
              _chip('TCP', r.tcpMs, isDark),
            ],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Copy IP',
              icon: const Icon(Icons.copy, size: 20),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: r.ip));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Copied ${r.ip}')),
                );
              },
            ),
            IconButton(
              tooltip: 'Use as Name Server',
              icon: Icon(Icons.check_circle, color: _accent),
              onPressed:
                  r.reachable ? () => Navigator.pop(context, r.ip) : null,
            ),
          ],
        ),
        onTap: r.reachable ? () => Navigator.pop(context, r.ip) : null,
      ),
    );
  }

  Widget _chip(String label, int ms, bool isDark) {
    final c = _latencyColor(ms);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Text(
        '$label ${_ms(ms)}',
        style: TextStyle(
            fontSize: 11.5, color: c, fontWeight: FontWeight.w600),
      ),
    );
  }
}
