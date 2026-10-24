# 4win VPN

**4win VPN** is a Flutter-based Android VPN client. Its connection UI and shared application state are written in Dart; the VPN engines and Android system-VPN integration use native Android services and bundled or locally built native cores.

> **Platform scope:** The VPN implementations documented here target **Android**. The repository contains Flutter scaffolding for other platforms, but that does not imply equivalent VPN functionality or support on iOS, desktop, or web.

- Android application ID: `com.forwin.vpn`
- Flutter package name: `vpn_swift` (historical name)
- App version: maintained in [`pubspec.yaml`](pubspec.yaml)
- Source repository: [4win-official/4win-VPN-Source](https://github.com/4win-official/4win-VPN-Source)
- Android releases: [4win-official/4win-VPN/releases](https://github.com/4win-official/4win-VPN/releases)
- Minimum Android API: 24 (Android 7.0), subject to the Flutter toolchain's own minimum.

## Features

- Eight standalone connection methods: Xray, Psiphon, Cloudflare WARP, OpenVPN, SSTP, DNS Changer, Proxy, and Slow DNS. **Mix** is an additional beta mode for ordered multi-hop strategies.
- Import and manage server links, proxy endpoints, OpenVPN profiles, DNS servers, and Slow DNS configurations.
- Xray and Proxy subscription groups, server latency tests, and fastest-working-server selection when a group is selected.
- Mix strategies can chain supported protocol and DNS blocks in a chosen order; see [Mix limitations and implementation notes](docs/MIX.md).
- Per-app include/exclude split tunneling in supported standalone Android VPN services. Support is service-specific; Mix has separate routing behavior.
- An optional kill switch for **standalone Psiphon mode**: when enabled, a Psiphon failure holds a blackhole VPN interface and retries rather than restoring ordinary traffic.
- VPN mode and local-proxy mode. Xray, Proxy, and WARP can expose a local proxy at `127.0.0.1:4444`; all other protocols, plus Mix, require system VPN mode.
- Connection status and traffic statistics, connection logs, and an in-app Android update checker.
- DNS scanner, first-run guide, and appearance options including System, Liquid Glass, Pixel, Pink, Rain, Snow, Summer (Day & Night), Autumn, and Cat themes.

## Standalone connection methods

| Method | What it does | Configuration / notes |
|---|---|---|
| **Xray** | Connects through the bundled Xray core, with optional TLS ClientHello fragmentation. | VLESS, VMess, Trojan, and Shadowsocks share links; individual servers or subscription groups. |
| **Psiphon** | Runs the native Psiphon tunnel service with automatic egress selection. | Native Android integration; the optional kill switch applies to standalone Psiphon mode. |
| **WARP** | Connects to Cloudflare WARP using the app's native Aether/WireGuard data plane. | Registers a device identity with Cloudflare on first use; its private key is generated and kept on-device. |
| **OpenVPN** | Connects using an imported OpenVPN client profile. | Import `.ovpn` profiles; credentials may be included in the profile or entered in the app. The profile selects its transport, such as TCP or UDP. |
| **SSTP** | Connects using Secure Socket Tunneling Protocol. | Uses the app's server list or a custom server configured in settings. |
| **DNS Changer** | Changes DNS handling through an Android VPN interface; it is not a general-purpose full-tunnel protocol. | Select a DNS server from the app's DNS list. |
| **Proxy** | Routes traffic through an upstream SOCKS4, SOCKS5, or HTTP proxy. | Add a proxy link or endpoint, or import a subscription. Offers a TCP latency test and an open-site test through the proxy. |
| **Slow DNS** | Standalone dnstt TCP tunnel over UDP DNS, DoT, or DoH. | Requires a delegated domain, server public key, and remote SOCKS5 endpoint. DNS is tunneled over TCP; other UDP is blocked. Scanner results are candidates, not authenticated tunnel verification. Excluded from Mix. See [Slow DNS setup and limitations](docs/SLOW_DNS.md). |

## Mix (beta)

Mix is a separate, ordered multi-hop system-VPN mode. It creates one Android VPN interface and routes the chain from the phone through the blocks in the order shown in the strategy; it does not start multiple independent Android VPNs. Supported blocks are Xray, Proxy, WARP, SSTP, OpenVPN, Psiphon, and DNS. Slow DNS is standalone only. Strategies may repeat protocols and contain up to 50 blocks (including DNS blocks, excluding the fixed Start block).

The app tests the complete chain before reporting a successful connection. It does not silently remove a failed hop or fall back to a direct connection. A supported configuration is not proof that every provider, server, or ordering will work: **the Psiphon → WARP direction remains unverified in the documented live tests**. UDP support also depends on the chosen upstreams; an optional UDP-over-TLS relay is not enabled automatically. Mix requires VPN mode and is not covered by the standalone Psiphon kill switch. See [the detailed Mix documentation](docs/MIX.md) for ordering, DNS behavior, transport limits, and current test status.

### Server and profile formats

- **Xray:** `vless://`, `vmess://`, `trojan://`, and `ss://` links, including supported encrypted `4ws://` share links. HTTP(S) subscription URLs can be organized into named groups.
- **Proxy:** `socks4://`, `socks5://`, `socks://`, and `http://` links, as well as supported `host:port` entries and HTTP(S) subscription URLs.
- **OpenVPN:** Import an `.ovpn` profile from the device or open/share a profile to 4win VPN. If credentials are not embedded, enter them in the app.
- **SSTP, DNS Changer, and Slow DNS:** Use the protocol's in-app server/configuration list and settings.

For Xray and Proxy, selecting a group lets the app test its endpoints and choose a working, low-latency server for the connection. Individual server/profile tests are also available where provided by that protocol's screen. Latency results depend on the network and test endpoint; they are not a guarantee of throughput or availability.

## Security and behavior notes

- **Kill switch scope:** The setting protects the standalone Psiphon tunnel path only. Do not treat it as a system-wide kill switch for OpenVPN, SSTP, Xray, WARP, Proxy, DNS Changer, Slow DNS, or Mix.
- **Split tunneling:** The standalone Android services for Xray/WARP, Psiphon, DNS Changer, and Slow DNS apply the app's include/exclude rules. Reconnect after changing the selection. Mix uses its own chain routing and should not be assumed to inherit the same app-selection behavior; see [docs/MIX.md](docs/MIX.md).
- **Local proxy mode:** This exposes a loopback proxy on the device, not a system-wide VPN tunnel. Use VPN mode when you want device traffic routed through Android's VPN interface. Mix requires VPN mode.
- **Secret Text:** This is a reversible obfuscation helper for casual sharing, **not audited cryptographic encryption** and not appropriate for passwords, private keys, or other sensitive information.
- **WARP registration:** First-time WARP setup contacts Cloudflare's registration API. The app generates the WireGuard key pair locally and sends the public key for registration.

## Build from source

### Requirements

- Flutter stable with a Dart SDK satisfying the constraint in [`pubspec.yaml`](pubspec.yaml) (`^3.9.2`). The primary Android build workflow pins Flutter `3.47.3`.
- Android SDK and NDK, CMake `3.22.1`, and JDK 17. The Aether helper prefers NDK `26.3.11579264` when installed and can fall back to another installed NDK.
- Rust `1.91` or newer, the Android Rust targets, and `cargo-ndk` to build Aether for WARP and Mix.
- Python 3 and Go `1.21` or newer. Android Gradle tasks use Python for native dependency processing and Go to build the standalone Slow DNS executable.
- Network access on the first build to fetch Flutter/Rust dependencies and the checksum-pinned Slow DNS source.

Install Rust and the Android targets used by the universal build, then install `cargo-ndk`:

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

# Build Aether for all four ABIs included in the universal APK.
for abi in arm64-v8a armeabi-v7a x86_64 x86; do
  bash core/build-android.sh --abi "$abi"
done

flutter build apk --release
```

The Aether script expects the Android SDK/NDK and CMake to be installed and discoverable. The Gradle build automatically instruments the OpenVPN AAR, relocates the Psiphon bridge, trims unused Xray AAR data, and builds the checksum-pinned Slow DNS executable for Android. Python 3, Java/JDK tools, Go 1.21+, and the Android NDK must be available on `PATH` or through the Android SDK configuration. The first build also needs network access for dependencies and the Slow DNS source archive.

On Windows, the repository provides [`core/build-android.ps1`](core/build-android.ps1) for Aether, but its ABI list covers `arm64-v8a`, `armeabi-v7a`, and `x86_64` only; it does not build the `x86` ABI. The Bash helper supports all four ABIs.

The release APK is written to:

```text
build/app/outputs/flutter-apk/app-release.apk
```

## Tests and analysis

Fetch dependencies, run the Dart/Flutter tests, and optionally run static analysis:

```bash
flutter pub get
flutter test
flutter analyze
```

The test suite covers protocol configuration and link/profile parsing (including Xray, OpenVPN, Proxy, and Slow DNS), Mix strategies and chain planning, DNS scanning, connection/state handling, and widget/theme behavior. The device/emulator smoke test is `flutter test integration_test/app_smoke_test.dart`; it checks that the app starts but intentionally does **not** request VPN permission or establish a tunnel. JVM, native, and live-chain checks have additional prerequisites and are documented in [docs/MIX.md](docs/MIX.md) and [docs/SLOW_DNS.md](docs/SLOW_DNS.md). Passing unit tests does not verify VPN behavior on an Android device or on a particular network.

## CI workflows

The root GitHub Actions workflows are manually dispatched; they are not automatic push/PR checks.

- [Flutter Tests](.github/workflows/flutter-test.yml) runs `flutter test` and uploads its output. Its static-analysis step is explicitly non-blocking.
- [Android Build](.github/workflows/android-build.yml) uses JDK 17 and Flutter `3.47.3`, builds Aether for all four Android ABIs, then builds and verifies a universal APK. It uploads the APK as a workflow artifact; it does **not** publish a GitHub Release.
- [Build Android APK](.github/workflows/build-android-apk.yml) is another manual APK job. It invokes `flutter build apk --release` but does not build Aether first. Since generated `libaether.so` files are not tracked in the source tree, this job needs those native libraries to be supplied or built beforehand; use **Android Build** for the clean-checkout all-ABI build path.

## Project layout

```text
lib/
├── main.dart                  # Flutter entry point
├── models/                    # VPN profiles, server models, and Mix strategies
├── providers/                 # Application state and connection orchestration
├── screens/                   # Home, settings, protocol, Mix, logs, and tools UI
├── services/                  # Protocol services, persistence, parsing, updates
└── widgets/                   # Shared controls, protocol picker, animations

android/app/src/main/kotlin/com/forwin/vpn/
├── MainActivity.kt             # Flutter method-channel bridges
├── XrayVpnService.kt           # Xray and WARP Android VPN service
├── XrayProxyService.kt         # Local-proxy foreground service
├── PsiphonVpnService.kt        # Psiphon Android VPN service
├── DnsVpnService.kt            # DNS Changer Android VPN service
├── SplitTunnel.kt              # Per-app routing rules for supported services
├── mix/                        # Mix coordinator, workers, and protocol adapters
└── slowdns/                    # Standalone Slow DNS service/configuration

android/app/src/main/cpp/       # JNI bridges for native cores and Mix packets
core/aether/                    # Rust native core used by WARP and Mix
core/build-android.sh           # Build Aether for one Android ABI

docs/MIX.md                     # Mix design, limitations, and test status
docs/SLOW_DNS.md                # Slow DNS setup, scanner, and limitations
test/                           # Flutter unit and widget tests
integration_test/                # Device/emulator smoke test
```

Important Dart files include [`lib/providers/vpn_provider.dart`](lib/providers/vpn_provider.dart) for shared connection state and coordination, [`lib/providers/mix_provider.dart`](lib/providers/mix_provider.dart) for Mix state, and `lib/services/` for protocol implementations. The Android build configuration is in [`android/app/build.gradle.kts`](android/app/build.gradle.kts).

## Releases and updates

The in-app updater checks the latest GitHub release, downloads an Android APK asset when one is available, and opens the Android installer flow. Release builds are published separately from this source repository at [4win-official/4win-VPN/releases](https://github.com/4win-official/4win-VPN/releases). The Android Actions workflow described above uploads an artifact; it does not create that release.

## License

No root-level open-source license is provided for the 4win VPN application source. All rights are reserved by the project unless stated otherwise. Third-party and vendored components retain their own licenses; see their included license and notice files, including [`core/LICENSE`](core/LICENSE).
