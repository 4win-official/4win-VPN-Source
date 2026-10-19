import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/dns_scanner_service.dart';
import '../services/operator_ipv4_catalog.dart';

class DnsScannerScreen extends StatefulWidget {
  final String? probeDomain;
  final int initialPort;
  final ValueChanged<int>? onPortSelected;
  const DnsScannerScreen({
    super.key,
    this.probeDomain,
    this.initialPort = 53,
    this.onPortSelected,
  });
  @override
  State<DnsScannerScreen> createState() => _DnsScannerScreenState();
}

class _DnsScannerScreenState extends State<DnsScannerScreen> {
  final _cidrs = TextEditingController();
  final _fromIp = TextEditingController();
  final _toIp = TextEditingController();
  final _randomCount = TextEditingController(text: '100');
  final _domain = TextEditingController();
  final _port = TextEditingController();
  final _timeout = TextEditingController(text: '2500');
  final _parallel = TextEditingController(text: '64');
  final _scanner = DnsScannerService();
  // 0 = user-provided operator IPv4 ranges, 1 = generated public IPv4.
  int _mode = 0;
  String _operatorId = 'custom';
  int _operatorBatch = 0;
  String? _scanScope;
  bool _scanning = false, _cancel = false, _shuffle = false, _nearby = false;
  int _resultPort = 53, _tested = 0, _total = 0;
  int _resultTimeout = 2500, _resultWorkers = 64;
  String _resultTarget = 'google.com';
  bool _exporting = false;
  double _progress = 0;
  String? _sourceLabel, _error;
  List<DnsScanResult> _results = [];

  @override
  void initState() {
    super.initState();
    _domain.text = widget.probeDomain?.trim().isNotEmpty == true
        ? widget.probeDomain!.trim()
        : 'google.com';
    _port.text = '${widget.initialPort}';
  }

  @override
  void dispose() {
    _cancel = true;
    for (final c in [
      _cidrs,
      _fromIp,
      _toIp,
      _randomCount,
      _domain,
      _port,
      _timeout,
      _parallel,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  void _stop() {
    if (mounted) {
      setState(() {
        _cancel = true;
        _error =
            'Stopping after the current batch; no further batches will start.';
      });
    }
  }

  Future<void> _importRanges() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        withData: true,
        type: FileType.custom,
        allowedExtensions: ['txt', 'csv', 'cidr'],
      );
      if (!mounted || picked == null || picked.files.single.bytes == null) {
        return;
      }
      final bytes = picked.files.single.bytes!;
      if (bytes.length > 2 * 1024 * 1024) {
        _message('Range file is too large (maximum 2 MB).');
        return;
      }
      setState(() {
        _cidrs.text = utf8.decode(bytes, allowMalformed: false);
        _sourceLabel = picked.files.single.name;
        _mode = 0;
        _operatorId = 'custom';
      });
    } catch (_) {
      _message('Could not read the range file.');
    }
  }

  List<String> _targets() {
    if (_mode == 1) {
      final count = int.tryParse(_randomCount.text.trim());
      if (count == null || count < 1 || count > DnsScannerService.maxTargets) {
        throw const FormatException(
          'Enter a random IPv4 count from 1 to 200000.',
        );
      }
      return DnsScannerService.generateRandom(count);
    }
    if (_operatorId != 'custom') {
      return OperatorIpv4Catalog.operators
          .firstWhere((operator) => operator.id == _operatorId)
          .targetsForBatch(_operatorBatch);
    }
    final targets = <String>[];
    final from = _fromIp.text.trim(), to = _toIp.text.trim();
    if (from.isNotEmpty || to.isNotEmpty) {
      if (DnsScannerService.parseIp(from) == null ||
          DnsScannerService.parseIp(to) == null) {
        throw const FormatException(
          'Enter valid operator From IPv4 and To IPv4 addresses. IPv6 is not supported.',
        );
      }
      targets.addAll(DnsScannerService.generateRange(from, to));
    }
    if (_cidrs.text.trim().isNotEmpty) {
      try {
        targets.addAll(
          DnsScannerService.expandTargets(
            _cidrs.text.split(RegExp(r'[\s,;\n]+')).where((e) => e.isNotEmpty),
          ),
        );
      } on FormatException catch (e) {
        throw FormatException(
          '${e.message} IPv4 ranges only; IPv6 is not supported.',
        );
      }
    }
    final unique = DnsScannerService.expandTargets(targets);
    if (unique.isEmpty) {
      throw const FormatException(
        'Provide From/To IPv4 addresses or paste at least one IPv4 address/CIDR.',
      );
    }
    return unique;
  }

