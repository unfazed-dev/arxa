import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_data/testing.dart';

/// Smoke tests for the [FakeKitRepository] test double — proves the fake
/// honors the KitRepository contract the same way the seed backend does:
/// canonical-id lookups, KitQuery evaluation, stream-backed watchers.
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

final _registration = KitEntityRegistration<_Widget>(
  schema: KitTableSchema(
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
  ),
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

  FakeKitRepository<_Widget> makeRepo({Iterable<_Widget>? seed}) =>
      FakeKitRepository<_Widget>(
        registration: _registration,
        idService: idService,
        seed: seed,
      );

  test('getById resolves by seed key and by the canonical uuid', () async {
    final repo = makeRepo(seed: [const _Widget(id: 'w-1', name: 'Alpha')]);

    final canonical = idService.canonicalId('widgets', 'w-1');
    final byKey = await repo.getById('w-1');
    final byUuid = await repo.getById(canonical);

    expect(byKey, isNotNull);
    expect(byKey!.id, canonical);
    expect(byUuid, isNotNull);
    expect(byUuid!.id, canonical);
    expect(repo.getByIdCalls, ['w-1', canonical]);
  });

  test('upsert returns the stored entity with canonical ids and records it',
      () async {
    final repo = makeRepo();

    final stored = await repo.upsert(
      const _Widget(id: 'w-1', name: 'Alpha', categoryId: 'cat-1'),
    );

    expect(stored.id, idService.canonicalId('widgets', 'w-1'));
    expect(stored.categoryId, idService.canonicalId('categories', 'cat-1'));
    expect(repo.upsertedEntities, hasLength(1));
    expect(repo.length, 1);
  });

  test('KitQuery evaluation: eq, gt, lt, orderBy, limit', () async {
    final repo = makeRepo(seed: [
      const _Widget(id: 'w-1', name: 'Alpha', categoryId: 'cat-1', qty: 5),
      const _Widget(id: 'w-2', name: 'Beta', categoryId: 'cat-1', qty: 1),
      const _Widget(id: 'w-3', name: 'Gamma', qty: 3),
    ]);

    // eq on a reference column by seed key (canonicalized like the backends).
    final inCat = await repo.getAll(
      const KitQuery(filters: [KitFilter.eq('category', 'cat-1')]),
    );
    expect(inCat.map((w) => w.name), ['Alpha', 'Beta']);

    final gt = await repo.getAll(
      const KitQuery(filters: [KitFilter.gt('qty', 2)]),
    );
    expect(gt.map((w) => w.name), containsAll(['Alpha', 'Gamma']));

    final lt = await repo.getAll(
      const KitQuery(filters: [KitFilter.lt('qty', 5)]),
    );
    expect(lt.map((w) => w.name), containsAll(['Beta', 'Gamma']));

    // Ascending: null qty sorts last.
    final asc = await repo.getAll(const KitQuery(orderBy: 'name'));
    expect(asc.map((w) => w.name), ['Alpha', 'Beta', 'Gamma']);

    final limited = await repo.getAll(
      const KitQuery(orderBy: 'name', descending: true, limit: 2),
    );
    expect(limited.map((w) => w.name), ['Gamma', 'Beta']);

    expect(repo.getAllCalls, hasLength(5));
  });

  test('watchAll emits the current set, then again after upsert and delete',
      () async {
    final repo = makeRepo(seed: [const _Widget(id: 'w-1', name: 'Alpha')]);

    final expectation = expectLater(
      repo.watchAll(),
      emitsInOrder([
        isA<List<_Widget>>().having((l) => l.length, 'length', 1),
        isA<List<_Widget>>().having((l) => l.length, 'length', 2),
        isA<List<_Widget>>().having((l) => l.length, 'length', 1),
      ]),
    );

    await repo.upsert(const _Widget(id: 'w-2', name: 'Beta'));
    await repo.delete('w-1');

    await expectation;
    expect(repo.watchAllCalls, hasLength(1));
    expect(repo.deletedIds, ['w-1']);
  });

  test('scripted errors throw from the matching operations', () async {
    final repo = makeRepo(seed: [const _Widget(id: 'w-1', name: 'Alpha')]);
    final boom = StateError('boom');

    repo.readError = boom;
    expect(() => repo.getById('w-1'), throwsA(boom));
    expect(() => repo.getAll(), throwsA(boom));

    repo.readError = null;
    repo.upsertError = boom;
    expect(() => repo.upsert(const _Widget(id: 'w-2', name: 'B')), throwsA(boom));

    repo.upsertError = null;
    repo.deleteError = boom;
    expect(() => repo.delete('w-1'), throwsA(boom));

    // reset clears the scripting (and the records) — the repo answers again.
    repo.reset();
    expect(await repo.getById('w-1'), isNotNull);
    expect(repo.getByIdCalls, ['w-1']); // record restarted after reset
  });

  test('clear() empties the table and notifies watchers', () async {
    final repo = makeRepo(seed: [const _Widget(id: 'w-1', name: 'Alpha')]);

    final expectation = expectLater(
      repo.watchAll(),
      emitsInOrder([
        isA<List<_Widget>>().having((l) => l.length, 'length', 1),
        isA<List<_Widget>>().having((l) => l.length, 'length', 0),
      ]),
    );

    repo.clear();
    await expectation;
    expect(repo.currentRows, isEmpty);
  });
}
