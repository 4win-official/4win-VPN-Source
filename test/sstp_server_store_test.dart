import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vpn_swift/models/vpn_server.dart';
import 'package:vpn_swift/services/server_service.dart';
import 'package:vpn_swift/services/sstp_server_store.dart';

class _FakeServerService extends ServerService {
  int calls = 0;
  final List<VpnServer> servers;

  _FakeServerService(this.servers);

  @override
  Future<List<VpnServer>> fetchServers({bool forceRefresh = false}) async {
    calls++;
    return servers;
  }
}

class _OfflineServerService extends ServerService {
  @override
  Future<List<VpnServer>> fetchServers({bool forceRefresh = false}) async {
    throw StateError('offline');
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'always exposes protected built-in group and cannot delete it',
    () async {
      final fake = _FakeServerService([
        VpnServer(address: 'free.example', port: 443),
      ]);
      final store = SstpServerStore(serverService: fake);

      final groups = await store.loadGroups();
      expect(groups.single.id, 'default');
      expect(groups.single.name, '4win Free Servers');
      expect(groups.single.isDefault, isTrue);
      expect(() => store.deleteGroup('default'), throwsStateError);
    },
  );

  test(
    'parses valid manual lines, credentials, and persists custom group',
    () async {
      final fake = _FakeServerService([
        VpnServer(address: 'free.example', port: 443),
      ]);
      final store = SstpServerStore(serverService: fake);
      final groups = await store.addGroup(
        'Office',
        'one.example:443\ninvalid\ntwo.example:65536\ntwo.example:8443',
        username: 'alice',
        password: 'secret',
      );

      expect(groups, hasLength(2));
      expect(groups[1].servers, hasLength(2));
      expect(groups[1].servers[0].username, 'alice');
      expect(groups[1].servers[1].port, 8443);

      final reloaded = await SstpServerStore(serverService: fake).loadGroups();
      expect(reloaded.map((group) => group.name), contains('Office'));
    },
  );

  test(
    'refreshes only a custom subscription and preserves old cache on failure',
    () async {
      final fake = _FakeServerService([
        VpnServer(address: 'free.example', port: 443),
      ]);
      var shouldFail = false;
      final client = MockClient((request) async {
        if (shouldFail) return http.Response('no', 500);
        return http.Response('new.example:9443\n', 200);
      });
      final store = SstpServerStore(serverService: fake, client: client);
      final added = await store.addGroup(
        'Remote',
        'https://example.com/servers',
      );
      final id = added[1].id;
      expect(added[1].subscriptionUrl, 'https://example.com/servers');
      expect(added[1].servers.single.port, 9443);

      shouldFail = true;
      expect(() => store.refreshGroup(id), throwsStateError);
      final cached = await store.loadGroups();
      expect(cached[1].servers.single.port, 9443);
    },
  );

  test(
    'default refresh keeps custom groups and subscription credentials',
    () async {
      final fake = _FakeServerService([
        VpnServer(address: 'free.example', port: 443),
      ]);
      final client = MockClient((request) async {
        return http.Response('new.example:9443\n', 200);
      });
      final store = SstpServerStore(serverService: fake, client: client);
      final added = await store.addGroup(
        'Remote',
        'https://example.com/servers',
        username: 'alice',
        password: 'secret',
      );

      final refreshed = await store.refreshGroup('default');
      expect(refreshed.map((group) => group.name), contains('Remote'));
      final remote = await store.refreshGroup(added[1].id);
      expect(remote[1].servers.single.username, 'alice');
      expect(remote[1].servers.single.password, 'secret');
    },
  );

  test('custom groups remain available when default feed is offline', () async {
    final store = SstpServerStore(serverService: _OfflineServerService());
    final added = await store.addGroup('Offline', '[::1]:443');
    expect(added.map((group) => group.name), contains('Offline'));
    expect(added.first.id, 'default');
    expect(added.first.servers, isEmpty);

    final loaded = await store.loadGroups();
    expect(loaded.map((group) => group.name), contains('Offline'));
    final deleted = await store.deleteGroup(added[1].id);
    expect(deleted.map((group) => group.name), isNot(contains('Offline')));
  });

  test('rejects URL-like and malformed manual server entries', () async {
    final store = SstpServerStore(serverService: _FakeServerService([]));
    expect(
      () => store.addGroup('Bad', 'ftp://host.example:443'),
      throwsFormatException,
    );
    expect(
      () => store.addGroup('Bad IPv6', '2001:db8::1:443'),
      throwsFormatException,
    );
  });
}
