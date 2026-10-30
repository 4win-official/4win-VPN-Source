import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/app_mode_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/vpn_provider.dart';
import '../services/vpn_service.dart';
import '../widgets/app_language_setting.dart';
import 'split_tunnel_screen.dart';

/// Shows the mode chooser once, after the language gate has completed.
class AppModeGate extends StatefulWidget {
  const AppModeGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppModeGate> createState() => _AppModeGateState();
}

class _AppModeGateState extends State<AppModeGate> {
  late final Future<void> _loadFuture;

  @override
  void initState() {
    super.initState();
    _loadFuture = context.read<AppModeProvider>().load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _loadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final mode = context.watch<AppModeProvider>();
        if (!mode.hasSavedChoice) return const AppModeSelectionScreen();
        return widget.child;
      },
    );
  }
}

class AppModeSelectionScreen extends StatelessWidget {
  const AppModeSelectionScreen({super.key});

  Future<void> _choose(BuildContext context, AppExperienceMode mode) =>
      context.read<AppModeProvider>().setMode(mode);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.tune,
                    size: 48,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 20),
                  const LocalizedText(
                    'How would you like to use the app?',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 24),
                  _ModeChoice(
                    modeName: 'Simple',
                    description: 'Connect with one tap; the app chooses for you.',
                    icon: Icons.power_settings_new,
                    isDark: isDark,
                    onPressed: () => _choose(context, AppExperienceMode.simple),
                  ),
                  const SizedBox(height: 12),
                  _ModeChoice(
                    modeName: 'Advanced',
                    description: 'Choose protocols, servers, and detailed settings.',
                    icon: Icons.settings_suggest_outlined,
                    isDark: isDark,
                    onPressed: () =>
                        _choose(context, AppExperienceMode.advanced),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeChoice extends StatelessWidget {
  const _ModeChoice({
    required this.modeName,
    required this.description,
    required this.icon,
    required this.isDark,
    required this.onPressed,
  });

  final String modeName;
  final String description;
  final IconData icon;
  final bool isDark;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.all(18),
        alignment: Alignment.centerLeft,
        side: BorderSide(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.55),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LocalizedText(
                  modeName,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                LocalizedText(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The intentionally small Simple-mode home: one connection control and one
/// settings entry point. The mode switch lives inside Simple Settings.
class SimpleHomeScreen extends StatefulWidget {
  const SimpleHomeScreen({super.key});

  @override
  State<SimpleHomeScreen> createState() => _SimpleHomeScreenState();
}

class _SimpleHomeScreenState extends State<SimpleHomeScreen>
    with WidgetsBindingObserver {
  bool _appInForeground = true;
  bool _promptScheduled = false;
  bool _feedbackDialogOpen = false;
  int? _lastPromptedConnectionGeneration;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _appInForeground =
        lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _appInForeground = true;
      if (mounted) {
        final provider = context.read<VpnProvider>();
        unawaited(_refreshAndScheduleFeedbackPrompt(provider));
      }
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _appInForeground = false;
      if (mounted &&
          (state == AppLifecycleState.paused ||
              state == AppLifecycleState.hidden ||
              state == AppLifecycleState.detached)) {
        unawaited(context.read<VpnProvider>().markSimpleAppLeft());
      }
    }
  }

  Future<void> _refreshAndScheduleFeedbackPrompt(VpnProvider provider) async {
    await provider.refreshConnectionState();
    if (mounted) _scheduleFeedbackPrompt(provider);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _openSettings(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const SimpleSettingsScreen()),
    );
  }

  void _scheduleFeedbackPrompt(VpnProvider provider) {
    if (!_appInForeground ||
        !provider.isConnected ||
        provider.simpleCurrentAttempt == null ||
        !provider.simpleConnectionNeedsFeedback) {
      return;
    }
    final generation = provider.simpleConnectionGeneration;
    if (_lastPromptedConnectionGeneration == generation ||
        _promptScheduled ||
        _feedbackDialogOpen) {
      return;
    }

    _promptScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _promptScheduled = false;
      if (!mounted || !_appInForeground || _feedbackDialogOpen) return;
      final currentProvider = context.read<VpnProvider>();
      if (!currentProvider.isConnected ||
          currentProvider.simpleCurrentAttempt == null ||
          !currentProvider.simpleConnectionNeedsFeedback ||
          currentProvider.simpleConnectionGeneration != generation ||
          _lastPromptedConnectionGeneration == generation) {
        return;
      }
      _lastPromptedConnectionGeneration = generation;
      _feedbackDialogOpen = true;
      unawaited(_showFeedbackDialog(currentProvider, generation));
    });
  }

  Future<void> _showFeedbackDialog(
    VpnProvider provider,
    int generation,
  ) async {
    final changeServer = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const LocalizedText('Are you satisfied with this connection?'),
          content: const LocalizedText(
            'If not, the app will try the next available option.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const LocalizedText('Satisfied'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const LocalizedText('Change server'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    _feedbackDialogOpen = false;
    if (!provider.isConnected ||
        provider.simpleCurrentAttempt == null ||
        provider.simpleConnectionGeneration != generation) {
      return;
    }
    if (changeServer == true) {
      unawaited(provider.cycleSimpleConnection());
    } else if (changeServer == false) {
      await provider.markSimpleConnectionSatisfied();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('4win VPN'),
        actions: [
          IconButton(
            tooltip: context.l10n.text('Settings'),
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _openSettings(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Consumer<VpnProvider>(
          builder: (context, provider, _) {
            _scheduleFeedbackPrompt(provider);
            final connected = provider.status == VpnConnectionStatus.connected;
            final connecting = provider.status == VpnConnectionStatus.connecting ||
                provider.status == VpnConnectionStatus.disconnecting ||
                provider.simpleConnectionInProgress;
            final statusText = provider.simpleConnectionFailed
                ? provider.simpleConnectionFailureMessage ??
                    'Could not connect with WARP, Plus, or free Xray.'
                : connected
                ? 'Connected'
                : connecting
                ? 'Connecting...'
                : 'Disconnected';
            final buttonText = connected
                ? 'Disconnect'
                : connecting
                ? 'Cancel'
                : 'Connect';

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        connected
                            ? Icons.shield
                            : Icons.shield_outlined,
                        size: 74,
                        color: connected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 18),
                      LocalizedText(
                        statusText,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: provider.simpleConnectionFailed ? 15 : 18,
                          fontWeight: FontWeight.w600,
                          color: provider.simpleConnectionFailed
                              ? Theme.of(context).colorScheme.error
                              : null,
                        ),
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        height: 58,
                        child: FilledButton.icon(
                          onPressed: () {
                            if (connected || connecting) {
                              unawaited(provider.disconnect());
                            } else {
                              unawaited(provider.connectSimple());
                            }
                          },
                          icon: Icon(
                            connected || connecting
                                ? Icons.power_settings_new
                                : Icons.power,
                          ),
                          label: LocalizedText(buttonText),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class SimpleSettingsScreen extends StatelessWidget {
  const SimpleSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const LocalizedText('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        children: [
          const LocalizedText(
            'Appearance',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment<bool>(
                value: false,
                icon: Icon(Icons.light_mode_outlined),
                label: LocalizedText('Light'),
              ),
              ButtonSegment<bool>(
                value: true,
                icon: Icon(Icons.dark_mode_outlined),
                label: LocalizedText('Dark'),
              ),
            ],
            selected: {theme.isDarkMode},
            onSelectionChanged: (selection) =>
                theme.setSimpleDarkMode(selection.single),
          ),
          const SizedBox(height: 20),
          Divider(color: isDark ? Colors.white24 : Colors.black12),
          const AppLanguageSetting(),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.call_split),
            title: const LocalizedText('Split Tunneling'),
            subtitle: const LocalizedText('Choose apps & websites'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const SplitTunnelScreen(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.tune),
            title: const LocalizedText('Switch to Advanced'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () async {
              context
                  .read<VpnProvider>()
                  .restoreSimpleAdvancedProtocolIfStopped();
              await context
                  .read<AppModeProvider>()
                  .setMode(AppExperienceMode.advanced);
              if (!context.mounted) return;
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}
