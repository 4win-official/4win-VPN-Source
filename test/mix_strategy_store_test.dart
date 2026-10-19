import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vpn_swift/models/mix_strategy.dart';
import 'package:vpn_swift/services/mix_strategy_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = MixStrategyStore();
  final strategy = MixStrategy(
    id: 'one',
    name: 'My chain',
    hops: [const MixHop(protocol: 'xray', serverId: 'profile')],
  );
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'selected_xray_server': 'standalone-xray',
      'selected_protocol': 'warp',
      'xray_selected_group': 'standalone-group',
      'connection_mode': 'proxy',
    }),
  );
  test(
    'Mix protocol selections round-trip without standalone changes',
    () async {
      final mixed = MixStrategy(
        id: 'targets',
        name: 'Targets',
        hops: const [
          MixHop(
            protocol: 'sstp',
            group: 'custom',
            serverId: 'vpn.example:443',
          ),
          MixHop(protocol: 'sstp', group: 'default'),
          MixHop(protocol: 'xray', group: 'subscription'),
          MixHop(protocol: 'xray', serverId: 'xray-manual'),
        ],
      );
      await store.save([mixed]);
      expect((await store.load()).single.toJson(), mixed.toJson());
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('selected_xray_server'), 'standalone-xray');
      expect(prefs.getString('xray_selected_group'), 'standalone-group');
      expect(prefs.getString('selected_protocol'), 'warp');
    },
  );
  test('fresh storage has no strategies and no selected id', () async {
    expect(await store.load(), isEmpty);
    expect(await store.selectedId(), isNull);
  });
  test('save, load and select round-trip', () async {
    await store.save([strategy]);
    await store.select(strategy.id);
    expect((await store.load()).single.toJson(), strategy.toJson());
    expect(await store.selectedId(), strategy.id);
    await store.save([]);
    await store.select(null);
    expect(await store.load(), isEmpty);
    expect(await store.selectedId(), isNull);
  });
  test('malformed entries do not destroy valid strategies', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(MixStrategyStore.strategiesKey, [
      'broken',
      '{}',
      jsonEncode(strategy.toJson()),
      jsonEncode(strategy.toJson()),
    ]);
    expect((await store.load()).map((value) => value.id), ['one']);
  });
  test('all Mix mutations leave standalone preferences unchanged', () async {
    final prefs = await SharedPreferences.getInstance();
    final before = {for (final key in prefs.getKeys()) key: prefs.get(key)};
    await store.save([strategy]);
    await store.select(strategy.id);
    await store.save([]);
    await store.select(null);
    for (final entry in before.entries) {
      expect(
        prefs.get(entry.key),
        entry.value,
        reason: '${entry.key} must not change',
      );
    }
  });
}
