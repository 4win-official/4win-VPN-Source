import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../providers/vpn_provider.dart';

/// A lightweight, screenshot-inspired dashboard for Simple mode.
///
/// The app logo is the actual connect/disconnect control. Decorative rings are
/// drawn once with CustomPainter; there are no continuous animations or timers.
class SimpleModeHomeLayout extends StatelessWidget {
  const SimpleModeHomeLayout({
    super.key,
    required this.provider,
    required this.onSettings,
    required this.onSplitTunnel,
  });

  final VpnProvider provider;
  final VoidCallback onSettings;
  final VoidCallback onSplitTunnel;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final connected = provider.status == VpnConnectionStatus.connected;
    final connecting =
        provider.status == VpnConnectionStatus.connecting ||
        provider.status == VpnConnectionStatus.disconnecting ||
        provider.simpleConnectionInProgress;
    final failed = provider.simpleConnectionFailed;
    final actionLabel = connected
        ? 'Disconnect'
        : connecting
        ? 'Cancel'
        : 'Connect';
    final headline = failed
        ? 'Connection failed'
        : connected
        ? "You're connected."
        : connecting
        ? 'Connecting...'
        : 'Your VPN, one tap away.';
    final helperText = failed
        ? provider.simpleConnectionFailureMessage ??
              'Tap the logo to try again.'
        : connected
        ? 'Tap the logo to disconnect.'
        : connecting
        ? 'Setting up your connection...'
        : 'Tap the 4win logo to connect.';

    final colors = isDark
        ? connecting
              ? const [Color(0xFF242016), Color(0xFF171819)]
              : connected
              ? const [Color(0xFF18221C), Color(0xFF171819)]
              : const [Color(0xFF171819), Color(0xFF292A2D)]
        : connecting
        ? const [Color(0xFFFFF5D9), Color(0xFFF4F1E8)]
        : connected
        ? const [Color(0xFFE9F7ED), Color(0xFFF4F8F4)]
        : const [Color(0xFFF8F9FB), Color(0xFFE7E9ED)];
    final accent = failed
        ? (isDark ? const Color(0xFFFF7777) : const Color(0xFFB3261E))
        : connecting
        ? const Color(0xFFFFC857)
        : connected
        ? const Color(0xFF49C887)
        : const Color(0xFFF5C542);
    final primaryText = isDark ? Colors.white : const Color(0xFF15171A);
    final secondaryText = isDark ? Colors.white70 : const Color(0xFF575B63);

