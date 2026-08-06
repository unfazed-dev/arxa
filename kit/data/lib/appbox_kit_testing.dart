/// Test doubles for appbox_kit_data.
///
/// Import this from tests to run repositories and facades fully in memory —
/// no Supabase client, no Appwrite client, no fixture assets, no snapshot
/// persistence:
///
/// ```dart
/// final products = FakeAppBoxKitRepository<Product>(
///   registration: productRegistration,
///   seed: [const Product(id: 'p-1', name: 'Shoes')],
/// );
/// appBoxKitLocator.registerSingleton<AppBoxKitRepository<Product>>(products);
///
/// final facade = ProductsFacade();
/// expect(await facade.featured(), hasLength(1));
/// expect(products.getAllCalls.single.orderBy, 'name');
/// ```
library;

import 'dart:async';

import 'package:rxdart/rxdart.dart';
import 'package:appbox_kit_ui_library/utils/kit_action/appbox_kit_action_builder.dart';

import 'facades/appbox_kit_data_facade.dart';
import 'ids/appbox_kit_id_service.dart';
import 'models/appbox_kit_entity_registration.dart';
import 'query/appbox_kit_query.dart';
import 'repositories/appbox_kit_repository.dart';

export 'facades/appbox_kit_data_facade.dart';
export 'ids/appbox_kit_id_service.dart';
export 'models/appbox_kit_entity_registration.dart';
export 'query/appbox_kit_query.dart';
export 'repositories/appbox_kit_repository.dart';
export 'schema/appbox_kit_table_schema.dart';

/// An in-memory, stream-backed [AppBoxKitRepository] — the test double for the
/// swap seam.
///
/// Rows live as canonicalized JSON (the same wire shape the seed backend
/// stores) keyed by canonical id, behind a seeded [BehaviorSubject], so
/// `watch*` emits the current result set immediately and again on every
/// write. ID canonicalization and [AppBoxKitQuery] evaluation (`eq` / `gt` / `lt` /
/// `orderBy` with nulls-last / `limit`) mirror `AppBoxKitSeedRepository` — if the
/// seed engine's semantics change, change this fake too.
///
/// Canonicalization is always on (default-namespace [AppBoxKitIdService] unless one
/// is passed), matching `AppBoxKitData.initialize`: seed keys like `p-1` and their
/// v5 UUIDs address the same row on reads and writes alike.
class FakeAppBoxKitRepository<T> implements AppBoxKitRepository<T> {
  FakeAppBoxKitRepository({
    required this.registration,
    AppBoxKitIdService? idService,
    Iterable<T>? seed,
  }) : idService = idService ?? AppBoxKitIdService() {
    if (seed != null) seedAll(seed);
  }

  /// The entity codec + schema this repository serves.
  final AppBoxKitEntityRegistration<T> registration;

  /// The canonicalizer applied to ids, reference columns, and `eq` filters.
  final AppBoxKitIdService idService;

  final BehaviorSubject<Map<String, Map<String, dynamic>>> _rows$ =
      BehaviorSubject<Map<String, Map<String, dynamic>>>.seeded(const {});

  // ---- call records --------------------------------------------------------

  /// Every raw `id` passed to [getById], in call order.
  final List<String> getByIdCalls = [];

  /// Every raw [AppBoxKitQuery] passed to [getAll], in call order.
  final List<AppBoxKitQuery> getAllCalls = [];

  /// Every raw `id` passed to [watchById], in call order.
  final List<String> watchByIdCalls = [];

  /// Every raw [AppBoxKitQuery] passed to [watchAll], in call order.
  final List<AppBoxKitQuery> watchAllCalls = [];

  /// Every entity returned by [upsert] (i.e. as stored, canonical ids),
  /// in call order. [upsertMany] records one entry per entity.
  final List<T> upsertedEntities = [];

  /// Number of [upsertMany] calls.
  int upsertManyCallCount = 0;

  /// Every raw `id` passed to [delete], in call order.
  final List<String> deletedIds = [];

  // ---- scripted failures ----------------------------------------------------

  /// When non-null, [getById] / [getAll] throw this instead of answering.
  Object? readError;

  /// When non-null, [upsert] / [upsertMany] throw this instead of writing.
  Object? upsertError;

  /// When non-null, [delete] throws this instead of removing the row.
  Object? deleteError;

  String get _table => registration.schema.table;

  String get _idColumn => registration.schema.idColumn.name;

  // ---- AppBoxKitRepository ---------------------------------------------------------

  @override
  Future<T?> getById(String id) async {
    getByIdCalls.add(id);
    _throwIf(readError);
    final row = _rows$.value[idService.canonicalId(_table, id)];
    return row == null ? null : registration.fromJson(row);
  }

  @override
  Future<List<T>> getAll([AppBoxKitQuery query = const AppBoxKitQuery()]) async {
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
  Stream<List<T>> watchAll([AppBoxKitQuery query = const AppBoxKitQuery()]) {
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
    upsertManyCallCount = 0;
    deletedIds.clear();
    readError = null;
    upsertError = null;
    deleteError = null;
  }

  /// Closes the backing subject.
  Future<void> dispose() => _rows$.close();

  // ---- query evaluation (mirrors AppBoxKitSeedRepository._evaluate) -----------------

  void _throwIf(Object? error) {
    if (error != null) throw error;
  }

  AppBoxKitQuery _canonicalize(AppBoxKitQuery query) =>
      idService.canonicalizeQuery(registration.schema, query);

  List<T> _evaluate(Map<String, Map<String, dynamic>> rows, AppBoxKitQuery query) {
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

  bool _matchesAll(Map<String, dynamic> row, List<AppBoxKitFilter> filters) {
    for (final filter in filters) {
      if (!_matchesOne(row[filter.column], filter)) return false;
    }
    return true;
  }

  bool _matchesOne(Object? value, AppBoxKitFilter filter) {
    switch (filter.op) {
      case AppBoxKitFilterOp.eq:
        return value == filter.value;
      case AppBoxKitFilterOp.gt:
        final cmp = _compare(value, filter.value);
        return cmp != null && cmp > 0;
      case AppBoxKitFilterOp.lt:
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

/// A [AppBoxKitDataFacade] that records the mutations started through it.
///
/// `repository<T>()` / `auth` resolve through the appBoxKitLocator exactly as in a
/// real facade subclass — register [FakeAppBoxKitRepository] instances for the
/// entities under test. `mutate` still returns the real [AppBoxKitActionBuilder]
/// (so the chain can be executed against kit fakes); it just records each
/// chain's label and value type first.
class FakeAppBoxKitDataFacade extends AppBoxKitDataFacade {
  /// Every [mutate] chain started, in call order (`label` is `name.entity` —
  /// either part may be null).
  final List<({String? name, String? entity, String type})> mutateCalls = [];

  /// Number of times [dispose] ran.
  int disposeCallCount = 0;

  @override
  AppBoxKitActionBuilder<T> mutate<T>(
    FutureOr<T> Function() operation, {
    String? name,
    String? entity,
    String? error,
    String? success,
  }) {
    mutateCalls.add((name: name, entity: entity, type: T.toString()));
    return super.mutate<T>(
      operation,
      name: name,
      entity: entity,
      error: error,
      success: success,
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
