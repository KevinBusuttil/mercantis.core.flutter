import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// Pins child-row default coercion: FieldDefinition.defaultValue is a String,
/// but numeric/boolean cells must start as typed values so they don't crash the
/// cell casts and flow into derivation as numbers. This is the bug behind the
/// "type 'String' is not a subtype of type 'num?'" crash on Add.
void main() {
  test('numeric defaults coerce to numbers', () {
    expect(coerceChildDefault(FieldType.integer, '5'), 5);
    expect(coerceChildDefault(FieldType.integer, '5'), isA<int>());
    expect(coerceChildDefault(FieldType.currency, '1.5'), 1.5);
    expect(coerceChildDefault(FieldType.float, '2'), isA<num>());
    expect(coerceChildDefault(FieldType.percent, '10'), 10);
  });

  test('check defaults coerce to bool', () {
    expect(coerceChildDefault(FieldType.check, '1'), isTrue);
    expect(coerceChildDefault(FieldType.check, 'true'), isTrue);
    expect(coerceChildDefault(FieldType.check, '0'), isFalse);
  });

  test('non-numeric / unparsable defaults stay strings', () {
    expect(coerceChildDefault(FieldType.data, 'Each'), 'Each');
    expect(coerceChildDefault(FieldType.integer, 'n/a'), 'n/a');
  });
}
