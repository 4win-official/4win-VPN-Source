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
the first tunnel attempt. A fresh installation also needs the server-list URL
and signature key because standalone starts without embedded server entries.
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
