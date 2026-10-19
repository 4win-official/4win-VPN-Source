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

## Profile form and reference compatibility

`Add Config` opens a full, scrollable **Add Slow DNS Profile** page. It requests **Profile Name**, **Domain**, the server's **Public Key** (64 hex characters), **DNS Transport**, and **DNS Resolver** (`host[:port]`, IPv4 or hostname only; IPv6 is intentionally unsupported). DoH requests an HTTPS resolver URL instead. Existing saved profiles remain compatible: resolver host and port are still stored separately. UDP defaults to 53 and DoT to 853; explicitly chosen nonstandard ports are preserved when switching transport.

The resolver scan icon and **Scan for Working Resolvers** button carry the tunnel domain and UDP port into the scanner, then return the selected IP and scan port to the still-open form. No incomplete profile needs to be saved first. The scanner checks plaintext DNS capabilities, not encrypted resolver identity, so navigation is disabled for DoT/DoH rather than silently downgrading them. Advanced failover resolvers retain the existing ordered behavior and common port (up to 31 additional bare addresses). Optional credentials authenticate the remote SOCKS5 endpoint and are validated in UTF-8 bytes.

The full official workflow, including the fields below the supplied screenshot, was reviewed against [the user guide](https://github.com/anonvector/SlipNet/blob/552ab5078d90ae84294fcd6ef649b8e023ba2a63/docs/USER_GUIDE.md), [profile editing](https://github.com/anonvector/SlipNet/blob/552ab5078d90ae84294fcd6ef649b8e023ba2a63/app/src/main/java/app/slipnet/presentation/profiles/EditProfileViewModel.kt), and [scanner state](https://github.com/anonvector/SlipNet/blob/552ab5078d90ae84294fcd6ef649b8e023ba2a63/app/src/main/java/app/slipnet/presentation/scanner/DnsScannerViewModel.kt). This is an independent functional adaptation, not a source transplant or license change.

**Not feature parity:** SlipNet also offers TCP resolver transport, authoritative polling, custom query payload size, auto-tuning, round-robin/fanout and spread settings, keep-alive tuning, and DNSTT + SSH (SSH host/port, username, password or PEM key and optional passphrase). The pinned original dnstt executable exposes none of those tuning/TCP flags, and this app has no SSH chaining engine. The form explicitly marks TCP, authoritative mode, custom query size and SSH as unavailable rather than collecting ineffective settings. The app manages the local proxy address and port. Remaining options need separate engine/SSH integration and validation; copying SlipNet's AGPL implementation would require the owner's informed licensing decision first.

SlipNet's scanner additionally supports Simple/E2E/Prism verification, bundled country/IR datasets, scan persistence and multi-selection. This app remains a bounded capability scanner with single-resolver profile selection, collected candidate results and TXT/JSON export. It has offline operator snapshots and user-provided ranges, but does not claim E2E/Prism verification, a bundled country database or a 58,845-entry resolver list.

## Scanner

The scanner's editable **Test domain or IPv4** defaults to `google.com` (or the profile domain when launched from its form). A domain is tested with an actual **A lookup**; an IPv4 test target is converted to its reversed **PTR lookup** under `in-addr.arpa`. A positive answer is required to qualify as a candidate. An IP without a PTR record does not qualify, even if a resolver otherwise responds. IPv6, URLs and malformed names are rejected before scanning. This is a DNS test, not ping, HTTP, or proof that a website opens.

The scanner also sends TXT DNS capability queries with EDNS, verifies response framing, transaction ID, peer, question, flags and record bounds, and probes random names under reserved `.invalid` for unexpected positive answers. TCP results require a full DNS response, not merely an open port.

EDNS and safe NXDOMAIN responses identify candidates, not an authenticated tunnel or a censorship guarantee. Advertised EDNS size is not a measured path MTU. A timeout is unknown, not proof of hijacking. The selected server is checked end to end during connection using SOCKS5 negotiation and a DNS-over-TCP query through dnstt.

Offline country-range lists can be imported/pasted as CIDRs or IPs. No built-in country-allocation database or automatic geolocation is claimed. Scan expansion is capped at 200,000 unique targets and native concurrency is bounded. Cancellation stops after the current bounded wave; it never schedules another wave.

The scanner presents exactly two discovery methods: **operator IPv4 ranges** and **random public IPv4** when no range is available. Operator mode has a named source selector for **MCI / همراه اول (AS197207)**, **Irancell / ایرانسل (AS44244)**, and **Custom IPv4 ranges**. Custom mode preserves From/To, pasted CIDRs/IPs and file import; switching to a preset does not erase custom input. Random mode generates unique public IPv4 addresses and uses the same DNS capability probes, without quietly substituting the built-in public DNS list. IPv6 remains excluded at both Dart and native scanner boundaries; unrelated protocols are unchanged.

Built-in operator ranges are a bundled offline snapshot from [RIPE NCC's Announced Prefixes API](https://stat.ripe.net/docs/02.data-api/announced-prefixes.html), not invented allocations or a list of working resolvers. The sources are [AS197207](https://stat.ripe.net/data/announced-prefixes/data.json?resource=AS197207) and [AS44244](https://stat.ripe.net/data/announced-prefixes/data.json?resource=AS44244). The API defaults to a two-week observation window and a minimum of 10 observing peers: only IPv4 announcements whose timelines include the returned query end time are bundled. Overlapping announcements are merged before counting addresses. The UI shows the source URL, snapshot date, unique announced address count, batch size, and number of batches. These routing observations do not guarantee complete carrier ownership, visibility of local/private DNS, current routing, or usable DNS service.

The bundled snapshot ends at **2026-10-19 00:00 UTC**. MCI has **796** visible IPv4 announcements collapsed to **65** prefixes and **2,301,440** unique addresses (**12** batches; last **101,440**). Irancell has **394** visible IPv4 announcements collapsed to **12** prefixes and **1,231,872** unique addresses (**7** batches; last **31,872**). The full two-week MCI response contains 846 IPv4 entries, but those no longer visible at the snapshot endpoint are deliberately excluded; treating all historical entries as currently announced would overstate coverage. These are dataset counts, not addresses tested or working resolvers found.

Each built-in batch contains at most **200,000** disjoint, numerically ordered IPv4 addresses from the merged union, including every numeric address in that union rather than silently omitting per-prefix network/broadcast values. Users explicitly choose another batch to continue. A single scan never claims complete operator coverage; batches do not auto-run, selection/progress is not persisted, and restarting a batch repeats it. Shuffle changes only the order within the chosen batch. Nearby `/24` expansion is disabled for presets so it cannot spill outside the chosen batch or announced space. Presets work offline; there is no runtime automatic refresh. Maintainers can regenerate the snapshot with `python3 tools/update_operator_ipv4.py` and rebuild the app; `--input-dir` supports saved API fixtures.

Custom ranges may include local/private resolvers. They retain the existing cap of the first 200,000 unique expanded addresses, with an explicit warning before and alongside scan results; shuffle does not sample beyond this cap. Oversized custom input is not an exhaustive scan, and there is no automatic continuation for it. Random mode is explicitly a bounded sample and never claims an exhaustive Internet scan. Result progress reports only the queued batch/sample, and a DNS candidate still requires authenticated tunnel verification during connection.

Configuration exposes the actual scan **Port**, **Timeout per probe**, and **Workers** (1–64), plus shuffle and optional nearby discovery for custom range/imported sources only. Nearby discovery enqueues all 256 addresses in a candidate's `/24` only after a safe candidate is found, deduplicates already queued addresses/subnets, shares the 200,000-target cap, and obeys cancellation. The progress total may grow as neighbours are discovered. DNS capability success is still not proof that the user's authenticated DNSTT tunnel or internet egress works.

All responding resolvers remain visible together; only candidates with successful UDP target resolution, EDNS and safe UDP NXDOMAIN checks can be selected or exported. **Copy all candidates** copies newline-separated `IPv4:port` endpoints. **Export TXT** saves the same list; **Export JSON** saves candidate capability/latency fields and the test target, query mode, port, timeout and worker settings used for that scan. Exports never claim tunnel verification. Settings edited after completion do not relabel old results. Bulk actions become available after completion or cancellation; cancelling preserves candidates from completed waves and marks the JSON as cancelled. Save-dialog cancellation is not reported as a successful export, and save failures are shown without discarding results. The system save dialog chooses the destination; no broad storage permission is required.

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
