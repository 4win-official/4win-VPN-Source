# Standalone Slow DNS

Slow DNS is independent of Mix. It does not change Psiphon, WARP, or the unresolved Psiphon → WARP chain.

## Why the old implementation was unsafe

The previous Dart handler waited 350 milliseconds, selected a resolver and reported success without a DNS tunnel, Android VPN interface or authenticated server connection. DNS responsiveness alone cannot establish tunnel readiness.

## Official SlipNet reference

The owner requested the [official SlipNet repository](https://github.com/anonvector/SlipNet). The reviewed revision is `552ab5078d90ae84294fcd6ef649b8e023ba2a63`. Its README distinguishes DNSTT, NoizDNS, VayDNS and Slipstream and describes EDNS probing, NXDOMAIN hijacking detection and country-range scanning.

The reference files are `app/src/main/java/app/slipnet/data/repository/ResolverScannerRepositoryImpl.kt`, `tunnel/DnsttBridge.kt`, `data/repository/VpnRepositoryImpl.kt` and `service/SlipNetVpnService.kt`. They informed the separation between resolver capability checks, tunnel authentication, application-UID exclusion and lifecycle cleanup. No SlipNet implementation code is copied: SlipNet is AGPL-3.0, while the app README reserves rights to the application source. This change does not relicense the app or claim full SlipNet feature parity.

The executable uses the [original dnstt implementation](https://www.bamsoftware.com/software/dnstt/) (CC0), version `20260501`, revision `0c5c52a57d899c05428c116898941761a2ed83c2`. The official source archive SHA-256 is `a7b21d3d787570d9127643e360e150d2da7b33aa8039d0546a04dcfe8ee1864f`.

## Server requirements and supported traffic

A profile needs a delegated tunnel domain, its server's 64-hex public key and a reachable recursive DNS resolver. The dnstt server must forward to a SOCKS5 endpoint. Optional username/password fields authenticate that remote SOCKS5 endpoint, not SSH.

UDP DNS, DoT and DoH are transports for this one dnstt protocol, not separate tunnel engines. DoH uses its HTTPS URL and never silently falls back to plaintext DNS. NoizDNS, VayDNS, Slipstream and SSH chaining are not implemented here.

Application TCP travels through the authenticated tunnel. The packet bridge converts captured DNS to TCP inside the tunnel. Other application UDP, including QUIC, is blocked, not sent directly. Applications need TCP fallback.

The VPN app UID is excluded to keep its dnstt child sockets outside its own TUN; other captured apps have no direct outbound. Include-mode split tunneling requires at least one installed application other than this VPN app.

## Scanner

The scanner sends actual TXT DNS queries with EDNS, verifies response framing, transaction ID, peer, question, flags and record bounds, and probes random names under reserved `.invalid` for unexpected positive answers. TCP results require a full DNS response, not merely an open port.

EDNS and safe NXDOMAIN responses identify candidates, not an authenticated tunnel or a censorship guarantee. Advertised EDNS size is not a measured path MTU. A timeout is unknown, not proof of hijacking. The selected server is checked end to end during connection using SOCKS5 negotiation and a DNS-over-TCP query through dnstt.

Offline country-range lists can be imported/pasted as CIDRs or IPs. No built-in country-allocation database or automatic geolocation is claimed. Scan expansion is capped at 200,000 unique targets and native concurrency is bounded. Cancellation stops after the current bounded wave; it never schedules another wave.

## Build and validation

Gradle `buildSlowDns` downloads the checksum-pinned source into ignored `build/`, uses the Android NDK and Go, and produces PIE executables named `libdnstt.so` for all four existing ABIs. Legacy native-library extraction is required: Android executes dnstt only from the installed native library directory, never from writable application storage. dnstt has a separate process/runtime; no third gomobile runtime is loaded into the app.

The first build needs Go 1.21 or later, Python 3, the Android NDK and network access for source/modules. Generated binaries and Go dependency files stay in ignored build caches. The upstream source and its `COPYING` accompany the build cache; distribution must retain applicable third-party notices.

Unit tests cover configuration, DNS parsing, capability results, SOCKS5 data-plane checks, cancellation and false-readiness regressions. Local integration tests can verify real dnstt client/server streams without scanning public address ranges. These are not a replacement for testing the installed APK on Android and under the intended censored network.

The [Xray DNS outbound documentation](https://xtls.github.io/en/config/outbounds/dns.html) describes DNS transport/address rewriting; forwarding must remain chained to the Slow DNS outbound, with no `freedom` fallback.

## Reproducing the checks

Run `flutter test --no-pub` for Flutter model, connection lifecycle, cancellation, scanner UI and existing-protocol regressions. Run `gradle -p android :app:testDebugUnitTest` for the JVM suite, including real loopback UDP/TCP DNS fixtures and malformed-response rejection.

After `tools/build_slowdns.py` has cached the pinned source, run `python3 tools/test_slowdns_live.py --xray /path/to/linux/xray`. Add `--no-build` to reuse its ignored native test binaries. This finite loopback-only test covers encrypted TCP, RFC1929 authentication, framed DNS-over-TCP, complete A and TXT DNS replies through Xray, non-DNS UDP blocking, a wrong real server key, a dead resolver, and server shutdown. It contacts no public DNS service: the fixture maps `1.1.1.1:53` to its own local TCP server.

The remote SOCKS5 endpoint must permit TCP DNS to `1.1.1.1:53`; the connection probe uses an `example.com` A query through that endpoint. Arbitrary UDP applications are intentionally unsupported rather than silently bypassed.

A full APK also requires the existing Aether native libraries for every packaged ABI, built by `core/build-android.sh` as in the existing Android CI workflow. If `libaether.so` is absent, CMake stops before APK packaging; do not replace it with a stub or change other protocols to bypass this prerequisite. Successful JVM/Linux loopback tests do not replace Android device tests of VPN permission, TUN routing, executable extraction, or behavior on the intended filtered network. These device/network checks remain necessary before calling this production-verified.
