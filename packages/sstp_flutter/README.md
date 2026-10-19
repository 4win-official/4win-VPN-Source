# Local SSTP plugin

Vendored from `sstp_flutter` 1.3.0 (pub.dev package; original homepage: https://github.com/NavidShokoufeh/sstp_flutter). The upstream license is preserved in `LICENSE`. Dart and iOS implementation files are unchanged. The example app and wrapper scripts are not needed by the parent app.

## Android lifecycle fixes

The upstream plugin throws `NotImplementedError` in all three ActivityAware detach/reattach callbacks. Flutter invokes these callbacks when the UI task is removed, even when another VPN protocol is selected. A crash in this shared process can also terminate the app's native VPN services. Detaching now releases only activity result listeners and UI channels; it never sends a disconnect command or stops a service.

Service callbacks are posted on the Android main thread only while an engine is attached. Queued callbacks for a detached engine are dropped, while native connection state remains available for the next UI instance. No UI callback is required for the tunnel to run.

The standalone SSTP service explicitly survives task removal, uses the `specialUse` foreground-service type (rather than the time-limited `dataSync` type), and publishes an ongoing notification. A null sticky restart recovers only a session marked active; explicit disconnect clears that marker before stopping and returns `START_NOT_STICKY`. An already-running client is not replaced by a null restart. These changes do not touch the separate SSTP implementation used by Mix.

## Tests (no APK)

From the repository root:

```sh
flutter pub get
python3 -m unittest tools.test_vpn_background_contract -v
flutter test --no-pub
cd android
./gradlew :sstp_flutter:testDebugUnitTest :app:testDebugUnitTest :app:processDebugMainManifest
```

The plugin tests use Robolectric/JVM, not a physical device. They exercise Activity/engine detach and reattach, background UI-event delivery, task removal with an existing client, explicit disconnect, sticky callbacks and notification properties. App tests cover the existing native configuration/routing logic; the Python checks protect service declarations and process isolation.

Removing a task from Recents is not Android Force stop. User Force stop, revoking VPN permission, the system's active-app Stop control, and some manufacturers' aggressive battery/background policies can still terminate a VPN. No automatic restart can guarantee uninterrupted traffic in those cases; device testing is still required.
