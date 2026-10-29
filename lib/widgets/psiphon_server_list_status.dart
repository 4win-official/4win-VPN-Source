import 'dart:async';

import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

import '../models/psiphon_server.dart';
import '../services/psiphon_service.dart';
import '../screens/psiphon_servers_screen.dart';

/// Compact Psiphon list status used from Home and Settings.
class PsiphonServerListStatus extends StatefulWidget {
  final bool isDark;
  final PsiphonService? service;

  const PsiphonServerListStatus({
    super.key,
    required this.isDark,
    this.service,
  });

  @override
  State<PsiphonServerListStatus> createState() =>
      _PsiphonServerListStatusState();
}

class _PsiphonServerListStatusState extends State<PsiphonServerListStatus> {
  late PsiphonService _service;
  PsiphonServerList? _list;
  PsiphonRefreshResult? _refreshResult;
  Timer? _metadataTimer;
  bool _refreshing = false;
  bool _metadataReadInFlight = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? PsiphonService();
    _readMetadata();
    _metadataTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _readMetadata(),
    );
  }

  @override
  void dispose() {
    _metadataTimer?.cancel();
    super.dispose();
  }

  Future<void> _readMetadata() async {
    if (_metadataReadInFlight) return;
    _metadataReadInFlight = true;
    try {
      final list = await _service.getServerList();
      if (mounted) {
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
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _refreshResult = PsiphonRefreshResult(
            error: 'Unable to read the Psiphon server list: $error',
          ),
        );
      }
    } finally {
      _metadataReadInFlight = false;
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _refreshResult = null;
    });
    try {
      final result = await _service.refreshServerListNow();
      if (!mounted) return;
      setState(() => _refreshResult = result);
      if (result.updated) {
        await _readMetadata();
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  String _metadataLabel() {
    final list = _list;
    if (list?.updatedAt != null) {
      final d = list!.updatedAt!.toLocal();
      String two(int n) => n.toString().padLeft(2, '0');
      return 'Last successful update: ${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)} (local)';
    }
    return list?.source == 'bundled'
        ? 'Bundled list · No successful online update yet'
        : 'No successful online update yet';
  }

  @override
  Widget build(BuildContext context) {
    final foreground = widget.isDark ? Colors.white : Colors.black87;
    final muted = widget.isDark ? Colors.white60 : Colors.black54;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: widget.isDark
            ? Colors.white.withValues(alpha: .05)
            : Colors.black.withValues(alpha: .03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueAccent.withValues(alpha: .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.dns_outlined,
                color: widget.isDark ? Colors.lightBlueAccent : Colors.blue,
                size: 21,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: LocalizedText(
                  'Psiphon server list',
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PsiphonServersScreen(service: _service),
                  ),
                ),
                child: const LocalizedText('Open'),
              ),
            ],
          ),
          Text(_metadataLabel(), style: TextStyle(color: muted, fontSize: 12)),
          if (_list?.error != null) ...[
            const SizedBox(height: 4),
            Text(
              _list!.error!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ],
          if (_refreshResult?.error != null) ...[
            const SizedBox(height: 4),
            Text(
              _refreshResult!.error!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ],
          if (_refreshResult != null &&
              !_refreshResult!.updated &&
              _refreshResult!.error == null) ...[
            const SizedBox(height: 4),
            LocalizedText(
              _refreshResult!.busy
                  ? 'A signed-list refresh is already in progress.'
                  : 'The signed server list was not updated.',
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              onPressed: _refreshing ? null : _refresh,
              icon: _refreshing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 18),
              label: const LocalizedText('Refresh signed list'),
            ),
          ),
        ],
      ),
    );
  }
}
