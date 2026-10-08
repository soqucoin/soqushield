import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soqushield/main.dart';

void main() {
  testWidgets('App launches successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: SoquShieldApp()));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('SOQUSHIELD'), findsOneWidget);

    // Dispose widget tree and advance to drain pending session timers
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SizedBox.shrink())),
    );
    await tester.pump(const Duration(minutes: 30));
  });
}
