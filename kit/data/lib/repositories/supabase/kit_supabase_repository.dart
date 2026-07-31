/// [KitRepository] backed by Supabase (PostgREST reads/writes, Realtime via
/// `.stream()` for the watch methods).
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../ids/kit_id_service.dart';
import '../../models/kit_entity_registration.dart';
import '../../query/kit_query.dart';
import '../kit_repository.dart';

/// Supabase implementation of [KitRepository].
///
/// Constraints (docs/plans/appbox-kit-data-layer.md, "swap rules"):
/// - Stream-backed, never double-buffered: `watchAll`/`watchById` forward
///   straight to `supabase`'s `.stream()`. Its `BehaviorSubject` lives inside
///   the `supabase` package itself — this repository adds no Subject of its
///   own on top of it.
/// - Single-table only: every method touches exactly `registration.schema.table`.
/// - `.stream(primaryKey: ['id'])` accepts at most ONE server-side filter
///   (verified against `package:supabase/src/supabase_stream_filter_builder.dart`,
///   whose doc comments say "Only one filter can be applied to `.stream()`").
///   PostgREST's own `.select()` surface (used by [getAll]/[getById]) has no
///   such limit — it takes every filter, `.order`, and `.limit` PostgREST
///   supports. Because Realtime's change-feed filtering is narrower than
///   PostgREST's query filtering, [watchAll] pushes only one filter to the
///   server and re-applies everything else (remaining filters, order, limit)
///   client-side in a `.map`, over the raw wire-shape rows before decoding.
class KitSupabaseRepository<T> implements KitRepository<T> {
  KitSupabaseRepository({
    required SupabaseClient client,
    required KitEntityRegistration<T> registration,
    required KitIdService idService,
  })  : _client = client,
        _registration = registration,
        _idService = idService;

  final SupabaseClient _client;
  final KitEntityRegistration<T> _registration;
  final KitIdService _idService;

  String get _table => _registration.schema.table;

  @override
  Future<T?> getById(String id) async {
    final canonical = _idService.canonicalId(_table, id);
    final row =
        await _client.from(_table).select().eq('id', canonical).maybeSingle();
    if (row == null) return null;
    return _registration.fromJson(row);
  }

  @override
  Future<List<T>> getAll([KitQuery kitQuery = const KitQuery()]) async {
    final query = _idService.canonicalizeQuery(_registration.schema, kitQuery);
    var builder = _client.from(_table).select();
    for (final filter in query.filters) {
      builder = _applyFilter(builder, filter);
    }
    PostgrestTransformBuilder<PostgrestList> transform = builder;
    if (query.orderBy != null) {
      transform =
          transform.order(query.orderBy!, ascending: !query.descending);
    }
    if (query.limit != null) {
      transform = transform.limit(query.limit!);
    }
    final rows = await transform;
    return rows.map(_registration.fromJson).toList();
  }

  @override
  Stream<T?> watchById(String id) {
    final canonical = _idService.canonicalId(_table, id);
    // A single `eq('id', ...)` is exactly the ONE filter `.stream()` allows,
    // so this never needs client-side re-filtering.
    return _client
        .from(_table)
        .stream(primaryKey: ['id'])
        .eq('id', canonical)
        .map(
          (rows) => rows.isEmpty ? null : _registration.fromJson(rows.first),
        );
  }

  @override
  Stream<List<T>> watchAll([KitQuery kitQuery = const KitQuery()]) {
    final query = _idService.canonicalizeQuery(_registration.schema, kitQuery);
    final base = _client.from(_table).stream(primaryKey: ['id']);
    final pushed = _pickServerSideFilter(query.filters);
    final Stream<List<Map<String, dynamic>>> stream =
        pushed == null ? base : _applyStreamFilter(base, pushed);
    final remaining = pushed == null
        ? query.filters
        : query.filters.where((f) => !identical(f, pushed)).toList();

    return stream.map((rows) {
      var mapped = List<Map<String, dynamic>>.from(rows);
      mapped = _filterRows(mapped, remaining);
      mapped = _sortRows(mapped, query.orderBy, query.descending);
      mapped = _limitRows(mapped, query.limit);
      return mapped.map(_registration.fromJson).toList();
    });
  }

