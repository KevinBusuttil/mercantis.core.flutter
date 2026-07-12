import 'package:mercantis_core/mercantis_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

/// Field tokens in naming-series patterns (`.{field_key}.`): the counter is
/// keyed on the fully resolved prefix, so a field-parameterised series
/// sequences independently per value — the per-till receipt series that
/// makes two POS devices structurally unable to mint the same id.
void main() {
  setUpAll(sqfliteFfiInit);

  test('expandFields substitutes, sanitises, and collapses blanks', () {
    expect(
      NamingSeriesStrategy.expandFields(
          'POS-.{till_series}.-.####', {'till_series': 'TILL1'}),
      'POS-.TILL1.-.####',
    );
    // Hostile values sanitise to id-safe characters.
    expect(
      NamingSeriesStrategy.expandFields(
          'POS-.{till_series}.-.####', {'till_series': 'a/b c*'}),
      'POS-.abc.-.####',
    );
    // Missing or blank collapses to a single dot — well-formed, not '..'.
    expect(
      NamingSeriesStrategy.expandFields('POS-.{till_series}.-.####', {}),
      'POS-.-.####',
    );
    // Patterns without tokens pass through untouched.
    expect(
      NamingSeriesStrategy.expandFields('SINV-.YYYY.-.####', {'x': 1}),
      'SINV-.YYYY.-.####',
    );
  });

  test('two field values sequence independently from counter 1', () async {
    final database = await MercantisDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(database.close);

    const docType = DocType(id: 'Receipt', name: 'Receipt', fields: []);
    const strategy = NamingSeriesStrategy('R-.{till}.-.###');
    final context = NamingContext(database: database.db, userId: 'u', deviceId: 'devA');

    Future<String> mint(String till) => strategy.resolve(
          docType,
          Document(id: '', docType: 'Receipt', payload: {'till': till}),
          context,
        );

    final a1 = await mint('T1');
    final a2 = await mint('T1');
    final b1 = await mint('T2');

    // Same till increments; a different till starts its own series — no
    // shared counter, no possible collision.
    expect(a1, isNot(a2));
    expect(a1, contains('T1'));
    expect(b1, contains('T2'));
    expect(a1.substring(a1.lastIndexOf('-')),
        b1.substring(b1.lastIndexOf('-'))); // both begin at their series' 001
  });
}
