import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Write-through durability contract for [ArxaKitSeedStore] — the store's
/// `BehaviorSubject`s stay the reactive source of truth; implementations of
/// this interface only mirror writes to durable storage.
///
/// [load] returns `null` to mean "no persisted state exists" (first boot, or
/// [ArxaKitNoPersistence]), which is distinct from "persisted and empty".
abstract interface class ArxaKitSeedPersistence {
  /// table -> id -> row. `null` when nothing has been persisted yet.
  Future<Map<String, Map<String, Map<String, dynamic>>>?> load();

  /// Overwrites the durable copy of one table with [rows].
  Future<void> persistTable(String table, Map<String, Map<String, dynamic>> rows);

  /// table -> [arxaKitFixtureFingerprint] recorded at the last boot. `null` when
  /// never recorded — including snapshots written before fingerprinting
  /// existed, which [arxaKitResolveBootTables] deliberately treats as "fixtures
  /// changed" so stale snapshots pick up current bundled data.
  Future<Map<String, String>?> loadFixtureFingerprints();

  /// Records the fingerprints of the currently bundled fixtures.
  Future<void> persistFixtureFingerprints(Map<String, String> byTable);

  /// Clears all persisted state.
  Future<void> reset();
}

/// Pure in-memory seed backend (`ArxaKitSeedPersistenceMode.none`): every boot
/// reloads fixtures fresh, nothing survives a restart.
class ArxaKitNoPersistence implements ArxaKitSeedPersistence {
  @override
  Future<Map<String, Map<String, Map<String, dynamic>>>?> load() async => null;

  @override
  Future<void> persistTable(
    String table,
    Map<String, Map<String, dynamic>> rows,
  ) async {}

  @override
  Future<Map<String, String>?> loadFixtureFingerprints() async => null;

  @override
  Future<void> persistFixtureFingerprints(Map<String, String> byTable) async {}

  @override
  Future<void> reset() async {}
}

/// Deep key-sorted copy, so [arxaKitFixtureFingerprint] is insensitive to JSON map
/// ordering (jsonEncode walks a SplayTreeMap in key order).
Object? _canonicalJson(Object? value) => switch (value) {
      Map() => SplayTreeMap<String, Object?>.of({
          for (final entry in value.entries)
            entry.key as String: _canonicalJson(entry.value),
        }),
      List() => [for (final item in value) _canonicalJson(item)],
      _ => value,
    };