  int _int(TextEditingController c, String label, int min, int max) {
    final value = int.tryParse(c.text.trim());
    if (value == null || value < min || value > max) {
      throw FormatException('$label must be between $min and $max.');
    }
    return value;
  }

  Future<void> _start() async {
    if (_scanning) return;
    try {
      final target = DnsScannerService.validateTestTarget(_domain.text);
      var targets = _targets();
      final scope = _mode == 1
          ? 'Random public IPv4 sample: ${targets.length} targets; not an exhaustive Internet scan.'
          : _operatorId == 'custom'
          ? 'Custom ranges: ${targets.length} queued targets. Inputs are limited to the first 200000 unique IPv4 addresses; larger inputs are not fully scanned.'
          : _operatorScope();
      final port = _int(_port, 'Port', 1, 65535),
          timeout = _int(_timeout, 'Timeout', 100, 10000),
          workers = _int(
            _parallel,
            'Workers',
            1,
            DnsScannerService.maxParallel,
          );
      if (_shuffle) targets = [...targets]..shuffle(Random());
      setState(() {
        _scanning = true;
        _cancel = false;
        _error = null;
        _scanScope = scope;
        _results = [];
        _tested = 0;
        _total = targets.length;
        _resultPort = port;
        _resultTarget = target;
        _resultTimeout = timeout;
        _resultWorkers = workers;
        _progress = 0;
      });
      final found = await _scanner.scanRange(
        targets: targets,
        domain: target,
        parallel: workers,
        chunkSize: workers,
        port: port,
        timeoutMs: timeout,
        expandNearby: _nearby && _mode == 0 && _operatorId == 'custom',
        isCancelled: () => _cancel || !mounted,
        onProgress: (done, total) {
          if (!mounted || _cancel) return;
          setState(() {
            _tested = done;
            _total = total;
            _progress = total == 0 ? 0 : (done / total).clamp(0, 1);
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
      if (mounted && !_cancel) {
        setState(() {
          _results = found;
          _progress = _total == 0 ? 1 : _progress;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('FormatException: ', ''),
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

  String _latency(int value) => value < 0 ? '—' : '$value ms';

  Future<void> _copyCandidates() async {
    try {
      final text = DnsScanExport.toText(_results, port: _resultPort);
      await Clipboard.setData(ClipboardData(text: text));
      _message('Copied candidate resolver endpoints.');
    } catch (_) {
      _message('Could not copy candidate resolvers.');
    }
  }

  Future<void> _exportCandidates(String extension) async {
    if (_exporting) return;
    final content = extension == 'json'
        ? DnsScanExport.toJson(
            _results,
            testTarget: _resultTarget,
            port: _resultPort,
            timeoutMs: _resultTimeout,
            workers: _resultWorkers,
            cancelled: _cancel,
          )
        : DnsScanExport.toText(_results, port: _resultPort);
    setState(() => _exporting = true);
    try {
      final bytes = Uint8List.fromList(utf8.encode(content));
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Export candidate resolvers',
        fileName: 'candidate-resolvers.$extension',
        type: FileType.custom,
        allowedExtensions: [extension],
        bytes: bytes,
      );
      if (path == null) return;
      // Mobile/web save the bytes; desktop pickers only return a destination.
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.linux ||
              defaultTargetPlatform == TargetPlatform.macOS ||
              defaultTargetPlatform == TargetPlatform.windows)) {
        await File(path).writeAsBytes(bytes, flush: true);
      }
      _message('Exported candidate resolvers as ${extension.toUpperCase()}.');
    } catch (_) {
      _message('Could not export candidate resolvers. Please try again.');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Widget _resultActions() {
    final count = DnsScanExport.candidates(_results).length;
    final enabled = count > 0 && !_scanning && !_exporting;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Candidate resolvers ($count)',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const Text(
          'Candidates are not verified tunnels or proof that a website opens. '
          'Copy and exports include only candidates, one IPv4:port per TXT line.',
        ),
        if (_total > 0)
          Text(
            'Test: $_resultTarget · ${DnsScannerService.parseIp(_resultTarget) == null ? 'A lookup' : 'reverse PTR lookup'}'
            ' · Port $_resultPort · Timeout $_resultTimeout ms per probe'
            ' · $_resultWorkers workers'
            '${_cancel ? ' · Cancelled (partial results)' : ''}',
          ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            OutlinedButton.icon(
              onPressed: enabled ? _copyCandidates : null,
              icon: const Icon(Icons.copy_all),
              label: const Text('Copy all candidates'),
            ),
            OutlinedButton.icon(
              onPressed: enabled ? () => _exportCandidates('txt') : null,
              icon: const Icon(Icons.download),
              label: const Text('Export TXT'),
            ),
            OutlinedButton.icon(
              onPressed: enabled ? () => _exportCandidates('json') : null,
              icon: const Icon(Icons.data_object),
              label: const Text('Export JSON'),
            ),
          ],
        ),
      ],
    );
  }

  String _operatorScope() {
    final operator = OperatorIpv4Catalog.operators.firstWhere(
      (operator) => operator.id == _operatorId,
    );
    return '${operator.label} · ${operator.asn}\n'
        'RIPE NCC snapshot: ${operator.updatedAt}\n'
        '${operator.totalAddresses} announced IPv4 addresses. '
        'Batch ${_operatorBatch + 1} of ${operator.batchCount}: '
        '${operator.batchSize(_operatorBatch)} targets only. '
        'Choose another batch to continue; batches do not run automatically. '
        'Restarting a batch repeats it. No saved continuation.\n'
        'Routing data is not a list of working DNS servers and may change.\n'
        'Source: ${operator.sourceUrl}';
  }

  Widget _operatorChoice() => DropdownButtonFormField<String>(
    key: ValueKey('operator-$_operatorId'),
    initialValue: _operatorId,
    isExpanded: true,
    decoration: const InputDecoration(
      labelText: 'Operator / range source',
      border: OutlineInputBorder(),
    ),
    items: [
      const DropdownMenuItem(
        value: 'custom',
        child: Text('Custom IPv4 ranges'),
      ),
      ...OperatorIpv4Catalog.operators.map(
        (operator) =>
            DropdownMenuItem(value: operator.id, child: Text(operator.label)),
      ),
    ],
    onChanged: _scanning
        ? null
        : (value) {
            if (value == null) return;
            setState(() {
              _operatorId = value;
              _operatorBatch = 0;
            });
          },
  );

  Widget _modeChoice(int value, String title, String subtitle, IconData icon) =>
      RadioListTile<int>(
        value: value,
        title: Text(title),
        subtitle: Text(subtitle),
        secondary: Icon(icon),
        contentPadding: EdgeInsets.zero,
      );
  Widget _sourceFields() {
    if (_mode == 1) {
      return TextField(
        controller: _randomCount,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'Random public IPv4 count (max 200000)',
          border: OutlineInputBorder(),
          isDense: true,
        ),
      );
    }
    if (_operatorId != 'custom') {
      final operator = OperatorIpv4Catalog.operators.firstWhere(
        (operator) => operator.id == _operatorId,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _operatorChoice(),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            key: ValueKey('$_operatorId-$_operatorBatch'),
            initialValue: _operatorBatch,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'IPv4 batch (max 200000 targets)',
              border: OutlineInputBorder(),
            ),
            items: List.generate(
              operator.batchCount,
              (index) => DropdownMenuItem(
                value: index,
                child: Text(
                  'Batch ${index + 1} / ${operator.batchCount} · ${operator.batchSize(index)} IPs',
                ),
              ),
            ),
            onChanged: _scanning
                ? null
                : (value) {
                    if (value != null) {
                      setState(() => _operatorBatch = value);
                    }
                  },
          ),
          const SizedBox(height: 8),
          Text(_operatorScope()),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _operatorChoice(),
        const SizedBox(height: 8),
        const Text(
          'Enter your own IPv4 ranges, or choose a built-in operator above. '
          'Custom inputs use at most the first 200000 unique targets; '
          'shuffle changes their order, not the capped selection.',
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _fromIp,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'From IPv4',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _toIp,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'To IPv4',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _cidrs,
          minLines: 2,
          maxLines: 4,
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(
            labelText: 'Paste IPv4 addresses or CIDR ranges',
            hintText: '198.51.100.1\n203.0.113.0/24',
            helperText: _sourceLabel == null
                ? 'IPv4 only; separate entries with spaces, commas, or new lines.'
                : 'Imported: $_sourceLabel',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _scanning ? null : _importRanges,
          icon: const Icon(Icons.upload_file),
          label: const Text('Import IPv4 ranges'),
        ),
      ],
    );
  }

  Widget _fieldRow() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      SizedBox(
        width: 150,
        child: TextField(
          controller: _domain,
          enabled: !_scanning,
          decoration: const InputDecoration(
            labelText: 'Test domain or IPv4',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ),
      SizedBox(
        width: 90,
        child: TextField(
          controller: _port,
          enabled: !_scanning,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Port',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ),
      SizedBox(
        width: 120,
        child: TextField(
          controller: _timeout,
          enabled: !_scanning,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Timeout ms',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ),
      SizedBox(
        width: 125,
        child: TextField(
          controller: _parallel,
          enabled: !_scanning,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Workers (1–64)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ),
    ],
  );
  Widget _resultsView() {
    if (_results.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('No reachable resolvers yet.')),
      );
    }
    return Column(
      children: _results.map((r) {
        final safe = r.isCandidate;
        return Card(
          child: InkWell(
            onTap: safe
                ? () {
                    widget.onPortSelected?.call(_resultPort);
                    Navigator.of(context).pop<String>(r.ip);
                  }
                : null,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        safe ? Icons.verified : Icons.dns,
                        color: safe ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${r.ip}${r.name == null ? '' : ' · ${r.name}'}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Text(_latency(r.bestMs)),
                      if (safe)
                        IconButton(
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: r.ip));
                            if (mounted) _message('Copied ${r.ip}');
                          },
                          icon: const Icon(Icons.copy),
                          tooltip: 'Copy resolver',
                        ),
                    ],
                  ),
                  Text(
                    safe
                        ? 'Candidate resolver · UDP port $_resultPort · Tap to use'
                        : 'Not selectable · DNS capability checks incomplete or unsafe',
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('DNS resolver discovery'),
      actions: [
        if (_scanning)
          IconButton(
            onPressed: _stop,
            icon: const Icon(Icons.stop),
            tooltip: 'Stop',
          ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text(
          'Choose one IPv4 discovery approach.',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        RadioGroup<int>(
          groupValue: _mode,
          onChanged: _scanning
              ? (_) {}
              : (v) {
                  if (v != null) setState(() => _mode = v);
                },
          child: Column(
            children: [
              _modeChoice(
                0,
                'Operator IPv4 ranges',
                'Choose MCI or Irancell, or enter/import your own IPv4 ranges.',
                Icons.business,
              ),
              _modeChoice(
                1,
                'Random public IPv4',
                'Generate and test random public IPv4 addresses when ranges are unavailable.',
                Icons.shuffle,
              ),
            ],
          ),
        ),
        const Divider(),
        AbsorbPointer(absorbing: _scanning, child: _sourceFields()),
        const SizedBox(height: 12),
        _fieldRow(),
        const SizedBox(height: 8),
        const Text(
          'Domains use an A lookup; IPv4 targets use a reverse PTR lookup. '
          'An IP without a PTR record will not qualify. No ping or website test is used. '
          'Timeout applies to each DNS probe, not the whole scan.',
        ),
        CheckboxListTile(
          value: _shuffle,
          onChanged: _scanning
              ? null
              : (v) => setState(() => _shuffle = v ?? false),
          title: const Text('Shuffle targets'),
          contentPadding: EdgeInsets.zero,
        ),
        CheckboxListTile(
          value: _nearby,
          onChanged: _scanning || _mode == 1 || _operatorId != 'custom'
              ? null
              : (v) => setState(() => _nearby = v ?? false),
          title: const Text('Include nearby IPv4 addresses'),
          subtitle: Text(
            _mode == 1 || _operatorId != 'custom'
                ? 'Available only for custom ranges; built-in batches stay within their announced ranges.'
                : 'Expand each safe resolver to its nearby /24 addresses.',
          ),
          contentPadding: EdgeInsets.zero,
        ),
        const Text(
          'IPv6 is not supported. Only IPv4 addresses and CIDR ranges are accepted.',
        ),
        const SizedBox(height: 8),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        FilledButton.icon(
          onPressed: _scanning ? null : _start,
          icon: const Icon(Icons.play_arrow),
          label: Text(_scanning ? 'Scanning…' : 'Start scan'),
        ),
        if (_scanning || _total > 0) ...[
          const SizedBox(height: 10),
          LinearProgressIndicator(value: _progress),
          const SizedBox(height: 4),
          Text('Tested $_tested / $_total'),
          if (_scanScope != null) Text(_scanScope!),
        ],
        const SizedBox(height: 8),
        _resultActions(),
        _resultsView(),
      ],
    ),
  );
}
