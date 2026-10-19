import 'package:flutter/material.dart';

/// A comprehensive in-app guide shown to new users on first launch (and any
/// time from the "?" icon on the home screen). It explains every major part of
/// 4win VPN section by section: connecting, protocols, servers, subscriptions,
/// the proxy protocol, split tunneling, themes, settings, tools and updates.
class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? const Color(0xFF00FF88) : const Color(0xFF4CAF50);
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white60 : Colors.black54;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF000000) : Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Quick Guide',
          style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SizedBox(height: 8),
            Icon(Icons.lightbulb_outline, size: 56, color: accent),
            const SizedBox(height: 12),
            Text(
              'Welcome to 4win VPN',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textColor,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'A full walkthrough of everything the app can do. '
              'You can reopen this guide anytime from the "?" icon at the top.',
              textAlign: TextAlign.center,
              style: TextStyle(color: subColor, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 28),

            // 1 — Connect / disconnect
            _GuideCard(
              isDark: isDark,
              accent: accent,
              stepNumber: '1',
              title: 'Connect & disconnect',
              description:
                  'Tap the big round power button in the middle of the home '
                  'screen to connect. Tap it again to disconnect. The colour and '
                  'the glow at the bottom of the screen show the current state: '
                  'idle, connecting, or connected. Live download / upload speed '
                  'and total data usage appear below the button while connected.',
              illustration:
                  _PowerButtonIllustration(isDark: isDark, accent: accent),
            ),
            const SizedBox(height: 20),

            // 2 — Open settings (long press)
            _GuideCard(
              isDark: isDark,
              accent: accent,
              stepNumber: '2',
              title: 'Open Settings',
              description:
                  'Press and HOLD the power button. A spinning gear appears and '
                  'takes you to the settings for the protocol you are using. The '
                  'gear icon on the protocol selector opens the same per-protocol '
                  'settings, and the top gear opens the General Settings.',
              illustration:
                  _PowerButtonIllustration(isDark: isDark, accent: accent),
            ),
            const SizedBox(height: 20),

            // 3 — Choose a protocol
            _GuideTextCard(
              isDark: isDark,
              accent: accent,
              icon: Icons.swap_vert,
              title: 'Choose a protocol',
              description:
                  'Tap the protocol name to open the protocol selector. 4win VPN '
                  'supports several ways to connect:\n\n'
                  '• SSTP — classic tunnel, good on restrictive networks.\n'
                  '• DNS Changer — changes only your DNS.\n'
                  '• OpenVPN — import .ovpn configs.\n'
                  '• Slow DNS — tunnels over DNS when everything else is blocked.\n'
                  '• Xray — VLESS / VMess / Trojan / Shadowsocks with fragment.\n'
                  '• Proxy — connect directly through a SOCKS4 / SOCKS5 / HTTP '
                  'proxy.\n\n'
                  'Each protocol has its own gear ⚙ for settings and its own '
                  'server / config list.',
            ),
            const SizedBox(height: 20),

            // 4 — Servers, testing, best server
            _GuideTextCard(
              isDark: isDark,
              accent: accent,
              icon: Icons.dns,
              title: 'Servers & speed testing',
              description:
                  'Open the server list button under the power button (for Xray '
                  'and Proxy it is the "Servers" button). You can:\n\n'
                  '• Add servers one by one, or import many at once.\n'
                  '• Test ping / delay to find the fastest server — the app can '
                  'test many servers at the same time.\n'
                  '• Pick a whole GROUP and let the app connect to the fastest '
                  'server in it, then jump to the next one with "Next".\n'
                  '• Copy or delete individual servers.\n\n'
                  'The 3-second ping shown on the home screen is a real test that '
                  'opens the delay-test URL through the active server.',
            ),
            const SizedBox(height: 20),

            // 5 — Subscription links
            _GuideTextCard(
              isDark: isDark,
              accent: accent,
              icon: Icons.link,
              title: 'Subscription links',
              description:
                  'Instead of adding servers manually you can paste a '
                  'subscription link (a URL that returns a list of servers). The '
                  'app fetches it, decodes it and keeps it updated. You can add '
                  'several subscriptions, give each one a name, refresh them, or '
                  'remove them. Works for both Xray and the Proxy protocol.',
            ),
            const SizedBox(height: 20),

            // 6 — Proxy protocol (new)
            _GuideTextCard(
              isDark: isDark,
              accent: accent,
              icon: Icons.settings_ethernet,
              title: 'Proxy protocol (SOCKS / HTTP)',
              description:
                  'The Proxy protocol connects you through a real SOCKS4, SOCKS5 '
                  'or HTTP proxy. Add proxies as links (socks5://, socks4://, '
                  'http://…), as host:port, or from a subscription link.\n\n'
                  'Each proxy in the list has TWO tests:\n'
                  '• Ping test — a quick TCP latency check to the proxy.\n'
                  '• Open-site test — actually opens a website through the proxy '
                  'to prove it really works for browsing.\n\n'
                  'You can copy or delete any proxy, and select one to connect.',
            ),
            const SizedBox(height: 20),

            // 7 — Split tunneling
            _GuideTextCard(
              isDark: isDark,
              accent: accent,
              icon: Icons.call_split,
              title: 'Split tunneling',
              description:
                  'In General Settings → Split Tunneling you choose which apps '
                  'use the VPN:\n\n'
                  '• Only selected — just the apps you pick go through the VPN, '
                  'everything else uses your normal connection.\n'
                  '• Bypass selected — the apps you pick skip the VPN, everything '
                  'else is tunnelled.\n\n'
                  'Search for apps and tick the ones you want. Reconnect for the '
                  'change to take effect.',
            ),
            const SizedBox(height: 20),

            // 8 — Themes
            _GuideCard(
              isDark: isDark,
              accent: accent,
              stepNumber: '8',
              title: 'Themes & appearance',
              description:
                  'Tap the palette icon at the top to open VPN Themes. Switch '
                  'between the day / night toggle and pick a theme: Liquid Glass, '
                  'Pixel, Pink, and the Seasonal group (Rain, Snow, Day & Night, '
                  'Autumn). Some themes use a fixed mode. The System Default '
                  'theme has its own gear ⚙ where you can set a custom '
                  'background image for day and for night.',
              illustration: _TopBarIllustration(isDark: isDark, accent: accent),
            ),
            const SizedBox(height: 20),

            // 9 — Connection mode (VPN / Proxy) - now inside Xray settings
            _GuideTextCard(
              isDark: isDark,
              accent: accent,
              icon: Icons.vpn_lock,
              title: 'Connection mode (Xray)',
              description:
                  'Inside the Xray settings you can choose the connection mode:\n\n'
                  '• VPN mode — tunnels the whole device (the system VPN key icon '
                  'appears).\n'
                  '• Proxy mode — runs a local proxy on 127.0.0.1:4444 with no '
                  'VPN icon; apps opt in by using that proxy.\n\n'
                  'Only Xray supports proxy mode; the other protocols always run '
                  'as a system VPN.',
            ),
            const SizedBox(height: 20),

            // 10 — Extra tools
            _GuideTextCard(
              isDark: isDark,
              accent: accent,
              icon: Icons.build,
              title: 'Extra tools & security',
              description:
                  '• Secret Text (lock icon) — encode/decode text so only 4win '
                  'VPN can read it.\n'
                  '• Kill Switch (Settings → Security) — blocks the internet if '
                  'the VPN drops, so nothing leaks.\n'
                  '• Refresh (↻) — reloads the server list.\n'
                  '• Fragment (Xray) — splits the TLS handshake to bypass deep '
                  'packet inspection.',
            ),
            const SizedBox(height: 20),

            // 11 — Updates
            _GuideTextCard(
              isDark: isDark,
              accent: accent,
              icon: Icons.system_update,
              title: 'Staying up to date',
              description:
                  'General Settings → Updates checks GitHub for a newer version '
                  'of 4win VPN. If one is available you can download and install '
                  'it right from the app. If you like 4win VPN, the ❤ icon at the '
                  'top opens the support / donate page.',
            ),
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: isDark ? Colors.black : Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Got it!',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// A card containing a numbered step: an illustration, a title and a description.
class _GuideCard extends StatelessWidget {
  final bool isDark;
  final Color accent;
  final String stepNumber;
  final String title;
  final String description;
  final Widget illustration;

  const _GuideCard({
    required this.isDark,
    required this.accent,
    required this.stepNumber,
    required this.title,
    required this.description,
    required this.illustration,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white60 : Colors.black54;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111111) : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: accent.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  stepNumber,
                  style: TextStyle(
                    color: isDark ? Colors.black : Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Center(child: illustration),
          const SizedBox(height: 16),
          Text(
            description,
            style: TextStyle(color: subColor, fontSize: 14, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// A text-only guide card (icon + title + longer description) for the many
/// sections that don't need a custom illustration.
class _GuideTextCard extends StatelessWidget {
  final bool isDark;
  final Color accent;
  final IconData icon;
  final String title;
  final String description;

  const _GuideTextCard({
    required this.isDark,
    required this.accent,
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white60 : Colors.black54;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111111) : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: accent.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: TextStyle(color: subColor, fontSize: 14, height: 1.45),
          ),
        ],
      ),
    );
  }
}

/// Mock of the home-screen top bar, highlighting the palette (theme) icon.
class _TopBarIllustration extends StatelessWidget {
  final bool isDark;
  final Color accent;
  const _TopBarIllustration({required this.isDark, required this.accent});

  @override
  Widget build(BuildContext context) {
    final faded = isDark ? Colors.white38 : Colors.black38;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? Colors.black : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: faded.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Text(
            '4win VPN',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.18),
              shape: BoxShape.circle,
              border: Border.all(color: accent, width: 2),
            ),
            child: Icon(Icons.palette_outlined, color: accent, size: 22),
          ),
          const SizedBox(width: 10),
          Icon(Icons.favorite_border, color: faded, size: 22),
        ],
      ),
    );
  }
}

/// Mock of the round power button with a "hold" hint and a gear overlay,
/// illustrating the long-press-to-settings gesture.
class _PowerButtonIllustration extends StatelessWidget {
  final bool isDark;
  final Color accent;
  const _PowerButtonIllustration({required this.isDark, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent,
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.4),
                    blurRadius: 20,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Icon(
                Icons.power_settings_new,
                size: 48,
                color: isDark ? Colors.black87 : Colors.white,
              ),
            ),
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Colors.black87,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.settings, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.touch_app, size: 18, color: accent),
            const SizedBox(width: 6),
            Text(
              'Press & hold',
              style: TextStyle(
                color: accent,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
