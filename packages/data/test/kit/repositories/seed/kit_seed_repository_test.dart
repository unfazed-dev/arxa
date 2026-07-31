import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_data/ids/kit_id_service.dart';
import 'package:appbox_kit_data/models/kit_entity_registration.dart';
import 'package:appbox_kit_data/query/kit_query.dart';
import 'package:appbox_kit_data/repositories/seed/kit_seed_persistence.dart';
import 'package:appbox_kit_data/repositories/seed/kit_seed_repository.dart';
import 'package:appbox_kit_data/repositories/seed/kit_seed_store.dart';
import 'package:appbox_kit_data/schema/kit_table_schema.dart';

/// KitSeedRepository tests, backed by [KitSeedStore] + [KitNoPersistence].
///
/// Branches under test:
/// - `getById` resolves the same row whether asked by seed key or by the
///   already-canonicalized UUID.
/// - `watchAll` replays the current list on listen (BehaviorSubject seed),
///   then emits again after an `upsert` and again after a `delete`.
/// - `KitQuery` evaluation: `eq`, `gt`, `lt`, `orderBy` ascending and
///   descending (with a `null` value always sorting last regardless of
///   direction), and `limit`; an `eq` filter on a reference column using a
///   seed key matches because the repository canonicalizes the query the
///   same way it canonicalizes writes.
/// - `delete` by seed key removes the row (by `getById` and `getAll`).
/// - `upsertMany` returns entities in the same order they were given.
class _Widget {
  final String id;
  final String name;
  final String? categoryId;
  final int? qty;

  const _Widget({
    required this.id,
    required this.name,
    this.categoryId,
    this.qty,
  });
}

final _schema = KitTableSchema(
  table: 'widgets',
  columns: const [
    KitColumn.id(),
    KitColumn('name', KitColumnType.text),
    KitColumn(
      'category',
      KitColumnType.reference,
      references: 'categories',
      nullable: true,
    ),
    KitColumn('qty', KitColumnType.integer, nullable: true),
  ],
);

final _registration = KitEntityRegistration<_Widget>(
  schema: _schema,
  fromJson: (json) => _Widget(
    id: json['id'] as String,
    name: json['name'] as String,
    categoryId: json['category'] as String?,
    qty: json['qty'] as int?,
  ),
  toJson: (w) => {
    'id': w.id,
    'name': w.name,
    'category': w.categoryId,
    'qty': w.qty,
  },
);

void main() {
  final idService = KitIdService();

  KitSeedRepository<_Widget> makeRepo() => KitSeedRepository<_Widget>(
        store: KitSeedStore(persistence: KitNoPersistence()),
        registration: _registration,
        idService: idService,
      );

  test('getById resolves by seed key and by the canonical uuid', () async {
    final repo = makeRepo();
    await repo.upsert(const _Widget(id: 'w-1', name: 'Alpha'));

    final canonical = idService.canonicalId('widgets', 'w-1');
    final byKey = await repo.getById('w-1');
    final byUuid = await repo.getById(canonical);

    expect(byKey, isNotNull);
    expect(byKey!.id, canonical);
    expect(byUuid, isNotNull);
    expect(byUuid!.id, canonical);
  });

  test('watchAll emits current list on listen, then again after upsert and delete',
      () async {
    final repo = makeRepo();

    final expectation = expectLater(
      repo.watchAll(),
      emitsInOrder([isEmpty, hasLength(1), isEmpty]),
    );

    await repo.upsert(const _Widget(id: 'w-1', name: 'Alpha'));
    await repo.delete('w-1');

    await expectation;
  });

  group('KitQuery evaluation', () {
    late KitSeedRepository<_Widget> repo;

    setUp(() async {
      repo = makeRepo();
      await repo.upsertMany(const [
        _Widget(id: 'w-1', name: 'Alpha', categoryId: 'cat-1', qty: 10),
        _Widget(id: 'w-2', name: 'Beta', categoryId: 'cat-2', qty: 5),
        _Widget(id: 'w-3', name: 'Gamma', categoryId: 'cat-1', qty: null),
        _Widget(id: 'w-4', name: 'Delta', qty: 20),
      ]);
    });

    test('eq filters to the matching row', () async {
      final results = await repo.getAll(
        const KitQuery(filters: [KitFilter.eq('name', 'Beta')]),
      );
      expect(results, hasLength(1));
      expect(results.single.name, 'Beta');
    });

    test('gt filters to rows strictly greater', () async {
      final results = await repo.getAll(
        const KitQuery(filters: [KitFilter.gt('qty', 10)]),
      );
      expect(results.map((w) => w.name), ['Delta']);
    });

    test('lt filters to rows strictly less', () async {
      final results = await repo.getAll(
        const KitQuery(filters: [KitFilter.lt('qty', 10)]),
      );
      expect(results.map((w) => w.name), ['Beta']);
    });

    test('orderBy ascending sorts nulls last', () async {
      final results = await repo.getAll(const KitQuery(orderBy: 'qty'));
      expect(results.map((w) => w.name), ['Beta', 'Alpha', 'Delta', 'Gamma']);
    });

    test('orderBy descending still sorts nulls last', () async {
      final results = await repo.getAll(
        const KitQuery(orderBy: 'qty', descending: true),
      );
      expect(results.map((w) => w.name), ['Delta', 'Alpha', 'Beta', 'Gamma']);
    });

    test('limit caps the result count after ordering', () async {
      final results = await repo.getAll(
        const KitQuery(orderBy: 'qty', limit: 2),
      );
      expect(results.map((w) => w.name), ['Beta', 'Alpha']);
    });

    test('eq filter on a reference column matches via a seed key', () async {
      final results = await repo.getAll(
        const KitQuery(filters: [KitFilter.eq('category', 'cat-1')]),
      );
      expect(results.map((w) => w.name).toSet(), {'Alpha', 'Gamma'});
    });
  });

  test('delete by seed key removes the row', () async {
    final repo = makeRepo();
    await repo.upsert(const _Widget(id: 'w-1', name: 'Alpha'));

    await repo.delete('w-1');

    expect(await repo.getById('w-1'), isNull);
    expect(await repo.getAll(), isEmpty);
  });

  test('upsertMany returns entities in the same order they were given', () async {
    final repo = makeRepo();

    final results = await repo.upsertMany(const [
      _Widget(id: 'w-3', name: 'Gamma'),
      _Widget(id: 'w-1', name: 'Alpha'),
      _Widget(id: 'w-2', name: 'Beta'),
    ]);

    expect(results.map((w) => w.name), ['Gamma', 'Alpha', 'Beta']);
  });
}
