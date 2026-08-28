/// [ArxaKitRepository] backed by cairn — the swap-seam implementation that
/// lets every kit facade and codec run on a cairn database unchanged.
///
/// Mapping onto the cairn surface (structured predicates only — never raw
/// SQL, so there is no view-name collapse and no outbox foot-gun):
/// - getById → `Collection.fetchById`; getAll/watchAll → `Collection.getAll` /
///   `.watch` with [Where] composed from [ArxaKitQuery] (ordering + limit for
///   ordered reads are client-side — the contract's nulls-last rule is not
///   expressible in cairn's `Order`/SQL, see [_orderAndLimit]);
/// - upsert → `Collection.upsertRow` (the atlet-proven per-row
///   `write(op: 'upsert')` shape); upsertMany → `writeBatch` (local-atomic
///   outbox entry — NOT a server transaction, per ADR-0032 T3);
/// - patch → [arxaKitJsonPatch] column diff → canonicalize →
///   `Collection.patch` (cairn's per-field LWW IS the kit patch contract);
/// - watch streams ride cairn's hot-replay-shared pump: the current set emits
///   immediately and late listeners replay it — no extra subjects here
///   (repositories never double-buffer, swap rule 1).
///
/// Read normalization: the WS2 read-views are `json_extract` projections, so
/// booleans arrive as 0/1 integers and jsonb columns as JSON text. Rows are
/// normalized against the kit schema before the entity codec ever sees them.
library;

import 'dart:async';
import 'dart:convert';

import 'package:cairn_flutter/cairn_flutter.dart';
import 'package:arxa_kit_data/arxa_kit_data.dart';

import 'arxa_kit_crdt_capable.dart';

class CairnKitRepository<E> implements ArxaKitRepository<E>, ArxaKitCrdtCapable {
  CairnKitRepository({
    required CairnDatabase db,
    required ArxaKitEntityRegistration<E> registration,
    required this._idService,
    this._orSetTables = const {},
    this._counterTables = const {},
    this._userIdProvider,
  })  : _registration = registration,
        _collection = db.collection<E>(
          table: registration.schema.table,
          fromRow: (row) =>
              registration.fromJson(_normalizeRow(registration.schema, row)),
        );
  final ArxaKitEntityRegistration<E> _registration;
  final ArxaKitIdService _idService;
  final Set<String> _orSetTables;
  final Set<String> _counterTables;

  /// Tenant-table stamping hook (PgWriteBack's `auth.uid()` is NULL for
  /// local writes): when set, upserts onto a schema carrying a `user_id`
  /// column get it filled in — an explicit value is never overwritten.
  final String? Function()? _userIdProvider;

  final Collection<E> _collection;

  ArxaKitTableSchema get _schema => _registration.schema;
  String get _table => _schema.table;
  String get _idColumn => _schema.idColumn.name;

  // ── Reads ─────────────────────────────────────────────────────────────────

  @override
  Future<E?> getById(String id) =>
      _collection.fetchById(_idService.canonicalId(_table, id));

  @override
  Future<List<E>> getAll([ArxaKitQuery query = const ArxaKitQuery()]) {
    final canonical = _idService.canonicalizeQuery(_schema, query);
    if (canonical.orderBy == null) {
      return _collection.getAll(
        where: _where(canonical),
        limit: canonical.limit,
      );
    }
    // Ordered reads sort (and limit) CLIENT-SIDE after the SQL filter: the
    // kit contract sorts nulls last in BOTH directions, but cairn's Order has
    // no NULLS LAST and SQLite's default pushes them first on ASC — the SQL
    // layer cannot express the contract.
    return _collection
        .getAll(where: _where(canonical))
        .then((rows) => _orderAndLimit(rows, canonical));
  }

  @override
  Stream<E?> watchById(String id) {
    final canonical = _idService.canonicalId(_table, id);
    return _prepend(
      () => _collection.fetchById(canonical),
      () => _collection.watchOne(canonical),
    ).distinct(_sameEntity);
  }

  @override
  Stream<List<E>> watchAll([ArxaKitQuery query = const ArxaKitQuery()]) {
    final canonical = _idService.canonicalizeQuery(_schema, query);
    final where = _where(canonical);
    if (canonical.orderBy == null) {
      return _prepend(
        () => _collection.getAll(where: where, limit: canonical.limit),
        () => _collection.watch(where: where, limit: canonical.limit),
      ).distinct(_sameRows);
    }
    return _prepend(
      () => _collection
          .getAll(where: where)
          .then((rows) => _orderAndLimit(rows, canonical)),
      () => _collection
          .watch(where: where)
          .map((rows) => _orderAndLimit(rows, canonical)),
    ).distinct(_sameRows);
  }

