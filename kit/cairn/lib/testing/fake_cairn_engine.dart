/// A store-backed, no-native-library [CairnEngine] for kit behavior tests.
///
/// Unlike cairn's own canned-result fakes, this one KEEPS the rows: writes
/// mutate a per-table store, `query` evaluates the exact SQL grammar the SDK
/// composes (`_composeQuery` + `Where.toSql`), and every mutation re-ticks the
/// table's watch stream — so kit tests exercise the real
/// Cairn → CairnDatabase → Collection stack end to end.
///
/// Served rows emulate the WS2 read-view reality (`json_extract`): booleans
/// arrive as 0/1 integers and nested JSON (jsonb) arrives as JSON text. The
/// kit adapter's per-schema normalization is what turns those back into the
/// types the entity codecs expect — that round-trip is under test here.
library;

import 'dart:async';
import 'dart:convert';

import 'package:cairn_flutter/cairn_flutter.dart';

/// One recorded CRDT verb call (the real engine applies CRDT merge semantics;
/// the fake records delegation and enforces the tagged-table gate).
typedef FakeCrdtCall = ({String table, String pk, Object value});

class FakeCairnEngine implements CairnEngine {
  /// table → pk → stored row (the decoded write payload, JSON-typed).
  final Map<String, Map<String, Map<String, dynamic>>> _store = {};
  final Map<String, StreamController<String>> _ticks = {};

  Set<String> _subscribed = {};
  Set<String> _orSetTables = const {};
  Set<String> _counterTables = const {};
  int _nextOutboxId = 1;

  /// Recorded CRDT delegations, in call order.
  final List<FakeCrdtCall> orSetAddCalls = [];
  final List<FakeCrdtCall> orSetRemoveCalls = [];
  final List<FakeCrdtCall> counterIncrementCalls = [];
  final List<FakeCrdtCall> counterDecrementCalls = [];

  /// Schema tables passed to [applySchema] (names only), in order.
  final List<String> appliedSchemaTables = [];

  int writeCalls = 0;
  int writeBatchCalls = 0;
  int closeCalls = 0;
  int signOutCalls = 0;
  String? lastSetToken;

  // ── CairnEngine ──────────────────────────────────────────────────────────

  @override
  Stream<CairnConnectionState> subscribe({
    required List<CairnTableSub> tables,
    Set<String> orSetTables = const <String>{},
    Set<String> counterTables = const <String>{},
  }) {
    _subscribed = tables.map((t) => t.name).toSet();
    _orSetTables = orSetTables;
    _counterTables = counterTables;
    for (final table in _subscribed) {
      _store.putIfAbsent(table, () => {});
    }
    return const Stream<CairnConnectionState>.empty();
  }

  @override
  Stream<String> watch({required String table}) {
    final controller = _ticks.putIfAbsent(
      table,
      () => StreamController<String>.broadcast(
        // The engine contract: a listener gets the durable snapshot
        // immediately, then a tick after every applied change. The tick
        // payload is the current served row set (Cairn.watch decodes it;
        // watchQuery only uses the tick as a re-query trigger).
        onListen: () => scheduleMicrotask(
          () => _ticks[table]?.add(_snapshot(table)),
        ),
      ),
    );
    return controller.stream;
  }

  @override
  Stream<({int pending, int deadLettered, String? lastError})>
      watchWriteStatus() =>
          Stream.value((pending: 0, deadLettered: 0, lastError: null));

  @override
  Future<String> subscribeStream({
    required String name,
    required String paramsJson,
  }) async =>
      'fake-stream';

  @override
  Future<void> unsubscribeStream({required String id}) async {}

  @override
  Future<int> write({
    required String table,
    required String op,
    required String pk,
    String? payloadJson,
  }) async {
    writeCalls++;
    _apply(table, op, pk, payloadJson);
    _emitTick(table);
    return _nextOutboxId++;
  }

