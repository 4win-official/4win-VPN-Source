# Psiphon VPN Integration

## Overview

Psiphon Tunnel Core (`ca.psiphon:psiphontunnel:2.0.40`, a gomobile-built Go
library) powers the app's Psiphon protocol. This document describes the
**actual** data flow and the build-time runtime isolation that keeps Psiphon's
Go runtime from crashing against Xray's Go runtime.

## Runtime isolation — the problem and the solution

### The problem

This app embeds TWO gomobile-built Go runtimes:

| runtime | Java bridge | native library |
|---|---|---|
| Xray (`libv2ray.aar` + `jniLibs`) | `go.Seq` … | `libgojni.so` |
| Psiphon (`psiphontunnel` AAR) | `go.Seq` … (same names!) | `libgojni.so` |

gomobile's `go.Seq` has a static initializer that runs
`System.loadLibrary("gojni")`, and its JNI exports (`Java_go_Seq_*`) plus the
`go/Seq` FindClass strings are baked into each `.so`. Two Go runtimes can
never live in one Android process: both `.so` files export ~90 identical
default-visibility C symbols (`main.main`, `crosscall1/2`, `_cgo_*`,
`go_seq_*`) and Android resolves symbols process-wide, so the second runtime
executes the first one's scheduler → native crash.

Running Psiphon in its own `:psiphon` process is necessary but **not
sufficient**: as long as Psiphon's Java bridge classes are named `go.*`, the
`:psiphon` process resolves them to the Xray copies packaged in the APK,
loads the 31 MB Xray runtime into the Psiphon process via
`System.loadLibrary("gojni")`, and then `libpsiphon-gojni.so` loads a second
Go runtime on top → crash on the first connection. (Stripping `go/*` out of
the Psiphon AAR — the previous approach — made this worse, not better.)

### The solution: relocate the Psiphon bridge at build time

`android/app/build.gradle.kts` defines the **`relocatePsiphonAar`** task,
which resolves `ca.psiphon:psiphontunnel:2.0.40` from the Psiphon maven
repository and runs `tools/relocate_psiphon_aar.py` on it. The script:

1. relocates the gomobile Java bridge package `go` → `gi` in every class of
   the AAR's `classes.jar` (constant-pool rewrite of class references and
   `Lgo/…;` descriptors, plus the `loadLibrary("gojni")` constant →
   `"psiphon-gojni"`). The public `ca.psiphon.*` API is untouched;
2. renames `jni/<abi>/libgojni.so` → `libpsiphon-gojni.so` and patches each
   `.so` in place (length-preserving, ELF layout unchanged):
   - dynamic-symbol names `Java_go_*` → `Java_gi_*`,
   - baked-in FindClass strings `go/Seq` → `gi/Seq`, `go/Seq$Ref` →
     `gi/Seq$Ref`, `go/Universe…` → `gi/Universe…`;
3. verifies nothing `go`-bridge-related survives (hard build failure
   otherwise).

Because the task runs inside the Gradle build, **local builds and CI produce
identical results** — there is no CI-only AAR surgery anymore.

### Process × runtime matrix (after the fix)

| process | classes | Go runtime loaded |
|---|---|---|
| main | `go.Seq` + `libv2ray.*` (Xray) | `libgojni.so` (Xray) only |
| `:psiphon` | `gi.Seq` + `ca.psiphon.*` (Psiphon) | `libpsiphon-gojni.so` only |
| `:psiphonbridge` | `go.Seq` + `libv2ray.*` (Xray tun2socks bridge) | `libgojni.so` (Xray) only |

`GomobileRuntimeInitializer` (a `ContentProvider` declared with
`android:process=":psiphon"`) calls `gi.Seq.setContext(…)` at process start,
so the relocated Psiphon runtime is initialized before anything else in that
process.

## Architecture

### Components

