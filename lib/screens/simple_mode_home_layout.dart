import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../providers/vpn_provider.dart';
import '../services/ip_geolocation_service.dart';
import '../widgets/simple_mode_world_map.dart';

/// A screenshot-inspired, single-purpose home for Simple mode.
///
/// The page deliberately keeps the connection flow simple: an edge-to-edge
/// map stays behind the page, the central control starts/stops the connection,
/// and the bottom connection card explains what will be selected.
class SimpleModeHomeLayout extends StatelessWidget {
  const SimpleModeHomeLayout({
    super.key,
    required this.provider,
    required this.onSettings,
    this.lookupSourceIpLocation,
    this.lookupCurrentIpLocation,
  });

  final VpnProvider provider;
  final VoidCallback onSettings;
  final IpLocationLookup? lookupSourceIpLocation;
  final IpLocationLookup? lookupCurrentIpLocation;

  @override
  Widget build(BuildContext context) {
    final connected = provider.status == VpnConnectionStatus.connected;
    final connecting =
        provider.status == VpnConnectionStatus.connecting ||
        provider.status == VpnConnectionStatus.disconnecting ||
        provider.simpleConnectionInProgress;
    final failed = provider.simpleConnectionFailed;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final background = isDark
        ? const Color(0xFF191822)
        : const Color(0xFFF2EFF7);
    final cardBackground = isDark
        ? const Color(0xD02A2935)
        : const Color(0xDDFFFFFF);
    final foreground = isDark ? const Color(0xFFF7F3FB) : const Color(0xFF292634);
    final secondary = isDark ? const Color(0xFFB5B0C0) : const Color(0xFF716B7D);
    final accent = failed
        ? const Color(0xFFFF7796)
        : connected
        ? const Color(0xFF75E5A5)
        : connecting
        ? const Color(0xFFFFC56B)
        : const Color(0xFFB98AFF);

    final headline = failed
        ? 'Connection failed'
        : connected
        ? 'You are protected'
        : connecting
        ? 'Connecting securely'
        : 'You are unprotected';
    final actionLabel = connected
        ? 'Disconnect'
        : connecting
        ? 'Cancel'
        : 'Connect';
    final protocol = provider.selectedProtocol.toUpperCase();
    final mapConnecting =
        provider.status == VpnConnectionStatus.connecting ||
        (provider.simpleConnectionInProgress &&
            provider.status != VpnConnectionStatus.disconnecting);

    void toggleConnection() {
      if (connected || connecting) {
        unawaited(provider.disconnect());
      } else {
        unawaited(provider.connectSimple());
      }
    }

    return Scaffold(
      backgroundColor: background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: SimpleModeWorldMap(
              status: provider.status,
              connecting: mapConnecting,
              isDark: isDark,
              locationLabelTopInset: MediaQuery.of(context).padding.top + 73,
              lookupSourceIpLocation: lookupSourceIpLocation,
              lookupCurrentIpLocation: lookupCurrentIpLocation,
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    background.withValues(alpha: isDark ? 0.77 : 0.73),
                    background.withValues(alpha: isDark ? 0.52 : 0.46),
                    background.withValues(alpha: isDark ? 0.82 : 0.76),
                  ],
                  stops: const [0, 0.47, 1],
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _SimpleTopBar(
                  foreground: foreground,
                  secondary: secondary,
                  accent: accent,
                  isDark: isDark,
                  onSettings: onSettings,
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final height = constraints.maxHeight;
                      final mapHeight =
                          (height * 0.72).clamp(390.0, 720.0).toDouble();
                      // Grow the lower map area without shifting the centered
                      // power control from its previous on-screen position.
                      final controlReferenceHeight =
                          (height * 0.64).clamp(390.0, 640.0).toDouble();
                      final controlAlignmentY =
                          (controlReferenceHeight * 0.55 / mapHeight) * 2 - 1;
                      return SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          children: [
                            SizedBox(
                              height: mapHeight,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Align(
                                    alignment: Alignment(0, controlAlignmentY),
                                    child: _SimpleMapControl(
                                      accent: accent,
                                      connected: connected,
                                      connecting: connecting,
                                      failed: failed,
                                      onTap: toggleConnection,
                                    ),
                                  ),
                                  Positioned(
                                    left: 24,
                                    right: 24,
                                    bottom: 14,
                                    child: _MapStatusLine(
                                      headline: headline,
                                      secondary: connected
                                          ? 'Your connection is private and protected.'
                                          : connecting
                                          ? 'Finding the best available route for you.'
                                          : 'Connect to protect your internet traffic.',
                                      foreground: foreground,
                                      secondaryColor: secondary,
                                      accent: accent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              color: Colors.transparent,
                              padding: const EdgeInsets.fromLTRB(24, 20, 24, 14),
                              child: _SimpleConnectionCard(
                                isDark: isDark,
                                cardBackground: cardBackground,
                                foreground: foreground,
                                secondary: secondary,
                                accent: accent,
                                connected: connected,
                                connecting: connecting,
                                failed: failed,
                                protocol: protocol,
                                actionLabel: actionLabel,
                                ping: provider.currentPing,
                                pingFailed: provider.pingFailed,
                                pinging: provider.xrayPinging,
                                onConnect: toggleConnection,
                                onPing: provider.isConnected &&
                                        const {'xray', 'mix', 'warp'}
                                            .contains(provider.selectedProtocol)
                                    ? () => unawaited(provider.manualXrayPing())
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
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

class _SimpleTopBar extends StatelessWidget {
  const _SimpleTopBar({
    required this.foreground,
    required this.secondary,
    required this.accent,
    required this.isDark,
    required this.onSettings,
  });

  final Color foreground;
  final Color secondary;
  final Color accent;
  final bool isDark;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 18, 5),
      child: Row(
        children: [
          Icon(Icons.shield_outlined, color: accent, size: 24),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              '4win VPN',
              style: TextStyle(
                color: foreground,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ),
          IconButton(
            tooltip: context.l10n.text('Settings'),
            onPressed: onSettings,
            icon: Icon(Icons.settings_outlined, color: secondary),
            style: IconButton.styleFrom(
              backgroundColor: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapStatusLine extends StatelessWidget {
  const _MapStatusLine({
    required this.headline,
    required this.secondary,
    required this.foreground,
    required this.secondaryColor,
    required this.accent,
  });

  final String headline;
  final String secondary;
  final Color foreground;
  final Color secondaryColor;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          child: Text(
            headline,
            key: ValueKey(headline),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: foreground,
              fontSize: 25,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.1,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          secondary,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: secondaryColor, fontSize: 13),
        ),
        const SizedBox(height: 7),
        Container(
          width: 42,
          height: 3,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ],
    );
  }
}

class _SimpleMapControl extends StatelessWidget {
  const _SimpleMapControl({
    required this.accent,
    required this.connected,
    required this.connecting,
    required this.failed,
    required this.onTap,
  });

  final Color accent;
  final bool connected;
  final bool connecting;
  final bool failed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pulseColor = failed
        ? const Color(0xFFFF6F91)
        : connected
        ? const Color(0xFF68E5A0)
        : accent;
    return Semantics(
      button: true,
      label: context.l10n.text(connected ? 'Disconnect' : 'Connect'),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          width: 152,
          height: 152,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                pulseColor.withValues(alpha: 0.55),
                pulseColor.withValues(alpha: 0.18),
                Colors.transparent,
              ],
              stops: const [0.12, 0.55, 1],
            ),
          ),
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFF9F7FF),
                boxShadow: [
                  BoxShadow(
                    color: pulseColor.withValues(alpha: 0.55),
                    blurRadius: 24,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Icon(
                connecting
                    ? Icons.more_horiz_rounded
                    : connected
                    ? Icons.lock_rounded
                    : Icons.power_settings_new_rounded,
                color: pulseColor,
                size: 29,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SimpleConnectionCard extends StatelessWidget {
  const _SimpleConnectionCard({
    required this.isDark,
    required this.cardBackground,
    required this.foreground,
    required this.secondary,
    required this.accent,
    required this.connected,
    required this.connecting,
    required this.failed,
    required this.protocol,
    required this.actionLabel,
    required this.ping,
    required this.pingFailed,
    required this.pinging,
    required this.onConnect,
    required this.onPing,
  });

  final bool isDark;
  final Color cardBackground;
  final Color foreground;
  final Color secondary;
  final Color accent;
  final bool connected;
  final bool connecting;
  final bool failed;
  final String protocol;
  final String actionLabel;
  final int? ping;
  final bool pingFailed;
  final bool pinging;
  final VoidCallback onConnect;
  final VoidCallback? onPing;

  @override
  Widget build(BuildContext context) {
    final pingLabel = pinging
        ? 'Testing…'
        : pingFailed
        ? 'Ping failed'
        : ping == null
        ? 'Tap to test'
        : '$ping ms';
    return Container(
      padding: const EdgeInsets.fromLTRB(17, 17, 17, 16),
      decoration: BoxDecoration(
        color: cardBackground,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.13) : Colors.black.withValues(alpha: 0.09),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: connected
                      ? const Color(0xFF5DDBA0).withValues(alpha: 0.18)
                      : const Color(0xFF42E8CD).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  connected ? Icons.verified_user_outlined : Icons.bolt_rounded,
                  color: connected ? const Color(0xFF63D99A) : const Color(0xFF42E8CD),
                  size: 25,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      connected ? 'Secure connection' : 'Fastest free server',
                      style: TextStyle(
                        color: foreground,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      connected ? 'Protected by 4win VPN' : 'Auto-selected from available servers',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: secondary, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              if (onPing != null)
                InkWell(
                  onTap: pinging ? null : onPing,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(7),
                    child: Column(
                      children: [
                        Icon(Icons.info_outline_rounded, color: secondary, size: 22),
                        const SizedBox(height: 2),
                        Text(
                          pingLabel,
                          style: TextStyle(
                            color: pingFailed ? Colors.redAccent : secondary,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 15),
          SizedBox(
            height: 53,
            child: FilledButton(
              onPressed: onConnect,
              style: FilledButton.styleFrom(
                backgroundColor: failed ? const Color(0xFFFF6688) : const Color(0xFF7650FF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              child: Text(
                context.l10n.text(actionLabel),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 9),
          Center(
            child: Text(
              protocol.isEmpty ? 'AUTO' : protocol,
              style: TextStyle(color: accent, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}
