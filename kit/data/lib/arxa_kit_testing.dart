/// Test doubles for arxa_kit_data.
///
/// Import this from tests to run repositories and facades fully in memory —
/// no Supabase client, no Appwrite client, no fixture assets, no snapshot
/// persistence:
///
/// ```dart
/// final products = FakeArxaKitRepository<Product>(
///   registration: productRegistration,
///   seed: [const Product(id: 'p-1', name: 'Shoes')],
/// );
/// arxaKitLocator.registerSingleton<ArxaKitRepository<Product>>(products);
///
/// final facade = ProductsFacade();
/// expect(await facade.featured(), hasLength(1));
/// expect(products.getAllCalls.single.orderBy, 'name');
/// ```
library;

import 'dart:async';

// This library IS the test-support surface: the contract runner below needs
// test()/expect(), and only tests ever import it (dev_dependency by design).
// ignore: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:rxdart/rxdart.dart';

import 'facades/arxa_kit_data_facade.dart';
import 'ids/arxa_kit_id_service.dart';
import 'models/arxa_kit_entity_registration.dart';
import 'query/arxa_kit_query.dart';
import 'repositories/arxa_kit_repository.dart';
import 'schema/arxa_kit_table_schema.dart';

export 'facades/arxa_kit_data_facade.dart';
export 'ids/arxa_kit_id_service.dart';
export 'models/arxa_kit_entity_registration.dart';
export 'query/arxa_kit_query.dart';
export 'repositories/arxa_kit_repository.dart';
export 'schema/arxa_kit_table_schema.dart';

/// An in-memory, stream-backed [ArxaKitRepository] — the test double for the
/// swap seam.
///
/// Rows live as canonicalized JSON (the same wire shape the seed backend
/// stores) keyed by canonical id, behind a seeded [BehaviorSubject], so
/// `listen*` emits the current result set immediately and again on every
/// write. ID canonicalization and [ArxaKitQuery] evaluation (`eq` / `gt` / `lt` /
/// `orderBy` with nulls-last / `limit`) mirror `ArxaKitSeedRepository` — if the
/// seed engine's semantics change, change this fake too.
///
/// Canonicalization is always on (default-namespace [ArxaKitIdService] unless one
/// is passed), matching `ArxaKitData.initialize`: seed keys like `p-1` and their
/// v5 UUIDs address the same row on reads and writes alike.
class FakeArxaKitRepository<T> implements ArxaKitRepository<T> {
  FakeArxaKitRepository({
    required this.registration,
    ArxaKitIdService? idService,
    Iterable<T>? seed,
  }) : idService = idService ?? ArxaKitIdService() {
    if (seed != null) seedAll(seed);
  }

  /// The entity codec + schema this repository serves.
  final ArxaKitEntityRegistration<T> registration;

  /// The canonicalizer applied to ids, reference columns, and `eq` filters.
  final ArxaKitIdService idService;

  final BehaviorSubject<Map<String, Map<String, dynamic>>> _rows$ =
      BehaviorSubject<Map<String, Map<String, dynamic>>>.seeded(const {});

  // ---- call records --------------------------------------------------------

  /// Every raw `id` passed to [getById], in call order.
  final List<String> getByIdCalls = [];

  /// Every raw [ArxaKitQuery] passed to [getAll], in call order.
  final List<ArxaKitQuery> getAllCalls = [];

  /// Every raw `id` passed to [watchById], in call order.
  final List<String> watchByIdCalls = [];

  /// Every raw [ArxaKitQuery] passed to [watchAll], in call order.
  final List<ArxaKitQuery> watchAllCalls = [];

  /// Every entity returned by [upsert] (i.e. as stored, canonical ids),
  /// in call order. [upsertMany] records one entry per entity.
  final List<T> upsertedEntities = [];

  /// Every entity returned by [patch], in call order.
  final List<T> patchedEntities = [];

  /// Number of [upsertMany] calls.
  int upsertManyCallCount = 0;

  /// Every raw `id` passed to [delete], in call order.
  final List<String> deletedIds = [];

  // ---- scripted failures ----------------------------------------------------

  /// When non-null, [getById] / [getAll] throw this instead of answering.
  Object? readError;

