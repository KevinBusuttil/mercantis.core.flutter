import 'package:mercantis_core/mercantis_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

/// Covers ADR-040: DocType.namingRules — conditional per-company / per-fiscal
/// naming series chosen before the plain namingRule fallback.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase database;
  late NamingService naming;

  setUp(() async {
    database = await MercantisDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    naming = NamingService();
  });

  tearDown(() => database.close());

  NamingContext ctx() => NamingContext(database: database.db, userId: 'u');

  Future<String> nameFor(DocType dt, Map<String, dynamic> payload) =>
      naming.resolve(dt, Document(id: '', docType: dt.id, payload: payload), ctx());

  test('picks the first matching conditional series', () async {
    const dt = DocType(
      id: 'Sales Invoice',
      name: 'Sales Invoice',
      namingRule: 'SINV-.YYYY.-.####', // fallback
      namingRules: [
        DocumentNamingRule(condition: 'company == "ACME"', series: 'ACME-.####'),
        DocumentNamingRule(condition: 'company == "GLOBEX"', series: 'GLX-.####'),
      ],
      fields: [
        FieldDefinition(key: 'company', label: 'Company', type: FieldType.data),
      ],
    );

    final acme = await nameFor(dt, {'company': 'ACME'});
    expect(acme, 'ACME-0001');

    final globex = await nameFor(dt, {'company': 'GLOBEX'});
    expect(globex, 'GLX-0001');
  });

  test('falls back to namingRule when no condition matches', () async {
    const dt = DocType(
      id: 'Sales Invoice',
      name: 'Sales Invoice',
      namingRule: 'SINV-.YYYY.-.####',
      namingRules: [
        DocumentNamingRule(condition: 'company == "ACME"', series: 'ACME-.####'),
      ],
      fields: [
        FieldDefinition(key: 'company', label: 'Company', type: FieldType.data),
      ],
    );

    final other = await nameFor(dt, {'company': 'OTHER'});
    expect(other, startsWith('SINV-'));
    expect(other, endsWith('0001'));
  });

  test('a null/empty condition always matches (unconditional series)', () async {
    const dt = DocType(
      id: 'Lead',
      name: 'Lead',
      namingRules: [DocumentNamingRule(series: 'LEAD-.####')],
    );
    expect(await nameFor(dt, {}), 'LEAD-0001');
  });

  test('round-trips through JSON', () {
    const dt = DocType(
      id: 'X',
      name: 'X',
      namingRules: [
        DocumentNamingRule(condition: 'a == 1', series: 'X-.####'),
        DocumentNamingRule(series: 'Y-.####'),
      ],
    );
    final back = DocType.fromJson(dt.toJson());
    expect(back.namingRules.length, 2);
    expect(back.namingRules.first.condition, 'a == 1');
    expect(back.namingRules.first.series, 'X-.####');
    expect(back.namingRules[1].condition, isNull);
  });
}
