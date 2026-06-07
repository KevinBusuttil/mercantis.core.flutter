import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// Pins the child-table data binding used by GenericFormView: child rows are
/// read from / written to Document.children (the document_children table), not
/// the parent payload. This is what makes line items display in the form and
/// flow into ledger derivation on save.
void main() {
  group('childRowsAsMaps', () {
    test('reads rows from Document.children, not payload', () {
      final doc = Document(
        id: 'O1',
        docType: 'Demo Order',
        payload: {'items': 'ignored-payload-value'},
        children: {
          'items': [
            ChildRow(
              id: 'r0',
              parentId: 'O1',
              parentDocType: 'Demo Order',
              tableName: 'items',
              rowIndex: 0,
              payload: {'item_code': 'WIDGET-1', 'qty': 5},
            ),
          ],
        },
      );

      final rows = childRowsAsMaps(doc, 'items');
      expect(rows, [
        {'item_code': 'WIDGET-1', 'qty': 5}
      ]);
    });

    test('returns empty for a field with no child rows', () {
      final doc = Document(id: 'O1', docType: 'Demo Order');
      expect(childRowsAsMaps(doc, 'items'), isEmpty);
    });
  });

  group('applyChildChanges', () {
    test('rebuilds Document.children as ChildRows, never payload', () {
      final base = Document(id: 'O1', docType: 'Demo Order');
      final out = applyChildChanges(base, {
        'items': [
          {'item_code': 'A', 'qty': 1},
          {'item_code': 'B', 'qty': 2},
        ],
      });

      final rows = out.children['items']!;
      expect(rows.length, 2);
      expect(rows[0].payload['item_code'], 'A');
      expect(rows[0].tableName, 'items');
      expect(rows[0].parentId, 'O1');
      expect(rows[0].parentDocType, 'Demo Order');
      expect(rows[0].rowIndex, 0);
      expect(rows[1].rowIndex, 1);
      // Child rows must not leak into the parent payload.
      expect(out.payload.containsKey('items'), isFalse);
    });

    test('replaces existing child rows wholesale', () {
      final base = Document(
        id: 'O1',
        docType: 'Demo Order',
        children: {
          'items': [
            ChildRow(
              id: 'old',
              parentId: 'O1',
              parentDocType: 'Demo Order',
              tableName: 'items',
              rowIndex: 0,
              payload: {'item_code': 'OLD'},
            ),
          ],
        },
      );

      final out = applyChildChanges(base, {
        'items': [
          {'item_code': 'NEW'},
        ],
      });
      expect(out.children['items']!.single.payload['item_code'], 'NEW');
    });

    test('no changes returns the document unchanged', () {
      final base = Document(id: 'O1', docType: 'Demo Order');
      expect(identical(applyChildChanges(base, const {}), base), isTrue);
    });
  });
}
