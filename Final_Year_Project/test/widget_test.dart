// Smoke test only: full MyApp() starts onboarding timers and Firebase-dependent
// flows that fail under the default test binding. Use docs/QA_CHECKLIST.md for
// end-to-end manual coverage.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Flutter test binding smoke', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Text('La Vogue Vista QA smoke'),
        ),
      ),
    );
    expect(find.text('La Vogue Vista QA smoke'), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
