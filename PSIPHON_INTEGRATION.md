# Psiphon VPN Integration

## Overview

This document describes the complete integration of Psiphon Tunnel Core into the 4win VPN Flutter application. The implementation provides a native Android VPN service backed by the official Psiphon tunnel core library.

## Architecture

### Components

1. **Android Native Layer**
   - `PsiphonVpnService.kt` - Main VPN service extending Android's VpnService
   - `PsiphonBridgePlugin.kt` - Flutter method channel bridge
   - Integrated with official `ca.psiphon:psiphontunnel` library

2. **Flutter Layer**
   - `PsiphonVpnManager` - Service manager for native communication
   - `PsiphonProvider` - Provider pattern for state management
   - `PsiphonScreen` - UI for Psiphon connections

### Data Flow

```
Flutter UI (PsiphonScreen)
    ↓
PsiphonProvider (State Management)
    ↓
PsiphonVpnManager (MethodChannel)
    ↓
PsiphonBridgePlugin (Kotlin)
    ↓
PsiphonVpnService (VpnService)
    ↓
PsiphonTunnel Core (Native)
```

## Features

✅ **Connection Management**
- Start/Stop/Reconnect VPN tunnel
- Region selection (US, CA, DE, FR, JP, AU, BR, IN, Auto)
- Automatic reconnection on failure

✅ **Traffic Monitoring**
- Real-time upload/download statistics
- Speed calculation (bytes/second)
- Connection duration tracking

✅ **User Interface**
- Connection status display with gradient
- Traffic stats cards
- Region selector with FilterChip
- Error messages and logging

✅ **Android Integration**
- Foreground service with notification
- VPN permission handling
- TUN interface setup
- IPv4 and IPv6 support

## Installation & Setup

### Prerequisites

1. Android SDK 24+ (API level 24)
2. Flutter 3.9.2+
3. Java 11+

### Step 1: Add Dependencies

The `android/app/build.gradle.kts` already includes:

```gradle
implementation("ca.psiphon:psiphontunnel:2.0.40")
implementation("org.json:json:20231013")
```

### Step 2: Flutter Dependencies

Ensure `pubspec.yaml` includes:

```yaml
dependencies:
  provider: ^6.0.0
  psiphon_bridge:
    path: ./psiphon_bridge
```

### Step 3: Build & Run

```bash
# Clean build
flutter clean
flutter pub get

# Run on Android
flutter run -d <device-id>

# Build APK
flutter build apk --release
```

## Usage

### Basic Example

```dart
import 'package:provider/provider.dart';
import 'lib/providers/psiphon_provider.dart';
import 'lib/screens/psiphon_screen.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => PsiphonProvider(),
      child: const MyApp(),
    ),
  );
}

// In your widget:
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const PsiphonScreen(),
    );
  }
}
```

### Connect to VPN

```dart
final provider = context.read<PsiphonProvider>();
await provider.startConnection('US'); // or 'Auto' for auto-select
```

### Disconnect from VPN

```dart
final provider = context.read<PsiphonProvider>();
await provider.stopConnection();
```

### Query Connection Status

```dart
final provider = context.read<PsiphonProvider>();
print('Connected: ${provider.isConnected}');
print('Running: ${provider.isRunning}');
print('Status: ${provider.connectionStatus}');
```

### Query Traffic Stats

```dart
final stats = await PsiphonVpnManager.queryTrafficStats();
print('Upload: ${stats['uplink']} bytes');
print('Download: ${stats['downlink']} bytes');
```

## Android Manifest Permissions

The following permissions are required (already in `AndroidManifest.xml`):

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.CHANGE_NETWORK_STATE" />
<uses-permission android:name="android.permission.BIND_VPN_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

## Service Definition

The `PsiphonVpnService` is already defined in `AndroidManifest.xml`:

