import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_data/ids/arxa_kit_id_service.dart';
import 'package:arxa_kit_data/query/arxa_kit_query.dart';
import 'package:arxa_kit_data/schema/arxa_kit_table_schema.dart';

/// ArxaKitIdService tests.
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
  final products = ArxaKitTableSchema(
    table: 'products',
    columns: const [
      ArxaKitColumn.id(),
      ArxaKitColumn('name', ArxaKitColumnType.text),
      ArxaKitColumn(
        'category',
        ArxaKitColumnType.reference,
        references: 'categories',
        nullable: true,
      ),
      ArxaKitColumn('price', ArxaKitColumnType.real),
    ],
  );

  group('canonicalId', () {
    test('kit.data.id-service — same (table, key) yields identical UUID across instances', () {
      final a = ArxaKitIdService();
      final b = ArxaKitIdService();
      expect(a.canonicalId('products', 'p-1'), b.canonicalId('products', 'p-1'));
    });

    test('kit.data.id-service — different table, same key yields different UUID', () {
      final service = ArxaKitIdService();
      expect(
        service.canonicalId('products', 'x-1'),
        isNot(service.canonicalId('categories', 'x-1')),
      );
    });

    test('kit.data.id-service — valid-UUID key passes through lowercased', () {
      final service = ArxaKitIdService();
      const upper = 'A1B2C3D4-E5F6-4711-8899-AABBCCDDEEFF';
      expect(service.canonicalId('products', upper), upper.toLowerCase());
    });

    test('kit.data.id-service — empty key throws ArgumentError', () {
      final service = ArxaKitIdService();
      expect(
        () => service.canonicalId('products', ''),
        throwsArgumentError,
      );
    });

    test('kit.data.id-service — invalid namespace throws in the constructor', () {
      expect(
        () => ArxaKitIdService(namespace: 'not-a-uuid'),
        throwsArgumentError,
      );
    });
  });

  group('canonicalizeRow', () {
    test('kit.data.id-service — canonicalizes id and reference columns; leaves the rest alone', () {
      final service = ArxaKitIdService();
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

    test('kit.data.id-service — leaves a null reference column untouched', () {
      final service = ArxaKitIdService();
      final row = <String, dynamic>{
        'id': 'p-2',
        'name': 'Gadget',
        'category': null,
        'price': 1.0,
      };

      final out = service.canonicalizeRow(products, row);

      expect(out['category'], isNull);
    });

    test('kit.data.id-service — row missing id throws', () {
      final service = ArxaKitIdService();
      final row = <String, dynamic>{'name': 'no id'};

      expect(
        () => service.canonicalizeRow(products, row),
        throwsArgumentError,
      );
    });
  });

  group('canonicalizeQuery', () {
    test('kit.data.id-service — eq on the id column is canonicalized against the schema\'s own table', () {
      final service = ArxaKitIdService();
      final query = const ArxaKitQuery(filters: [ArxaKitFilter.eq('id', 'p-1')]);

      final out = service.canonicalizeQuery(products, query);

      expect(out.filters.single.value, service.canonicalId('products', 'p-1'));
    });

    test('kit.data.id-service — eq on a reference column is canonicalized against the REFERENCED table', () {
      final service = ArxaKitIdService();
      final query = const ArxaKitQuery(filters: [ArxaKitFilter.eq('category', 'cat-1')]);

      final out = service.canonicalizeQuery(products, query);

      expect(
        out.filters.single.value,
        service.canonicalId('categories', 'cat-1'),
        reason: 'reference filters canonicalize against the referenced '
            'table\'s namespace, not the querying table\'s',
      );
    });

    test('kit.data.id-service — gt/lt filters pass through untouched', () {
      final service = ArxaKitIdService();
      final query = const ArxaKitQuery(
        filters: [ArxaKitFilter.gt('price', 5), ArxaKitFilter.lt('price', 100)],
      );

      final out = service.canonicalizeQuery(products, query);

      expect(out.filters[0].value, 5);
      expect(out.filters[1].value, 100);
    });

    test('kit.data.id-service — eq on a non-id, non-reference column passes through untouched', () {
      final service = ArxaKitIdService();
      final query = const ArxaKitQuery(filters: [ArxaKitFilter.eq('name', 'Widget')]);

      final out = service.canonicalizeQuery(products, query);

      expect(out.filters.single.value, 'Widget');
    });

    test('kit.data.id-service — empty-filter query is returned as the same instance', () {
      final service = ArxaKitIdService();
      const query = ArxaKitQuery(orderBy: 'name');

      final out = service.canonicalizeQuery(products, query);

      expect(identical(out, query), isTrue);
    });
  });

  group('canonicalizePatch', () {
    test('kit.data.id-service — reference values canonicalize, scalars and nulls pass through', () {
      final service = ArxaKitIdService();

      final out = service.canonicalizePatch(products, {
        'category': 'cat-1',
        'name': 'Widget',
        'price': null,
      });

      expect(out['category'], service.canonicalId('categories', 'cat-1'));
      expect(out['name'], 'Widget');
      expect(out.containsKey('price'), isTrue,
          reason: 'a null patch value clears the column, it is not dropped');
      expect(out['price'], isNull);
    });

    test('kit.data.id-service — a patch containing the id column throws', () {
      final service = ArxaKitIdService();

      expect(
        () => service.canonicalizePatch(products, {'id': 'p-1', 'name': 'Widget'}),
        throwsArgumentError,
      );
    });
  });
}
