import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_data/ids/arxa_kit_id_service.dart';
import 'package:arxa_kit_data/models/arxa_kit_entity_registration.dart';
import 'package:arxa_kit_data/query/arxa_kit_query.dart';
import 'package:arxa_kit_data/repositories/seed/arxa_kit_seed_persistence.dart';
import 'package:arxa_kit_data/repositories/seed/arxa_kit_seed_repository.dart';
import 'package:arxa_kit_data/repositories/seed/arxa_kit_seed_store.dart';
import 'package:arxa_kit_data/schema/arxa_kit_table_schema.dart';

/// ArxaKitSeedRepository tests, backed by [ArxaKitSeedStore] + [ArxaKitNoPersistence].
///
/// Branches under test:
/// - `getById` resolves the same row whether asked by seed key or by the
///   already-canonicalized UUID.
/// - `watchAll` replays the current list on listen (BehaviorSubject seed),
///   then emits again after an `upsert` and again after a `delete`.
/// - `ArxaKitQuery` evaluation: `eq`, `gt`, `lt`, `orderBy` ascending and
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

final _schema = ArxaKitTableSchema(
  table: 'widgets',
  columns: const [
    ArxaKitColumn.id(),
    ArxaKitColumn('name', ArxaKitColumnType.text),
    ArxaKitColumn(
      'category',
      ArxaKitColumnType.reference,
      references: 'categories',
      nullable: true,
    ),
    ArxaKitColumn('qty', ArxaKitColumnType.integer, nullable: true),
  ],
);