  /// When non-null, [upsert] / [upsertMany] throw this instead of writing.
  Object? upsertError;

  /// When non-null, [patch] throws this instead of writing.
  Object? patchError;

  /// When non-null, [delete] throws this instead of removing the row.
  Object? deleteError;

  String get _table => registration.schema.table;

  String get _idColumn => registration.schema.idColumn.name;

  // ---- ArxaKitRepository ---------------------------------------------------------

  @override
  Future<T?> getById(String id) async {
    getByIdCalls.add(id);
    _throwIf(readError);
    final row = _rows$.value[idService.canonicalId(_table, id)];
    return row == null ? null : registration.fromJson(row);
  }

  @override
  Future<List<T>> getAll([ArxaKitQuery query = const ArxaKitQuery()]) async {
    getAllCalls.add(query);
    _throwIf(readError);
    return _evaluate(_rows$.value, _canonicalize(query));
  }

  @override
  Stream<T?> watchById(String id) {
    watchByIdCalls.add(id);
    final canonical = idService.canonicalId(_table, id);
    return _rows$.map((rows) {
      final row = rows[canonical];
      return row == null ? null : registration.fromJson(row);
    });
  }

  @override
  Stream<List<T>> watchAll([ArxaKitQuery query = const ArxaKitQuery()]) {
    watchAllCalls.add(query);
    final canonical = _canonicalize(query);
    return _rows$.map((rows) => _evaluate(rows, canonical));
  }

  @override
  Future<T> upsert(T entity) async {
    _throwIf(upsertError);
    final row = idService.canonicalizeRow(
      registration.schema,
      registration.toJson(entity),
    );
    final next = Map<String, Map<String, dynamic>>.from(_rows$.value);
    next[row[_idColumn] as String] = row;
    _rows$.add(next);
    final stored = registration.fromJson(row);
    upsertedEntities.add(stored);
    return stored;
  }

  @override
  Future<List<T>> upsertMany(List<T> entities) async {
    upsertManyCallCount++;
    final result = <T>[];
    for (final entity in entities) {
      result.add(await upsert(entity));
    }
    return result;
  }

  @override
  Future<T> patch(T original, T patched) async {
    _throwIf(patchError);
    final originalJson = registration.toJson(original);
    final canonical = idService.canonicalId(_table, originalJson[_idColumn]!);
    final diff = arxaKitJsonPatch(originalJson, registration.toJson(patched));
    if (diff.isEmpty) return patched;
    final row = _rows$.value[canonical];
    if (row == null) {
      throw StateError('patch: no "$_table" row "$canonical"');
    }
    final merged = <String, dynamic>{
      ...row,
      ...idService.canonicalizePatch(registration.schema, diff),
    };
    final next = Map<String, Map<String, dynamic>>.from(_rows$.value);
    next[canonical] = merged;
    _rows$.add(next);
    final stored = registration.fromJson(merged);
    patchedEntities.add(stored);
    return stored;
  }

  @override
  Future<void> delete(String id) async {
    deletedIds.add(id);
    _throwIf(deleteError);
    final next = Map<String, Map<String, dynamic>>.from(_rows$.value);
    next.remove(idService.canonicalId(_table, id));
    _rows$.add(next);
  }

  // ---- test controls ---------------------------------------------------------

  /// Inserts [entities] WITHOUT touching the call records — for arranging a
  /// starting table. Same canonicalization as [upsert].
  void seedAll(Iterable<T> entities) {
    final next = Map<String, Map<String, dynamic>>.from(_rows$.value);
    for (final entity in entities) {
      final row = idService.canonicalizeRow(
        registration.schema,
        registration.toJson(entity),
      );
      next[row[_idColumn] as String] = row;
    }
    _rows$.add(next);
  }

  /// The current rows, as stored entities (canonical ids), unordered.
  List<T> get currentRows =>
      _rows$.value.values.map(registration.fromJson).toList(growable: false);

  /// The number of rows currently stored.
  int get length => _rows$.value.length;

  /// Removes every row (emits to watchers). Call records are kept.
  void clear() => _rows$.add(const {});

