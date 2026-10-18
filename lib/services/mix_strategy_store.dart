import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/mix_strategy.dart';

class MixStrategyStore {
  static const strategiesKey = 'mix_strategies_v1';
  static const selectionKey = 'mix_selected_strategy_v1';

  Future<List<MixStrategy>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final result = <MixStrategy>[];
    for (final raw in prefs.getStringList(strategiesKey) ?? <String>[]) {
      try {
        final strategy = MixStrategy.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
        if (!result.any((item) => item.id == strategy.id)) result.add(strategy);
      } catch (_) {
        // A damaged entry must not hide other strategies or break standalone VPN.
      }
    }
    return result;
  }

  Future<void> save(List<MixStrategy> strategies) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setStringList(
      strategiesKey,
      strategies.map((strategy) => jsonEncode(strategy.toJson())).toList(),
    );
    if (!saved) throw StateError('Could not save Mix strategies.');
  }

  Future<String?> selectedId() async =>
      (await SharedPreferences.getInstance()).getString(selectionKey);

  Future<void> select(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = id == null
        ? await prefs.remove(selectionKey)
        : await prefs.setString(selectionKey, id);
    if (!saved) throw StateError('Could not save the selected Mix strategy.');
  }
}
