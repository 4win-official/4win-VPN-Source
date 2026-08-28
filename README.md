# 🌐 4win VPN — Multi-Protocol VPN Client

<div align="center">

![Version](https://img.shields.io/badge/version-1.4.7%2B26-blue)
![Platform](https://img.shields.io/badge/platform-Android-green)
![Flutter](https://img.shields.io/badge/Flutter-3.44.1-02569B?logo=flutter)
![Dart](https://img.shields.io/badge/Dart-3.12.1-0175C2?logo=dart)
![License](https://img.shields.io/badge/license-Private-red)

**A fast, secure and beautiful multi-protocol VPN client for Android.**

[Features](#-features) • [Protocols](#-supported-protocols) • [Themes](#-themes) • [Build](#-build-from-source) • [Structure](#️-project-structure)

</div>

---

## 📱 Overview

**4win VPN** (`com.forwin.vpn`) is a modern VPN client built with Flutter. It
bundles several tunnelling technologies behind one clean interface so a user can
pick whichever works best on their network — from classic **SSTP** and
**OpenVPN**, through **Xray** (VLESS / VMess / Trojan / Shadowsocks) with TLS
fragmentation, all the way to a direct **SOCKS4 / SOCKS5 / HTTP proxy** mode.

It ships with automatic fastest-server selection, subscription-link support,
per-app **split tunneling**, a kill switch, live traffic stats, and a set of
animated themes.

> The Flutter/Dart package is named `vpn_swift` for historical reasons; the
> shipping application is **4win VPN** with the application id `com.forwin.vpn`.

---

## ✨ Features

### 🔐 Connectivity & Security
- **Six connection methods** — SSTP, DNS Changer, OpenVPN (TCP/UDP), Slow DNS,
  Xray, and a real SOCKS/HTTP Proxy protocol.
- **Automatic server selection** — connect to the fastest server in a group.
- **Real delay testing** — servers are ranked by actually opening a test URL
  through them, with configurable concurrency.
- **Subscription links** — paste a subscription URL and the app fetches, decodes
  and keeps your server list updated (Xray & Proxy).
- **Split tunneling** — choose which apps use the VPN (include mode) or which
  apps bypass it (exclude mode).
- **Kill switch** — block all traffic if the tunnel drops so nothing leaks.
- **Xray fragment** — real TLS ClientHello fragmentation to defeat DPI.
- **Connection mode (Xray)** — run as a full system VPN, or as a local proxy on
  `127.0.0.1:4444` with no VPN key icon.

### 🧰 Tools
- **Secret Text** — encode / decode text so only 4win VPN can read it.
- **DNS scanner** — find working DNS servers.
- **In-app updater** — checks GitHub Releases and installs new versions.
- **First-run guide** — a full walkthrough of every part of the app.

### 🎨 User Experience
- Material Design 3, dark & light modes.
- Live upload / download speed, session duration and total data usage.
- Animated themes (see below).

---

## 🔌 Supported Protocols

| Protocol       | Description                                                            |
|----------------|------------------------------------------------------------------------|
| **SSTP**       | Secure Socket Tunneling Protocol — robust on restrictive networks.     |
| **DNS Changer**| Routes only DNS through the tunnel to bypass DNS-level blocks.          |
| **OpenVPN**    | Industry standard, import your own `.ovpn` / `.conf` configs (TCP/UDP).|
| **Slow DNS**   | Tunnels traffic over DNS when everything else is blocked.              |
| **Xray**       | VLESS / VMess / Trojan / Shadowsocks via the Xray core, with fragment. |
| **Proxy**      | Direct connection through a real **SOCKS4 / SOCKS5 / HTTP** proxy.      |

### Proxy protocol
- Add proxies as links (`socks5://`, `socks4://`, `http://…`), as `host:port`,
  `host:port:user:pass`, or via a subscription link.
- **Two test types per proxy:** a quick TCP **ping test**, and an **open-site
  test** that actually loads a website through the proxy to prove it works.
- Copy or delete any proxy; the UI mirrors the Xray server screen.
- Real upstream connection is built on the Xray core (`socks` / `http` outbound).

---

## 🎨 Themes

Open the **palette icon** at the top of the home screen.

- **System Default** — light/dark, with its own settings gear to set a **custom
  background image** (separate picture for day and night).
- **Liquid Glass** 🫧 — modern frosted-glass look (light + dark).
- **Pixel** 🎮 — retro 8-bit style (light + dark).
- **Pink** 💕 — cute pink theme with day & night versions (colourful hearts burst
  from the power button on connect).
- **Seasonal Themes** group:
  - **Rain** 🌧️ (dark only) · **Snow** ❄️ (dark only) ·
    **Summer** ☀️ (light only, shining sun) · **Autumn** 🍂 (falling leaves).

---

## 📦 Build from Source

### Prerequisites
- **Flutter** 3.44.1 (stable)
- **Dart** 3.12.1
- **Android SDK** (compile/target API per `android/app/build.gradle.kts`)
- **JDK** 17

### Steps

```bash
# Clone
git clone https://github.com/4win-official/4win-VPN-Source.git
cd 4win-VPN-Source

# Dependencies
flutter pub get

# Universal release APK (all ABIs)
flutter build apk --release

# (Optional) Play Store bundle
flutter build appbundle --release
```

### Output
- **APK:** `build/app/outputs/flutter-apk/app-release.apk`
- **Bundle:** `build/app/outputs/bundle/release/app-release.aab`

> The auto-update feature downloads release APKs from the separate releases repo:
> `https://github.com/4win-official/4win-VPN/releases`.

---

## 🏗️ Project Structure

```
lib/
├── main.dart                          # App entry point
├── models/                            # Data models
│   ├── vpn_server.dart                # SSTP server
│   ├── dns_server.dart                # DNS server
│   ├── openvpn_config.dart            # OpenVPN config
│   ├── slowdns_config.dart            # Slow DNS config
│   ├── xray_server.dart               # Xray server (vmess/vless/trojan/ss)
│   └── proxy_server.dart              # Proxy server (socks4/socks5/http)
├── providers/                         # State management (ChangeNotifier)
│   ├── vpn_provider.dart              # Connection state + all protocols
│   └── theme_provider.dart            # Theme & day/night state
├── screens/                           # UI screens
│   ├── home_screen.dart               # Main screen
│   ├── settings_screen.dart           # Per-protocol & general settings
│   ├── theme_selection_screen.dart    # Theme picker
│   ├── default_theme_settings_screen.dart # Default-theme background picker
│   ├── split_tunnel_screen.dart       # Per-app split tunneling
│   ├── guide_screen.dart              # First-run walkthrough
│   ├── xray_servers_screen.dart       # Xray server list
│   ├── proxy_servers_screen.dart      # Proxy server list
│   ├── dns_servers_screen.dart        # DNS servers
│   ├── openvpn_configs_screen.dart    # OpenVPN configs
│   ├── slowdns_configs_screen.dart    # Slow DNS configs
│   └── secret_text_screen.dart        # Secret Text tool
├── services/                          # Backend / core integration
│   ├── vpn_service.dart               # SSTP
│   ├── dns_service.dart               # DNS Changer
│   ├── openvpn_connection.dart        # OpenVPN
│   ├── slowdns_service.dart           # Slow DNS
│   ├── xray_connection.dart           # Xray core controller
│   ├── xray_config_builder.dart       # Builds Xray configs (incl. proxy)
│   ├── proxy_service.dart             # Proxy server / subscription manager
│   ├── update_service.dart            # In-app updater
│   └── secret_text_cipher.dart        # Secret Text encryption
└── widgets/                           # Reusable widgets & animations
    ├── rain_animation.dart            # Rain theme
    ├── snow_animation.dart            # Snow theme
    ├── summer_animation.dart          # Summer sun theme
    ├── autumn_animation.dart          # Autumn falling-leaves theme
    ├── pixel_effect.dart              # Pixel theme
    ├── protocol_selector_dialog.dart  # Protocol picker
    └── rainbow_heart_button.dart      # Animated support/donate button

android/app/src/main/kotlin/com/forwin/vpn/
├── MainActivity.kt                    # Method channels (incl. installed apps)
├── XrayVpnService.kt                  # Xray VpnService (TUN)
├── XrayProxyService.kt               # Xray local-proxy foreground service
├── DnsVpnService.kt                   # DNS Changer VpnService
└── SplitTunnel.kt                     # Applies per-app split tunneling
```

---

## 🔧 OpenVPN Configs

Supported formats: `.ovpn`, `.conf`, `.open`. Credentials can be embedded
(`<auth-user-pass>`) or entered manually. The app auto-adds sane defaults
(Google DNS, `persist-key`, `persist-tun`, `nobind`, retry options for TCP) when
they are missing.

---

## 📊 Key Dependencies

```yaml
provider                # State management
shared_preferences      # Local settings storage
sstp_flutter            # SSTP protocol
openvpn_flutter         # OpenVPN protocol
connectivity_plus       # Network status
http                    # Subscriptions / updates / tests
file_picker             # Import .ovpn configs
image_picker            # Custom theme background
url_launcher            # Open links
permission_handler      # VPN / storage permissions
path_provider           # App storage paths
```

Xray is integrated natively through the bundled `libv2ray` (AndroidLibXrayLite)
core.

---

## 📄 License

Private / proprietary. All rights reserved by the 4win VPN project.
