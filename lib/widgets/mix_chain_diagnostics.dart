import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/mix_diagnostics.dart';
import '../models/mix_strategy.dart';
import '../providers/vpn_provider.dart';

/// Only a failure action is shown on the home screen. The actual configured
/// graph is opened on demand, not replaced by a textual diagnostic report.
class MixChainDiagnostics extends StatelessWidget {
  const MixChainDiagnostics({super.key, required this.diagnostics});
  final MixDiagnostics diagnostics;

  static bool hasFailure(MixDiagnostics data) =>
      data.phase == 'Chain failed' ||
      data.phase == 'Chain stopped' ||
      data.states.contains(MixBlockState.failed);

  void _showGraph(BuildContext context) {
    final provider = context.read<VpnProvider>();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ChangeNotifierProvider<VpnProvider>.value(
        value: provider,
        child: Consumer<VpnProvider>(
          builder: (context, provider, _) {
            final current = provider.mixDiagnostics;
            final data = current?.attemptId == diagnostics.attemptId
                ? current!
                : diagnostics;
            return SizedBox(
              height: MediaQuery.sizeOf(context).height * .85,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            data.strategyName,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close chain graph',
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Initialized does not prove remote reachability.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  const Divider(),
                  Expanded(child: MixChainGraph(diagnostics: data)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => hasFailure(diagnostics)
      ? OutlinedButton.icon(
          key: const ValueKey('mix-failure-graph-button'),
          onPressed: () => _showGraph(context),
          icon: const Icon(Icons.account_tree, color: Colors.red),
          label: const Text('View failed chain'),
        )
      : const SizedBox.shrink();
}

/// A vertical connected block diagram, in device-to-exit order. The list is
/// merely its scrolling viewport: every item is a bordered graph node joined
/// to the next by a line and an arrow, not a status-report row.
class MixChainGraph extends StatelessWidget {
  const MixChainGraph({super.key, required this.diagnostics});
  final MixDiagnostics diagnostics;

  static String label(MixBlockState state) => switch (state) {
    MixBlockState.pending => 'Not reached',
    MixBlockState.starting => 'Starting',
    MixBlockState.ready => 'Initialized',
    MixBlockState.failed => 'Failed here',
    MixBlockState.unverified => 'Unknown',
  };

  static (IconData, Color) appearance(MixBlockState state) => switch (state) {
    MixBlockState.pending => (Icons.radio_button_unchecked, Colors.grey),
    MixBlockState.starting => (Icons.pending, Colors.blue),
    MixBlockState.ready => (Icons.check_circle, Colors.green),
    MixBlockState.failed => (Icons.cancel, Colors.red),
    MixBlockState.unverified => (Icons.help_outline, Colors.orange),
  };

  Widget _connector(Color color) => Column(
    children: [
      Container(height: 12, width: 3, color: color),
      Icon(Icons.arrow_downward, color: color, size: 20),
    ],
  );

  Widget _node(BuildContext context, int index) {
    final hop = diagnostics.hops[index];
    final state = diagnostics.states[index];
    final (icon, color) = appearance(state);
    final title =
        '${index + 1}. ${MixStrategy.protocols[hop.protocol] ?? hop.protocol}';
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Semantics(
          label: '$title: ${label(state)}',
          child: Container(
            key: ValueKey('mix-graph-block-$index'),
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .10),
              border: Border.all(
                color: color,
                width: state == MixBlockState.failed ? 3 : 2,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label(state),
                    style: TextStyle(color: color, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final attributed = diagnostics.states.contains(MixBlockState.failed);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      itemCount: diagnostics.hops.length + 2,
      itemBuilder: (context, item) {
        if (item == 0) {
          return Column(
            children: [
              const Icon(Icons.phone_android, size: 32),
              const Text('Start'),
              _connector(Colors.grey),
            ],
          );
        }
        if (item == diagnostics.hops.length + 1) {
          return Column(
            children: [
              Icon(
                attributed ? Icons.block : Icons.help_outline,
                size: 34,
                color: attributed ? Colors.grey : Colors.orange,
              ),
              Text(
                attributed ? 'Chain stopped' : 'Failure location unknown',
                textAlign: TextAlign.center,
              ),
            ],
          );
        }
        final index = item - 1;
        final (_, color) = appearance(diagnostics.states[index]);
        return Column(children: [_node(context, index), _connector(color)]);
      },
    );
  }
}
