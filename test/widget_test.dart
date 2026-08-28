// Basic smoke test for 4win VPN.
//
// Verifies that the root widget builds without throwing. The app relies on
// platform channels and shared preferences at runtime, so this stays a light
// build-only smoke test rather than a full interaction test.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vpn_swift/main.dart';

void main() {
  testWidgets('App builds without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    // The root MaterialApp should be present after the first frame.
    expect(find.byType(MaterialApp), findsWidgets);
  });
}