  /// Clears the call records and scripted failures (rows are kept; use
  /// [clear] to empty the table).
  void reset() {
    getByIdCalls.clear();
    getAllCalls.clear();
    watchByIdCalls.clear();
    watchAllCalls.clear();
    upsertedEntities.clear();
    patchedEntities.clear();
    upsertManyCallCount = 0;
    deletedIds.clear();
    readError = null;
    upsertError = null;
    patchError = null;
    deleteError = null;
  }

  /// Closes the backing subject.
  Future<void> dispose() => _rows$.close();

  // ---- query evaluation (mirrors ArxaKitSeedRepository._evaluate) -----------------

  void _throwIf(Object? error) {
    if (error != null) throw error;
  }

  ArxaKitQuery _canonicalize(ArxaKitQuery query) =>
      idService.canonicalizeQuery(registration.schema, query);

  List<T> _evaluate(Map<String, Map<String, dynamic>> rows, ArxaKitQuery query) {
    var values = rows.values
        .where((row) => _matchesAll(row, query.filters))
        .toList();

    final orderBy = query.orderBy;
    if (orderBy != null) {
      values.sort(
        (a, b) => _compareRows(a[orderBy], b[orderBy], query.descending),
      );
    }

    final limit = query.limit;
    if (limit != null && values.length > limit) {
      values = values.sublist(0, limit);
    }

    return values.map(registration.fromJson).toList();
  }

  bool _matchesAll(Map<String, dynamic> row, List<ArxaKitFilter> filters) {
    for (final filter in filters) {
      if (!_matchesOne(row[filter.column], filter)) return false;
    }
    return true;
  }

  bool _matchesOne(Object? value, ArxaKitFilter filter) {
    switch (filter.op) {
      case ArxaKitFilterOp.eq:
        return value == filter.value;
      case ArxaKitFilterOp.gt:
        final cmp = _compare(value, filter.value);
        return cmp != null && cmp > 0;
      case ArxaKitFilterOp.lt:
        final cmp = _compare(value, filter.value);
        return cmp != null && cmp < 0;
    }
  }

  /// `null` when [a] and [b] aren't both [Comparable] of compatible runtime
  /// types — gt/lt treat that as "no match" rather than throwing.
  int? _compare(Object? a, Object b) {
    if (a is! Comparable) return null;
    try {
      return a.compareTo(b);
    } catch (_) {
      return null;
    }
  }

  /// `null` sorts last regardless of [descending] — the sign flip only
  /// applies to two present, comparable values.
  int _compareRows(Object? a, Object? b, bool descending) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    final cmp = _compare(a, b) ?? 0;
    return descending ? -cmp : cmp;
  }
}

/// A [ArxaKitDataFacade] that records the mutations started through it.
///
/// `repository<T>()` / `auth` resolve through the arxaKitLocator exactly as in a
/// real facade subclass — register [FakeArxaKitRepository] instances for the
/// entities under test. `mutate` still returns the real hub observation
/// handle (so the mutation executes against kit fakes); it just records each
/// call's label and value type first.
class FakeArxaKitDataFacade extends ArxaKitDataFacade {
  /// Every [mutate] call started, in call order (`label` is `name.entity` —
  /// either part may be null).
  final List<({String? name, String? entity, String type})> mutateCalls = [];

  /// Number of times [dispose] ran.
  int disposeCallCount = 0;

  @override
  Future<T> mutate<T>(
    FutureOr<T> Function() operation, {
    String? name,
    String? entity,
    String? error,
    String? success,
    String? fallback,
  }) {
    mutateCalls.add((name: name, entity: entity, type: T.toString()));
    return super.mutate<T>(
      operation,
      name: name,
      entity: entity,
      error: error,
      success: success,
      fallback: fallback,
    );
  }

  @override
  Future<void> dispose() async {
    disposeCallCount++;
    await super.dispose();
  }

  /// Clears the [mutateCalls] record ([disposeCallCount] is kept).
  void reset() => mutateCalls.clear();
}

// ─────────────────────── repository behavior contract ───────────────────────
//
// The cross-backend repository suite: the SAME behaviors every
// `ArxaKitRepository` backend must satisfy, parameterized by a repo factory.
// kit/data runs it against the seed backend (`kit.data.seed-repos — …`);
// backend kits (kit/cairn, …) run it against their adapter with their own
// suite name. Names are behavior sentences — keep them stable.

