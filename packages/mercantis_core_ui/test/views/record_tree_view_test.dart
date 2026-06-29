import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// Unit coverage for [RecordTree] — the pure hierarchy/ordering logic behind
/// [RecordTreeView]. Mirrors the behaviour pinned in Swift's RecordTreeView:
/// self-referential parent link, code-then-title ordering, and cycle/broken
/// link safety (a row with a bad parent surfaces as a root, never loops).
void main() {
  // An Account-like tree DocType: title in `account_name`, ordering by
  // `account_number`, self-referential parent in `parent_account`.
  const accountDocType = DocType(
    id: 'Account',
    name: 'Account',
    isTree: true,
    parentField: 'parent_account',
    fields: [
      FieldDefinition(key: 'account_name', type: FieldType.data, label: 'Name'),
      FieldDefinition(
          key: 'account_number', type: FieldType.data, label: 'Number'),
      FieldDefinition(
          key: 'parent_account',
          type: FieldType.link,
          label: 'Parent',
          linkDocType: 'Account'),
    ],
  );

  Document account(String id, String name, String number, {String? parent}) =>
      Document(
        id: id,
        docType: 'Account',
        payload: {
          'account_name': name,
          'account_number': number,
          if (parent != null) 'parent_account': parent,
        },
      );

  test('builds roots with nested children', () {
    final docs = [
      account('a-assets', 'Assets', '1000'),
      account('a-cash', 'Cash', '1010', parent: 'a-assets'),
      account('a-bank', 'Bank', '1020', parent: 'a-assets'),
      account('a-liab', 'Liabilities', '2000'),
      account('a-ap', 'Accounts Payable', '2010', parent: 'a-liab'),
    ];

    final roots = RecordTree.build(accountDocType, docs);

    expect(roots.map((n) => n.id), ['a-assets', 'a-liab']);
    final assets = roots.first;
    expect(assets.hasChildren, isTrue);
    expect(assets.children.map((n) => n.id), ['a-cash', 'a-bank']);
    expect(roots[1].children.single.id, 'a-ap');
  });

  test('orders siblings by code/number, not insertion order', () {
    final docs = [
      account('a-assets', 'Assets', '1000'),
      account('a-bank', 'Bank', '1020', parent: 'a-assets'),
      account('a-cash', 'Cash', '1010', parent: 'a-assets'),
    ];

    final assets = RecordTree.build(accountDocType, docs).single;
    expect(assets.children.map((n) => n.id), ['a-cash', 'a-bank']);
  });

  test('a document with a missing parent surfaces as a root', () {
    final docs = [
      account('a-cash', 'Cash', '1010', parent: 'does-not-exist'),
    ];

    final roots = RecordTree.build(accountDocType, docs);
    expect(roots.single.id, 'a-cash');
  });

  test('a parent cycle does not loop and leaves cyclic nodes out of roots', () {
    // a -> b -> a forms a cycle; neither has a valid root ancestor.
    final docs = [
      account('a', 'A', '1', parent: 'b'),
      account('b', 'B', '2', parent: 'a'),
      account('c', 'C', '3'),
    ];

    final roots = RecordTree.build(accountDocType, docs);
    // Only the acyclic node is a root; the build terminates (no stack overflow).
    expect(roots.map((n) => n.id), ['c']);
  });

  test('a self-parent is treated as a root', () {
    final docs = [account('a', 'A', '1', parent: 'a')];
    final roots = RecordTree.build(accountDocType, docs);
    expect(roots.single.id, 'a');
  });

  test('parentFieldKey falls back to a self-referential link field', () {
    const derived = DocType(
      id: 'Account',
      name: 'Account',
      isTree: true,
      fields: [
        FieldDefinition(
            key: 'parent',
            type: FieldType.link,
            label: 'Parent',
            linkDocType: 'Account'),
      ],
    );
    expect(RecordTree.parentFieldKey(derived), 'parent');
  });

  testWidgets('renders the hierarchy and selects a tapped leaf',
      (tester) async {
    final docs = [
      account('a-assets', 'Assets', '1000'),
      account('a-cash', 'Cash', '1010', parent: 'a-assets'),
    ];
    Document? selected;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RecordTreeView(
          docType: accountDocType,
          documents: docs,
          selectedDocumentId: null,
          onSelect: (d) => selected = d,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Parent and (initially expanded) child are both visible.
    expect(find.text('Assets'), findsOneWidget);
    expect(find.text('Cash'), findsOneWidget);
    // The numeric code shows as a trailing label.
    expect(find.text('1010'), findsOneWidget);

    await tester.tap(find.text('Cash'));
    await tester.pump();
    expect(selected?.id, 'a-cash');
  });

  testWidgets('shows an empty state when there are no records',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: RecordTreeView(
          docType: accountDocType,
          documents: [],
          selectedDocumentId: null,
          onSelect: _noop,
        ),
      ),
    ));
    expect(find.text('No records'), findsOneWidget);
  });
}

void _noop(Document _) {}
