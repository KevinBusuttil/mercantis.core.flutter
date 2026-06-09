import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

void main() {
  testWidgets('RatingField renders filled/empty stars and reports taps',
      (tester) async {
    int? captured;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RatingField(
          label: 'Score',
          required: false,
          value: 2,
          readOnly: false,
          onChanged: (v) => captured = v as int?,
        ),
      ),
    ));

    expect(find.byIcon(Icons.star), findsNWidgets(2));
    expect(find.byIcon(Icons.star_border), findsNWidgets(3));

    // Tap the 3rd star (first empty one) → rating becomes 3.
    await tester.tap(find.byIcon(Icons.star_border).first);
    expect(captured, 3);
  });

  testWidgets('DurationField seeds hours/minutes from a seconds value',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DurationField(
          label: 'Duration',
          required: false,
          value: 3 * 3600 + 25 * 60,
          readOnly: false,
          onChanged: (_) {},
        ),
      ),
    ));

    expect(find.text('3'), findsOneWidget);
    expect(find.text('25'), findsOneWidget);
  });

  testWidgets('CodeField is multi-line and reports edits', (tester) async {
    String? captured;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CodeField(
          label: 'Script',
          required: false,
          value: null,
          readOnly: false,
          onChanged: (v) => captured = v as String?,
        ),
      ),
    ));

    await tester.enterText(find.byType(TextField), 'a = 1');
    expect(captured, 'a = 1');
  });
}