```xml
<service
    android:name=".PsiphonVpnService"
    android:permission="android.permission.BIND_VPN_SERVICE"
    android:exported="false"
    android:foregroundServiceType="specialUse">
    <intent-filter><action android:name="android.net.VpnService"/></intent-filter>
    <property android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE" 
        android:value="Psiphon VPN tunnel service" />
</service>
```

## Troubleshooting

### Build Errors

**Error: `Unresolved reference 'PsiphonVpnService'`**
- Solution: Ensure `android/app/src/main/kotlin/com/forwin/vpn/PsiphonVpnService.kt` exists
- Rebuild: `flutter clean && flutter pub get`

**Error: `Cannot resolve dependency 'ca.psiphon:psiphontunnel'`**
- Solution: Maven repository is correctly configured in `build.gradle.kts`
- Check internet connection and try again

### Runtime Issues

**VPN won't connect**
- Check logcat: `adb logcat | grep Psiphon`
- Verify VPN permission is granted
- Ensure Psiphon servers are reachable

**Traffic stats not updating**
- Stats polling runs every 1 second while connected
- Check if service is actually running: `provider.isRunning`

**Permission denied**
- First time connecting, user must approve VPN permission
- Call `preparePsiphon()` before `startConnection()`

## Testing

### Manual Testing

1. **Connect Test**
   - Launch app → PsiphonScreen
   - Select region → Click "Connect"
   - Verify notification appears and stats update

2. **Disconnect Test**
   - While connected → Click "Disconnect"
   - Verify notification disappears
   - Verify stats stop updating

3. **Reconnect Test**
   - While connected → Click "Reconnect"
   - Verify brief disconnection then reconnection
   - Verify connection time resets

4. **Region Change Test**
   - Select different region → Reconnect
   - Verify notification shows new region

### Debug Logging

Enable detailed logging:

```bash
adb logcat | grep "Psiphon"
```

Key log tags:
- `PsiphonVpnService` - Service lifecycle
- `PsiphonBridgePlugin` - Flutter communication
- `TAG: PsiphonVpnService` - Core tunnel events

## File Structure

```
android/
├── app/
│   ├── build.gradle.kts (modified)
│   ├── src/main/
│   │   ├── kotlin/com/forwin/vpn/
│   │   │   ├── PsiphonVpnService.kt (NEW)
│   │   │   ├── MainActivity.kt
│   │   │   └── ...
│   │   └── AndroidManifest.xml (modified)
│   └── ...
└── ...

lib/
├── services/
│   └── psiphon_manager.dart (NEW)
├── providers/
│   └── psiphon_provider.dart (NEW)
├── screens/
│   └── psiphon_screen.dart (NEW)
└── ...

psiphon_bridge/
├── android/
│   ├── src/main/kotlin/com/forwin/psiphon_bridge/
│   │   └── PsiphonBridgePlugin.kt (modified)
│   └── build.gradle (modified)
└── pubspec.yaml
```

## Performance Considerations

1. **Traffic Polling**
   - Stats polled every 1 second for smooth UI updates
   - Stops automatically when disconnected

2. **Thread Safety**
   - Uses `Volatile` for thread-safe state
   - Semaphore ensures only one operation at a time

3. **Memory**
   - Traffic stats reset on new connection
   - Foreground service keeps process alive

## Future Enhancements

- [ ] Split tunneling by app package name
- [ ] Protocol selection (auto/fastest/slowest DNS)
- [ ] Server list caching and refresh
- [ ] Connection history and favorites
- [ ] Advanced statistics (latency, packet loss)
- [ ] Custom DNS configuration
- [ ] VPN kill switch option

## License

Psiphon Tunnel Core is licensed under GPL. Ensure your app license is compatible.

## References

- [Psiphon Tunnel Core](https://github.com/Psiphon-Inc/psiphon-tunnel-core)
- [Android VpnService](https://developer.android.com/reference/android/net/VpnService)
- [Flutter Method Channels](https://docs.flutter.dev/platform-integration/platform-channels)
- [Provider State Management](https://pub.dev/packages/provider)
