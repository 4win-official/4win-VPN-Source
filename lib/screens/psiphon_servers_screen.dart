import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/psiphon_server.dart';
import '../providers/vpn_provider.dart';
import '../services/psiphon_service.dart';

class PsiphonServersScreen extends StatefulWidget {
  final PsiphonService? service;
  final VpnProvider? provider;

  const PsiphonServersScreen({super.key, this.service, this.provider});

  @override
  State<PsiphonServersScreen> createState() => _PsiphonServersScreenState();
}

class _PsiphonServersScreenState extends State<PsiphonServersScreen> {
  late final PsiphonService _service;
  PsiphonServerList? _list;
  final _searchController = TextEditingController();
  final Map<String, int?> _latencies = {};
  final Set<String> _testing = {};
  final Map<String, int> _probeRuns = {};
  int _nextProbeRun = 0;
  bool _loading = true;
  bool _refreshing = false;
  bool _batchTesting = false;
  bool _connecting = false;
  bool _initialLoadStarted = false;
  String? _refreshMessage;
  bool _sortByLatency = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? PsiphonService();
    _searchController.addListener(() => mounted ? setState(() {}) : null);
    _load();
  }

  @override
  void dispose() {
    _generation++;
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading && _list == null && _initialLoadStarted) {
      // The initial load is already in flight.
      return;
    }
    _initialLoadStarted = true;
    final generation = ++_generation;
    _batchTesting = false;
    _testing.clear();
    if (mounted) {
      setState(() => _loading = true);
    }
    try {
      final list = await _service.getServerList();
      if (!mounted || generation != _generation) return;
      setState(() {
        if (list.error != null && _list != null && _list!.servers.isNotEmpty) {
          _list = PsiphonServerList(
            servers: _list!.servers,
            source: _list!.source,
            updatedAt: _list!.updatedAt,
            error: list.error,
          );
        } else {
          _list = list;
        }
        _loading = false;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _refreshMessage = 'Unable to read the Psiphon server list: $error';
        });
      }
    } finally {
      if (mounted && generation == _generation && _loading) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    final generation = ++_generation;
    _batchTesting = false;
    _testing.clear();
    setState(() {
      _refreshing = true;
      _refreshMessage = null;
    });
    try {
      final result = await _service.refreshServerListNow();
      if (!mounted || generation != _generation) return;
      if (result.busy) {
        setState(
          () =>
              _refreshMessage = 'A signed-list refresh is already in progress.',
        );
      } else if (result.updated) {
        final list = await _service.getServerList();
        if (!mounted || generation != _generation) return;
        setState(() {
          if (list.error != null &&
              _list != null &&
              _list!.servers.isNotEmpty) {
            _list = PsiphonServerList(
              servers: _list!.servers,
              source: _list!.source,
              updatedAt: _list!.updatedAt,
              error: list.error,
            );
          } else {
            _list = list;
          }
        });
      } else {
        // A false/null-error result is still a failed refresh, not success.
        setState(
          () => _refreshMessage =
              result.error ?? 'The signed server list was not updated.',
        );
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(
          () => _refreshMessage = 'Unable to refresh the server list: $error',
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _refreshing = false);
      }
    }
  }

  List<PsiphonServer> get _visibleServers {
    final query = _searchController.text.trim().toLowerCase();
    final values = (_list?.servers ?? const <PsiphonServer>[]).where((s) {
      return query.isEmpty ||
          s.ipAddress.toLowerCase().contains(query) ||
          s.region.toLowerCase().contains(query);
    }).toList();
    if (_sortByLatency) {
      values.sort(
        (a, b) => (_latencies[a.id] ?? 1 << 30).compareTo(
          _latencies[b.id] ?? 1 << 30,
        ),
      );
    }
    return values;
  }

  Future<void> _test(PsiphonServer server) async {
    if (server.port == null || _testing.contains(server.id) || _batchTesting) {
      return;
    }
    final generation = _generation;
    final run = ++_nextProbeRun;
    _probeRuns[server.id] = run;
    setState(() => _testing.add(server.id));
    try {
      final latency = await _service.testServerLatency(server);
      if (mounted && generation == _generation) {
        setState(() => _latencies[server.id] = latency);
      }
    } finally {
      if (mounted && _probeRuns[server.id] == run) {
        _probeRuns.remove(server.id);
        setState(() => _testing.remove(server.id));
      }
    }
  }

  Future<void> _testAll() async {
    if (_batchTesting || _connecting || _testing.isNotEmpty) return;
    _batchTesting = true;
    final servers = _visibleServers;
    final generation = _generation;
    try {
      for (var i = 0; i < servers.length; i += 4) {
        if (!mounted || generation != _generation) return;
        final batch = servers
            .skip(i)
            .take(4)
            .where((s) => s.port != null)
            .toList();
        await Future.wait(
          batch.map((s) async {
            final run = ++_nextProbeRun;
            _probeRuns[s.id] = run;
            if (mounted) setState(() => _testing.add(s.id));
            try {
              final latency = await _service.testServerLatency(s);
              if (mounted && generation == _generation) {
                setState(() => _latencies[s.id] = latency);
              }
            } finally {
              if (mounted && _probeRuns[s.id] == run) {
                _probeRuns.remove(s.id);
                setState(() => _testing.remove(s.id));
              }
            }
          }),
        );
      }
    } finally {
      _batchTesting = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _connect(PsiphonServer? server) async {
    if (_connecting) return;
    setState(() => _connecting = true);
    final provider = widget.provider ?? context.read<VpnProvider>();
    try {
      await provider.disconnect();
      if (!mounted) return;
      await provider.switchProtocol('psiphon');
      await provider.selectPsiphonServer(server?.id);
      await provider.connect();
      if (mounted && provider.isConnected) {
        Navigator.of(context).pop();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              provider.errorMessage ?? 'Unable to connect to Psiphon.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(provider.errorMessage ?? 'Unable to connect: $error'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  String _metadataLabel() {
    final d = _list?.updatedAt?.toLocal();
    if (d == null) {
      return _list?.source == 'bundled'
          ? 'Bundled list · No successful online update yet'
          : 'No successful online update yet';
    }
    String two(int n) => n.toString().padLeft(2, '0');
    return 'Last successful update: ${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)} (local)';
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    final inheritedProvider = Provider.of<VpnProvider?>(context, listen: false);
    final selectedId =
        (widget.provider ?? inheritedProvider)?.selectedPsiphonServerId;
    final selectedMissing =
        selectedId != null &&
        list != null &&
        !list.servers.any((server) => server.id == selectedId);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Psiphon servers'),
        actions: [
          IconButton(
            onPressed: _loading || _refreshing ? null : _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh signed list',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'TCP reachability, not VPN latency. A successful test does not guarantee a Psiphon connection.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(_metadataLabel(), style: const TextStyle(fontSize: 12)),
                  if (list?.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        list!.error!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  if (_refreshMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _refreshMessage!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText: 'Search IP or region',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _batchTesting || _testing.isNotEmpty
                              ? null
                              : _testAll,
                          icon: const Icon(Icons.network_check),
                          label: const Text('Test all (max 4 at a time)'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () =>
                            setState(() => _sortByLatency = !_sortByLatency),
                        tooltip: 'Sort by TCP latency',
                        icon: Icon(
                          _sortByLatency ? Icons.sort : Icons.sort_outlined,
                        ),
                      ),
                    ],
                  ),
                  if (_refreshing) const LinearProgressIndicator(),
                  if (selectedMissing)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'The selected server is no longer listed. Choose another server or Automatic.',
                        style: TextStyle(color: Colors.orange),
                      ),
                    ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.auto_awesome),
                    title: const Text('Automatic selection'),
                    subtitle: const Text('Let Psiphon choose a server'),
                    trailing: FilledButton(
                      onPressed: _connecting ? null : () => _connect(null),
                      child: const Text('Connect'),
                    ),
                  ),
                  if (_visibleServers.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        list?.error ?? 'No servers available.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ..._visibleServers.map(_serverTile),
                ],
              ),
            ),
    );
  }

  Widget _serverTile(PsiphonServer server) {
    final latency = _latencies[server.id];
    final testing = _testing.contains(server.id);
    return Card(
      child: ListTile(
        title: Text(server.ipAddress),
        subtitle: Text(
          '${server.region} · ${server.port == null ? 'No TCP port; not testable' : 'port ${server.port}'}${latency == null ? '' : ' · $latency ms TCP'}',
        ),
        trailing: Wrap(
          spacing: 2,
          children: [
            IconButton(
              onPressed: testing || server.port == null
                  ? null
                  : () => _test(server),
              tooltip: 'Test TCP latency',
              icon: testing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.network_check),
            ),
            FilledButton(
              onPressed: _connecting ? null : () => _connect(server),
              child: const Text('Connect'),
            ),
          ],
        ),
      ),
    );
  }
}
