import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

ResolvedFieldDefinition _field(String key, FieldType type) =>
    ResolvedFieldDefinition(key: key, type: type, label: key);

Future<void> _pump(WidgetTester tester, FieldType type, dynamic value) =>
    tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FieldWidget(
          field: _field('f', type),
          value: value,
          readOnly: false,
          onChanged: (_) {},
        ),
      ),
    ));

/// Payload values arrive both typed and stringly — seeders, interceptors,
/// and synced JSON write '1'/'0' and numeric strings. A String in a check
/// or number field used to throw `type 'String' is not a subtype of type
/// 'int?'` and take down the whole form.
void main() {
  testWidgets('check field renders "1" as on and "0" as off', (tester) async {
    await _pump(tester, FieldType.check, '1');
    expect(tester.takeException(), isNull);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

    await _pump(tester, FieldType.check, '0');
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets('check field still accepts the typed forms', (tester) async {
    await _pump(tester, FieldType.check, 1);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

    await _pump(tester, FieldType.check, true);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

    await _pump(tester, FieldType.check, null);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets('integer field renders a stringly value', (tester) async {
    await _pump(tester, FieldType.integer, '42');
    expect(tester.takeException(), isNull);
    expect(find.text('42'), findsOneWidget);
  });

  testWidgets('float and currency fields render stringly values',
      (tester) async {
    await _pump(tester, FieldType.float, '18.5');
    expect(tester.takeException(), isNull);

    await _pump(tester, FieldType.currency, '99.90');
    expect(tester.takeException(), isNull);
  });
}