/// Stable content hash of one fixture table (FNV-1a 32 over deep key-sorted
/// JSON — deterministic across boots and platforms, unlike `Object.hash`).
/// Changes whenever any bundled fixture row for the table changes.
String arxaKitFixtureFingerprint(Map<String, Map<String, dynamic>> rows) {
  final encoded = jsonEncode(_canonicalJson(rows));
  var hash = 0x811c9dc5;
  for (final unit in encoded.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

/// What boot resolved: the tables to load, which of them must be re-persisted
/// (their snapshot was refreshed from changed fixtures), and the fingerprints
/// of the currently bundled fixtures to record for the next boot.
class ArxaKitBootResolution {
  final Map<String, Map<String, Map<String, dynamic>>> tables;
  final Set<String> reseededTables;
  final Map<String, String> fingerprints;

  const ArxaKitBootResolution({
    required this.tables,
    required this.reseededTables,
    required this.fingerprints,
  });
}

/// Boot precedence, resolved PER TABLE:
///
/// 1. A table the snapshot has never seen comes from [fixtures].
/// 2. A snapshotted table whose recorded fingerprint matches the bundled
///    fixtures comes from the snapshot verbatim — user edits AND deletions
///    survive reboot.
/// 3. A snapshotted table whose fingerprint differs — the app shipped new
///    fixture content — or was never recorded (snapshots written before
///    fingerprinting existed) is RE-SEEDED: fixture rows win by canonical id,
///    rows the user created (ids the fixtures don't know) are preserved.
///
/// Rule 3 is the "stale snapshot" fix: without it, a device that ever
/// persisted a table kept serving that generation of demo data forever —
/// updated bundled fixtures (e.g. notes for newly added seed users) never
/// loaded again, and no rebuild/reinstall of the binary could help because
/// snapshots live in app documents. The cost is deliberate and bounded:
/// user deletions of *seed* rows resurrect only when the bundled fixtures
/// actually change.
///
/// Snapshots are written per table ([ArxaKitSeedPersistence.persistTable]), so a
/// partial snapshot is normal — e.g. `ArxaKitSeedAuthService.initialize`
/// write-throughs only `kit_auth_users` on first boot; rule 1 keeps that
/// partial snapshot from shadowing unseen fixture tables.
ArxaKitBootResolution arxaKitResolveBootTables({
  required Map<String, Map<String, Map<String, dynamic>>> fixtures,
  Map<String, Map<String, Map<String, dynamic>>>? snapshot,
  Map<String, String>? recordedFingerprints,
}) {
  final fingerprints = <String, String>{
    for (final entry in fixtures.entries)
      entry.key: arxaKitFixtureFingerprint(entry.value),
  };
  final tables = <String, Map<String, Map<String, dynamic>>>{
    ...fixtures,
    ...?snapshot,
  };
  final reseeded = <String>{};

  if (snapshot != null) {
    for (final entry in fixtures.entries) {
      final table = entry.key;
      final persisted = snapshot[table];
      if (persisted == null) continue; // rule 1: fixtures already in place
      if (recordedFingerprints?[table] == fingerprints[table]) {
        continue; // rule 2: fixtures unchanged, snapshot is the truth
      }
      // Rule 3: fixtures changed (or predate fingerprinting) — re-seed.
      tables[table] = {...persisted, ...entry.value};
      reseeded.add(table);
    }
  }

  return ArxaKitBootResolution(
    tables: tables,
    reseededTables: reseeded,
    fingerprints: fingerprints,
  );
}

/// Write-through JSON snapshot, one file per table, under
/// `<baseDir>/arxa_kit_data/seed/<table>.json`. Boot resolves snapshot vs
/// fixtures per table (see [arxaKitResolveBootTables]). A corrupt
/// snapshot file throws — naming the file — rather than silently discarding
/// data, so the operator deletes it deliberately instead of losing state
/// unnoticed.
class ArxaKitSnapshotPersistence implements ArxaKitSeedPersistence {
  /// Boot-metadata sidecar (see [ArxaKitSeedPersistence.loadFixtureFingerprints]).
  /// The leading dot keeps it visually distinct from table snapshots; [load]
  /// filters it out of the table scan explicitly.
  static const _fingerprintsFile = '.fixture_fingerprints.json';

  final Directory? _overrideDirectory;

  ArxaKitSnapshotPersistence({Directory? overrideDirectory})
      : _overrideDirectory = overrideDirectory;

  Future<Directory> _seedDir() async {
    final base = _overrideDirectory ?? await getApplicationDocumentsDirectory();
    return Directory('${base.path}/arxa_kit_data/seed');
  }

  @override
  Future<Map<String, Map<String, Map<String, dynamic>>>?> load() async {
    final dir = await _seedDir();
    if (!dir.existsSync()) return null;

    final files = dir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.json'))
        // The fingerprints sidecar is boot metadata, not a table.
        .where((file) => file.uri.pathSegments.last != _fingerprintsFile)
        .toList();
    if (files.isEmpty) return null;

    final result = <String, Map<String, Map<String, dynamic>>>{};
    for (final file in files) {
      final fileName = file.uri.pathSegments.last;
      final table = fileName.substring(0, fileName.length - '.json'.length);

      Object? decoded;
      try {
        decoded = jsonDecode(await file.readAsString());
      } on FormatException {
        decoded = null;
      }
      if (decoded is! Map) {
        throw FormatException('Corrupt seed snapshot at "${file.path}"');
      }

      result[table] = decoded.map(
        (id, row) => MapEntry(id as String, Map<String, dynamic>.from(row as Map)),
      );
    }
    return result;
  }

  @override
  Future<void> persistTable(
    String table,
    Map<String, Map<String, dynamic>> rows,
  ) async {
    final dir = await _seedDir();
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final file = File('${dir.path}/$table.json');
    await file.writeAsString(jsonEncode(rows));
  }

  @override
  Future<Map<String, String>?> loadFixtureFingerprints() async {
    final dir = await _seedDir();
    final file = File('${dir.path}/$_fingerprintsFile');
    if (!file.existsSync()) return null;

    // Unlike table snapshots, corrupt fingerprints are NOT fatal: they carry
    // no user data — treating them as absent just re-seeds fixture rows on
    // this boot, which is the safe self-healing outcome.
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      return decoded.cast<String, String>();
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> persistFixtureFingerprints(Map<String, String> byTable) async {
    final dir = await _seedDir();
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final file = File('${dir.path}/$_fingerprintsFile');
    await file.writeAsString(jsonEncode(byTable));
  }

  @override
  Future<void> reset() async {
    final dir = await _seedDir();
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  }
}
