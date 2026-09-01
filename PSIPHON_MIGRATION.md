# Migration Guide: Adding Psiphon to Navigation

## Integration with Existing App

### Option 1: Add to Existing Navigation

If your app uses a navigation system (like BottomNavigationBar), add Psiphon as a new tab:

```dart
import 'package:provider/provider.dart';
import 'lib/providers/psiphon_provider.dart';
import 'lib/screens/psiphon_screen.dart';

// In main.dart
void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PsiphonProvider()),
        // Your other providers...
      ],
      child: MaterialApp(
        title: '4win VPN',
        home: const HomeScreen(),
      ),
    );
  }
}
```

### Option 2: Replace Existing Screen

If you want to replace an existing VPN protocol screen:

```dart
// Before
case VpnProtocol.psiphon:
  return const PlaceholderScreen();

// After  
case VpnProtocol.psiphon:
  return const PsiphonScreen();
```

### Option 3: Separate Psiphon Section

Add Psiphon as a dedicated section in your app menu:

```dart
listTile(
  icon: const Icon(Icons.vpn_lock),
  title: const Text('Psiphon VPN'),
  onTap: () {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const PsiphonScreen(),
      ),
    );
  },
)
```

## State Management Integration

If using other state management (GetX, Riverpod, etc.), adapt as follows:

### With GetX

```dart
class PsiphonGetXController extends GetxController {
  final isRunning = false.obs;
  final isConnected = false.obs;
  final connectionStatus = 'Disconnected'.obs;

  void startConnection(String region) async {
    await PsiphonVpnManager.startPsiphon(egressRegion: region);
    isRunning.value = true;
    connectionStatus.value = 'Connecting...';
  }
  
  // ... other methods
}

// In widget
Ob(() => Text(psiphonController.connectionStatus.value))
```

### With Riverpod

```dart
final psiphonStateProvider = 
  StateNotifierProvider<PsiphonNotifier, PsiphonState>(
    (ref) => PsiphonNotifier(),
  );

class PsiphonNotifier extends StateNotifier<PsiphonState> {
  PsiphonNotifier() : super(PsiphonState());
  
  Future<void> startConnection(String region) async {
    await PsiphonVpnManager.startPsiphon(egressRegion: region);
    state = state.copyWith(isRunning: true);
  }
}
```

## Handling Multiple VPN Protocols

If your app supports multiple protocols, create a unified interface:

```dart
abstract class VpnProtocolManager {
  Future<bool> prepare();
  Future<bool> connect({String? region});
  Future<bool> disconnect();
  Future<bool> isConnected();
  Stream<VpnStats> getStats();
}

class PsiphonProtocolManager implements VpnProtocolManager {
  @override
  Future<bool> prepare() => PsiphonVpnManager.preparePsiphon();
  
  @override
  Future<bool> connect({String? region}) => 
    PsiphonVpnManager.startPsiphon(egressRegion: region ?? '');
  
  @override
  Future<bool> disconnect() => PsiphonVpnManager.stopPsiphon();
  
  @override
  Future<bool> isConnected() => PsiphonVpnManager.isPsiphonConnected();
  
  @override
  Stream<VpnStats> getStats() async* {
    while (true) {
      final stats = await PsiphonVpnManager.queryTrafficStats();
      yield VpnStats(
        uplink: stats['uplink'] ?? 0,
        downlink: stats['downlink'] ?? 0,
      );
      await Future.delayed(const Duration(seconds: 1));
    }
  }
}
```

## Testing the Integration

### Unit Test Example

```dart
void main() {
  group('PsiphonVpnManager', () {
    test('preparePsiphon should return bool', () async {
      final result = await PsiphonVpnManager.preparePsiphon();
      expect(result, isA<bool>());
    });

    test('isPsiphonConnected should return false when not connected', () async {
      final result = await PsiphonVpnManager.isPsiphonConnected();
      expect(result, false);
    });
  });
}
```

### Widget Test Example

```dart
void main() {
  testWidgets('PsiphonScreen should display connect button', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => PsiphonProvider(),
        child: const MaterialApp(home: PsiphonScreen()),
      ),
    );
    
    expect(find.text('Connect'), findsOneWidget);
  });
}
```

## Common Issues & Solutions

### Issue 1: Psiphon screen not showing
**Solution**: Ensure PsiphonProvider is added to MultiProvider at app root

### Issue 2: Connection fails silently
**Solution**: Check logs with `adb logcat | grep Psiphon`

### Issue 3: States not updating
**Solution**: Ensure Consumer widget is wrapping the UI that displays state

## Best Practices

1. **Always prepare before connecting**
   ```dart
   await PsiphonVpnManager.preparePsiphon();
   await PsiphonVpnManager.startPsiphon();
   ```

2. **Handle errors gracefully**
   ```dart
   try {
     await provider.startConnection('US');
   } catch (e) {
     ScaffoldMessenger.of(context).showSnackBar(
       SnackBar(content: Text('Error: $e')),
     );
   }
   ```

3. **Cleanup on dispose**
   ```dart
   @override
   void dispose() {
     // Stop connection if active
     if (_provider.isConnected) {
       _provider.stopConnection();
     }
     super.dispose();
   }
   ```

4. **Request permissions properly**
   ```dart
   // For Android 12+
   if (Platform.isAndroid) {
     final permission = Permission.camera;
     await permission.request();
   }
   ```
