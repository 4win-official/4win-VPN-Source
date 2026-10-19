import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/dns_scanner_service.dart';

class DnsScannerScreen extends StatefulWidget {
  final String? probeDomain;
  const DnsScannerScreen({super.key, this.probeDomain});

  @override
  State<DnsScannerScreen> createState() => _DnsScannerScreenState();
}

class _DnsScannerScreenState extends State<DnsScannerScreen> {
  final _scanner = DnsScannerService();
  final _custom = TextEditingController();
  final _cidrs = TextEditingController();
  final _fromIp = TextEditingController();
  final _toIp = TextEditingController();
  final _randomCount = TextEditingController(text: '100');
  final _domain = TextEditingController();
  final _parallel = TextEditingController(text: '64');
  bool _scanning = false;
  bool _cancel = false;
  int _mode = 0;
  int _tested = 0;
  int _total = 0;
  double _progress = 0;
  String? _countryLabel;
  String? _error;
  List<DnsScanResult> _results = [];

  @override
  void initState() {
    super.initState();
    _domain.text = widget.probeDomain?.trim().isNotEmpty == true
        ? widget.probeDomain!.trim()
        : 'google.com';
  }

  @override
  void dispose() {
    _cancel = true;
    for (final c in [
      _custom,
      _cidrs,
      _fromIp,
      _toIp,
      _randomCount,
      _domain,
      _parallel,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  int get _parallelValue => (int.tryParse(_parallel.text.trim()) ?? 64).clamp(
    1,
    DnsScannerService.maxParallel,
  );

  void _stop() {
    if (!mounted) return;
    setState(() {
      _cancel = true;
      _error =
          'Stopping after the current native batch; no further batches will start.';
    });
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _importCidrs() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        withData: true,
        type: FileType.custom,
        allowedExtensions: ['txt', 'csv', 'cidr'],
      );
      if (!mounted || picked == null || picked.files.single.bytes == null)
        return;
      final bytes = picked.files.single.bytes!;
      if (bytes.length > 2 * 1024 * 1024) {
        _message('CIDR file is too large (maximum 2 MB).');
        return;
      }
      final text = utf8.decode(bytes, allowMalformed: false);
      if (!mounted) return;
      setState(() {
        _cidrs.text = text;
        _countryLabel = picked.files.single.name;
        _mode = 3;
      });
    } catch (e) {
      _message('Could not read the CIDR file: $e');
    }
  }

  List<String> _targets() {
    switch (_mode) {
      case 0:
        return DnsScannerService.expandTargets([
          ...DnsScannerService.defaultServers,
          _custom.text,
        ]);
      case 1:
        final from = _fromIp.text.trim();
        final to = _toIp.text.trim();
        if (DnsScannerService.parseIp(from) == null ||
            DnsScannerService.parseIp(to) == null) {
          throw const FormatException(
            'Enter valid From IP and To IP addresses.',
          );
        }
        final targets = DnsScannerService.generateRange(from, to);
        if (targets.isEmpty)
          throw const FormatException('The IP range is empty.');
        return targets;
      case 2:
        final count = int.tryParse(_randomCount.text.trim());
        if (count == null || count < 1) {
          throw const FormatException(
            'Enter a random IP count from 1 to 200000.',
          );
        }
        return DnsScannerService.generateRandom(count);
      case 3:
        final entries = _cidrs.text
            .split(RegExp(r'[\s,;\n]+'))
            .where((x) => x.isNotEmpty);
        final targets = DnsScannerService.expandTargets(entries);
        if (targets.isEmpty)
          throw const FormatException('Enter at least one CIDR or IP.');
        return targets;
      default:
        throw const FormatException('Unknown scan mode.');
    }
  }

  Future<void> _start() async {
    if (_scanning) return;
    try {
      final targets = _targets();
      if (targets.isEmpty)
        throw const FormatException('Enter at least one IP or CIDR.');
      setState(() {
        _scanning = true;
        _cancel = false;
        _error = null;
        _results = [];
        _tested = 0;
        _total = targets.length;
        _progress = 0;
      });
      final result = await _scanner.scanRange(
        targets: targets,
        domain: _domain.text.trim(),
        parallel: _parallelValue,
        chunkSize: _parallelValue,
        isCancelled: () => _cancel || !mounted,
        onProgress: (done, total) {
          if (!mounted || _cancel) return;
          setState(() {
            _tested = done;
            _total = total;
            _progress = total == 0 ? 0 : done / total;
          });
        },
        onFound: (batch) {
          if (!mounted || _cancel) return;
          setState(() {
            _results.addAll(batch);
            _results.sort(_sort);
          });
        },
      );
      if (!mounted || _cancel) return;
      setState(() {
        _results = result;
        _tested = targets.length;
        _progress = 1;
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e.toString().replaceFirst('FormatException: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  int _sort(DnsScanResult a, DnsScanResult b) {
    if (a.isCandidate != b.isCandidate) return a.isCandidate ? -1 : 1;
    return (a.bestMs < 0 ? 1 << 30 : a.bestMs).compareTo(
      b.bestMs < 0 ? 1 << 30 : b.bestMs,
    );
  }

  String _latency(int n) => n < 0 ? '—' : '$n ms';

  Widget _status(DnsScanResult r) => Wrap(
    spacing: 6,
    runSpacing: 3,
    children: [
      Text(r.ednsSupported ? 'EDNS ${r.ednsPayload}' : 'EDNS unsupported'),
      Text(
        '· ${r.nxdomainSafe
            ? 'NXDOMAIN safe'
            : r.nxdomainHijacked
            ? 'NXDOMAIN hijacked'
            : 'NXDOMAIN unknown'}',
      ),
      Text('· UDP ${_latency(r.udpMs)} / TCP ${_latency(r.tcpMs)}'),
      Text('· ${r.responseBytes} B'),
    ],
  );

  Future<void> _copy(DnsScanResult r) async {
    if (!r.isCandidate) return;
    await Clipboard.setData(ClipboardData(text: r.ip));
    if (mounted) _message('Copied ${r.ip}');
  }

  Widget _modeControls() {
    switch (_mode) {
      case 0:
        return TextField(
          controller: _custom,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Additional DNS IPs (optional)',
            hintText: 'IP addresses only; domains are rejected',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        );
      case 1:
        return Row(
          children: [
            Expanded(
              child: TextField(
                controller: _fromIp,
                decoration: const InputDecoration(
                  labelText: 'From IP',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _toIp,
                decoration: const InputDecoration(
                  labelText: 'To IP',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ],
        );
      case 2:
        return TextField(
          controller: _randomCount,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Random public IP count (max 200000)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        );
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _cidrs,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'User-provided country CIDRs or IPs',
                hintText: 'No built-in country database',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _scanning ? null : _importCidrs,
                  icon: const Icon(Icons.file_upload),
                  label: const Text('Import offline file'),
                ),
                if (_countryLabel != null)
                  Text(_countryLabel!, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final candidates = _results.where((r) => r.isCandidate).length;
    final height = MediaQuery.sizeOf(context).height;
    return Scaffold(
      appBar: AppBar(
        title: const Text('DNS Scanner'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
          if (_scanning)
            IconButton(
              onPressed: _stop,
              tooltip: 'Stop',
              icon: const Icon(Icons.stop),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: Text(
              'Candidates require reachable UDP, EDNS, and safe NXDOMAIN behavior. TCP-only or unsafe resolvers cannot be selected. This does not verify a tunnel; connection verification happens separately.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Card(
            margin: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: ExpansionTile(
              initiallyExpanded: true,
              title: const Text('Scan controls'),
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: height * .42),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Column(
                      children: [
                        DropdownButtonFormField<int>(
                          value: _mode,
                          isDense: true,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Scan mode',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 0,
                              child: Text('Public DNS list'),
                            ),
                            DropdownMenuItem(
                              value: 1,
                              child: Text('From IP / To IP range'),
                            ),
                            DropdownMenuItem(
                              value: 2,
                              child: Text('Random public IPs'),
                            ),
                            DropdownMenuItem(
                              value: 3,
                              child: Text('Imported country CIDRs'),
                            ),
                          ],
                          onChanged: _scanning
                              ? null
                              : (v) => setState(() => _mode = v ?? 0),
                        ),
                        const SizedBox(height: 8),
                        _modeControls(),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _domain,
                                decoration: const InputDecoration(
                                  labelText: 'Probe domain',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 104,
                              child: TextField(
                                controller: _parallel,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Parallel 1–64',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _scanning ? _stop : _start,
                            icon: Icon(_scanning ? Icons.stop : Icons.radar),
                            label: Text(
                              _scanning
                                  ? 'Stop (finish current batch)'
                                  : 'Start scan',
                            ),
                          ),
                        ),
                        const Text(
                          'Country ranges are user-provided; there is no built-in country database. Expansion is capped at 200,000 unique targets.',
                          style: TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_scanning) LinearProgressIndicator(value: _progress),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _error ??
                        (_scanning
                            ? 'Scanning $_tested / $_total…'
                            : '${_results.length} reachable · $candidates safe candidates'),
                  ),
                ),
                if (!_scanning)
                  IconButton(
                    onPressed: _start,
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Rescan',
                  ),
              ],
            ),
          ),
          Expanded(
            child: _results.isEmpty
                ? const Center(child: Text('No reachable resolvers yet.'))
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, i) {
                      final r = _results[i];
                      final safe = r.isCandidate;
                      return ListTile(
                        leading: Icon(
                          safe ? Icons.verified : Icons.dns,
                          color: safe ? Colors.green : Colors.grey,
                        ),
                        title: Text(
                          r.name == null ? r.ip : '${r.ip} · ${r.name}',
                        ),
                        subtitle: _status(r),
                        isThreeLine: true,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_latency(r.bestMs)),
                            if (safe)
                              IconButton(
                                onPressed: () => _copy(r),
                                icon: const Icon(Icons.copy),
                                tooltip: 'Copy resolver',
                              ),
                          ],
                        ),
                        onTap: safe
                            ? () => Navigator.of(context).pop<String>(r.ip)
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
