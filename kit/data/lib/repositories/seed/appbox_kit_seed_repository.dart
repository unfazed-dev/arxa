import '../../config/appbox_kit_seed_profile.dart';
import '../../ids/appbox_kit_id_service.dart';
import '../../models/appbox_kit_entity_registration.dart';
import '../../query/appbox_kit_query.dart';
import '../appbox_kit_repository.dart';
import 'appbox_kit_seed_store.dart';

/// [AppBoxKitRepository] backed by [AppBoxKitSeedStore]. Reads evaluate [AppBoxKitQuery]
/// in-memory against the store's stream/snapshot; writes canonicalize the
/// entity's id (and reference columns) before touching the store, so the
/// same key lands on the same row here as on every other backend.
///
/// Every operation passes through [profile] first — the Seed Profile's
/// latency/failure injection (pass-through by default).
class AppBoxKitSeedRepository<T> implements AppBoxKitRepository<T> {
  final AppBoxKitSeedStore store;
  final AppBoxKitEntityRegistration<T> registration;
  final AppBoxKitIdService idService;
  final AppBoxKitSeedProfile profile;

  AppBoxKitSeedRepository({
    required this.store,
    required this.registration,
    required this.idService,
    this.profile = const AppBoxKitSeedProfile(),
  });

  String get _table => registration.schema.table;

  @override
  Future<T?> getById(String id) async {
    await profile.gate();
    final canonical = idService.canonicalId(_table, id);
    final row = store.tableSnapshot(_table)[canonical];
    return row == null ? null : registration.fromJson(row);
  }

  @override
  Stream<T?> watchById(String id) {
    final canonical = idService.canonicalId(_table, id);
    return profile.apply(store.watchTable(_table)).map((rows) {
      final row = rows[canonical];
      return row == null ? null : registration.fromJson(row);
    });
  }

  @override
  Future<List<T>> getAll([AppBoxKitQuery query = const AppBoxKitQuery()]) async {
    await profile.gate();
    final canonical = idService.canonicalizeQuery(registration.schema, query);
    return _evaluate(store.tableSnapshot(_table), canonical);
  }

  @override
  Stream<List<T>> watchAll([AppBoxKitQuery query = const AppBoxKitQuery()]) {
    final canonical = idService.canonicalizeQuery(registration.schema, query);
    return profile
        .apply(store.watchTable(_table))
        .map((rows) => _evaluate(rows, canonical));
  }

  @override
  Future<T> upsert(T entity) async {
    await profile.gate();
    final json = registration.toJson(entity);
    final canonicalRow = idService.canonicalizeRow(registration.schema, json);
    await store.upsertRow(_table, canonicalRow);
    return registration.fromJson(canonicalRow);
  }

  @override
  Future<List<T>> upsertMany(List<T> entities) async {
    final result = <T>[];
    for (final entity in entities) {
      result.add(await upsert(entity));
    }
    return result;
  }

  @override
  Future<T> patch(T original, T patched) async {
    await profile.gate();
    final originalJson = registration.toJson(original);
    final canonical = idService.canonicalId(
        _table, originalJson[registration.schema.idColumn.name]!);
    final diff = appBoxKitJsonPatch(originalJson, registration.toJson(patched));
    if (diff.isEmpty) return patched;
    final row = store.tableSnapshot(_table)[canonical];
    if (row == null) {
      throw StateError('patch: no "$_table" row "$canonical"');
    }
    final merged = <String, dynamic>{
      ...row,
      ...idService.canonicalizePatch(registration.schema, diff),
    };
    await store.upsertRow(_table, merged);
    return registration.fromJson(merged);
  }

  @override
  Future<void> delete(String id) async {
    await profile.gate();
    final canonical = idService.canonicalId(_table, id);
    await store.removeRow(_table, canonical);
  }

  List<T> _evaluate(
    Map<String, Map<String, dynamic>> rows,
    AppBoxKitQuery query,
  ) {
    var values =
        rows.values.where((row) => _matchesAll(row, query.filters)).toList();

    final orderBy = query.orderBy;
    if (orderBy != null) {
      values.sort((a, b) => _compareRows(a[orderBy], b[orderBy], query.descending));
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
