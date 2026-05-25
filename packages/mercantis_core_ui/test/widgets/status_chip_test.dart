import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

void main() {
  group('StatusChip', () {
    testWidgets('renders label', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: StatusChip(label: 'Submitted', tone: StatusTone.submitted),
        ),
      ));
      expect(find.text('Submitted'), findsOneWidget);
    });

    test('forDocStatus maps to expected tone', () {
      expect(StatusChip.forDocStatus(0).tone, StatusTone.draft);
      expect(StatusChip.forDocStatus(1).tone, StatusTone.submitted);
      expect(StatusChip.forDocStatus(2).tone, StatusTone.cancelled);
    });
  });
}
