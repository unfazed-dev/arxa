import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_data/arxa_kit_testing.dart';

/// Smoke tests for the [FakeArxaKitRepository] test double — proves the fake
/// honors the ArxaKitRepository contract the same way the seed backend does:
/// canonical-id lookups, ArxaKitQuery evaluation, stream-backed watchers.
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

final _registration = ArxaKitEntityRegistration<_Widget>(
  schema: ArxaKitTableSchema(
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
  final idService = ArxaKitIdService();

  FakeArxaKitRepository<_Widget> makeRepo({Iterable<_Widget>? seed}) =>
      FakeArxaKitRepository<_Widget>(
        registration: _registration,
        idService: idService,
        seed: seed,
      );

  test('kit.data.fake-repository — getById resolves by seed key and by the canonical uuid', () async {
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

  test('kit.data.fake-repository — upsert returns the stored entity with canonical ids and records it',
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

  test('kit.data.fake-repository — ArxaKitQuery evaluation: eq, gt, lt, orderBy, limit', () async {
    final repo = makeRepo(seed: [
      const _Widget(id: 'w-1', name: 'Alpha', categoryId: 'cat-1', qty: 5),
      const _Widget(id: 'w-2', name: 'Beta', categoryId: 'cat-1', qty: 1),
      const _Widget(id: 'w-3', name: 'Gamma', qty: 3),
    ]);

    // eq on a reference column by seed key (canonicalized like the backends).
    final inCat = await repo.getAll(
      const ArxaKitQuery(filters: [ArxaKitFilter.eq('category', 'cat-1')]),
    );
    expect(inCat.map((w) => w.name), ['Alpha', 'Beta']);

    final gt = await repo.getAll(
      const ArxaKitQuery(filters: [ArxaKitFilter.gt('qty', 2)]),
    );
    expect(gt.map((w) => w.name), containsAll(['Alpha', 'Gamma']));

    final lt = await repo.getAll(
      const ArxaKitQuery(filters: [ArxaKitFilter.lt('qty', 5)]),
    );
    expect(lt.map((w) => w.name), containsAll(['Beta', 'Gamma']));

    // Ascending: null qty sorts last.
    final asc = await repo.getAll(const ArxaKitQuery(orderBy: 'name'));
    expect(asc.map((w) => w.name), ['Alpha', 'Beta', 'Gamma']);

    final limited = await repo.getAll(
      const ArxaKitQuery(orderBy: 'name', descending: true, limit: 2),
    );
    expect(limited.map((w) => w.name), ['Gamma', 'Beta']);

    expect(repo.getAllCalls, hasLength(5));
  });

  test('kit.data.fake-repository — watchAll emits the current set, then again after upsert and delete',
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

  test('kit.data.fake-repository — scripted errors throw from the matching operations', () async {
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

  test('kit.data.fake-repository — clear() empties the table and notifies watchers', () async {
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

  test('kit.data.fake-repository — patch merges only the differing columns and records the stored entity', () async {
    final repo = makeRepo(seed: [const _Widget(id: 'w-1', name: 'Alpha', qty: 1)]);
    const original = _Widget(id: 'w-1', name: 'Alpha', qty: 1);

    final patched =
        await repo.patch(original, const _Widget(id: 'w-1', name: 'Alpha', qty: 9));

    expect(patched.qty, 9);
    expect(patched.name, 'Alpha');
    expect(repo.patchedEntities.single.qty, 9);
  });

  test('kit.data.fake-repository — patchError scripts a patch failure', () async {
    final repo = makeRepo(seed: [const _Widget(id: 'w-1', name: 'Alpha')]);
    final boom = StateError('boom');

    repo.patchError = boom;

    expect(
      () => repo.patch(
        const _Widget(id: 'w-1', name: 'Alpha'),
        const _Widget(id: 'w-1', name: 'Beta'),
      ),
      throwsA(boom),
    );
  });
}
