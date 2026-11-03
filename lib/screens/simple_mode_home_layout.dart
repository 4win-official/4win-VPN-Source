import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../providers/vpn_provider.dart';
import '../services/ip_geolocation_service.dart';
import '../widgets/simple_mode_world_map.dart';

/// A lightweight, screenshot-inspired dashboard for Simple mode.
///
/// A lightweight, screenshot-inspired Simple-mode dashboard with a circular
/// power control and no continuous decorative animation.
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final connected = provider.status == VpnConnectionStatus.connected;
    final connecting =
        provider.status == VpnConnectionStatus.connecting ||
        provider.status == VpnConnectionStatus.disconnecting ||
        provider.simpleConnectionInProgress;
    final mapConnecting =
        provider.status == VpnConnectionStatus.connecting ||
        (provider.simpleConnectionInProgress &&
            provider.status != VpnConnectionStatus.disconnecting);
    final failed = provider.simpleConnectionFailed;
    final accent = failed
        ? (isDark ? const Color(0xFFFF7F93) : const Color(0xFFC13D57))
        : connected
        ? const Color(0xFF7BE5AA)
        : connecting
        ? const Color(0xFFFFCB69)
        : const Color(0xFF9B82FF);
    final background = isDark
        ? const Color(0xFF111116)
        : const Color(0xFFF4F2F8);
    final foreground = isDark ? const Color(0xFFF7F5FA) : const Color(0xFF20202A);
    final secondary = isDark ? const Color(0xFFAAA7B5) : const Color(0xFF6D6978);
    final actionLabel = connected
        ? 'Disconnect'
        : connecting
        ? 'Cancel'
        : 'Connect';
    final headline = failed
        ? 'Connection failed'
        : connected
        ? 'You are protected'
        : connecting
        ? 'Connecting securely'
        : 'Connect with confidence';
    final helper = failed
        ? provider.simpleConnectionFailureMessage ?? 'Tap connect to try again.'
        : connected
        ? 'Your connection is private and protected.'
        : connecting
        ? 'Finding the best available route for you.'
        : 'One tap to secure your connection.';

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 700;
            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, compact ? 10 : 18, 20, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SimpleHeader(
                        isDark: isDark,
                        foreground: foreground,
                        connected: connected,
                        connecting: connecting,
                        onSettings: onSettings,
                      ),
                      SizedBox(height: compact ? 18 : 28),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.12),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                        child: Column(
                          key: ValueKey(headline),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              headline,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: failed ? accent : foreground,
                                fontSize: compact ? 28 : 34,
                                height: 1.08,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.8,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              helper,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: failed ? accent : secondary,
                                fontSize: 15,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: compact ? 8 : 16),
                      SizedBox(
                        height: compact ? 280 : 370,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(36),
                                  gradient: RadialGradient(
                                    center: const Alignment(0, 0.05),
                                    radius: 0.9,
                                    colors: [
                                      accent.withValues(alpha: isDark ? 0.12 : 0.09),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            PositionedDirectional(
                              start: -36,
                              end: -36,
                              top: 4,
                              bottom: 0,
                              child: SimpleModeWorldMap(
                                status: provider.status,
                                connecting: mapConnecting,
                                isDark: isDark,
                                lookupSourceIpLocation: lookupSourceIpLocation,
                                lookupCurrentIpLocation: lookupCurrentIpLocation,
                              ),
                            ),
                            Center(
                              child: _SimplePowerButton(
                                size: compact ? 154 : 188,
                                accent: accent,
                                isDark: isDark,
                                label: actionLabel,
                                onTap: () {
                                  if (connected || connecting) {
                                    unawaited(provider.disconnect());
                                  } else {
                                    unawaited(provider.connectSimple());
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      _SimpleConnectionCard(
                        isDark: isDark,
                        accent: accent,
                        foreground: foreground,
                        secondary: secondary,
                        connected: connected,
                        connecting: connecting,
                        actionLabel: actionLabel,
                        protocol: provider.selectedProtocol,
                        ping: provider.currentPing,
                        pingFailed: provider.pingFailed,
                        pinging: provider.xrayPinging,
                        onConnect: () {
                          if (connected || connecting) {
                            unawaited(provider.disconnect());
                          } else {
                            unawaited(provider.connectSimple());
                          }
                        },
                        onPing: provider.isConnected &&
                                const {'xray', 'mix', 'warp'}
                                    .contains(provider.selectedProtocol)
                            ? () => unawaited(provider.manualXrayPing())
                            : null,
                      ),
                      const SizedBox(height: 18),
                      _ConnectionStatsCard(
                        isDark: isDark,
                        connected: connected,
                        ping: provider.currentPing,
                        pingFailed: provider.pingFailed,
                        pinging: provider.xrayPinging,
                        awaitingFirstPing: provider.xrayPingAwaitingFirstTap,
                        protocol: provider.selectedProtocol,
                        connectionGeneration: provider.simpleConnectionGeneration,
                        onPingTap: provider.isConnected &&
                                const {'xray', 'mix', 'warp'}
                                    .contains(provider.selectedProtocol)
                            ? () => unawaited(provider.manualXrayPing())
                            : null,
                        download: provider.downloadDataUsage,
                        upload: provider.uploadDataUsage,
                      ),
                      const SizedBox(height: 18),
                      _SimpleBottomBar(
                        isDark: isDark,
                        foreground: foreground,
                        onSettings: onSettings,
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

class _SimpleHeader extends StatelessWidget {
  const _SimpleHeader({
    required this.isDark,
    required this.foreground,
    required this.connected,
    required this.connecting,
    required this.onSettings,
  });

  final bool isDark;
  final Color foreground;
  final bool connected;
  final bool connecting;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final statusColor = connected
        ? const Color(0xFF63D99A)
        : connecting
        ? const Color(0xFFFFC857)
        : const Color(0xFF9B82FF);
    final status = connected
        ? 'Protected'
        : connecting
        ? 'Setting up'
        : 'Not protected';
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: statusColor.withValues(alpha: 0.32)),
                ),
                child: Icon(Icons.shield_outlined, color: statusColor, size: 21),
              ),
              const SizedBox(width: 11),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '4win VPN',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  Text(
                    status,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: context.l10n.text('Settings'),
          onPressed: onSettings,
          icon: Icon(Icons.settings_outlined, color: foreground),
          style: IconButton.styleFrom(
            backgroundColor: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
          ),
        ),
      ],
    );
  }
}

class _SimplePowerButton extends StatelessWidget {
  const _SimplePowerButton({
    required this.size,
    required this.accent,
    required this.isDark,
    required this.label,
    required this.onTap,
  });

  final double size;
  final Color accent;
  final bool isDark;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.l10n.text(label),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('simple-power-connect-control'),
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: AnimatedContainer(
            key: const ValueKey('simple-power-control-surface'),
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            width: size,
            height: size,
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(
                startAngle: -math.pi / 2,
                colors: [
                  accent.withValues(alpha: 0.9),
                  const Color(0xFF4A4A59),
                  accent.withValues(alpha: 0.28),
                  const Color(0xFF252531),
                  accent.withValues(alpha: 0.9),
                ],
              ),
              boxShadow: [
                BoxShadow(color: accent.withValues(alpha: 0.24), blurRadius: 35, spreadRadius: 2),
                const BoxShadow(color: Color(0x55000000), blurRadius: 24, offset: Offset(0, 14)),
              ],
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(-0.35, -0.45),
                  colors: isDark
                      ? const [Color(0xFF343442), Color(0xFF111117)]
                      : const [Color(0xFF5A596C), Color(0xFF1F1E29)],
                ),
                border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.power_settings_new_rounded, size: size * 0.28, color: accent),
                    const SizedBox(height: 8),
                    Text(
                      context.l10n.text(label),
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
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
    required this.accent,
    required this.foreground,
    required this.secondary,
    required this.connected,
    required this.connecting,
    required this.actionLabel,
    required this.protocol,
    required this.ping,
    required this.pingFailed,
    required this.pinging,
    required this.onConnect,
    required this.onPing,
  });

  final bool isDark;
  final Color accent;
  final Color foreground;
  final Color secondary;
  final bool connected;
  final bool connecting;
  final String actionLabel;
  final String protocol;
  final int? ping;
  final bool pingFailed;
  final bool pinging;
  final VoidCallback onConnect;
  final VoidCallback? onPing;

  @override
  Widget build(BuildContext context) {
    final pingText = pinging
        ? 'Testing…'
        : pingFailed
        ? 'Ping failed'
        : ping == null
        ? 'Tap to test'
        : '$ping ms';
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF19191F) : Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: accent.withValues(alpha: isDark ? 0.32 : 0.24)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.06), blurRadius: 22, offset: const Offset(0, 9))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
                child: Icon(connected ? Icons.verified_user_outlined : Icons.bolt_rounded, color: accent, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(connected ? 'Secure connection' : 'Fastest available route', style: TextStyle(color: foreground, fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(protocol.toUpperCase(), style: TextStyle(color: secondary, fontSize: 12, letterSpacing: 0.8, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              if (onPing != null)
                InkWell(
                  onTap: pinging ? null : onPing,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: [
                        Icon(Icons.speed_rounded, size: 19, color: pingFailed ? Colors.redAccent : accent),
                        const SizedBox(height: 3),
                        Text(pingText, style: TextStyle(color: pingFailed ? Colors.redAccent : secondary, fontSize: 10, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: onConnect,
              style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: const Color(0xFF15131D), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17))),
              child: Text(context.l10n.text(actionLabel), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}

class _SimpleBottomBar extends StatelessWidget {
  const _SimpleBottomBar({required this.isDark, required this.foreground, required this.onSettings});

  final bool isDark;
  final Color foreground;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final muted = isDark ? Colors.white54 : Colors.black45;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _BottomAction(icon: Icons.speed_rounded, label: 'Status', active: true, color: foreground, muted: muted),
        const SizedBox(width: 10),
        _BottomAction(icon: Icons.tune_rounded, label: 'Settings', active: false, color: foreground, muted: muted, onTap: onSettings),
      ],
    );
  }
}

class _BottomAction extends StatelessWidget {
  const _BottomAction({required this.icon, required this.label, required this.active, required this.color, required this.muted, this.onTap});

  final IconData icon;
  final String label;
  final bool active;
  final Color color;
  final Color muted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(22),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(color: active ? color.withValues(alpha: 0.12) : Colors.transparent, borderRadius: BorderRadius.circular(22)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 19, color: active ? color : muted),
        const SizedBox(width: 7),
        Text(label, style: TextStyle(color: active ? color : muted, fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
    ),
  );
}

class _ConnectionStatsCard extends StatefulWidget {
  const _ConnectionStatsCard({
    required this.isDark,
    required this.connected,
    required this.ping,
    required this.pingFailed,
    required this.pinging,
    required this.awaitingFirstPing,
    required this.protocol,
    required this.connectionGeneration,
    required this.onPingTap,
    required this.download,
    required this.upload,
  });

  final bool isDark;
  final bool connected;
  final int? ping;
  final bool pingFailed;
  final bool pinging;
  final bool awaitingFirstPing;
  final String protocol;
  final int connectionGeneration;
  final VoidCallback? onPingTap;
  final String download;
  final String upload;

  @override
  State<_ConnectionStatsCard> createState() => _ConnectionStatsCardState();
}

class _ConnectionStatsCardState extends State<_ConnectionStatsCard> {
  bool _initialPingStarted = false;

  @override
  void initState() {
    super.initState();
    _maybeStartInitialPing();
  }

  @override
  void didUpdateWidget(covariant _ConnectionStatsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.connected ||
        !oldWidget.connected ||
        oldWidget.protocol != widget.protocol ||
        oldWidget.connectionGeneration != widget.connectionGeneration) {
      _initialPingStarted = false;
    }
    _maybeStartInitialPing();
  }

  void _maybeStartInitialPing() {
    if (_initialPingStarted ||
        !widget.connected ||
        !widget.awaitingFirstPing ||
        widget.protocol == 'warp' ||
        widget.pinging ||
        widget.onPingTap == null) {
      return;
    }
    _initialPingStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !widget.connected ||
          !widget.awaitingFirstPing ||
          widget.protocol == 'warp' ||
          widget.pinging) {
        return;
      }
      widget.onPingTap?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final foreground = widget.isDark ? Colors.white : const Color(0xFF17191C);
    final secondary = widget.isDark ? Colors.white60 : const Color(0xFF686D75);
    final valuePing = !widget.connected
        ? '—'
        : widget.pinging
        ? 'Pinging…'
        : widget.ping != null
        ? '${widget.ping} ms'
        : widget.pingFailed
        ? 'Failed'
        : widget.awaitingFirstPing
        ? 'click to ping'
        : '—';
    final valueDownload = widget.connected ? widget.download : '—';
    final valueUpload = widget.connected ? widget.upload : '—';
    final valueIsLocalized =
        widget.pinging ||
        widget.pingFailed ||
        widget.awaitingFirstPing;
    final pingMetric = _MetricColumn(
      key: const ValueKey('simple-ping-metric'),
      label: LocalizedText(widget.protocol == 'warp' ? 'WARP RTT' : 'Ping'),
      metricKey: 'ping',
      value: valuePing,
      valueIsLocalized: valueIsLocalized,
      color: foreground,
      secondary: secondary,
    );
    final Widget pingCell;
    if (widget.onPingTap == null || !widget.connected) {
      pingCell = pingMetric;
    } else {
      pingCell = Tooltip(
        message: context.l10n.text(
          widget.protocol == 'warp'
              ? 'Fresh RTT to Cloudflare’s 1.1.1.1 resolver through the active WARP data plane.'
              : 'Test Ping',
        ),
        child: InkWell(
          key: const ValueKey('simple-ping-tap'),
          borderRadius: BorderRadius.circular(12),
          onTap: widget.pinging ? null : widget.onPingTap,
          child: pingMetric,
        ),
      );
    }

    return Container(
      key: const ValueKey('simple-connection-stats'),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 17),
      decoration: BoxDecoration(
        color: widget.isDark
            ? const Color(0xFF08090A).withValues(alpha: 0.78)
            : Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: widget.isDark
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
              Expanded(child: pingCell),
              _MetricDivider(isDark: widget.isDark),
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
              _MetricDivider(isDark: widget.isDark),
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
    this.valueIsLocalized = false,
    required this.color,
    required this.secondary,
  });

  final Widget label;
  final String metricKey;
  final String value;
  final bool valueIsLocalized;
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
          textDirection: valueIsLocalized
              ? Directionality.of(context)
              : TextDirection.ltr,
          child: Text(
            valueIsLocalized ? context.l10n.text(value) : value,
            key: ValueKey('simple-$metricKey-value'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: valueIsLocalized ? 11 : 15,
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