1. **Android native layer**
   - `PsiphonVpnService.kt` — VpnService running in the `:psiphon` process;
     owns the TUN, starts Psiphon core, then launches the bridge service
   - `PsiphonTunBridgeService.kt` / `PsiphonTunBridge.kt` — `:psiphonbridge`
     process; Xray TUN inbound bridges device packets to Psiphon's local
     SOCKS5 listener
   - `PsiphonStatusStore.kt` — main-process cache of cross-process status
     broadcasts (state + 2 s heartbeat + log lines)
   - `MainActivity.kt` — owns the `com.forwin.vpn/psiphon` MethodChannel
     (permission dialog via `startActivityForResult`, start/stop/reconnect,
     status/stats/log queries)

2. **Flutter layer**
   - `VpnProvider` — protocol-agnostic state machine; Psiphon is one of its
     transports
   - `PsiphonService` (`lib/services/psiphon_service.dart`) — MethodChannel
     client for `com.forwin.vpn/psiphon`

> The old `psiphon_bridge` plugin and the orphaned
> `psiphon_screen.dart` / `psiphon_provider.dart` / `psiphon_manager.dart`
> files were removed — they registered a second handler for the same channel
> and duplicated the real path.

### Data flow

```
Flutter UI
    ↓
VpnProvider (state management)
    ↓
PsiphonService (MethodChannel com.forwin.vpn/psiphon)
    ↓
MainActivity (Kotlin, main process — VPN permission + start intent)
    ↓
PsiphonVpnService (:psiphon process)
    ├─ gi.Seq → libpsiphon-gojni.so (relocated Psiphon Go runtime)
    ├─ PsiphonTunnel core → SOCKS5 on 127.0.0.1:<port>
    └─ startTunBridge(fd, port)
            ↓
       PsiphonTunBridgeService (:psiphonbridge process)
            ├─ go.Seq → libgojni.so (Xray Go runtime)
            └─ Xray TUN inbound → bridges TUN ⇄ SOCKS5
            ↓
       broadcasts bridge success/failure back to :psiphon
            ↓
PsiphonVpnService marks "connected" only when the bridge confirms
    ↓
ACTION_STATUS broadcasts → PsiphonStatusStore (main process)
    ↓
Flutter (isConnected / queryStats / getPsiphonLogs)
```

"Connected" is deliberately conservative: it requires **both** Psiphon core
`onConnected()` **and** the `:psiphonbridge` process confirming that device
packet processing is initialized and alive. This is **not** an end-to-end
internet reachability test. Session-tagged bridge heartbeats expire after
8 seconds; a dead bridge or exiting/reconnecting core must not remain connected.

### Standalone bootstrap and DNS

`PsiphonConfig` reads the same packaged **public** signed-discovery bootstrap
as Mix, but builds an independent standalone config. The SDK does not invent
`PropagationChannelId` or `SponsorId`; omitting them rejects the config before
the first tunnel attempt. Both paths also import an offline seed from
`psiphon_server_list.bin` through `startTunneling(embeddedServers)`. Previously
both passed an empty string: a fresh datastore could not attempt any server
until the single S3 discovery drop was reachable. A blocked drop therefore
prevented both standalone and Mix from bootstrapping.

`PsiphonBootstrap` verifies the original zlib-compressed authenticated envelope
using the configured public-key digest and RSA PKCS#1 v1.5/SHA-256 signature
before returning its newline-delimited hex entries to the SDK. Decompression
is bounded. The packaged snapshot contains 428 entries and is only an initial
seed, **not** a guarantee that any particular server remains reachable. The
SDK still selects servers, authenticates them, caches discoveries and refreshes
its signed remote lists. Missing/corrupt seed data is ignored, allowing cached
and remote discovery to continue; no unsigned entries or TLS bypass are added.
Each Mix stage imports into its own existing private datastore. Reading a local
snapshot adds no network fetch and leaves `UpstreamProxyURL` routing unchanged.

### Runtime refresh on every connection