  /// The contract's ordering: nulls LAST regardless of direction (the sign
  /// flip only applies between two present, comparable values) — mirrors
  /// `ArxaKitSeedRepository._compareRows` exactly.
  List<E> _orderAndLimit(List<E> rows, ArxaKitQuery query) {
    final orderBy = query.orderBy!;
    final sorted = List.of(rows)
      ..sort((a, b) => _compareEntities(a, b, orderBy, query.descending));
    final limit = query.limit;
    return limit != null && sorted.length > limit
        ? sorted.sublist(0, limit)
        : sorted;
  }

  int _compareEntities(E a, E b, String field, bool descending) {
    final av = _registration.toJson(a)[field];
    final bv = _registration.toJson(b)[field];
    if (av == null && bv == null) return 0;
    if (av == null) return 1;
    if (bv == null) return -1;
    var cmp = 0;
    if (av is Comparable) {
      try {
        cmp = av.compareTo(bv);
      } catch (_) {
        cmp = 0; // incomparable types tie, mirroring the seed engine
      }
    }
    return descending ? -cmp : cmp;
  }

  /// Prepends a one-shot current-state snapshot to a live stream, WITHOUT
  /// opening a subscription window: the live pump subscribes at listen time
  /// (its emissions buffer while the snapshot is in flight) and the snapshot
  /// future is issued first, so pending live states are never older than the
  /// snapshot they follow.
  ///
  /// Why eager: cairn's pump only re-queries on engine ticks, and a tick
  /// fired while NO listener is attached is gone — a write landing between
  /// `watchAll()`'s call and the pump's subscription would be invisible until
  /// the next write. Buffering closes that window; consecutive duplicates
  /// (snapshot vs the pump's own first emission) are collapsed by the
  /// `distinct` the callers chain on.
  Stream<T> _prepend<T>(Future<T> Function() snapshot, Stream<T> Function() live) {
    late StreamController<T> out;
    StreamSubscription<T>? liveSub;
    var snapshotDone = false;
    final pending = <T>[];
    out = StreamController<T>(
      onListen: () {
        final snap = snapshot();
        liveSub = live().listen((event) {
          if (snapshotDone) {
            out.add(event);
          } else {
            pending.add(event);
          }
        }, onError: out.addError);
        snap.then((value) {
          snapshotDone = true;
          out.add(value);
          for (final event in pending) {
            out.add(event);
          }
          pending.clear();
        }, onError: (Object e, StackTrace st) {
          snapshotDone = true;
          out.addError(e, st);
        });
      },
      onCancel: () => liveSub?.cancel(),
    );
    return out.stream;
  }

  /// Wire-shape equality for `distinct` — the same codec-independent
  /// comparison [arxaKitJsonPatch] uses, so a content-free re-emission is
  /// collapsed but any real change passes.
  bool _sameEntity(E? a, E? b) {
    if (a == null || b == null) return a == b;
    return jsonEncode(_registration.toJson(a)) ==
        jsonEncode(_registration.toJson(b));
  }

