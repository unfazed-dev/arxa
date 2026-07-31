/// [KitRepository] backed by Appwrite's TablesDB rows API + Realtime.
library;

import 'dart:async';
import 'dart:convert';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;

import '../../ids/kit_id_service.dart';
import '../../models/kit_entity_registration.dart';
import '../../query/kit_query.dart';
import '../../schema/kit_table_schema.dart';
import '../kit_repository.dart';

/// Appwrite implementation of [KitRepository], built on the 25.x TablesDB
/// rows API (`getRow`/`listRows`/`createRow`/`upsertRow`/`updateRow`/
/// `deleteRow` — verified against the installed `appwrite: 25.2.0` SDK
/// source at `package:appwrite/services/tables_db.dart`) plus `Realtime`.
///
/// Constraints (docs/plans/stacked-kit-data-layer.md, "swap rules"):
/// - Single-table only: every method touches exactly `registration.schema.table`
///   (as `tableId`) inside `databaseId`.
/// - Swap rule 1 ("never double-buffer a reactive source") is not violated by
///   [watchAll]/[watchById] even though they hand-build a `StreamController`:
///   Appwrite ships no ready-made query-scoped row stream (unlike Supabase's
///   `.stream()`), so there is no existing reactive source to buffer on top
///   of. The controller here *is* the source — it is fed directly by
///   `listRows` responses and `Realtime` events, not by re-wrapping another
///   stream that already holds the data.
/// - Appwrite table columns have no native JSON/jsonb type (verified: the
///   TablesDB row wire shape is a flat `Map<String, dynamic>` — see
///   `package:appwrite/src/models/row.dart`; there is no JSON column
///   primitive in the create/update row APIs), so `KitColumnType.jsonb`
///   columns are stored as JSON-encoded strings on this backend and decoded
///   back on read.
class KitAppwriteRepository<T> implements KitRepository<T> {
  KitAppwriteRepository({
    required TablesDB tablesDB,
    required Realtime realtime,
    required String databaseId,
    required KitEntityRegistration<T> registration,
    required KitIdService idService,
  })  : _tablesDB = tablesDB,
        _realtime = realtime,
        _databaseId = databaseId,
        _registration = registration,
        _idService = idService;

  final TablesDB _tablesDB;
  final Realtime _realtime;
  final String _databaseId;
  final KitEntityRegistration<T> _registration;
  final KitIdService _idService;

  String get _tableId => _registration.schema.table;

  /// Realtime channel for every row event on this table. Built with the
  /// `Channel` helper (`package:appwrite/channel.dart`) rather than a
  /// hand-written string: `Channel.tablesdb(db).table(id).row()` joins its
  /// segments as `tablesdb.<databaseId>.tables.<tableId>.rows` — confirmed by
  /// reading the `Channel` class source, which mirrors the TablesDB REST path
  /// (`/tablesdb/{databaseId}/tables/{tableId}/rows`). Note this is
  /// `tablesdb.…`, not `databases.…` — the SDK's own `Realtime.subscribe` doc
  /// comment still lists the pre-rename `collections`/`documents` channels;
  /// the `Channel` builder is the source of truth for the current shape.
  String get _tableChannel =>
      Channel.tablesdb(_databaseId).table(_tableId).row().toString();

  String _rowChannel(String rowId) =>
      Channel.tablesdb(_databaseId).table(_tableId).row(rowId).toString();

  @override
  Future<T?> getById(String id) async {
    final canonical = _idService.canonicalId(_tableId, id);
    try {
      final row = await _tablesDB.getRow(
        databaseId: _databaseId,
        tableId: _tableId,
        rowId: canonical,
      );
      return _registration.fromJson(_fromWire(row));
    } on AppwriteException catch (e) {
      if (e.code == 404) return null;
      rethrow;
    }
  }

  @override
  Future<List<T>> getAll([KitQuery kitQuery = const KitQuery()]) async {
    final query = _idService.canonicalizeQuery(_registration.schema, kitQuery);
    final list = await _tablesDB.listRows(
      databaseId: _databaseId,
      tableId: _tableId,
      queries: _buildQueries(query),
    );
    return list.rows
        .map((row) => _registration.fromJson(_fromWire(row)))
        .toList();
  }

  @override
  Stream<T?> watchById(String id) {
    final canonical = _idService.canonicalId(_tableId, id);
    late final StreamController<T?> controller;
    RealtimeSubscription? subscription;

    Future<void> refetch() async {
      try {
        final row = await getById(canonical);
        if (!controller.isClosed) controller.add(row);
      } catch (error, stackTrace) {
        if (!controller.isClosed) controller.addError(error, stackTrace);
      }
    }

    controller = StreamController<T?>.broadcast(
      onListen: () {
        unawaited(refetch());
        subscription = _realtime.subscribe([_rowChannel(canonical)]);
        subscription!.stream.listen(
          (_) => unawaited(refetch()),
          onError: (Object error, StackTrace stackTrace) {
            if (!controller.isClosed) controller.addError(error, stackTrace);
          },
        );
      },
      onCancel: () async {
        await subscription?.close();
      },
    );
    return controller.stream;
  }