On Android, a Psiphon list refresh is requested **three seconds after native
connected status**, for every protocol. Startup itself does not download.
`VpnConnectionObserver`, implemented by `VpnApplication` in each app process,
reports native startup/state without requiring MainActivity or Flutter.
DNS reports its established interface; Xray and the local proxy report started
cores; WARP reports its validated Aether connected event; standalone Psiphon
requires both its core and traffic bridge; Slow DNS requires its health/auth
probe and routing core; Mix requires the complete-chain probe and final core.
SSTP uses real HOME link status; OpenVPN uses `LEVEL_CONNECTED`, excluding Mix's
internal OpenVPN stage. These retain their existing protocol-specific meanings
of connected; they are not new guarantees that discovery hosts are reachable.

`PsiphonConnectedRefresh` schedules one 3,000-ms timer on the first connected
event of a session. Repeated status notifications do not reset it or download
again. Disconnect/failure/reconnect before it fires cancels it; a new connected
event starts a fresh three-second wait. Source identity and generation guards
reject stale service events/cancelled timer callbacks. Timers weakly reference
service owners. Existing quick-tile/notification and sticky-restoration paths
participate whenever they actually reconnect successfully. Mix schedules once
after the complete chain is ready, not per hop. Timing is best-effort: Android's
event loop/process scheduling can delay execution beyond three seconds.

Both Flutter startup and connected-state refresh requests are removed, avoiding
an immediate/duplicate download that would bypass the delay. All requests are
fire-and-forget: neither VPN startup nor Psiphon bootstrap waits for network,
disk I/O, a file lock or a platform-channel reply. Each process has a background
worker with at most one coalesced pending request. Workers use `tryLock()` on
the same private `refresh.lock` before downloading; requests overlapping an
attempt in another process join that attempt (skip duplicate work), not wait or
queue a parallel download. File locks are released on failure/process death.

`PsiphonServerListStore` downloads only the HTTPS URLs in the existing packaged
configuration, with normal TLS verification, no redirects, bounded compressed
and decompressed sizes (8 MiB each), 5-second connect and 10-second read timeouts,
and a best-effort 25-second body deadline. DNS/platform stalls are not a strict
wall-clock timeout, but cannot block the connection/UI thread. The original
official signature is verified before fsync and same-directory atomic rename
to `files/psiphon-server-list/server-list.bin`. Failures do not delete or overwrite
the previous valid cache. Each reader reverifies the cache; missing/corrupt cache
falls back to the signed bundled snapshot. Standalone Psiphon and all Mix Psiphon
stages share this snapshot but retain their separate SDK datastores/discovery.
If both local sources are damaged, SDK cached/online discovery remains enabled.

An in-flight refresh never restarts an active tunnel or hot-injects entries into
it; the next Psiphon core startup reads the latest completed snapshot. The SDK's
own ongoing discovery is unchanged. This auxiliary download follows the app's
normal Android routing, including existing split-tunnel/app exclusions; it does
not force traffic through a Mix hop or bypass a VPN/kill switch with protected
sockets. Successful provider connection does not guarantee the discovery host
is reachable. Native-only accepted starts/reconnects no longer need MainActivity
or Flutter; the VPN process schedules its own refresh. Refresh remains best-effort
while that process lives, not a persistent Android job, and overlapping requests
can share an already-running attempt. This does not add boot/force-stop recovery
or make services that do not already restore their sessions start themselves.
Existing sticky restorations refresh only after they actually report connected
and remain connected for the delay; failed starts/null/stop/rejected intents do
not trigger a download. Internal transport dials still belong to the SDK;
native reported connected-to-disconnected-to-connected transitions can schedule
a new delayed refresh. Once an HTTP refresh has begun, a later disconnect does
not abort that request or change the last-valid-cache guarantees. Real-device
lifecycle/tap behavior has not been verified by these local source/JVM tests.

### Server list, manual refresh and target selection

Home and Psiphon Settings expose the signed server list and the local time of
the last successful online refresh. This is the verified cache file's timestamp,
not a claimed upstream publication date or the time of a failed attempt. A
bundled-only fallback explicitly says no successful online update is available.
Visible status cards poll local metadata, not the network; metadata reads run
separately from HTTP refresh work. Manual refresh reports success, already busy,
or failure without discarding the previous usable rows/date or stopping a VPN.

