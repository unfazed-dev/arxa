import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_data/ids/appbox_kit_id_service.dart';
import 'package:appbox_kit_data/query/appbox_kit_query.dart';
import 'package:appbox_kit_data/schema/appbox_kit_table_schema.dart';

/// AppBoxKitIdService tests.
///
/// Branches under test:
/// - `canonicalId`: determinism across instances (same table/key → same
///   UUID), table-scoping (same key, different table → different UUID),
///   UUID pass-through (lowercased), empty-key rejection, and namespace
///   validation in the constructor.
/// - `canonicalizeRow`: the id column and every reference column are
///   canonicalized; everything else (including a null reference) is left
///   alone; a row missing `id` throws.
/// - `canonicalizeQuery`: `eq` filters on the id column or a reference
///   column get canonicalized — a reference column against the
///   *referenced* table's namespace, not the querying table's; `gt`/`lt`
///   and filters on plain columns pass through untouched; an empty-filter
///   query is returned as the same instance (`identical`).
void main() {
  final products = AppBoxKitTableSchema(
    table: 'products',
    columns: const [
      AppBoxKitColumn.id(),
      AppBoxKitColumn('name', AppBoxKitColumnType.text),
      AppBoxKitColumn(
        'category',
        AppBoxKitColumnType.reference,
        references: 'categories',
        nullable: true,
      ),
      AppBoxKitColumn('price', AppBoxKitColumnType.real),
    ],
  );

  group('canonicalId', () {
    test('same (table, key) yields identical UUID across instances', () {
      final a = AppBoxKitIdService();
      final b = AppBoxKitIdService();
      expect(a.canonicalId('products', 'p-1'), b.canonicalId('products', 'p-1'));
    });

    test('different table, same key yields different UUID', () {
      final service = AppBoxKitIdService();
      expect(
        service.canonicalId('products', 'x-1'),
        isNot(service.canonicalId('categories', 'x-1')),
      );
    });

    test('valid-UUID key passes through lowercased', () {
      final service = AppBoxKitIdService();
      const upper = 'A1B2C3D4-E5F6-4711-8899-AABBCCDDEEFF';
      expect(service.canonicalId('products', upper), upper.toLowerCase());
    });

    test('empty key throws ArgumentError', () {
      final service = AppBoxKitIdService();
      expect(
        () => service.canonicalId('products', ''),
        throwsArgumentError,
      );
    });

    test('invalid namespace throws in the constructor', () {
      expect(
        () => AppBoxKitIdService(namespace: 'not-a-uuid'),
        throwsArgumentError,
      );
    });
  });

  group('canonicalizeRow', () {
    test('canonicalizes id and reference columns; leaves the rest alone', () {
      final service = AppBoxKitIdService();
      final row = <String, dynamic>{
        'id': 'p-1',
        'name': 'Widget',
        'category': 'cat-1',
        'price': 9.99,
      };

      final out = service.canonicalizeRow(products, row);

      expect(out['id'], service.canonicalId('products', 'p-1'));
      expect(out['category'], service.canonicalId('categories', 'cat-1'));
      expect(out['name'], 'Widget');
      expect(out['price'], 9.99);
    });

    test('leaves a null reference column untouched', () {
      final service = AppBoxKitIdService();
      final row = <String, dynamic>{
        'id': 'p-2',
        'name': 'Gadget',
        'category': null,
        'price': 1.0,
      };

      final out = service.canonicalizeRow(products, row);

      expect(out['category'], isNull);
    });

    test('row missing id throws', () {
      final service = AppBoxKitIdService();
      final row = <String, dynamic>{'name': 'no id'};

      expect(
        () => service.canonicalizeRow(products, row),
        throwsArgumentError,
      );
    });
  });

  group('canonicalizeQuery', () {
    test('eq on the id column is canonicalized against the schema\'s own table', () {
      final service = AppBoxKitIdService();
      final query = const AppBoxKitQuery(filters: [AppBoxKitFilter.eq('id', 'p-1')]);

      final out = service.canonicalizeQuery(products, query);

      expect(out.filters.single.value, service.canonicalId('products', 'p-1'));
    });

    test('eq on a reference column is canonicalized against the REFERENCED table', () {
      final service = AppBoxKitIdService();
      final query = const AppBoxKitQuery(filters: [AppBoxKitFilter.eq('category', 'cat-1')]);

      final out = service.canonicalizeQuery(products, query);

      expect(
        out.filters.single.value,
        service.canonicalId('categories', 'cat-1'),
        reason: 'reference filters canonicalize against the referenced '
            'table\'s namespace, not the querying table\'s',
      );
    });

    test('gt/lt filters pass through untouched', () {
      final service = AppBoxKitIdService();
      final query = const AppBoxKitQuery(
        filters: [AppBoxKitFilter.gt('price', 5), AppBoxKitFilter.lt('price', 100)],
      );

      final out = service.canonicalizeQuery(products, query);

      expect(out.filters[0].value, 5);
      expect(out.filters[1].value, 100);
    });

    test('eq on a non-id, non-reference column passes through untouched', () {
      final service = AppBoxKitIdService();
      final query = const AppBoxKitQuery(filters: [AppBoxKitFilter.eq('name', 'Widget')]);

      final out = service.canonicalizeQuery(products, query);

      expect(out.filters.single.value, 'Widget');
    });

    test('empty-filter query is returned as the same instance', () {
      final service = AppBoxKitIdService();
      const query = AppBoxKitQuery(orderBy: 'name');

      final out = service.canonicalizeQuery(products, query);

      expect(identical(out, query), isTrue);
    });
  });
}