  bool _sameRows(List<E> a, List<E> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_sameEntity(a[i], b[i])) return false;
    }
    return true;
  }

  // ── Writes ────────────────────────────────────────────────────────────────

  @override
  Future<E> upsert(E entity) async {
    final row = _wireRow(entity);
    final pk = row[_idColumn]!.toString();
    await _collection.upsertRow(row);
    // The write applies locally before resolving (ADR-0013), so the re-fetch
    // IS the stored row — the same "as stored" echo the Supabase backend
    // returns from `.select()`.
    final stored = await _collection.fetchById(pk);
    return stored ??
        _registration.fromJson(_normalizeRow(_schema, row));
  }

  @override
  Future<List<E>> upsertMany(List<E> entities) async {
    if (entities.isEmpty) return [];
    final rows = [for (final e in entities) _wireRow(e)];
    await _collection.writeBatch([
      for (final row in rows)
        CairnWrite(
          table: _table,
          op: 'upsert',
          pk: row[_idColumn]!.toString(),
          payload: row,
        ),
    ]);
    return [
      for (final row in rows)
        await _collection.fetchById(row[_idColumn]!.toString()) ??
            _registration.fromJson(_normalizeRow(_schema, row)),
    ];
  }

  @override
  Future<E> patch(E original, E patched) async {
    final originalJson = _registration.toJson(original);
    final canonical =
        _idService.canonicalId(_table, originalJson[_idColumn]!);
    final diff = arxaKitJsonPatch(originalJson, _registration.toJson(patched));
    if (diff.isEmpty) return patched;
    final columns = _idService.canonicalizePatch(_schema, diff);
    // The kit contract: the row must exist. cairn's patch never inserts (a
    // missing row would silently no-op), so the adapter fails loudly first.
    if (await _collection.fetchById(canonical) == null) {
      throw StateError(
        'CairnKitRepository.patch: no row with id "$canonical" in "$_table" — '
        'patch cannot re-address or insert rows',
      );
    }
    await _collection.patch(canonical, columns);
    final stored = await _collection.fetchById(canonical);
    return stored!;
  }

  @override
  Future<void> delete(String id) =>
      _collection.delete(_idService.canonicalId(_table, id));

  // ── CRDT verbs (ArxaKitCrdtCapable) ───────────────────────────────────────

  @override
  Future<void> adjustCounter(String id, int delta) async {
    _requireTagged(_counterTables, 'counterTables', 'adjustCounter');
    if (delta == 0) return;
    final pk = _idService.canonicalId(_table, id);
    if (delta > 0) {
      await _collection.counterIncrement(pk: pk, delta: delta);
    } else {
      await _collection.counterDecrement(pk: pk, delta: -delta);
    }
  }

  @override
  Future<void> orSetAdd(String id, String element) async {
    _requireTagged(_orSetTables, 'orSetTables', 'orSetAdd');
    await _collection.orSetAdd(
      pk: _idService.canonicalId(_table, id),
      element: element,
    );
  }

  @override
  Future<void> orSetRemove(String id, String element) async {
    _requireTagged(_orSetTables, 'orSetTables', 'orSetRemove');
    await _collection.orSetRemove(
      pk: _idService.canonicalId(_table, id),
      element: element,
    );
  }

  /// CRDT verbs only merge on declared tables — an undeclared write would
  /// clobber. The client-side half of the triple-consistency rule (config ↔
  /// server env ↔ schema flags); the engine enforces the same gate again.
  void _requireTagged(Set<String> tagged, String configField, String verb) {
    if (!tagged.contains(_table)) {
      throw StateError(
        'CairnKitRepository.$verb: table "$_table" is not declared in '
        'ArxaKitCairnConfig.$configField — CRDT verbs merge only on declared '
        'tables (client config, server env, and schema crdt flags must match).',
      );
    }
  }

  // ── Row codecs ─────────────────────────────────────────────────────────────

  /// The wire row for writes: entity → JSON, the tenant `user_id` stamping
  /// hook, then canonical ids (the id column + every reference column).
  Map<String, dynamic> _wireRow(E entity) {
    final row = _registration.toJson(entity);
    final provider = _userIdProvider;
    if (provider != null &&
        _schema.column('user_id') != null &&
        row['user_id'] == null) {
      final userId = provider();
      if (userId != null) row['user_id'] = userId;
    }
    return _idService.canonicalizeRow(_schema, row);
  }

  /// Undo the WS2 view encoding per the kit schema, so entity codecs see the
  /// types they were written for: 0/1 → bool, JSON text → decoded jsonb.
  static Map<String, dynamic> _normalizeRow(
    ArxaKitTableSchema schema,
    Map<String, dynamic> row,
  ) {
    final out = Map<String, dynamic>.of(row);
    for (final column in schema.columns) {
      final value = out[column.name];
      if (value == null) continue;
      switch (column.type) {
        case ArxaKitColumnType.boolean:
          if (value is num) out[column.name] = value != 0;
        case ArxaKitColumnType.integer:
          if (value is num) out[column.name] = value.toInt();
        case ArxaKitColumnType.real:
          if (value is num) out[column.name] = value.toDouble();
        case ArxaKitColumnType.jsonb:
          if (value is String) out[column.name] = jsonDecode(value);
        default:
          break;
      }
    }
    return out;
  }

  // ── Query composition (structured predicates only) ─────────────────────────

  Where? _where(ArxaKitQuery query) {
    if (query.filters.isEmpty) return null;
    final leaves = [
      for (final filter in query.filters)
        switch (filter.op) {
          ArxaKitFilterOp.eq => Where.eq(filter.column, filter.value),
          ArxaKitFilterOp.gt => Where.gt(filter.column, filter.value),
          ArxaKitFilterOp.lt => Where.lt(filter.column, filter.value),
        },
    ];
    return leaves.length == 1 ? leaves.single : Where.and(leaves);
  }
}