  @override
  Stream<List<T>> watchAll([KitQuery query = const KitQuery()]) {
    late final StreamController<List<T>> controller;
    RealtimeSubscription? subscription;

    Future<void> refetch() async {
      try {
        final rows = await getAll(query);
        if (!controller.isClosed) controller.add(rows);
      } catch (error, stackTrace) {
        if (!controller.isClosed) controller.addError(error, stackTrace);
      }
    }

    controller = StreamController<List<T>>.broadcast(
      onListen: () {
        unawaited(refetch());
        // ponytail: refetch-on-event. Appwrite's row events carry the
        // changed row, not query-filter awareness, so the simplest correct
        // thing that works is: any row event on this table -> refetch the
        // whole `listRows(query)`. Ceiling: if a table gets chatty (frequent
        // writes, many concurrent watchers), fold bursts of events locally
        // (e.g. debounce the refetch) before reaching for anything fancier
        // like diffing individual row payloads against the in-flight query.
        subscription = _realtime.subscribe([_tableChannel]);
        subscription!.stream.listen(
          (_) => unawaited(refetch()),
          onError: (Object error, StackTrace stackTrace) {
            if (!controller.isClosed) controller.addError(error, stackTrace);
          },
        );
      },
      onCancel: () async {
        await subscription?.close();
      },
    );
    return controller.stream;
  }

  @override
  Future<T> upsert(T entity) async {
    final row = _idService.canonicalizeRow(
      _registration.schema,
      _registration.toJson(entity),
    );
    final rowId = row['id'] as String;
    final result = await _tablesDB.upsertRow(
      databaseId: _databaseId,
      tableId: _tableId,
      rowId: rowId,
      data: _toWireData(row),
    );
    return _registration.fromJson(_fromWire(result));
  }

  @override
  Future<List<T>> upsertMany(List<T> entities) async {
    final results = <T>[];
    for (final entity in entities) {
      results.add(await upsert(entity));
    }
    return results;
  }

  @override
  Future<void> delete(String id) async {
    final canonical = _idService.canonicalId(_tableId, id);
    try {
      await _tablesDB.deleteRow(
        databaseId: _databaseId,
        tableId: _tableId,
        rowId: canonical,
      );
    } on AppwriteException catch (e) {
      if (e.code == 404) return;
      rethrow;
    }
  }

  // -- KitQuery -> Appwrite Query strings -------------------------------

  List<String> _buildQueries(KitQuery query) {
    final queries = <String>[];
    for (final filter in query.filters) {
      switch (filter.op) {
        case KitFilterOp.eq:
          queries.add(Query.equal(filter.column, filter.value));
        case KitFilterOp.gt:
          queries.add(Query.greaterThan(filter.column, filter.value));
        case KitFilterOp.lt:
          queries.add(Query.lessThan(filter.column, filter.value));
      }
    }
    if (query.orderBy != null) {
      queries.add(
        query.descending
            ? Query.orderDesc(query.orderBy!)
            : Query.orderAsc(query.orderBy!),
      );
    }
    if (query.limit != null) {
      queries.add(Query.limit(query.limit!));
    }
    return queries;
  }

  // -- Wire-shape mapping --------------------------------------------------

  /// TO appwrite: the canonicalized row minus `id` (which becomes the
  /// `rowId` path parameter, not a data field) becomes `data`; `jsonb`
  /// columns are JSON-encoded to strings, schema-driven.
  Map<String, dynamic> _toWireData(Map<String, dynamic> canonicalRow) {
    final data = Map<String, dynamic>.from(canonicalRow)..remove('id');
    for (final column in _registration.schema.columns) {
      if (column.type != KitColumnType.jsonb) continue;
      final value = data[column.name];
      if (value != null) {
        data[column.name] = jsonEncode(value);
      }
    }
    return data;
  }

  /// FROM appwrite: `row.data` plus the canonical id from `row.$id`. Per
  /// `package:appwrite/src/models/row.dart`, `Row.data` already holds only
  /// the table's own columns — the `$`-prefixed system fields ($id,
  /// $sequence, $tableId, $databaseId, $createdAt, $updatedAt, $permissions)
  /// are separate top-level `Row` fields, not part of `data` — but the strip
  /// below is kept as a defensive no-op in case a future SDK version folds
  /// them in. `jsonb` columns are JSON-decoded back from their string form.
  Map<String, dynamic> _fromWire(models.Row row) {
    final out = <String, dynamic>{...row.data, 'id': row.$id}
      ..removeWhere((key, _) => key != 'id' && key.startsWith(r'$'));
    for (final column in _registration.schema.columns) {
      if (column.type != KitColumnType.jsonb) continue;
      final value = out[column.name];
      if (value is String) {
        out[column.name] = jsonDecode(value);
      }
    }
    return out;
  }
}
