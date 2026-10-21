/// Public server metadata only. Psiphon authentication material stays native.
class PsiphonServer {
  final String id;
  final String? legacyId;
  final String ipAddress;
  final String region;
  final int? port;

  const PsiphonServer({
    required this.id,
    required this.ipAddress,
    this.legacyId,
    this.region = '',
    this.port,
  });

  bool matchesId(String selectedId) =>
      id == selectedId || legacyId == selectedId;

  factory PsiphonServer.fromMap(Map<Object?, Object?> map) {
    final rawPort = map['port'];
    final port = rawPort is num ? rawPort.toInt() : int.tryParse('$rawPort');
    return PsiphonServer(
      id: (map['id'] ?? '').toString(),
      legacyId: map['legacyId']?.toString(),
      ipAddress: (map['ipAddress'] ?? '').toString(),
      region: (map['region'] ?? '').toString(),
      port: port != null && port > 0 && port <= 65535 ? port : null,
    );
  }
}

class PsiphonServerList {
  final List<PsiphonServer> servers;
  final String source;
  final DateTime? updatedAt;
  final String? error;

  const PsiphonServerList({
    this.servers = const [],
    this.source = 'unavailable',
    this.updatedAt,
    this.error,
  });

  factory PsiphonServerList.fromMap(Map<Object?, Object?> map) {
    final rawServers = map['servers'];
    final rawDate = map['updatedAt'];
    final timestamp = rawDate is num
        ? rawDate.toInt()
        : int.tryParse('$rawDate');
    final source = (map['source'] ?? 'unavailable').toString();
    return PsiphonServerList(
      servers: rawServers is List
          ? rawServers
                .whereType<Map>()
                .map((entry) => PsiphonServer.fromMap(entry))
                .where(
                  (server) =>
                      server.id.isNotEmpty && server.ipAddress.isNotEmpty,
                )
                .toList(growable: false)
          : const [],
      source: source,
      updatedAt:
          source == 'cache' &&
              timestamp != null &&
              timestamp > 0 &&
              timestamp < 8640000000000000
          ? DateTime.fromMillisecondsSinceEpoch(
              timestamp,
              isUtc: true,
            ).toLocal()
          : null,
      error: map['error']?.toString(),
    );
  }
}

class PsiphonRefreshResult {
  final bool updated;
  final bool busy;
  final String? error;

  const PsiphonRefreshResult({
    this.updated = false,
    this.busy = false,
    this.error,
  });
}
