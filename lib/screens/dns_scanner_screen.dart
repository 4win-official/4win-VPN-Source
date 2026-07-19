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
  // Range-scan inputs
  final _fromIpController = TextEditingController(text: '1.0.0.0');
  final _toIpController = TextEditingController(text: '1.0.31.255');
  final _countController = TextEditingController(text: '10000');
  final _parallelController = TextEditingController(text: '150');
  // Range submode: false = IP range (from→to), true = random IPs
  bool _randomMode = false;

  bool _scanning = false;
  bool _cancel = false;
  double _progress = 0;
  List<DnsScanResult> _results = [];
  int _testedCount = 0;
  int _totalCount = 0;
  int _foundCount = 0;
  // 0 = curated list mode, 1 = IP-range mode
  int _mode = 0;

  static const Color _accent = Colors.orange;

  @override
  void initState() {
    super.initState();
    _domainController.text = widget.probeDomain?.trim().isNotEmpty == true
        ? widget.probeDomain!.trim()
        : 'google.com';
    // Auto-start a curated-list scan as soon as the screen opens.
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScan());
  }

  @override
  void dispose() {
    _cancel = true;
    _customController.dispose();
    _domainController.dispose();
    _fromIpController.dispose();
    _toIpController.dispose();
    _countController.dispose();
    _parallelController.dispose();
    super.dispose();
  }

  int get _parallel =>
      (int.tryParse(_parallelController.text.trim()) ?? 150).clamp(10, 1000);

  String get _domain => _domainController.text.trim().isEmpty
      ? 'google.com'
      : _domainController.text.trim();

  List<String> _parseCustom() {
    final text = _customController.text.trim();
    if (text.isEmpty) return [];
    return text
        .split(RegExp(r'[\s,;\n]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  void _stopScan() {
    setState(() => _cancel = true);
  }

  Future<void> _startScan() async {
    if (_scanning) return;
    if (_mode == 1) return _startRangeScan();

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
      _cancel = false;
      _progress = 0;
      _results = [];
      _testedCount = 0;
      _foundCount = 0;
      _totalCount = unique.length;
    });

    // Indeterminate-ish progress feedback (native runs concurrently and returns
    // all at once, so we animate the bar while awaiting).
    _animateProgress();

    final results =
        await _scanner.scan(servers: unique, domain: _domain, parallel: _parallel);

    if (!mounted) return;
    setState(() {
      _results = results
        ..sort((a, b) {
          if (a.reachable != b.reachable) return a.reachable ? -1 : 1;
          final am = a.bestMs < 0 ? 1 << 30 : a.bestMs;
          final bm = b.bestMs < 0 ? 1 << 30 : b.bestMs;
          return am.compareTo(bm);
        });
      _testedCount = results.length;
      _foundCount = results.where((r) => r.reachable).length;
      _scanning = false;
      _progress = 1;
    });
  }

  /// Bulk scan: build a target list from either an IP range (from→to) or a
  /// set of random public IPs, then probe them in chunks against the domain,
  /// showing live progress and streaming working resolvers as found. Great for
  /// discovering a slowdns-friendly resolver on a hostile network.
  Future<void> _startRangeScan() async {
    if (_scanning) return;

    List<String> targets;
    if (_randomMode) {
      final count = int.tryParse(_countController.text.trim()) ?? 0;
      if (count <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Enter how many random IPs to scan (e.g. 10000)')),
        );
        return;
      }
      targets = DnsScannerService.generateRandom(count.clamp(1, 200000));
    } else {
      final from = _fromIpController.text.trim();
      final to = _toIpController.text.trim();
      if (from.split('.').length != 4 || to.split('.').length != 4) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Enter a valid IP range (from → to)')),
        );
        return;
      }
      targets = DnsScannerService.generateRange(from, to);
      if (targets.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid or empty IP range')),
        );
        return;
      }
    }

    setState(() {
      _scanning = true;
      _cancel = false;
      _progress = 0;
      _results = [];
      _testedCount = 0;
      _foundCount = 0;
      _totalCount = targets.length;
    });

    final found = await _scanner.scanRange(
      targets: targets,
      domain: _domain,
      parallel: _parallel,
      chunkSize: 500,
      isCancelled: () => _cancel || !mounted,
      onProgress: (scanned, total) {
        if (!mounted) return;
        setState(() {
          _testedCount = scanned;
          _totalCount = total;
          _progress = total == 0 ? 0 : scanned / total;
        });
      },
      onFound: (batch) {
        if (!mounted) return;
        setState(() {
          _results.addAll(batch);
          _results.sort((a, b) {
            final am = a.bestMs < 0 ? 1 << 30 : a.bestMs;
            final bm = b.bestMs < 0 ? 1 << 30 : b.bestMs;
            return am.compareTo(bm);
          });
          _foundCount = _results.length;
        });
      },
    );

    if (!mounted) return;
    setState(() {
      _foundCount = found.length;
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
          if (_scanning)
            IconButton(
              tooltip: 'Stop',
              onPressed: _stopScan,
              icon: const Icon(Icons.stop),
            )
          else
            IconButton(
              tooltip: 'Rescan',
              onPressed: _startScan,
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
                // Mode switch: curated list vs IP range brute-force scan.
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(
                        value: 0,
                        label: Text('Public list'),
                        icon: Icon(Icons.dns_outlined)),
                    ButtonSegment(
                        value: 1,
                        label: Text('IP range'),
                        icon: Icon(Icons.travel_explore)),
                  ],
                  selected: {_mode},
                  onSelectionChanged: _scanning
                      ? null
                      : (s) => setState(() => _mode = s.first),
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(height: 10),
                if (_mode == 0)
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
                  )
                else ...[
                  // Range submode: IP range (from→to) vs random IPs.
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('IP range'),
                          selected: !_randomMode,
                          onSelected: _scanning
                              ? null
                              : (_) => setState(() => _randomMode = false),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('Random IPs'),
                          selected: _randomMode,
                          onSelected: _scanning
                              ? null
                              : (_) => setState(() => _randomMode = true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_randomMode)
                    TextField(
                      controller: _countController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'How many random IPs',
                        hintText: '10000',
                        isDense: true,
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.shuffle),
                        filled: true,
                        fillColor: isDark ? Colors.white10 : Colors.white,
                      ),
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _fromIpController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'From IP',
                              hintText: '1.0.0.0',
                              isDense: true,
                              border: const OutlineInputBorder(),
                              filled: true,
                              fillColor:
                                  isDark ? Colors.white10 : Colors.white,
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: Icon(Icons.arrow_forward, size: 18),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _toIpController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'To IP',
                              hintText: '1.0.31.255',
                              isDense: true,
                              border: const OutlineInputBorder(),
                              filled: true,
                              fillColor:
                                  isDark ? Colors.white10 : Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _domainController,
                        decoration: InputDecoration(
                          labelText: 'Probe domain',
                          isDense: true,
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.language),
                          filled: true,
                          fillColor: isDark ? Colors.white10 : Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _parallelController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Parallel',
                          hintText: '150',
                          isDense: true,
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.bolt),
                          filled: true,
                          fillColor: isDark ? Colors.white10 : Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton.icon(
                    onPressed: _scanning ? _stopScan : _startScan,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _scanning ? Colors.redAccent : _accent,
                      foregroundColor: Colors.white,
                    ),
                    icon: _scanning
                        ? const Icon(Icons.stop)
                        : const Icon(Icons.radar),
                    label: Text(_scanning
                        ? 'Stop scan'
                        : (_mode == 1 ? 'Start range scan' : 'Scan')),
                  ),
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
                        ? (_mode == 1
                            ? 'Scanning $_testedCount / $_totalCount · found $_foundCount working'
                            : 'Scanning $_totalCount resolvers…')
                        : _results.isEmpty
                            ? 'No results yet'
                            : (_mode == 1
                                ? '$_foundCount working of $_testedCount scanned · fastest first'
                                : '$reachable of $_testedCount reachable · sorted fastest first'),
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
