import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vpn_swift/providers/theme_provider.dart';
import 'package:vpn_swift/widgets/pixelation_filter.dart';

Future<ThemeProvider> _newProvider() async {
  final provider = ThemeProvider();
  await Future<void>.delayed(Duration.zero);
  return provider;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('Pixel theme uses monospace typography in both brightness modes', () async {
    final provider = await _newProvider();
    addTearDown(provider.dispose);

    await provider.setTheme(AppTheme.pixel);

    expect(provider.lightTheme.textTheme.bodyMedium?.fontFamily, 'monospace');
    expect(provider.darkTheme.textTheme.bodyMedium?.fontFamily, 'monospace');
    expect(provider.currentTheme.textTheme.bodyMedium?.fontFamily, 'monospace');
  });

  test('non-Pixel themes retain their existing default font family', () async {
    final provider = await _newProvider();
    addTearDown(provider.dispose);

    expect(provider.currentTheme.textTheme.bodyMedium?.fontFamily, 'Roboto');
    await provider.setTheme(AppTheme.pixel);
    await provider.setTheme(AppTheme.cat);
    expect(provider.currentTheme.textTheme.bodyMedium?.fontFamily, 'Roboto');
  });

  testWidgets('pixel filter covers text and icons without breaking taps', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PixelationFilter(
            child: Center(
              child: GestureDetector(
                onTap: () => taps++,
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star),
                    Text('Pixel theme content'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(ImageFiltered), findsOneWidget);
    expect(find.byIcon(Icons.star), findsOneWidget);
    expect(find.text('Pixel theme content'), findsOneWidget);
    await tester.tap(find.byType(GestureDetector));
    expect(taps, 1);
  });
}
