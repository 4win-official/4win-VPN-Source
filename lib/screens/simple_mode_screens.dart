import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/app_mode_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/vpn_provider.dart';
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
                    description:
                        'Connect with one tap; the app chooses for you.',
                    icon: Icons.power_settings_new,
                    isDark: isDark,
                    onPressed: () => _choose(context, AppExperienceMode.simple),
                  ),
                  const SizedBox(height: 12),
                  _ModeChoice(
                    modeName: 'Advanced',
                    description:
                        'Choose protocols, servers, and detailed settings.',
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
        !provider.simpleConnectionNeedsFeedback ||
        !provider.simpleConnectionFeedbackReadyOnReturn) {
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
          !currentProvider.simpleConnectionFeedbackReadyOnReturn ||
          currentProvider.simpleConnectionGeneration != generation ||
          _lastPromptedConnectionGeneration == generation) {
        return;
      }
      _lastPromptedConnectionGeneration = generation;
      _feedbackDialogOpen = true;
      unawaited(_showFeedbackDialog(currentProvider, generation));
    });
  }

  Future<void> _showFeedbackDialog(VpnProvider provider, int generation) async {
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final transition = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 700);
    return Scaffold(
      body: Consumer<VpnProvider>(
        builder: (context, provider, _) {
          _scheduleFeedbackPrompt(provider);
          final connected = provider.status == VpnConnectionStatus.connected;
          final connecting =
              provider.status == VpnConnectionStatus.connecting ||
              provider.status == VpnConnectionStatus.disconnecting ||
              provider.simpleConnectionInProgress;
          final statusText = connected
              ? 'Connected'
              : connecting
              ? 'Connecting...'
              : 'Disconnected';
          final buttonText = connected
              ? 'Disconnect'
              : connecting
              ? 'Cancel'
              : 'Connect';
          final backgroundColors = isDark
              ? connecting
                    ? const [
                        Color(0xFF5B4918),
                        Color(0xFF382E11),
                        Color(0xFF111A2C),
                      ]
                    : connected
                    ? const [
                        Color(0xFF1A583A),
                        Color(0xFF103524),
                        Color(0xFF10192B),
                      ]
                    : const [
                        Color(0xFF173D6A),
                        Color(0xFF102744),
                        Color(0xFF11162B),
                      ]
              : connecting
              ? const [Color(0xFFFFE59A), Color(0xFFFFF4CF), Color(0xFFF0F2FA)]
              : connected
              ? const [Color(0xFFB9E7C6), Color(0xFFE6F6E9), Color(0xFFE9F0FF)]
              : const [Color(0xFFB7D8FF), Color(0xFFEAF4FF), Color(0xFFF3F0FF)];
          final accent = connecting
              ? const Color(0xFFD39A34)
              : connected
              ? const Color(0xFF25A878)
              : const Color(0xFF527FE6);

          return AnimatedContainer(
            key: const ValueKey('simple-status-background'),
            duration: transition,
            curve: Curves.easeInOutCubic,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: backgroundColors,
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  top: -132,
                  right: -110,
                  child: _AmbientGlow(color: accent, size: 330),
                ),
                Positioned(
                  bottom: -170,
                  left: -130,
                  child: _AmbientGlow(
                    color: const Color(0xFF9A83F5),
                    size: 360,
                    opacity: isDark ? 0.17 : 0.24,
                  ),
                ),
                SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final contentWidth = constraints.maxWidth - 44;
                      final powerDiameter = (contentWidth * 0.70)
                          .clamp(176.0, 220.0)
                          .toDouble();
                      return SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  22,
                                  18,
                                  22,
                                  24,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 44,
                                          height: 44,
                                          padding: const EdgeInsets.all(6),
                                          decoration: _glassIconDecoration(
                                            isDark: isDark,
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            child: Image.asset(
                                              'assets/icons/app_icon.png',
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        const Expanded(
                                          child: LocalizedText(
                                            '4win VPN',
                                            style: TextStyle(
                                              fontSize: 21,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: -0.3,
                                            ),
                                          ),
                                        ),
                                        _GlassIconButton(
                                          icon: Icons.tune_rounded,
                                          tooltip: context.l10n.text(
                                            'Settings',
                                          ),
                                          isDark: isDark,
                                          onPressed: () =>
                                              _openSettings(context),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 28),
                                    _GlassPanel(
                                      isDark: isDark,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 14,
                                      ),
                                      child: Row(
                                        children: [
                                          _GlassIconBadge(
                                            icon: Icons.auto_awesome_rounded,
                                            isDark: isDark,
                                            tint: accent,
                                          ),
                                          const SizedBox(width: 14),
                                          const Expanded(
                                            child: LocalizedText(
                                              'Connect with one tap; the app chooses for you.',
                                              style: TextStyle(
                                                fontSize: 14,
                                                height: 1.35,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 28),
                                    Center(
                                      child: _LiquidPowerControl(
                                        diameter: powerDiameter,
                                        isDark: isDark,
                                        accent: accent,
                                        label: buttonText,
                                        duration: reduceMotion
                                            ? Duration.zero
                                            : const Duration(milliseconds: 420),
                                        onPressed: () {
                                          if (connected || connecting) {
                                            unawaited(provider.disconnect());
                                          } else {
                                            unawaited(provider.connectSimple());
                                          }
                                        },
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    Center(
                                      child: _ConnectionStatusPill(
                                        label: statusText,
                                        connected: connected,
                                        connecting: connecting,
                                        isDark: isDark,
                                        duration: transition,
                                      ),
                                    ),
                                    if (provider.simpleConnectionFailed) ...[
                                      const SizedBox(height: 14),
                                      _GlassPanel(
                                        isDark: isDark,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 14,
                                        ),
                                        child: Row(
                                          children: [
                                            _GlassIconBadge(
                                              icon: Icons.error_outline_rounded,
                                              isDark: isDark,
                                              tint: Theme.of(
                                                context,
                                              ).colorScheme.error,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child:
                                                  provider.simpleConnectionFailureMessage ==
                                                      null
                                                  ? const LocalizedText(
                                                      'Could not connect with WARP, Plus, or free Xray.',
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        height: 1.35,
                                                      ),
                                                    )
                                                  : Text(
                                                      provider
                                                          .simpleConnectionFailureMessage!,
                                                      textAlign:
                                                          TextAlign.start,
                                                      style: const TextStyle(
                                                        fontSize: 13,
                                                        height: 1.35,
                                                      ),
                                                    ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 24),
                                    _GlassPanel(
                                      isDark: isDark,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 14,
                                      ),
                                      child: Row(
                                        children: [
                                          _GlassIconBadge(
                                            icon: Icons.shield_outlined,
                                            isDark: isDark,
                                            tint: accent,
                                          ),
                                          const SizedBox(width: 14),
                                          const Expanded(
                                            child: LocalizedText(
                                              'Private connection',
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          Icon(
                                            Icons.more_horiz_rounded,
                                            color:
                                                (isDark
                                                        ? Colors.white
                                                        : const Color(
                                                            0xFF26354F,
                                                          ))
                                                    .withValues(alpha: 0.55),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
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
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const LocalizedText('Settings'),
      ),
      body: _GlassBackdrop(
        isDark: isDark,
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 88, 20, 28),
            children: [
              _GlassPanel(
                isDark: isDark,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        _GlassIconBadge(
                          icon: Icons.brightness_6_outlined,
                          isDark: isDark,
                        ),
                        const SizedBox(width: 12),
                        const LocalizedText(
                          'Appearance',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
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
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _GlassPanel(
                isDark: isDark,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: const AppLanguageSetting(),
              ),
              const SizedBox(height: 14),
              _GlassPanel(
                isDark: isDark,
                padding: const EdgeInsets.all(8),
                child: _SettingsAction(
                  icon: Icons.call_split_rounded,
                  title: 'Split Tunneling',
                  subtitle: 'Choose apps & websites',
                  isDark: isDark,
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const SplitTunnelScreen(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _GlassPanel(
                isDark: isDark,
                padding: const EdgeInsets.all(8),
                child: _SettingsAction(
                  icon: Icons.tune_rounded,
                  title: 'Switch to Advanced',
                  isDark: isDark,
                  onTap: () async {
                    context
                        .read<VpnProvider>()
                        .restoreSimpleAdvancedProtocolIfStopped();
                    await context.read<AppModeProvider>().setMode(
                      AppExperienceMode.advanced,
                    );
                    if (!context.mounted) return;
                    Navigator.of(context).pop();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A blur-free glass surface: translucent fills, a fine rim and one restrained
/// static shadow create depth without a continuously rendered backdrop filter.
class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.isDark,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  final bool isDark;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  const Color(0xFF26344F).withValues(alpha: 0.76),
                  const Color(0xFF18243A).withValues(alpha: 0.78),
                ]
              : [
                  Colors.white.withValues(alpha: 0.72),
                  const Color(0xFFF7FAFF).withValues(alpha: 0.58),
                ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: isDark ? 0.16 : 0.76),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.13 : 0.045),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _GlassBackdrop extends StatelessWidget {
  const _GlassBackdrop({required this.isDark, required this.child});

  final bool isDark;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? const [
                      Color(0xFF10192B),
                      Color(0xFF11182A),
                      Color(0xFF201B37),
                    ]
                  : const [
                      Color(0xFFE5F0FF),
                      Color(0xFFF3F2FF),
                      Color(0xFFF8F8FF),
                    ],
            ),
          ),
        ),
        Positioned(
          top: -130,
          right: -100,
          child: _AmbientGlow(
            color: const Color(0xFF648BFF),
            size: 330,
            opacity: isDark ? 0.19 : 0.23,
          ),
        ),
        Positioned(
          bottom: -170,
          left: -140,
          child: _AmbientGlow(
            color: const Color(0xFFAA89FF),
            size: 380,
            opacity: isDark ? 0.17 : 0.22,
          ),
        ),
        child,
      ],
    );
  }
}

class _AmbientGlow extends StatelessWidget {
  const _AmbientGlow({
    required this.color,
    required this.size,
    this.opacity = 0.2,
  });

  final Color color;
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: opacity),
                color.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

BoxDecoration _glassIconDecoration({required bool isDark, Color? tint}) =>
    BoxDecoration(
      borderRadius: BorderRadius.circular(17),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: isDark ? 0.20 : 0.88),
          (tint ?? const Color(0xFF7B9EFF)).withValues(
            alpha: isDark ? 0.20 : 0.14,
          ),
        ],
      ),
      border: Border.all(
        color: Colors.white.withValues(alpha: isDark ? 0.24 : 0.82),
      ),
    );

class _GlassIconBadge extends StatelessWidget {
  const _GlassIconBadge({
    required this.icon,
    required this.isDark,
    this.tint,
    this.size = 46,
  });

  final IconData icon;
  final bool isDark;
  final Color? tint;
  final double size;

  @override
  Widget build(BuildContext context) {
    final iconColor = tint ?? const Color(0xFF557DE2);
    return Container(
      width: size,
      height: size,
      decoration: _glassIconDecoration(isDark: isDark, tint: iconColor),
      child: Icon(
        icon,
        size: size * 0.48,
        color: isDark ? Color.lerp(iconColor, Colors.white, 0.35) : iconColor,
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.tooltip,
    required this.isDark,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool isDark;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 50,
      decoration: _glassIconDecoration(isDark: isDark),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 22),
      ),
    );
  }
}

class _LiquidPowerControl extends StatelessWidget {
  const _LiquidPowerControl({
    required this.diameter,
    required this.isDark,
    required this.accent,
    required this.label,
    required this.duration,
    required this.onPressed,
  });

  final double diameter;
  final bool isDark;
  final Color accent;
  final String label;
  final Duration duration;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.l10n.text(label),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: AnimatedContainer(
            key: const ValueKey('simple-power-control'),
            duration: duration,
            curve: Curves.easeOutCubic,
            width: diameter,
            height: diameter,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [
                        Colors.white.withValues(alpha: 0.28),
                        accent.withValues(alpha: 0.52),
                        Colors.black.withValues(alpha: 0.28),
                      ]
                    : [
                        Colors.white.withValues(alpha: 0.92),
                        accent.withValues(alpha: 0.38),
                        Colors.white.withValues(alpha: 0.66),
                      ],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: isDark ? 0.38 : 0.88),
                width: 1.4,
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: isDark ? 0.24 : 0.20),
                  blurRadius: 25,
                  spreadRadius: 1,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.055),
                  blurRadius: 12,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(-0.36, -0.48),
                  radius: 1.15,
                  colors: isDark
                      ? [
                          const Color(0xFF344561),
                          const Color(0xFF1C2D47),
                          const Color(0xFF142139),
                        ]
                      : [
                          Colors.white.withValues(alpha: 0.97),
                          const Color(0xFFEAF1FF),
                          const Color(0xFFD5E1F7),
                        ],
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: isDark ? 0.18 : 0.70),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.power_settings_new_rounded,
                    size: diameter * 0.23,
                    color: isDark
                        ? Color.lerp(accent, Colors.white, 0.43)
                        : accent,
                  ),
                  const SizedBox(height: 8),
                  LocalizedText(
                    label,
                    style: TextStyle(
                      fontSize: diameter * 0.075,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.1,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.95)
                          : const Color(0xFF24324B),
                    ),
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

class _ConnectionStatusPill extends StatelessWidget {
  const _ConnectionStatusPill({
    required this.label,
    required this.connected,
    required this.connecting,
    required this.isDark,
    required this.duration,
  });

  final String label;
  final bool connected;
  final bool connecting;
  final bool isDark;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final stateColor = connecting
        ? const Color(0xFFD39A34)
        : connected
        ? const Color(0xFF25A878)
        : const Color(0xFF71809A);
    return AnimatedContainer(
      duration: duration,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: (isDark ? const Color(0xFF15223A) : Colors.white).withValues(
          alpha: isDark ? 0.68 : 0.68,
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: isDark ? 0.16 : 0.78),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.12 : 0.035),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: stateColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: stateColor.withValues(alpha: 0.35),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 9),
          LocalizedText(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF273650),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsAction extends StatelessWidget {
  const _SettingsAction({
    required this.icon,
    required this.title,
    required this.isDark,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Row(
            children: [
              _GlassIconBadge(icon: icon, isDark: isDark, size: 42),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LocalizedText(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      LocalizedText(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Directionality.of(context) == TextDirection.rtl
                    ? Icons.chevron_left_rounded
                    : Icons.chevron_right_rounded,
                color: isDark ? Colors.white70 : Colors.black45,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
