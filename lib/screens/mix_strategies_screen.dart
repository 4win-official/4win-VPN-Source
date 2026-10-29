import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../models/mix_strategy.dart';
import '../widgets/mix_chain_diagnostics.dart';
import '../providers/vpn_provider.dart';
import 'mix_strategy_editor_screen.dart';

/// Saved multi-hop Mix strategies.
class MixStrategiesScreen extends StatelessWidget {
  const MixStrategiesScreen({super.key});

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: LocalizedText(error.toString())));
      }
    }
  }

  Future<void> _openEditor(
    BuildContext context, [
    MixStrategy? strategy,
  ]) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MixStrategyEditorScreen(existingStrategy: strategy),
      ),
    );
  }

  Future<void> _delete(BuildContext context, MixStrategy strategy) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const LocalizedText('Delete strategy?'),
        content: LocalizedText('Delete “${strategy.name}”?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const LocalizedText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const LocalizedText('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await _run(
        context,
        () => context.read<VpnProvider>().deleteMixStrategy(strategy.id),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? Colors.black : const Color(0xfff6f7fb),
      appBar: AppBar(
        title: const LocalizedText('Mix Strategies'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: context.l10n.text('New strategy'),
            icon: const Icon(Icons.add),
            onPressed: () => _openEditor(context),
          ),
        ],
      ),
      body: Consumer<VpnProvider>(
        builder: (context, provider, _) {
          final strategies = provider.mixStrategies;
          if (strategies.isEmpty) {
            return _EmptyState(onCreate: () => _openEditor(context));
          }
          final diagnostics = provider.mixDiagnostics;
          final showDiagnostics =
              diagnostics != null &&
              diagnostics.strategyId == provider.selectedMixStrategyId;
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            itemCount: strategies.length + (showDiagnostics ? 1 : 0),
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              if (showDiagnostics && index == 0) {
                return MixChainDiagnostics(diagnostics: diagnostics);
              }
              final strategy = strategies[index - (showDiagnostics ? 1 : 0)];
              final selected = provider.selectedMixStrategyId == strategy.id;
              final error = strategy.validationError;
              return Card(
                elevation: selected ? 3 : 0,
                color: selected
                    ? Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: .14)
                    : (dark ? const Color(0xff171717) : Colors.white),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.transparent,
                  ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 7,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: selected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey.withValues(alpha: .18),
                    child: Icon(
                      selected ? Icons.check : Icons.route,
                      color: selected
                          ? Colors.white
                          : Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  title: Text(
                    strategy.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: LocalizedText(
                    error ??
                        '${strategy.hops.length} block${strategy.hops.length == 1 ? '' : 's'}  •  ${strategy.hops.map((h) => MixStrategy.protocols[h.protocol] ?? h.protocol).join(' → ')}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: error == null ? null : Colors.orange,
                    ),
                  ),
                  onTap: () => _run(
                    context,
                    () => provider.selectMixStrategy(strategy.id),
                  ),
                  trailing: PopupMenuButton<String>(
                    tooltip: context.l10n.text('Strategy actions'),
                    onSelected: (value) {
                      if (value == 'edit') _openEditor(context, strategy);
                      if (value == 'delete') _delete(context, strategy);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: LocalizedText('Edit')),
                      PopupMenuItem(value: 'delete', child: LocalizedText('Delete')),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});
  final VoidCallback onCreate;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.route,
            size: 64,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: .7),
          ),
          const SizedBox(height: 14),
          const LocalizedText(
            'No Mix strategies yet',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const LocalizedText(
            'Chain existing Xray, Proxy, and DNS profiles without changing your standalone connection.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add),
            label: const LocalizedText('Create strategy'),
          ),
        ],
      ),
    ),
  );
}