  @override
  Future<List<int>> writeBatch({
    required List<({String table, String op, String pk, String? payloadJson})>
        ops,
  }) async {
    writeBatchCalls++;
    final touched = <String>{};
    for (final w in ops) {
      _apply(w.table, w.op, w.pk, w.payloadJson);
      touched.add(w.table);
    }
    // Entry atomicity: all ops land, then each touched table ticks once.
    for (final table in touched) {
      _emitTick(table);
    }
    return [for (var i = 0; i < ops.length; i++) _nextOutboxId++];
  }

  void _apply(String table, String op, String pk, String? payloadJson) {
    final rows = _store.putIfAbsent(table, () => {});
    switch (op) {
      case 'upsert':
        rows[pk] = (jsonDecode(payloadJson!) as Map<String, dynamic>).cast();
      case 'patch':
        // The real engine never inserts via patch: a missing row is a no-op.
        final existing = rows[pk];
        if (existing != null) {
          existing.addAll(
              (jsonDecode(payloadJson!) as Map<String, dynamic>).cast());
        }
      case 'delete':
        rows.remove(pk);
      default:
        throw ArgumentError.value(op, 'op', 'unknown write op');
    }
  }

  @override
  Future<int> orSetAdd({
    required String table,
    required String pk,
    required String element,
  }) async {
    _requireTagged(table, _orSetTables, 'OrSetTableNotTagged');
    orSetAddCalls.add((table: table, pk: pk, value: element));
    return _nextOutboxId++;
  }

  @override
  Future<int> orSetRemove({
    required String table,
    required String pk,
    required String element,
  }) async {
    _requireTagged(table, _orSetTables, 'OrSetTableNotTagged');
    orSetRemoveCalls.add((table: table, pk: pk, value: element));
    return _nextOutboxId++;
  }

  @override
  Future<int> counterIncrement({
    required String table,
    required String pk,
    required int delta,
  }) async {
    _requireTagged(table, _counterTables, 'CounterTableNotTagged');
    counterIncrementCalls.add((table: table, pk: pk, value: delta));
    return _nextOutboxId++;
  }

  @override
  Future<int> counterDecrement({
    required String table,
    required String pk,
    required int delta,
  }) async {
    _requireTagged(table, _counterTables, 'CounterTableNotTagged');
    counterDecrementCalls.add((table: table, pk: pk, value: delta));
    return _nextOutboxId++;
  }

  void _requireTagged(String table, Set<String> tagged, String errorName) {
    if (!tagged.contains(table)) {
      throw StateError('$errorName: table "$table" was not declared at open');
    }
  }

  @override
  Future<String> query({required String sql}) async =>
      jsonEncode(_evaluate(sql));

  @override
  void applySchema(List<ClientTableFfi> tables) {
    appliedSchemaTables
      ..clear()
      ..addAll(tables.map((t) => t.name));
  }

  @override
  Future<void> setToken(String? token) async {
    lastSetToken = token;
  }

  @override
  Future<void> disconnect() async {}

  @override
  Stream<CairnConnectionState> resume() =>
      const Stream<CairnConnectionState>.empty();

  @override
  Future<void> close() async {
    closeCalls++;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
  }

  @override
  Stream<bool> get webStorageDegraded => const Stream<bool>.empty();

  // ── View emulation ─────────────────────────────────────────────────────────

  void _emitTick(String table) {
    final controller = _ticks[table];
    if (controller != null && controller.hasListener) {
      controller.add(_snapshot(table));
    }
  }

  String _snapshot(String table) => jsonEncode(_servedRows(table));

  /// The WS2 view reality: `json_extract(payload, '$.col')` turns booleans
  /// into 0/1 integers and nested JSON into its text encoding.
  List<Map<String, dynamic>> _servedRows(String table) => [
        for (final row in (_store[table] ?? const {}).values)
          row.map((key, value) => MapEntry(key, _viewValue(value))),
      ];