final _registration = ArxaKitEntityRegistration<_Widget>(
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
  final idService = ArxaKitIdService();

  ArxaKitSeedRepository<_Widget> makeRepo() => ArxaKitSeedRepository<_Widget>(
        store: ArxaKitSeedStore(persistence: ArxaKitNoPersistence()),
        registration: _registration,
        idService: idService,
      );

  test('kit.data.seed-repos — getById resolves by seed key and by the canonical uuid', () async {
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

  test('kit.data.seed-repos — watchAll emits current list on listen, then again after upsert and delete',
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

  group('ArxaKitQuery evaluation', () {
    late ArxaKitSeedRepository<_Widget> repo;

    setUp(() async {
      repo = makeRepo();
      await repo.upsertMany(const [
        _Widget(id: 'w-1', name: 'Alpha', categoryId: 'cat-1', qty: 10),
        _Widget(id: 'w-2', name: 'Beta', categoryId: 'cat-2', qty: 5),
        _Widget(id: 'w-3', name: 'Gamma', categoryId: 'cat-1', qty: null),
        _Widget(id: 'w-4', name: 'Delta', qty: 20),
      ]);
    });

    test('kit.data.seed-repos — eq filters to the matching row', () async {
      final results = await repo.getAll(
        const ArxaKitQuery(filters: [ArxaKitFilter.eq('name', 'Beta')]),
      );
      expect(results, hasLength(1));
      expect(results.single.name, 'Beta');
    });

    test('kit.data.seed-repos — gt filters to rows strictly greater', () async {
      final results = await repo.getAll(
        const ArxaKitQuery(filters: [ArxaKitFilter.gt('qty', 10)]),
      );
      expect(results.map((w) => w.name), ['Delta']);
    });

    test('kit.data.seed-repos — lt filters to rows strictly less', () async {
      final results = await repo.getAll(
        const ArxaKitQuery(filters: [ArxaKitFilter.lt('qty', 10)]),
      );
      expect(results.map((w) => w.name), ['Beta']);
    });

    test('kit.data.seed-repos — orderBy ascending sorts nulls last', () async {
      final results = await repo.getAll(const ArxaKitQuery(orderBy: 'qty'));
      expect(results.map((w) => w.name), ['Beta', 'Alpha', 'Delta', 'Gamma']);
    });

    test('kit.data.seed-repos — orderBy descending still sorts nulls last', () async {
      final results = await repo.getAll(
        const ArxaKitQuery(orderBy: 'qty', descending: true),
      );
      expect(results.map((w) => w.name), ['Delta', 'Alpha', 'Beta', 'Gamma']);
    });

    test('kit.data.seed-repos — limit caps the result count after ordering', () async {
      final results = await repo.getAll(
        const ArxaKitQuery(orderBy: 'qty', limit: 2),
      );
      expect(results.map((w) => w.name), ['Beta', 'Alpha']);
    });

    test('kit.data.seed-repos — eq filter on a reference column matches via a seed key', () async {
      final results = await repo.getAll(
        const ArxaKitQuery(filters: [ArxaKitFilter.eq('category', 'cat-1')]),
      );
      expect(results.map((w) => w.name).toSet(), {'Alpha', 'Gamma'});
    });
  });

  test('kit.data.seed-repos — delete by seed key removes the row', () async {
    final repo = makeRepo();
    await repo.upsert(const _Widget(id: 'w-1', name: 'Alpha'));

    await repo.delete('w-1');

    expect(await repo.getById('w-1'), isNull);
    expect(await repo.getAll(), isEmpty);
  });

  test('kit.data.seed-repos — upsertMany returns entities in the same order they were given', () async {
    final repo = makeRepo();

    final results = await repo.upsertMany(const [
      _Widget(id: 'w-3', name: 'Gamma'),
      _Widget(id: 'w-1', name: 'Alpha'),
      _Widget(id: 'w-2', name: 'Beta'),
    ]);

    expect(results.map((w) => w.name), ['Gamma', 'Alpha', 'Beta']);
  });

  group('patch', () {
    test('kit.data.seed-repos — patch writes only the differing columns, leaving a concurrent edit to another column intact', () async {
      final repo = makeRepo();
      const original = _Widget(id: 'w-1', name: 'Alpha', qty: 1);
      await repo.upsert(original);

      // Another surface edits `name` after `original` was read.
      await repo.upsert(const _Widget(id: 'w-1', name: 'Alpha edited', qty: 1));

      final patched =
          await repo.patch(original, const _Widget(id: 'w-1', name: 'Alpha', qty: 5));

      expect(patched.qty, 5);
      expect(patched.name, 'Alpha edited',
          reason: 'the concurrent edit to a column the patch did not touch survives');
    });

    test('kit.data.seed-repos — patch clearing a nullable column stores the null', () async {
      final repo = makeRepo();
      const original = _Widget(id: 'w-1', name: 'Alpha', categoryId: 'cat-1', qty: 3);
      await repo.upsert(original);

      final patched =
          await repo.patch(original, const _Widget(id: 'w-1', name: 'Alpha', qty: 3));

      expect(patched.categoryId, isNull);
      expect((await repo.getById('w-1'))!.categoryId, isNull);
    });

    test('kit.data.seed-repos — patch canonicalizes a reference column inside the diff', () async {
      final repo = makeRepo();
      const original = _Widget(id: 'w-1', name: 'Alpha');
      await repo.upsert(original);

      await repo.patch(original, const _Widget(id: 'w-1', name: 'Alpha', categoryId: 'cat-2'));

      final stored = await repo.getById('w-1');
      expect(stored!.categoryId, idService.canonicalId('categories', 'cat-2'));
    });

    test('kit.data.seed-repos — patch on a missing row throws instead of creating it', () async {
      final repo = makeRepo();

      expect(
        () => repo.patch(
          const _Widget(id: 'ghost', name: 'A'),
          const _Widget(id: 'ghost', name: 'B'),
        ),
        throwsStateError,
      );
    });

    test('kit.data.seed-repos — patch with no differing columns writes nothing', () async {
      final repo = makeRepo();
      const original = _Widget(id: 'w-1', name: 'Alpha', qty: 1);
      await repo.upsert(original);

      var emissions = 0;
      final sub = repo.watchById('w-1').listen((_) => emissions++);
      await Future<void>.delayed(Duration.zero); // flush the seeded replay

      final result = await repo.patch(original, original);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(result.qty, 1);
      expect(emissions, 1, reason: 'no store write, no watcher re-emit');
    });

    test('kit.data.seed-repos — patch rejects a diff that would re-address the row', () async {
      final repo = makeRepo();
      await repo.upsert(const _Widget(id: 'w-1', name: 'Alpha'));

      expect(
        () => repo.patch(
          const _Widget(id: 'w-1', name: 'Alpha'),
          const _Widget(id: 'w-2', name: 'Alpha'),
        ),
        throwsArgumentError,
      );
    });
  });
}
