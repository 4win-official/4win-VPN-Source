import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../models/protocol_diagnostics.dart';
import '../providers/vpn_provider.dart';

class ProtocolChainDiagnostics extends StatelessWidget {
  const ProtocolChainDiagnostics({super.key, required this.diagnostics});

  final ProtocolDiagnostics diagnostics;

  bool get _failed =>
      diagnostics.outcome == ConnectionAttemptOutcome.failed ||
      diagnostics.steps.any((step) => step.state == ConnectionStepState.failed);

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
            final current = provider.protocolDiagnostics;
            final data = current?.attemptId == diagnostics.attemptId
                ? current!
                : diagnostics;
            return SizedBox(
              height: MediaQuery.sizeOf(context).height * .85,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: LocalizedText(
                            '${data.displayName} connection stages',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: context.l10n.text('Close connection graph'),
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: LocalizedText(
                      'Only observed signals are marked complete. A running service '
                      'does not always prove remote reachability.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  const Divider(),
                  Expanded(child: ProtocolConnectionGraph(diagnostics: data)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final failed = _failed;
    final label = switch (diagnostics.outcome) {
      ConnectionAttemptOutcome.connecting => 'View connection stages',
      ConnectionAttemptOutcome.connected => 'View connection stages',
      ConnectionAttemptOutcome.failed => 'View failed connection stages',
      ConnectionAttemptOutcome.cancelled => 'View cancelled connection attempt',
      ConnectionAttemptOutcome.disconnected => 'View last connection stages',
    };
    return OutlinedButton.icon(
      key: ValueKey('protocol-connection-graph-${diagnostics.protocol}'),
      onPressed: () => _showGraph(context),
      icon: Icon(Icons.account_tree, color: failed ? Colors.red : null),
      label: Text(label),
    );
  }
}

class ProtocolConnectionGraph extends StatelessWidget {
  const ProtocolConnectionGraph({super.key, required this.diagnostics});

  final ProtocolDiagnostics diagnostics;

  static String _label(ConnectionStepState state) => switch (state) {
    ConnectionStepState.pending => 'Not reached',
    ConnectionStepState.running => 'In progress',
    ConnectionStepState.complete => 'Complete',
    ConnectionStepState.failed => 'Failed here',
    ConnectionStepState.unverified => 'Unverified',
    ConnectionStepState.skipped => 'Not required',
  };

  static (IconData, Color) _appearance(ConnectionStepState state) => switch (state) {
    ConnectionStepState.pending => (Icons.radio_button_unchecked, Colors.grey),
    ConnectionStepState.running => (Icons.pending, Colors.blue),
    ConnectionStepState.complete => (Icons.verified, Colors.green),
    ConnectionStepState.failed => (Icons.cancel, Colors.red),
    ConnectionStepState.unverified => (Icons.help_outline, Colors.orange),
    ConnectionStepState.skipped => (Icons.remove_circle_outline, Colors.blueGrey),
  };

  Widget _connector(Color color) => Column(
    children: [
      Container(height: 12, width: 3, color: color),
      Icon(Icons.arrow_downward, color: color, size: 20),
    ],
  );

  Widget _node(BuildContext context, int index) {
    final step = diagnostics.steps[index];
    final (icon, color) = _appearance(step.state);
    final title = '${index + 1}. ${step.title}';
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Semantics(
          label: '$title: ${_label(step.state)}',
          child: Container(
            key: ValueKey('protocol-chain-step-$index'),
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .10),
              border: Border.all(
                color: color,
                width: step.state == ConnectionStepState.failed ? 3 : 2,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (step.detail?.isNotEmpty == true)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            step.detail!,
                            style: TextStyle(fontSize: 12, color: color),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _label(step.state),
                    textAlign: TextAlign.end,
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

  (IconData, Color, String) _terminal() {
    final failedIndex = diagnostics.steps.indexWhere(
      (step) => step.state == ConnectionStepState.failed,
    );
    if (failedIndex >= 0 ||
        diagnostics.outcome == ConnectionAttemptOutcome.failed) {
      return (
        Icons.error_outline,
        Colors.red,
        failedIndex >= 0
            ? 'Failure detected at step ${failedIndex + 1}'
            : 'Failure location unknown',
      );
    }
    return switch (diagnostics.outcome) {
      ConnectionAttemptOutcome.connecting => (
        Icons.pending,
        Colors.blue,
        'Connection attempt in progress',
      ),
      ConnectionAttemptOutcome.connected => (
        Icons.check_circle_outline,
        Colors.green,
        diagnostics.steps.any(
              (step) => step.state == ConnectionStepState.unverified,
            )
            ? 'Connected (some stages remain unverified)'
            : 'Connected',
      ),
      ConnectionAttemptOutcome.cancelled => (
        Icons.block,
        Colors.blueGrey,
        'Connection attempt cancelled',
      ),
      ConnectionAttemptOutcome.disconnected => (
        Icons.stop_circle_outlined,
        Colors.blueGrey,
        'Disconnected — showing last observed attempt',
      ),
      ConnectionAttemptOutcome.failed => (
        Icons.error_outline,
        Colors.red,
        'Failure location unknown',
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (terminalIcon, terminalColor, terminalText) = _terminal();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      itemCount: diagnostics.steps.length + 2,
      itemBuilder: (context, item) {
        if (item == 0) {
          return Column(
            children: [
              const Icon(Icons.phone_android, size: 32),
              const LocalizedText('Start'),
              _connector(Colors.grey),
            ],
          );
        }
        if (item == diagnostics.steps.length + 1) {
          return Column(
            children: [
              Icon(terminalIcon, size: 34, color: terminalColor),
              Text(terminalText, textAlign: TextAlign.center),
              if (diagnostics.message?.isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    diagnostics.message!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: terminalColor, fontSize: 12),
                  ),
                ),
            ],
          );
        }
        final index = item - 1;
        final (_, color) = _appearance(diagnostics.steps[index].state);
        return Column(children: [_node(context, index), _connector(color)]);
      },
    );
  }
}
