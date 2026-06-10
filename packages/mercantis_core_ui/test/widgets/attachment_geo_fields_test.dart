import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

void main() {
  group('GeolocationField', () {
    testWidgets('seeds latitude/longitude inputs from a "lat,lng" value',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: GeolocationField(
            label: 'Where',
            required: false,
            value: '35.9,14.5',
            readOnly: false,
            onChanged: _noop,
          ),
        ),
      ));

      expect(find.text('35.9'), findsOneWidget);
      expect(find.text('14.5'), findsOneWidget);
    });

    testWidgets('emits a combined "lat,lng" string on edit', (tester) async {
      dynamic captured;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: GeolocationField(
            label: 'Where',
            required: false,
            value: null,
            readOnly: false,
            onChanged: (v) => captured = v,
          ),
        ),
      ));

      await tester.enterText(find.byType(TextField).first, '10');
      await tester.enterText(find.byType(TextField).last, '20');
      expect(captured, '10,20');
    });

    test('parse splits and tolerates partials', () {
      expect(GeolocationField.parse('1.5,-2.5').lat, 1.5);
      expect(GeolocationField.parse('1.5,-2.5').lng, -2.5);
      expect(GeolocationField.parse(null).lat, isNull);
      expect(GeolocationField.parse('').lng, isNull);
    });
  });

  group('AttachmentField', () {
    testWidgets('reports a typed file reference and clears it', (tester) async {
      dynamic captured = 'seed';
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AttachmentField(
            label: 'Doc',
            required: false,
            value: null,
            readOnly: false,
            onChanged: (v) => captured = v,
          ),
        ),
      ));

      await tester.enterText(find.byType(TextField), '/tmp/report.pdf');
      expect(captured, '/tmp/report.pdf');

      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();
      expect(captured, isNull);
    });
  });
}

void _noop(dynamic _) {}