The catalog decodes actual tunnel-core entries, including the legacy four-field
header plus JSON used by the packaged 428-entry snapshot. It verifies the signed
envelope before projecting server ID, IP, region and an optional TCP port. No
encoded entry, authentication key or other server secret is sent to Flutter.
The catalog is bounded to 512 entries. Valid servers without a TCP port remain
selectable but are explicitly not TCP-testable.

The English-only server screen supports search, automatic selection, individual
server connection, manual signed-list refresh, and individual/batch **TCP
reachability** tests. At most four probes run concurrently, including repeated
button taps; leaving/refreshing prevents further stale batches. In-flight TCP
connects have a three-second timeout and their stale results are ignored. These
measure a TCP connection to an advertised port over normal app routing, not ICMP,
authenticated Psiphon handshakes or full-tunnel latency. A successful probe does
not guarantee that the server will establish a Psiphon connection.

For standalone Psiphon, a selected opaque ID is resolved back to the exact entry
in the latest verified snapshot and passed as tunnel-core `TargetServerEntry`.
Automatic mode omits that field. The option is present in the pinned 2.0.40
native binaries for all four packaged ABIs; actual on-device handshakes were not
performed here. The selected ID is private/persistent and reused by reconnect
and sticky restore. If a newer snapshot removes that entry, starting/restarting
that chosen server fails explicitly rather than silently switching servers;
choose another entry or Automatic. No target override is added to Mix's Psiphon
stages, and refreshing the list does not hot-switch an active connection.

The SDK retains its standalone data directory; no Mix datastore or packet FD
is reused. SOCKS requests an ephemeral local port, and the unused HTTP proxy
is disabled, avoiding fixed-port 1080/8080 collisions.

The standalone bridge is a **TCP proxy path**, not Mix's native packet mode.
DNS packets on port 53 are converted to TCP DNS and sent **through Psiphon**.
Other UDP (including QUIC and UDP-only calls/games) is explicitly blocked;
there is no direct-network fallback. TCP-capable applications can fall back
from QUIC. Full UDP support would require a separate packet-tunnel integration,
not a SOCKS setting. IPv4 and IPv6 default routes remain inside the TUN.

Commands are serialized, and callbacks/status reports are scoped to the active
session. Internal reconnect with the kill switch enabled keeps the old TUN as
a blackhole until the new TUN replaces it; an explicit user disconnect still
releases the VPN. App exclusions/split tunneling remain intentional exceptions
to the VPN policy; this is not Android's system-wide always-on VPN lockdown.

### Refreshing the offline seed (not part of a build)

The snapshot is the signed response from the HTTPS URL already configured in
`mix_psiphon_bootstrap.json`, not an invented endpoint or third-party server
collection. Keep that configuration and its signing key as the trust source.
With Python 3.10+ and `cryptography` installed:

```bash
python3 tools/update_psiphon_bootstrap.py          # HTTPS fetch, verify, atomic replace
python3 tools/update_psiphon_bootstrap.py --check  # offline verification only
python3 tools/test_psiphon_bootstrap_update.py
```

`--source /path/to/signed-package` verifies and installs an already downloaded
signed envelope. Invalid input never replaces the previous asset. Refresh the
seed periodically when preparing a release; no network download occurs during
Gradle builds. Do not print or commit decoded server entries or raw core logs.

The desktop-only smoke test below uses a fresh datastore for each path and
**disables remote server-list fetching** to exercise this exact seed. It runs
only existing binaries and does not build anything:

```bash
python3 tools/test_psiphon_seed_live.py --psiphon /path/to/psiphon-console \
  --native-lib /path/to/libaether.so
```

It passed SOCKS/HTTPS and native Mix packet-stack HTTPS/UDP DNS in the Linux
test environment. That is not an Android service/permission/TUN test, a complete
multi-hop Mix validation, or evidence of connectivity on the owner's network.

