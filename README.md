# 4win VPN

**4win VPN** is a Flutter-based, multi-protocol VPN client. Its connection UI and shared application state are written in Dart; the VPN engines and Android system-VPN integration are implemented through native Android services and bundled or built native cores.

> **Platform scope:** The VPN implementations documented here target **Android**. The repository contains Flutter project scaffolding for other platforms, but that does not imply equivalent VPN functionality or support on iOS, desktop, or web.

- Android application ID: `com.forwin.vpn`
- Flutter package name: `vpn_swift` (historical name)
- App version: maintained in [`pubspec.yaml`](pubspec.yaml)
- Source repository: [4win-official/4win-VPN-Source](https://github.com/4win-official/4win-VPN-Source)
- Android releases: [4win-official/4win-VPN/releases](https://github.com/4win-official/4win-VPN/releases)
- Minimum Android API: 24 (Android 7.0), subject to the Flutter toolchain's own minimum.

## Features

- Eight connection options: Xray, Psiphon, Cloudflare WARP, OpenVPN, SSTP, DNS Changer, Proxy, and Slow DNS.
- Import and manage server links, proxy endpoints, OpenVPN profiles, DNS servers, and Slow DNS configurations.
- Xray and Proxy subscription groups, server latency tests, and fastest-working-server selection when a group is selected.
- Per-app include/exclude split tunneling for supported Android VPN services.
- An optional kill switch for **Psiphon**: when enabled, a Psiphon failure holds a blackhole VPN interface and retries rather than restoring ordinary traffic.
- VPN mode and local-proxy mode. Xray, Proxy, and WARP can expose a local proxy at `127.0.0.1:4444`; IP-tunnel protocols require VPN mode.
- Connection status and traffic statistics, connection logs, and an in-app Android update checker.
- DNS scanner, first-run guide, and appearance options including System, Liquid Glass, Pixel, Pink, Rain, Snow, Summer, and Autumn themes.

## Supported connection methods

| Method | What it does | Configuration / notes |
|---|---|---|
| **Xray** | Connects through the bundled Xray core, with optional TLS ClientHello fragmentation. | VLESS, VMess, Trojan, and Shadowsocks share links; individual servers or subscription groups. |
| **Psiphon** | Runs the native Psiphon tunnel service with automatic egress selection. | Native Android integration; the optional kill switch applies to this path. |
| **WARP** | Connects to Cloudflare WARP using the app's native Aether/WireGuard data plane. | Registers a device identity with Cloudflare on first use; its private key is generated and kept on-device. |
| **OpenVPN** | Connects using an imported OpenVPN client profile. | Import `.ovpn` profiles; credentials may be included in the profile or entered in the app. The profile selects its transport, such as TCP or UDP. |
| **SSTP** | Connects using Secure Socket Tunneling Protocol. | Uses the app's server list or a custom server configured in settings. |
| **DNS Changer** | Changes DNS handling through an Android VPN interface; it is not a general-purpose full-tunnel protocol. | Select a DNS server from the app's DNS list. |
| **Proxy** | Routes traffic through an upstream SOCKS4, SOCKS5, or HTTP proxy. | Add a proxy link or endpoint, or import a subscription. Offers a TCP latency test and an open-site test through the proxy. |
| **Slow DNS** | Standalone dnstt TCP tunnel over UDP DNS, DoT, or DoH. | Requires a delegated domain, server public key and remote SOCKS5 endpoint. DNS is tunneled over TCP; other UDP is blocked. Scanner results are candidates, not authenticated tunnel verification. Excluded from Mix. See [Slow DNS setup and limitations](docs/SLOW_DNS.md). |

### Server and profile formats

- **Xray:** `vless://`, `vmess://`, `trojan://`, and `ss://` links, including supported encrypted `4ws://` share links. HTTP(S) subscription URLs can be organized into named groups.
- **Proxy:** `socks4://`, `socks5://`, `socks://`, and `http://` links, as well as supported `host:port` entries and HTTP(S) subscription URLs.
- **OpenVPN:** Import an `.ovpn` profile from the device or open/share a profile to 4win VPN. If credentials are not embedded, enter them in the app.
- **SSTP, DNS Changer, and Slow DNS:** Use the protocol's in-app server/configuration list and settings.

For Xray and Proxy, selecting a group lets the app test its endpoints and choose a working, low-latency server for the connection. Individual server/profile tests are also available where provided by that protocol's screen. Latency results depend on the network and test endpoint; they are not a guarantee of throughput or availability.

## Security and behavior notes

- **Kill switch scope:** The setting protects the Psiphon tunnel path only. Do not treat it as a system-wide kill switch for OpenVPN, SSTP, Xray, WARP, Proxy, or DNS Changer.
- **Split tunneling:** The Android app can include selected apps in the VPN or exclude selected apps. The native Android VPN services for Xray, WARP, Psiphon, and DNS Changer apply these app-selection rules. Reconnect after changing the selection.
- **Local proxy mode:** This exposes a loopback proxy on the device, not a system-wide VPN tunnel. Use VPN mode when you want device traffic routed through Android's VPN interface.
- **Secret Text:** This is a reversible obfuscation helper for casual sharing, **not audited cryptographic encryption** and not appropriate for passwords, private keys, or other sensitive information.
- **WARP registration:** First-time WARP setup contacts Cloudflare's registration API. The app generates the WireGuard key pair locally and sends the public key for registration.

## Build from source

### Requirements

- Flutter stable with a Dart SDK satisfying the constraint in [`pubspec.yaml`](pubspec.yaml) (`^3.9.2`).
- Android SDK and Android NDK; the native Aether build uses NDK `26.3.11579264` when available and CMake `3.22.1`.
- JDK 17.
- Python 3 for the Gradle tasks that relocate the Psiphon AAR and trim the Xray AAR.
- Rust stable, the Android Rust targets, and `cargo-ndk` to build Aether for WARP.

Install the Android Rust targets and `cargo-ndk`:

```bash
rustup toolchain install stable
rustup target add \
  aarch64-linux-android \
  armv7-linux-androideabi \
  x86_64-linux-android \
  i686-linux-android
cargo install cargo-ndk --locked
```

### Build a universal Android APK

```bash
git clone https://github.com/4win-official/4win-VPN-Source.git
cd 4win-VPN-Source
flutter pub get

# Build the Aether WARP library for each ABI included in the universal APK.
for abi in arm64-v8a armeabi-v7a x86_64 x86; do
  bash core/build-android.sh --abi "$abi"
done

flutter build apk --release
```

The Aether build script expects the Android SDK/NDK and CMake to be installed and discoverable. The Gradle build performs the Psiphon bridge relocation and Xray AAR trimming automatically; Python 3 must be available on `PATH`. On Windows, the repository also provides [`core/build-android.ps1`](core/build-android.ps1) for building Aether.

The release APK is written to:

```text
build/app/outputs/flutter-apk/app-release.apk
```

The repository's Android release workflow also builds a universal APK and uploads it as a workflow artifact. See [`.github/workflows/android-build.yml`](.github/workflows/android-build.yml).

## Tests and analysis

Fetch dependencies, run the Dart/Flutter tests, and optionally run static analysis:

```bash
flutter pub get
flutter test
flutter analyze
```

The test suite covers configuration and link parsing, Xray config generation, OpenVPN profile handling, retry behavior, Secret Text encoding/decoding, connection logging, and basic widget/application startup. Native VPN behavior still needs to be verified on a compatible Android device.

## Project layout

```text
lib/
├── main.dart                  # Flutter entry point
├── models/                    # VPN server, profile, and account models
├── providers/                 # Application state and connection orchestration
├── screens/                   # Home, settings, server/config, logs, and tools UI
├── services/                  # Protocol services, persistence, parsing, updates
└── widgets/                   # Shared controls, protocol picker, animations

android/app/src/main/kotlin/com/forwin/vpn/
├── MainActivity.kt             # Flutter method-channel bridges
├── XrayVpnService.kt           # Xray and WARP Android VPN service
├── XrayProxyService.kt         # Local-proxy foreground service
├── PsiphonVpnService.kt        # Psiphon Android VPN service
├── DnsVpnService.kt            # DNS Changer Android VPN service
└── SplitTunnel.kt               # Per-app routing rules for supported services

core/aether/                    # Rust native core used by WARP
core/build-android.sh           # Build Aether for one Android ABI
test/                           # Unit and widget tests
integration_test/                # Device/emulator smoke test
```

Important Dart files include [`lib/providers/vpn_provider.dart`](lib/providers/vpn_provider.dart) for shared connection state and coordination, and `lib/services/` for individual protocol implementations. The Android build configuration is in [`android/app/build.gradle.kts`](android/app/build.gradle.kts).

## Releases and updates

The in-app updater checks the latest GitHub release, downloads an Android APK asset when one is available, and opens the Android installer flow. Release builds are published separately from this source repository at [4win-official/4win-VPN/releases](https://github.com/4win-official/4win-VPN/releases).

## License

No root-level open-source license is provided for the 4win VPN application source. All rights are reserved by the project unless stated otherwise. Third-party and vendored components retain their own licenses; see their included license and notice files, including [`core/LICENSE`](core/LICENSE).
