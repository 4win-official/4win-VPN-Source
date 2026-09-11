# Psiphon Protocol Implementation Checklist

## ✅ Completed Tasks

### Android Native Layer
- [x] Create `PsiphonVpnService` extending VpnService
- [x] Implement Psiphon Tunnel Core initialization
- [x] Add VPN interface (TUN) setup
- [x] Configure IPv4 and IPv6 support
- [x] Implement connection lifecycle (start/stop/reconnect)
- [x] Add foreground service with notifications
- [x] Implement traffic stats tracking (upload/download)
- [x] Add thread-safe state management (Volatile + Semaphore)
- [x] Implement proper error handling and logging
- [x] Create PsiphonBridgePlugin for Flutter communication
- [x] Add comprehensive logging for debugging

### Flutter Layer
- [x] Create `PsiphonVpnManager` service
- [x] Implement MethodChannel communication
- [x] Create `PsiphonProvider` with Provider pattern
- [x] Add state management for connection status
- [x] Implement traffic stats formatting
- [x] Add connection time tracking and formatting
- [x] Create `PsiphonScreen` UI component
- [x] Add region selector with FilterChip
- [x] Implement traffic stats display cards
- [x] Add connection status gradient display
- [x] Create action buttons (connect/disconnect/reconnect)
- [x] Add error message display
- [x] Implement proper error handling

### Configuration & Integration
- [x] Add Psiphon dependency to build.gradle.kts
- [x] Add JSON library for config serialization
- [x] Configure Maven repository for Psiphon
- [x] Add VPN service to AndroidManifest.xml
- [x] Add required Android permissions
- [x] Configure notification channel
- [x] Add service definition with specialUse foregroundServiceType
- [x] Update psiphon_bridge plugin configuration

### Documentation
- [x] Write comprehensive README with architecture
- [x] Document all API methods
- [x] Provide usage examples
- [x] Add troubleshooting section
- [x] Document file structure
- [x] Add testing guidelines
- [x] Include performance notes

## ✅ Completed in v1.4.8 (crash-fix + hardening release)

### Crash fix (Psiphon connect crash)
- [x] Isolate `PsiphonVpnService` in the `:psiphon` process — root cause of the
  connect crash was TWO gomobile/Go runtimes (Psiphon + Xray) loaded in the
  main process. Each process now loads exactly one Go runtime.
- [x] Cross-process status bridge: `:psiphon` publishes state/stats/logs via
  package-scoped broadcasts → `VpnApplication`-registered receiver →
  `PsiphonStatusStore` (with heartbeat staleness guard, so a dead service
  reads back as disconnected instead of sticking on "connected").
- [x] Guard every Psiphon core callback (they run on Go threads) so failures
  become log lines, never process kills; added missing `onRevoke()` teardown.
- [x] Added the missing `queryStats` handler to MainActivity's Psiphon channel
  (+ `getPsiphonLogs`, `isKillSwitchActive`); `PsiphonBridgePlugin` now reads
  the same store via reflection so behavior is identical regardless of
  channel-registration order.

### Advanced Features
- [x] Split tunneling for Psiphon (same include/exclude semantics as Xray)
- [x] VPN kill switch for Psiphon (native TUN blackhole + infinite auto-retry
  while engaged; the Settings toggle is now actually wired up)
- [ ] Add protocol selection (DNS Tunneling options)
- [ ] Implement server list refresh mechanism
- [ ] Add connection favorites/history
- [ ] Implement advanced statistics (latency, packet loss)
- [ ] Add custom DNS configuration UI

### Reliability
- [x] Connection retry with exponential backoff (`RetryPolicy`: 4 connect
  attempts; monitor heals with 5s→60s backoff, unlimited with kill switch)
- [x] Connection timeout detection (25s per-attempt timeout + give-up paths)
- [x] Health monitor with auto-reconnect (20s liveness checks + recovery)
- [x] Live traffic stats for Psiphon (upload/download counters in the UI)
- [ ] Optimize traffic polling frequency
- [ ] Cache server list locally

### Testing
- [x] Unit tests (`retry_policy`, `connection_logger`, `secret_text_cipher`,
  `xray_config_builder`, `proxy_server`, `xray_server`)
- [x] Widget smoke test (existing `widget_test.dart`)
- [x] E2E boot smoke test (`integration_test/app_smoke_test.dart`, on-device)
- [x] CI test gate (`.github/workflows/flutter-test.yml` on every push/PR)
- [ ] Android instrumented tests for PsiphonVpnService

### UI/UX
- [x] Unified connection logs view (all protocols + native lines, protocol
  filter, copy/clear, survives restarts for post-crash diagnosis)
- [ ] Add connection animation
- [ ] Implement speed test feature
- [ ] Add server latency display
- [ ] Implement connection preferences/settings

## ⏳ Still Pending
- Advanced statistics, favorites/history, custom DNS UI, protocol selection,
  instrumented tests, connection animation, speed test, latency display.

## 🔧 Build & Test Status

### Build
- [x] Kotlin compilation successful
- [x] Flutter analysis successful
- [x] Gradle build successful
- [ ] APK release build (pending testing)

### Tests
- [ ] Manual connection test
- [ ] Manual disconnect test
- [ ] Manual reconnect test
- [ ] Manual region change test
- [ ] Traffic stats accuracy test
- [ ] Error handling test

## 📝 Notes

1. **Psiphon Core Version**: 2.0.40
   - Latest version as of September 2026
   - Supports modern Android (API 24+)

2. **Thread Safety**
   - Uses Volatile for state variables
   - Semaphore prevents concurrent operations
   - Proper synchronization on all state changes

3. **Memory Management**
   - Stats reset on new connection
   - Foreground service keeps process alive
   - Proper cleanup on disconnect

4. **Error Handling**
   - All exceptions caught and logged
   - User-friendly error messages
   - Graceful degradation

## 🚀 Next Steps

1. **Build APK**
   ```bash
   flutter build apk --release
   ```

2. **Test on Real Device**
   - Install APK on Android device
   - Test connection flow
   - Verify traffic stats
   - Check notification behavior

3. **Merge to Main**
   - After successful testing
   - Update CHANGELOG
   - Create release notes

4. **Release**
   - Submit to Play Store
   - Monitor for crash reports
   - Collect user feedback
