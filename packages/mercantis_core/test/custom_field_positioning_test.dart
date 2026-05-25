import 'package:mercantis_core/mercantis_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

/// Covers ADR-021 positioning: end-user `CustomField` rows are composed
/// into a `ResolvedMeta` at their declared `insert_after` position, and
/// fall back to the v1 "append" behaviour when the column is null or the
/// anchor field has been removed.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  late MercantisDatabase database;
  late MetadataRegistry registry;
  late MetaComposer composer;

  setUp(() async {
    database = await MercantisDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    registry = MetadataRegistry(database.db);
    composer = MetaComposer(registry, database.db);

    // Register a tiny base DocType: customer_name → email → phone.
    await registry.register(
      const DocType(
        id: 'Customer',
        name: 'Customer',
        module: 'CRM',
        fields: [
          FieldDefinition(
              key: 'customer_name', label: 'Customer Name', type: FieldType.data),
          FieldDefinition(
              key: 'email', label: 'Email', type: FieldType.data),
          FieldDefinition(
              key: 'phone', label: 'Phone', type: FieldType.data),
        ],
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  test('insert_after null falls back to append (v1 behaviour)', () async {
    await CustomField.save(
      database.db,
      CustomField(
        id: '',
        docTypeId: 'Customer',
        fieldDefinition: const FieldDefinition(
          key: 'vat_number',
          label: 'VAT Number',
          type: FieldType.data,
        ),
        // no insertAfter — should append
      ),
    );

    final meta = await composer.resolve('Customer');
    expect(
      meta.fields.map((f) => f.key).toList(),
      ['customer_name', 'email', 'phone', 'vat_number'],
    );
  });

  test('insert_after places the field directly after the anchor', () async {
    await CustomField.save(
      database.db,
      CustomField(
        id: '',
        docTypeId: 'Customer',
        fieldDefinition: const FieldDefinition(
          key: 'vat_number',
          label: 'VAT Number',
          type: FieldType.data,
        ),
        insertAfter: 'email',
      ),
    );

    final meta = await composer.resolve('Customer');
    expect(
      meta.fields.map((f) => f.key).toList(),
      ['customer_name', 'email', 'vat_number', 'phone'],
    );
  });

  test('multiple custom fields stack at the same anchor in save order',
      () async {
    await CustomField.save(
      database.db,
      CustomField(
        id: '',
        docTypeId: 'Customer',
        fieldDefinition: const FieldDefinition(
          key: 'vat_number',
          label: 'VAT',
          type: FieldType.data,
        ),
        insertAfter: 'email',
      ),
    );
    composer.invalidate('Customer');
    await CustomField.save(
      database.db,
      CustomField(
        id: '',
        docTypeId: 'Customer',
        fieldDefinition: const FieldDefinition(
          key: 'loyalty_tier',
          label: 'Loyalty Tier',
          type: FieldType.data,
        ),
        insertAfter: 'email',
      ),
    );

    final meta = await composer.resolve('Customer');
    // Each field is placed at "email + 1" at the moment of resolution; the
    // second one ends up immediately after `email`, pushing the first
    // further down. Implementation is order-stable, not ergonomic — the
    // important guarantee is no field is silently dropped.
    final keys = meta.fields.map((f) => f.key).toList();
    expect(keys, [
      'customer_name',
      'email',
      'loyalty_tier',
      'vat_number',
      'phone',
    ]);
  });

  test('unknown insert_after anchor falls back to append', () async {
    await CustomField.save(
      database.db,
      CustomField(
        id: '',
        docTypeId: 'Customer',
        fieldDefinition: const FieldDefinition(
          key: 'vat_number',
          label: 'VAT Number',
          type: FieldType.data,
        ),
        insertAfter: 'no_such_field',
      ),
    );

    final meta = await composer.resolve('Customer');
    expect(meta.fields.last.key, 'vat_number',
        reason:
            'When the anchor is missing, the field should land at the end of the form so it stays visible.');
  });

  test('insert_after round-trips through DB (null vs empty)', () async {
    await CustomField.save(
      database.db,
      CustomField(
        id: '',
        docTypeId: 'Customer',
        fieldDefinition: const FieldDefinition(
          key: 'a', label: 'A', type: FieldType.data,
        ),
        insertAfter: 'email',
      ),
    );
    await CustomField.save(
      database.db,
      CustomField(
        id: '',
        docTypeId: 'Customer',
        fieldDefinition: const FieldDefinition(
          key: 'b', label: 'B', type: FieldType.data,
        ),
      ),
    );

    final all = await CustomField.forDocType(database.db, 'Customer');
    expect(all.firstWhere((f) => f.fieldDefinition.key == 'a').insertAfter,
        'email');
    expect(all.firstWhere((f) => f.fieldDefinition.key == 'b').insertAfter,
        isNull);
  });
}
