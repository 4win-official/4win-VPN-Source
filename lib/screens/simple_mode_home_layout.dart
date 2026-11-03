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
                        Row(
                          children: [
                            Expanded(
                              child: Directionality(
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
                            ),
                            IconButton(
                              key: const ValueKey('simple-settings-action'),
                              tooltip: context.l10n.text('Settings'),
                              onPressed: onSettings,
                              color: primaryText,
                              icon: const Icon(Icons.settings_outlined),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 72,
                          child: Align(
                            alignment: AlignmentDirectional.topStart,
                            child: LocalizedText(
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
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 44,
                          child: Align(
                            alignment: AlignmentDirectional.topStart,
                            child: Text(
                              helperText ==
                                          provider
                                              .simpleConnectionFailureMessage &&
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
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final controlSize = math.min(
                                208.0,
                                math.max(168.0, constraints.maxWidth * 0.56),
                              );
                              return Stack(
                                fit: StackFit.expand,
                                children: [
                                  // The atlas bleeds to screen edges; the Stack
                                  // and its centered connect control do not move.
                                  PositionedDirectional(
                                    start: -24,
                                    end: -24,
                                    top: 0,
                                    bottom: 0,
                                    child: SimpleModeWorldMap(
                                      status: provider.status,
                                      connecting: mapConnecting,
                                      isDark: isDark,
                                      lookupSourceIpLocation:
                                          lookupSourceIpLocation,
                                      lookupCurrentIpLocation:
                                          lookupCurrentIpLocation,
                                    ),
                                  ),
                                  Center(
                                    key: const ValueKey(
                                      'simple-power-control-area',
                                    ),
                                    child: Semantics(
                                      button: true,
                                      label: context.l10n.text(actionLabel),
                                      child: Material(
                                        type: MaterialType.transparency,
                                        child: InkWell(
                                          key: const ValueKey(
                                            'simple-power-connect-control',
                                          ),
                                          onTap: () {
                                            if (connected || connecting) {
                                              unawaited(provider.disconnect());
                                            } else {
                                              unawaited(
                                                provider.connectSimple(),
                                              );
                                            }
                                          },
                                          customBorder: const CircleBorder(),
                                          child: AnimatedContainer(
                                            key: const ValueKey(
                                              'simple-power-control-surface',
                                            ),
                                            duration: const Duration(
                                              milliseconds: 250,
                                            ),
                                            curve: Curves.easeOut,
                                            width: controlSize,
                                            height: controlSize,
                                            padding: const EdgeInsets.all(1),
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              gradient: const SweepGradient(
                                                startAngle: -math.pi / 2,
                                                colors: [
                                                  Color(0x7189A5B4),
                                                  Color(0x30627B89),
                                                  Color(0x4C253039),
                                                  Color(0x6D9DB8C7),
                                                  Color(0x7189A5B4),
                                                ],
                                                stops: [0, 0.24, 0.52, 0.78, 1],
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: accent.withValues(
                                                    alpha: isDark ? 0.18 : 0.12,
                                                  ),
                                                  blurRadius: 27,
                                                  spreadRadius: 0.5,
                                                ),
                                                const BoxShadow(
                                                  color: Color(0x70000000),
                                                  blurRadius: 28,
                                                  offset: Offset(0, 16),
                                                ),
                                                const BoxShadow(
                                                  color: Color(0x2489AFC0),
                                                  blurRadius: 16,
                                                  offset: Offset(-5, -6),
                                                ),
                                              ],
                                            ),
                                            child: ClipOval(
                                              child: Stack(
                                                fit: StackFit.expand,
                                                children: [
                                                  const Positioned.fill(
                                                    child: DecoratedBox(
                                                      decoration: BoxDecoration(
                                                        gradient: LinearGradient(
                                                          begin: Alignment(
                                                            -0.8,
                                                            -0.9,
                                                          ),
                                                          end: Alignment(
                                                            0.9,
                                                            0.95,
                                                          ),
                                                          colors: [
                                                            Color(0xFF27343B),
                                                            Color(0xFF13181B),
                                                            Color(0xFF080A0C),
                                                          ],
                                                          stops: [0, 0.38, 1],
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  const Positioned.fill(
                                                    child: DecoratedBox(
                                                      decoration: BoxDecoration(
                                                        gradient: RadialGradient(
                                                          center: Alignment(
                                                            -0.58,
                                                            -0.72,
                                                          ),
                                                          radius: 1.05,
                                                          colors: [
                                                            Color(0x2ABDD8E6),
                                                            Color(0x147E9DAD),
                                                            Colors.transparent,
                                                          ],
                                                          stops: [0, 0.42, 1],
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  Positioned(
                                                    top: controlSize * 0.08,
                                                    left: controlSize * 0.12,
                                                    child: SizedBox(
                                                      width: controlSize * 0.58,
                                                      height: controlSize * 0.36,
                                                      child: const DecoratedBox(
                                                        decoration: BoxDecoration(
                                                          gradient: RadialGradient(
                                                            center: Alignment(
                                                              -0.2,
                                                              -0.2,
                                                            ),
                                                            colors: [
                                                              Color(0x25C6E1EB),
                                                              Color(0x108DAFBD),
                                                              Colors.transparent,
                                                            ],
                                                            stops: [0, 0.48, 1],
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  Center(
                                                    child: Column(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .center,
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Icon(
                                                          Icons
                                                              .power_settings_new_rounded,
                                                          size: 50,
                                                          color: accent,
                                                        ),
                                                        const SizedBox(
                                                          height: 10,
                                                        ),
                                                        LocalizedText(
                                                          actionLabel,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: TextStyle(
                                                            color: Colors.white
                                                                .withValues(
                                                                  alpha: 0.94,
                                                                ),
                                                            fontSize: 15,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                          ),
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
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        _ConnectionStatsCard(
                          isDark: isDark,
                          connected: connected,
                          ping: provider.currentPing,
                          pingFailed: provider.pingFailed,
                          pinging: provider.xrayPinging,
                          awaitingFirstPing: provider.xrayPingAwaitingFirstTap,
                          protocol: provider.selectedProtocol,
                          connectionGeneration:
                              provider.simpleConnectionGeneration,
                          onPingTap:
                              const {
                                'xray',
                                'mix',
                                'warp',
                              }.contains(provider.selectedProtocol)
                              ? () => unawaited(provider.manualXrayPing())
                              : null,
                          download: provider.downloadDataUsage,
                          upload: provider.uploadDataUsage,
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