  @override
  Future<T> upsert(T entity) async {
    final row = _idService.canonicalizeRow(
      _registration.schema,
      _registration.toJson(entity),
    );
    final result = await _client.from(_table).upsert(row).select().single();
    return _registration.fromJson(result);
  }

  @override
  Future<List<T>> upsertMany(List<T> entities) async {
    if (entities.isEmpty) return [];
    final rows = entities
        .map(
          (e) => _idService.canonicalizeRow(
            _registration.schema,
            _registration.toJson(e),
          ),
        )
        .toList();
    final result = await _client.from(_table).upsert(rows).select();
    return result.map(_registration.fromJson).toList();
  }

  @override
  Future<void> delete(String id) async {
    final canonical = _idService.canonicalId(_table, id);
    await _client.from(_table).delete().eq('id', canonical);
  }

  // -- PostgREST (getAll) filter application --------------------------------

  PostgrestFilterBuilder<PostgrestList> _applyFilter(
    PostgrestFilterBuilder<PostgrestList> builder,
    KitFilter filter,
  ) {
    switch (filter.op) {
      case KitFilterOp.eq:
        return builder.eq(filter.column, filter.value);
      case KitFilterOp.gt:
        return builder.gt(filter.column, filter.value);
      case KitFilterOp.lt:
        return builder.lt(filter.column, filter.value);
    }
  }

  // -- `.stream()` (watchAll) server-side filter selection -------------------

  /// Picks at most one filter to push server-side: an `eq` filter if the
  /// query has one (cheapest, most selective — and `.stream()`'s realtime
  /// change-feed matches `eq` most naturally), otherwise the first filter of
  /// any kind. Returns `null` when there is nothing to push.
  KitFilter? _pickServerSideFilter(List<KitFilter> filters) {
    if (filters.isEmpty) return null;
    for (final f in filters) {
      if (f.op == KitFilterOp.eq) return f;
    }
    return filters.first;
  }

  Stream<List<Map<String, dynamic>>> _applyStreamFilter(
    SupabaseStreamFilterBuilder builder,
    KitFilter filter,
  ) {
    switch (filter.op) {
      case KitFilterOp.eq:
        return builder.eq(filter.column, filter.value);
      case KitFilterOp.gt:
        return builder.gt(filter.column, filter.value);
      case KitFilterOp.lt:
        return builder.lt(filter.column, filter.value);
    }
  }

  // -- Client-side filter/sort/limit (the rest of the KitQuery) -------------
  //
  // Operate on raw wire-shape rows (`Map<String, dynamic>`), not decoded
  // entities — KitQuery columns are wire-shape column names, and this avoids
  // any dependency on `toJson` being a faithful round-trip of `fromJson`.
  // timestamptz columns may arrive as ISO-8601 strings; those compare
  // correctly with plain string ordering, so no parsing happens here — the
  // codec owns parsing, per the layer's contract.

  List<Map<String, dynamic>> _filterRows(
    List<Map<String, dynamic>> rows,
    List<KitFilter> filters,
  ) {
    if (filters.isEmpty) return rows;
    return rows.where((row) => filters.every((f) => _matches(row, f))).toList();
  }

  bool _matches(Map<String, dynamic> row, KitFilter filter) {
    final value = row[filter.column];
    switch (filter.op) {
      case KitFilterOp.eq:
        return value == filter.value;
      case KitFilterOp.gt:
        return _compare(value, filter.value) > 0;
      case KitFilterOp.lt:
        return _compare(value, filter.value) < 0;
    }
  }

  List<Map<String, dynamic>> _sortRows(
    List<Map<String, dynamic>> rows,
    String? orderBy,
    bool descending,
  ) {
    if (orderBy == null) return rows;
    final sorted = List<Map<String, dynamic>>.from(rows)
      ..sort((a, b) => _compare(a[orderBy], b[orderBy]));
    return descending ? sorted.reversed.toList() : sorted;
  }

  List<Map<String, dynamic>> _limitRows(
    List<Map<String, dynamic>> rows,
    int? limit,
  ) {
    if (limit == null || rows.length <= limit) return rows;
    return rows.sublist(0, limit);
  }

  int _compare(Object? a, Object? b) {
    if (a is num && b is num) return a.compareTo(b);
    if (a is String && b is String) return a.compareTo(b);
    return a.toString().compareTo(b.toString());
  }
}