/// The contract suite's entity: one text column, one nullable reference, one
/// nullable integer — enough to cover canonicalization, filtering, ordering
/// with nulls, and patch diffs.
class ArxaKitContractWidget {
  final String id;
  final String name;
  final String? categoryId;
  final int? qty;

  const ArxaKitContractWidget({
    required this.id,
    required this.name,
    this.categoryId,
    this.qty,
  });
}

final arxaKitContractSchema = ArxaKitTableSchema(
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

final arxaKitContractRegistration =
    ArxaKitEntityRegistration<ArxaKitContractWidget>(
  schema: arxaKitContractSchema,
  fromJson: (json) => ArxaKitContractWidget(
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

/// Runs the repository behavior contract against the backend [makeRepo]
/// builds. Every test name is `<suite> — <behavior>`; [idService] must be the
/// same instance the factory's repositories use (canonicalization is part of
/// the contract).
void runArxaKitRepositoryContract({
  required String suite,
  required Future<ArxaKitRepository<ArxaKitContractWidget>> Function()
      makeRepo,
  required ArxaKitIdService idService,
}) {
  test('$suite — getById resolves by seed key and by the canonical uuid', () async {
    final repo = await makeRepo();
    await repo.upsert(const ArxaKitContractWidget(id: 'w-1', name: 'Alpha'));

    final canonical = idService.canonicalId('widgets', 'w-1');
    final byKey = await repo.getById('w-1');
    final byUuid = await repo.getById(canonical);

    expect(byKey, isNotNull);
    expect(byKey!.id, canonical);
    expect(byUuid, isNotNull);
    expect(byUuid!.id, canonical);
  });

  test('$suite — watchAll emits current list on listen, then again after upsert and delete',
      () async {
    final repo = await makeRepo();

    final expectation = expectLater(
      repo.watchAll(),
      emitsInOrder([isEmpty, hasLength(1), isEmpty]),
    );

    await repo.upsert(const ArxaKitContractWidget(id: 'w-1', name: 'Alpha'));
    await repo.delete('w-1');

    await expectation;
  });

  group('$suite ArxaKitQuery evaluation', () {
    late ArxaKitRepository<ArxaKitContractWidget> repo;

    setUp(() async {
      repo = await makeRepo();
      await repo.upsertMany(const [
        ArxaKitContractWidget(id: 'w-1', name: 'Alpha', categoryId: 'cat-1', qty: 10),
        ArxaKitContractWidget(id: 'w-2', name: 'Beta', categoryId: 'cat-2', qty: 5),
        ArxaKitContractWidget(id: 'w-3', name: 'Gamma', categoryId: 'cat-1', qty: null),
        ArxaKitContractWidget(id: 'w-4', name: 'Delta', qty: 20),
      ]);
    });

    test('$suite — eq filters to the matching row', () async {
      final results = await repo.getAll(
        const ArxaKitQuery(filters: [ArxaKitFilter.eq('name', 'Beta')]),
      );
      expect(results, hasLength(1));
      expect(results.single.name, 'Beta');
    });

    test('$suite — gt filters to rows strictly greater', () async {
      final results = await repo.getAll(
        const ArxaKitQuery(filters: [ArxaKitFilter.gt('qty', 10)]),
      );
      expect(results.map((w) => w.name), ['Delta']);
    });

    test('$suite — lt filters to rows strictly less', () async {
      final results = await repo.getAll(
        const ArxaKitQuery(filters: [ArxaKitFilter.lt('qty', 10)]),
      );
      expect(results.map((w) => w.name), ['Beta']);
    });

    test('$suite — orderBy ascending sorts nulls last', () async {
      final results = await repo.getAll(const ArxaKitQuery(orderBy: 'qty'));
      expect(results.map((w) => w.name), ['Beta', 'Alpha', 'Delta', 'Gamma']);
    });

    test('$suite — orderBy descending still sorts nulls last', () async {
      final results = await repo.getAll(
        const ArxaKitQuery(orderBy: 'qty', descending: true),
      );
      expect(results.map((w) => w.name), ['Delta', 'Alpha', 'Beta', 'Gamma']);
    });

    test('$suite — limit caps the result count after ordering', () async {
      final results = await repo.getAll(
        const ArxaKitQuery(orderBy: 'qty', limit: 2),
      );
      expect(results.map((w) => w.name), ['Beta', 'Alpha']);
    });

    test('$suite — eq filter on a reference column matches via a seed key', () async {
      final results = await repo.getAll(
        const ArxaKitQuery(filters: [ArxaKitFilter.eq('category', 'cat-1')]),
      );
      expect(results.map((w) => w.name).toSet(), {'Alpha', 'Gamma'});
    });
  });

  test('$suite — delete by seed key removes the row', () async {
    final repo = await makeRepo();
    await repo.upsert(const ArxaKitContractWidget(id: 'w-1', name: 'Alpha'));

    await repo.delete('w-1');

    expect(await repo.getById('w-1'), isNull);
    expect(await repo.getAll(), isEmpty);
  });

  test('$suite — upsertMany returns entities in the same order they were given', () async {
    final repo = await makeRepo();

    final results = await repo.upsertMany(const [
      ArxaKitContractWidget(id: 'w-3', name: 'Gamma'),
      ArxaKitContractWidget(id: 'w-1', name: 'Alpha'),
      ArxaKitContractWidget(id: 'w-2', name: 'Beta'),
    ]);

    expect(results.map((w) => w.name), ['Gamma', 'Alpha', 'Beta']);
  });

  group('$suite patch', () {
    test('$suite — patch writes only the differing columns, leaving a concurrent edit to another column intact', () async {
      final repo = await makeRepo();
      const original = ArxaKitContractWidget(id: 'w-1', name: 'Alpha', qty: 1);
      await repo.upsert(original);

      // Another surface edits `name` after `original` was read.
      await repo.upsert(const ArxaKitContractWidget(id: 'w-1', name: 'Alpha edited', qty: 1));

      final patched =
          await repo.patch(original, const ArxaKitContractWidget(id: 'w-1', name: 'Alpha', qty: 5));

      expect(patched.qty, 5);
      expect(patched.name, 'Alpha edited',
          reason: 'the concurrent edit to a column the patch did not touch survives');
    });

    test('$suite — patch clearing a nullable column stores the null', () async {
      final repo = await makeRepo();
      const original = ArxaKitContractWidget(id: 'w-1', name: 'Alpha', categoryId: 'cat-1', qty: 3);
      await repo.upsert(original);

      final patched =
          await repo.patch(original, const ArxaKitContractWidget(id: 'w-1', name: 'Alpha', qty: 3));

      expect(patched.categoryId, isNull);
      expect((await repo.getById('w-1'))!.categoryId, isNull);
    });

    test('$suite — patch canonicalizes a reference column inside the diff', () async {
      final repo = await makeRepo();
      const original = ArxaKitContractWidget(id: 'w-1', name: 'Alpha');
      await repo.upsert(original);

      await repo.patch(original, const ArxaKitContractWidget(id: 'w-1', name: 'Alpha', categoryId: 'cat-2'));

      final stored = await repo.getById('w-1');
      expect(stored!.categoryId, idService.canonicalId('categories', 'cat-2'));
    });

    test('$suite — patch on a missing row throws instead of creating it', () async {
      final repo = await makeRepo();

      expect(
        () => repo.patch(
          const ArxaKitContractWidget(id: 'ghost', name: 'A'),
          const ArxaKitContractWidget(id: 'ghost', name: 'B'),
        ),
        throwsStateError,
      );
    });

    test('$suite — patch with no differing columns writes nothing', () async {
      final repo = await makeRepo();
      const original = ArxaKitContractWidget(id: 'w-1', name: 'Alpha', qty: 1);
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

    test('$suite — patch rejects a diff that would re-address the row', () async {
      final repo = await makeRepo();
      await repo.upsert(const ArxaKitContractWidget(id: 'w-1', name: 'Alpha'));

      expect(
        () => repo.patch(
          const ArxaKitContractWidget(id: 'w-1', name: 'Alpha'),
          const ArxaKitContractWidget(id: 'w-2', name: 'Alpha'),
        ),
        throwsArgumentError,
      );
    });
  });
}