  Object? _viewValue(Object? value) => switch (value) {
        final bool b => b ? 1 : 0,
        final Map<String, dynamic> m => jsonEncode(m),
        final List<dynamic> l => jsonEncode(l),
        _ => value,
      };

  // ── The composed-SQL evaluator ─────────────────────────────────────────────
  //
  // Parses exactly what `CairnDatabase._composeQuery` + `Where.toSql` emit,
  // plus the attachments driver's projection queries (attachments.dart pump):
  //   SELECT * | <col>, … FROM <view> [WHERE <expr>] [ORDER BY …] [LIMIT n]
  // with <expr> leaves `col <op> lit`, `col IN (…)`, `col IS [NOT] NULL`,
  // fully-parenthesized AND/OR junctions, and `(NOT x)`. Anything outside that
  // grammar throws — the fake never silently accepts SQL the adapter would
  // not produce.

  List<Map<String, dynamic>> _evaluate(String sql) {
    final parser = _SqlParser(sql);
    final (table, projection) = parser.parseSelectFrom();
    final where = parser.parseWhere();
    final orders = parser.parseOrderBy();
    final limit = parser.parseLimit();
    parser.expectEnd();

    var rows = _servedRows(table);
    if (where != null) rows = rows.where(where).toList();
    for (final (field, descending) in orders.reversed) {
      rows = List.of(rows)
        ..sort((a, b) {
          final cmp = _compareValues(a[field], b[field]);
          return descending ? -cmp : cmp;
        });
    }
    if (limit != null && limit >= 0 && rows.length > limit) {
      rows = rows.sublist(0, limit);
    }
    if (projection != null) {
      rows = [
        for (final row in rows)
          {for (final column in projection) column: row[column]},
      ];
    }
    return rows;
  }

  /// The raw stored rows for [table] (decoded write payloads — NOT the
  /// view-encoded serving shape), for test assertions on what landed.
  List<Map<String, dynamic>> rowsFor(String table) =>
      [for (final row in (_store[table] ?? const {}).values) Map.of(row)];

  int _compareValues(Object? a, Object? b) {
    if (a == null && b == null) return 0;
    if (a == null) return -1; // SQLite: NULLs sort first on ASC
    if (b == null) return 1;
    if (a is num && b is num) return a.compareTo(b);
    return a.toString().compareTo(b.toString());
  }
}

class _SqlParser {
  _SqlParser(String sql) : _tokens = _tokenize(sql);

  final List<String> _tokens;
  int _pos = 0;

  static List<String> _tokenize(String sql) {
    final tokens = <String>[];
    var i = 0;
    while (i < sql.length) {
      final c = sql[i];
      if (c.trim().isEmpty) {
        i++;
      } else if (c == '(' || c == ')' || c == ',' || c == '*') {
        tokens.add(c);
        i++;
      } else if (c == "'") {
        final buffer = StringBuffer();
        i++;
        while (i < sql.length) {
          if (sql[i] == "'") {
            if (i + 1 < sql.length && sql[i + 1] == "'") {
              buffer.write("'");
              i += 2;
            } else {
              i++;
              break;
            }
          } else {
            buffer.write(sql[i]);
            i++;
          }
        }
        tokens.add("'${buffer.toString()}'");
      } else if ('<>!='.contains(c)) {
        final two = i + 1 < sql.length ? sql.substring(i, i + 2) : c;
        if (two == '<=' || two == '>=' || two == '!=') {
          tokens.add(two);
          i += 2;
        } else {
          tokens.add(c);
          i++;
        }
      } else if (c == '=') {
        tokens.add('=');
        i++;
      } else {
        final match =
            RegExp(r'[A-Za-z0-9_.\-]+').matchAsPrefix(sql, i);
        if (match == null) {
          throw FormatException('cannot tokenize at $i in: $sql');
        }
        tokens.add(match.group(0)!);
        i = match.end;
      }
    }
    return tokens;
  }

