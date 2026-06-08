import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// Pins live per-row formula evaluation used by the child-table grid: a field
/// with a `formulaExpression` (e.g. amount = qty * rate) recomputes from the
/// row's own values whenever a cell changes.
void main() {
  const fields = [
    FieldDefinition(key: 'qty', label: 'Qty', type: FieldType.float),
    FieldDefinition(key: 'rate', label: 'Rate', type: FieldType.currency),
    FieldDefinition(
        key: 'amount',
        label: 'Amount',
        type: FieldType.currency,
        readOnly: true,
        formulaExpression: 'qty * rate'),
  ];

  test('computes amount = qty * rate', () {
    final row = <String, dynamic>{'qty': 2, 'rate': 50};
    applyRowFormulas(fields, row);
    expect(row['amount'], 100);
  });

  test('recomputes when an operand changes', () {
    final row = <String, dynamic>{'qty': 2, 'rate': 50, 'amount': 100};
    row['qty'] = 3;
    applyRowFormulas(fields, row);
    expect(row['amount'], 150);
  });

  test('a missing operand does not throw', () {
    final row = <String, dynamic>{'qty': 2}; // rate not entered yet
    expect(() => applyRowFormulas(fields, row), returnsNormally);
  });
}