    return Scaffold(
      backgroundColor: colors.last,
      body: AnimatedContainer(
        key: const ValueKey('simple-status-background'),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: colors,
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, viewportConstraints) {
              final contentHeight = math.max(
                viewportConstraints.maxHeight,
                560.0,
              );
              return SingleChildScrollView(
                child: SizedBox(
                  height: contentHeight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: LocalizedText(
                            '4win VPN',
                            style: TextStyle(
                              color: primaryText.withValues(alpha: 0.66),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.7,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        LocalizedText(
                          headline,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: failed ? accent : primaryText,
                            fontSize: 32,
                            height: 1.12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          helperText ==
                                      provider.simpleConnectionFailureMessage &&
                                  failed
                              ? helperText
                              : context.l10n.text(helperText),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.start,
                          style: TextStyle(
                            color: failed ? accent : secondaryText,
                            fontSize: 15,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final controlSize = math.min(
                                176.0,
                                math.max(126.0, constraints.maxHeight * 0.56),
                              );
                              return CustomPaint(
                                painter: _OrbitalRingsPainter(
                                  color: primaryText.withValues(
                                    alpha: isDark ? 0.045 : 0.07,
                                  ),
                                ),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Semantics(
                                        button: true,
                                        label: context.l10n.text(actionLabel),
                                        child: Material(
                                          type: MaterialType.transparency,
                                          child: InkWell(
                                            key: const ValueKey(
                                              'simple-logo-connect-control',
                                            ),
                                            onTap: () {
                                              if (connected || connecting) {
                                                unawaited(
                                                  provider.disconnect(),
                                                );
                                              } else {
                                                unawaited(
                                                  provider.connectSimple(),
                                                );
                                              }
                                            },
                                            customBorder: const CircleBorder(),
                                            child: AnimatedContainer(
                                              duration: const Duration(
                                                milliseconds: 350,
                                              ),
                                              width: controlSize,
                                              height: controlSize,
                                              padding: EdgeInsets.all(
                                                controlSize * 0.20,
                                              ),
                                              decoration: BoxDecoration(
                                                color: isDark
                                                    ? const Color(0xFF101112)
                                                    : Colors.white.withValues(
                                                        alpha: 0.88,
                                                      ),
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: accent.withValues(
                                                    alpha: 0.82,
                                                  ),
                                                  width: 1.5,
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: accent.withValues(
                                                      alpha: isDark
                                                          ? 0.12
                                                          : 0.16,
                                                    ),
                                                    blurRadius: 24,
                                                    spreadRadius: 2,
                                                  ),
                                                ],
                                              ),
                                              child: Image.asset(
                                                'assets/icons/app_icon.png',
                                                fit: BoxFit.contain,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      LocalizedText(
                                        actionLabel,
                                        style: TextStyle(
                                          color: secondaryText,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        _ConnectionStatsCard(
                          isDark: isDark,
                          connected: connected,
                          ping: provider.currentPing,
                          pingFailed: provider.pingFailed,
                          download: provider.downloadDataUsage,
                          upload: provider.uploadDataUsage,
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF090A0B),
                              borderRadius: BorderRadius.circular(40),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.16),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _DockButton(
                                  key: const ValueKey(
                                    'simple-split-tunnel-action',
                                  ),
                                  tooltip: context.l10n.text('Split Tunneling'),
                                  icon: Icons.call_split_rounded,
                                  onPressed: onSplitTunnel,
                                ),
                                const SizedBox(width: 6),
                                _DockButton(
                                  key: const ValueKey('simple-settings-action'),
                                  tooltip: context.l10n.text('Settings'),
                                  icon: Icons.tune_rounded,
                                  onPressed: onSettings,
                                ),
                              ],
                            ),
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
      ),
    );
  }
}

class _ConnectionStatsCard extends StatelessWidget {
  const _ConnectionStatsCard({
    required this.isDark,
    required this.connected,
    required this.ping,
    required this.pingFailed,
    required this.download,
    required this.upload,
  });

  final bool isDark;
  final bool connected;
  final int? ping;
  final bool pingFailed;
  final String download;
  final String upload;

  @override
  Widget build(BuildContext context) {
    final foreground = isDark ? Colors.white : const Color(0xFF17191C);
    final secondary = isDark ? Colors.white60 : const Color(0xFF686D75);
    final valuePing = !connected
        ? '—'
        : ping != null
        ? '$ping ms'
        : pingFailed
        ? context.l10n.text('Failed')
        : '—';
    final valueDownload = connected ? download : '—';
    final valueUpload = connected ? upload : '—';

    return Container(
      key: const ValueKey('simple-connection-stats'),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 17),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF08090A).withValues(alpha: 0.78)
            : Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? Colors.white24
              : const Color(0xFF22252A).withValues(alpha: 0.18),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LocalizedText(
            'Connection stats',
            style: TextStyle(
              color: foreground,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MetricColumn(
                  key: const ValueKey('simple-ping-metric'),
                  label: const LocalizedText('Ping'),
                  metricKey: 'ping',
                  value: valuePing,
                  color: foreground,
                  secondary: secondary,
                ),
              ),
              _MetricDivider(isDark: isDark),
              Expanded(
                child: _MetricColumn(
                  key: const ValueKey('simple-download-metric'),
                  label: const LocalizedText('Download'),
                  metricKey: 'download',
                  value: valueDownload,
                  color: foreground,
                  secondary: secondary,
                ),
              ),
              _MetricDivider(isDark: isDark),
              Expanded(
                child: _MetricColumn(
                  key: const ValueKey('simple-upload-metric'),
                  label: const LocalizedText('Upload'),
                  metricKey: 'upload',
                  value: valueUpload,
                  color: foreground,
                  secondary: secondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricColumn extends StatelessWidget {
  const _MetricColumn({
    super.key,
    required this.label,
    required this.metricKey,
    required this.value,
    required this.color,
    required this.secondary,
  });

  final Widget label;
  final String metricKey;
  final String value;
  final Color color;
  final Color secondary;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DefaultTextStyle(
          style: TextStyle(color: secondary, fontSize: 11.5),
          child: label,
        ),
        const SizedBox(height: 6),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text(
            value,
            key: ValueKey('simple-$metricKey-value'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class _MetricDivider extends StatelessWidget {
  const _MetricDivider({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 36,
    margin: const EdgeInsets.symmetric(horizontal: 8),
    color: isDark ? Colors.white24 : Colors.black12,
  );
}

class _DockButton extends StatelessWidget {
  const _DockButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    splashRadius: 25,
    color: Colors.white,
    iconSize: 25,
    icon: Icon(icon),
  );
}

class _OrbitalRingsPainter extends CustomPainter {
  const _OrbitalRingsPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.min(size.width * 0.48, size.height * 0.46);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..isAntiAlias = true;

    for (var ring = 0; ring < 5; ring++) {
      final radius = maxRadius * (0.42 + ring * 0.145);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitalRingsPainter oldDelegate) =>
      oldDelegate.color != color;
}