  String _next() {
    if (_pos >= _tokens.length) {
      throw const FormatException('unexpected end of SQL');
    }
    return _tokens[_pos++];
  }

  String _expect(String token) {
    final actual = _next();
    if (actual != token) {
      throw FormatException('expected "$token", got "$actual"');
    }
    return actual;
  }

  bool _peek(String token) =>
      _pos < _tokens.length && _tokens[_pos] == token;

  /// Parses `SELECT * FROM t` or `SELECT col, … FROM t`. Returns the table
  /// and the projection (null = all columns).
  (String, List<String>?) parseSelectFrom() {
    _expect('SELECT');
    List<String>? projection;
    if (_peek('*')) {
      _next();
    } else {
      projection = [_next()];
      while (_peek(',')) {
        _next();
        projection.add(_next());
      }
    }
    _expect('FROM');
    return (_next(), projection);
  }

  bool Function(Map<String, dynamic> row)? parseWhere() {
    if (!_peek('WHERE')) return null;
    _next();
    return _parseExpr();
  }

  bool Function(Map<String, dynamic> row) _parseExpr() {
    if (_peek('(')) {
      _next();
      if (_peek('NOT')) {
        _next();
        final inner = _parseExpr();
        _expect(')');
        return (row) => !inner(row);
      }
      final first = _parseExpr();
      // A junction uses one operator throughout (Where.and / Where.or).
      final op = _next(); // AND | OR
      final parts = <bool Function(Map<String, dynamic>)>[first];
      while (!_peek(')')) {
        parts.add(_parseExpr());
      }
      _expect(')');
      return switch (op) {
        'AND' => (row) => parts.every((p) => p(row)),
        'OR' => (row) => parts.any((p) => p(row)),
        _ => throw FormatException('unknown junction op "$op"'),
      };
    }
    return _parseLeaf();
  }

  bool Function(Map<String, dynamic> row) _parseLeaf() {
    final column = _next();
    if (_peek('IS')) {
      _next();
      final negated = _peek('NOT');
      if (negated) _next();
      _expect('NULL');
      return negated
          ? (row) => row[column] != null
          : (row) => row[column] == null;
    }
    if (_peek('IN')) {
      _next();
      _expect('(');
      final values = <Object>[];
      while (!_peek(')')) {
        values.add(_parseLiteral());
        if (_peek(',')) _next();
      }
      _expect(')');
      return (row) => values.any((v) => row[column] == v);
    }
    final op = _next();
    final literal = _parseLiteral();
    return switch (op) {
      '=' => (row) => row[column] == literal,
      '!=' => (row) => row[column] != null && row[column] != literal,
      '<' => (row) =>
          row[column] is num && (row[column]! as num) < (literal as num),
      '<=' => (row) =>
          row[column] is num && (row[column]! as num) <= (literal as num),
      '>' => (row) =>
          row[column] is num && (row[column]! as num) > (literal as num),
      '>=' => (row) =>
          row[column] is num && (row[column]! as num) >= (literal as num),
      _ => throw FormatException('unknown comparison op "$op"'),
    };
  }

  Object _parseLiteral() {
    final token = _next();
    if (token.startsWith("'")) {
      return token.substring(1, token.length - 1);
    }
    final number = num.parse(token);
    return number;
  }

  List<(String, bool)> parseOrderBy() {
    if (!_peek('ORDER')) return const [];
    _next();
    _expect('BY');
    final terms = <(String, bool)>[];
    while (true) {
      final field = _next();
      final direction = _next();
      terms.add((field, direction == 'DESC'));
      if (!_peek(',')) break;
      _next();
    }
    return terms;
  }

  int? parseLimit() {
    if (!_peek('LIMIT')) return null;
    _next();
    return int.parse(_next());
  }

  void expectEnd() {
    if (_pos != _tokens.length) {
      throw FormatException('trailing tokens: ${_tokens.sublist(_pos)}');
    }
  }
}