## Build

```bash
flutter pub get
flutter build apk --release   # relocatePsiphonAar runs automatically
```

Requirements:

- Android SDK 24+ / Flutter 3.9+ / JDK 17
- **python3** (used by `tools/relocate_psiphon_aar.py`; preinstalled on
  macOS, Linux and most Windows setups)
- network access to `raw.github.com/Psiphon-Labs/psiphon-tunnel-core-Android-library`
  on first build (then cached by Gradle)

CI builds (`android-build.yml`, `build-android-apk.yml`) run
`tools/verify_apk_psiphon.py` on the produced APK to prove both runtimes
shipped correctly (`libpsiphon-gojni.so` + `libgojni.so`, `gi.Seq` + `go.Seq`
classes in the dex).

## Troubleshooting

**Build fails with "Psiphon AAR relocation" / verification errors**
- The relocation script hard-fails if any `go` bridge reference survives —
  that is intentional. Re-run with the full log; if the upstream AAR changed
  structure, adjust `tools/relocate_psiphon_aar.py`.

**`python3 is required to build the Psiphon runtime relocation step`**
- Install Python 3 and rebuild.

**Unresolved reference `gi.Seq` in the IDE**
- Expected before the first Gradle sync: `gi.*` classes exist only inside the
  AAR generated by `relocatePsiphonAar`. Run a Gradle sync / build once.

**VPN won't connect**
- First check VPN consent, selected protocol, and the native error shown by
  the app. A failed service must not be described only as a generic timeout.
- For a real-device check, select standalone Psiphon and auto region, start
  once and allow the complete connection window. Check a normal HTTPS page,
  background/foreground the app, disconnect, then repeat on the other network
  type (Wi-Fi/mobile) if available. Record only Android/app version, network
  type, kill-switch/split mode, the last completed stage, and a sanitized error
  category: permission, runtime initialization, TUN, server discovery, core
  connection, SOCKS listener, or traffic bridge. Do not share raw logcat,
  server addresses, browsing history, identifiers, or credentials.
- Unit tests and desktop core/config checks do not establish that an Android
  device on the owner's network can connect. Signed-list retrieval may itself
  be blocked by that network and needs device-stage evidence.

**Non-APK regression checks**
```bash
flutter test test/psiphon_service_test.dart --no-pub
cd android && ./gradlew :app:testDebugUnitTest
```
These are tests, not APK packaging or device/network validation.

**First connect crash on older builds**
- Fixed by this relocation: exactly one Go runtime per process. If you see
  both `libgojni.so` and a *second* runtime loading in one process in the
  logs, you are running a stale APK.

## File map

```
tools/
├── relocate_psiphon_aar.py     # go → gi AAR relocation + ELF patching
└── verify_apk_psiphon.py       # post-build APK sanity checks

android/app/
├── build.gradle.kts            # relocatePsiphonAar task + dependency wiring
├── libs/libv2ray.aar           # Xray bindings (own go.Seq; untouched)
├── src/main/jniLibs/*/libgojni.so   # Xray Go runtime (untouched)
└── src/main/kotlin/com/forwin/vpn/
    ├── PsiphonVpnService.kt        # :psiphon — uses gi.Seq
    ├── PsiphonConfig.kt            # standalone IDs, signed discovery, proxy options
    ├── GomobileRuntimeInitializer.kt # :psiphon provider — gi.Seq.setContext
    ├── PsiphonTunBridgeService.kt  # :psiphonbridge — Xray-based bridge
    └── PsiphonStatusStore.kt       # cross-process status cache

lib/services/psiphon_service.dart # MethodChannel client
lib/providers/vpn_provider.dart   # VpnProvider wires it into the UI
```

## References

- [Psiphon Tunnel Core](https://github.com/Psiphon-Inc/psiphon-tunnel-core)
- [Psiphon Android library maven repo](https://github.com/Psiphon-Labs/psiphon-tunnel-core-Android-library)
- [Android VpnService](https://developer.android.com/reference/android/net/VpnService)
