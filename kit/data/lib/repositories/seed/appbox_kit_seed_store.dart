import 'package:rxdart/rxdart.dart';

import 'appbox_kit_seed_persistence.dart';

/// The only place in the data layer where `BehaviorSubject`s are the source
/// of truth (swap rule 1) — every repository built over this store is
/// stream-backed from here, never buffering its own copy of a table.
///
/// Every mutation emits a new immutable map (never mutates a previously
/// emitted map in place) and write-throughs to [persistence] after emitting.
class AppBoxKitSeedStore {
  final Map<String, BehaviorSubject<Map<String, Map<String, dynamic>>>>
      _tables$ = {};
  final AppBoxKitSeedPersistence persistence;

  AppBoxKitSeedStore({required this.persistence});

  BehaviorSubject<Map<String, Map<String, dynamic>>> _subjectFor(
    String table,
  ) {
    return _tables$.putIfAbsent(
      table,
      () => BehaviorSubject<Map<String, Map<String, dynamic>>>.seeded(
        const {},
      ),
    );
  }

  /// Boot-time replace: seeds table contents from persistence or fixtures.
  /// Does NOT write through — the data already came from durable storage.
  void loadTables(Map<String, Map<String, Map<String, dynamic>>> tables) {
    for (final entry in tables.entries) {
      _subjectFor(
        entry.key,
      ).add(Map<String, Map<String, dynamic>>.from(entry.value));
    }
  }

  /// Emits the table's rows immediately, then on every change. Auto-creates
  /// an empty table subject for tables not yet loaded or written to.
  Stream<Map<String, Map<String, dynamic>>> watchTable(String table) =>
      _subjectFor(table).stream;

  Map<String, Map<String, dynamic>> tableSnapshot(String table) =>
      _subjectFor(table).value;

  /// [row] must already be canonicalized and keyed by `row['id']`.
  Future<void> upsertRow(String table, Map<String, dynamic> row) async {
    final id = row['id'] as String;
    final subject = _subjectFor(table);
    final next = Map<String, Map<String, dynamic>>.from(subject.value);
    next[id] = row;
    subject.add(next);
    await persistence.persistTable(table, next);
  }

  Future<void> removeRow(String table, String id) async {
    final subject = _subjectFor(table);
    final next = Map<String, Map<String, dynamic>>.from(subject.value);
    next.remove(id);
    subject.add(next);
    await persistence.persistTable(table, next);
  }

  Future<void> dispose() async {
    for (final subject in _tables$.values) {
      // Fire-and-forget: awaiting close() deadlocks a testWidgets FakeAsync
      // zone (rxdart's close waits for in-flight dispatch that never drains
      // under the fake clock).
      // ignore: unawaited_futures
      subject.close();
    }
  }
}
