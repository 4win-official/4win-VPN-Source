import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vpn_swift/providers/theme_provider.dart';
import 'package:vpn_swift/screens/theme_selection_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('shows Day & Night and enables the toggle when selected',
      (tester) async {
    final provider = ThemeProvider();
    await Future<void>.delayed(Duration.zero);
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: provider,
        child: AnimatedBuilder(
          animation: provider,
          builder: (context, _) => MaterialApp(
            theme: provider.currentTheme,
            home: const ThemeSelectionScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Day & Night'), findsOneWidget);
    final dayNight = find.ancestor(
      of: find.text('Day & Night'),
      matching: find.byType(InkWell),
    );
    expect(dayNight, findsOneWidget);
    await tester.ensureVisible(dayNight);
    await tester.tap(dayNight);
    await tester.pumpAndSettle();

    expect(provider.selectedTheme, AppTheme.summer);
    await tester.scrollUntilVisible(find.byType(Switch), -400);
    final toggle = tester.widget<Switch>(find.byType(Switch));
    expect(toggle.onChanged, isNotNull);
    expect(toggle.value, provider.isDarkMode);
  });
}
