import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_mobile/screens/dashboard_screen.dart';
import 'package:supabase_mobile/screens/more_screen.dart';

void main() {
  testWidgets('Dashboard without a project asks to pick one',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: DashboardScreen()));
    expect(find.textContaining('Pick a project first'), findsOneWidget);
  });

  testWidgets('More hub lists the A-to-Z screens', (tester) async {
    // Tall viewport so every hub entry is built in one frame
    // (ListView only builds visible children).
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(const MaterialApp(home: MoreScreen()));
    for (final label in [
      'Organizations',
      'Webhooks',
      'GraphQL playground',
      'Database admin',
      'Auth config',
      'Log drains',
      'Network & security',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
  });
}
