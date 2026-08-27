// Phase 5c — the LIVE proof: the kit's CRDT verbs (ArxaKitCrdtCapable on
// CairnKitRepository) driven through the REAL Rust engine against a REAL
// cairn-server + REAL docker Postgres, wired by tool/live_up.sh.
//
// What this proves that the fake-engine suites cannot (the fake only records
// delegations): two replicas of ONE account writing the same row concurrently
// MERGE on the server instead of last-writer-wins clobbering —
//   - counter-merge:   concurrent increments both survive (Σp − Σn across
//                      per-replica PN entries),
//   - or-set add-wins: concurrent adds of different elements both survive; a
//                      tombstone does not kill a concurrent re-add.
//
// Skip discipline (D4 — `arxa gate tests` stays green everywhere): the group
// self-skips unless ALL of these hold —
//   1. the hook-built host dylib exists (Flutter 3.44 runs cairn_flutter's
//      native-assets hook for `flutter test`),
//   2. tool/live_up.sh has run (its .cairn-live/live.env carries the ws URL
//      + dev JWTs — the test never shells out for tokens),
//   3. /healthz answers (probed synchronously via curl, which live_up.sh
//      already requires).
//
// VM tests have no app bundle, so FRB's default loader can't find
// cairn_flutter_rust.framework in its bundle location — but dlopen DOES try
// the bare relative path against the process cwd (verified against the
// loader's tried-paths list). setUpAll therefore drops a cwd-relative
// `cairn_flutter_rust.framework/cairn_flutter_rust` symlink onto the
// hook-built dylib and the package's own RustLib.init() loads it — no manual
// init (a second init throws "Should not initialize flutter_rust_bridge
// twice"), no src imports.
//
// Ground truth is asserted SERVER-SIDE via `docker exec … psql` (the merge
// happens on the server; the local read views project json_extract columns
// out of the CRDT payload, so only `_pk` is meaningful client-side — see
// cairn-client sqlite.rs:120 "a row's payload IS the counter").
//
// Engine truth this suite is designed to (cairn-client sqlite.rs:120,158):
// a CRDT-tagged table's whole row payload is the CRDT state, and a table is
// exactly ONE tier — hence dedicated kit_live_counters / kit_live_orsets
// tables rather than a mixed-column table.
//
// Run:  kit/cairn/tool/live_up.sh && flutter test test/kit/cairn_live_sync_test.dart
// Stop: kit/cairn/tool/live_down.sh

import 'dart:convert';
import 'dart:io';

import 'package:cairn_flutter/cairn_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_cairn/arxa_kit_cairn.dart';
import 'package:arxa_kit_data/arxa_kit_data.dart';

const _dylibPath = 'build/native_assets/macos/libcairn_flutter_rust.dylib';
const _liveEnvPath = '.cairn-live/live.env';
const _counterTable = 'kit_live_counters';
const _orSetTable = 'kit_live_orsets';

const _counterSchema = ArxaKitTableSchema(
  table: _counterTable,
  columns: [
    ArxaKitColumn.id(),
    ArxaKitColumn('value', ArxaKitColumnType.jsonb,
        nullable: true, crdt: ArxaKitCrdtTier.counter),
  ],
);
const _orSetSchema = ArxaKitTableSchema(
  table: _orSetTable,
  columns: [
    ArxaKitColumn.id(),
    ArxaKitColumn('tags', ArxaKitColumnType.jsonb,
        nullable: true, crdt: ArxaKitCrdtTier.orSet),
  ],
);

/// Minimal row carrier: CRDT payloads are opaque to the read views (only
/// `_pk` round-trips), so reads exist for convergence polling, not values.
class _LiveRow {
  const _LiveRow({required this.id});
  final String id;
  factory _LiveRow.fromJson(Map<String, dynamic> json) =>
      _LiveRow(id: (json['_pk'] ?? json['id'] ?? '') as String);
  static Map<String, dynamic> toRow(_LiveRow r) => {'id': r.id};
}

Map<String, String>? _readLiveEnv() {
  final file = File(_liveEnvPath);
  if (!file.existsSync()) return null;
  final out = <String, String>{};
  for (final line in file.readAsLinesSync()) {
    if (line.startsWith('#') || !line.contains('=')) continue;
    final idx = line.indexOf('=');
    out[line.substring(0, idx)] = line.substring(idx + 1);
  }
  return out;
}

bool _healthzAnswers(String url) {
  try {
    final res = Process.runSync('curl', ['-sf', '-m', '2', '-o', '/dev/null', url]);
    return res.exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// The synchronous skip probe — every reason names its remedy.
String? _skipReason() {
  if (!File(_dylibPath).existsSync()) {
    return 'SKIP: hook-built dylib missing at $_dylibPath '
        '(run any `flutter test` once on macOS to build it)';
  }
  final env = _readLiveEnv();
  if (env == null) {
    return 'SKIP: $_liveEnvPath not found — run tool/live_up.sh first';
  }
  final health = env['CAIRN_LIVE_HEALTH_URL'] ?? '';
  if (health.isEmpty || !_healthzAnswers(health)) {
    return 'SKIP: cairn-server not answering at $health — run tool/live_up.sh';
  }
  return null;
}

/// Server ground truth: one `-t -A` psql scalar via docker (the harness's own
/// deployment; the skip probe already guarantees the stack).
Future<String> _psql(String sql) async {
  final res = await Process.run(
    'docker',
    ['exec', '-i', 'cairn-postgres', 'psql', '-U', 'cairn', '-d', 'cairn',
     '-t', '-A', '-c', sql],
  );
  if (res.exitCode != 0) {
    fail('psql failed (${res.exitCode}): ${res.stderr}\nSQL: $sql');
  }
  return (res.stdout as String).trim();
}

/// Poll [read] until [predicate] holds or the budget runs out. Sync over
/// localhost lands in well under a second; 15s is generous, not fragile.
Future<String> _untilServer(
  String what,
  String sql,
  bool Function(String value) predicate,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  Object? lastError;
  var last = '';
  while (DateTime.now().isBefore(deadline)) {
    try {
      last = await _psql(sql);
      if (predicate(last)) return last;
    } catch (e) {
      lastError = e;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  fail('server did not reach the expected $what within 15s — '
      'last value: "$last", last error: $lastError');
}

Future<void> _untilClientSees(CairnDatabase db, String table, String pk) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (DateTime.now().isBefore(deadline)) {
    final rows = await db.getAllMapped(
      'SELECT _pk FROM $table',
      (row) => row['_pk'] as String,
    );
    if (rows.contains(pk)) return;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  fail('client never saw $pk in $table within 15s');
}

/// cairn's OR-set keeps ONE dot per element (`h` = latest add-HLC, `d` =
/// remove tombstone-HLC); presence is `d == null || h > d` — add-wins revival
/// leaves the tombstone in place and mints a newer `h` (crdt.rs
/// `OrSetElement::is_present`). HLCs compare (wall_ms, ctr) lexicographically.
bool _elementLive(Map<dynamic, dynamic> e) {
  final d = e['d'];
  if (d == null) return true;
  final h = e['h'] as Map;
  final hWall = (h['wall_ms'] as num).toInt();
  final hCtr = (h['ctr'] as num).toInt();
  final dWall = (d['wall_ms'] as num).toInt();
  final dCtr = (d['ctr'] as num).toInt();
  return hWall > dWall || (hWall == dWall && hCtr > dCtr);
}

void main() {
  final skip = _skipReason();

  group('kit.cairn.live-sync', () {
    final ids = ArxaKitIdService();
    late Directory tmp;
    late String wsUrl;
    late String token;
    final dbs = <CairnDatabase>[];

    /// Unique run suffix — the live tables persist between runs (the harness
    /// never drops data), so fixed seeds would collide with a previous run's
    /// merged state.
    final runId = DateTime.now().microsecondsSinceEpoch;

    /// Opens a real-engine client. The harness runs WITHOUT tenant scoping
    /// (live_env.sh explains: cairn's server-side CRDT merge paths are
    /// no-tenant only), so one dev token drives every replica — the merge
    /// story is two DEVICES of one account, and replica identity comes from
    /// the per-file client_id: reopening the same [sqliteName] resumes the
    /// same replica.
    Future<CairnKitRepository<_LiveRow>> openRepo(
      String table,
      String sqliteName,
    ) async {
      final db = await CairnDatabase.connect(
        url: wsUrl,
        token: token,
        sqlitePath: '${tmp.path}/$sqliteName',
        schema: CairnSchemaEmitter().schemaFor(const [_counterSchema, _orSetSchema]),
        orSetTables: const {_orSetTable},
        counterTables: const {_counterTable},
      );
      // connect() returns ready-but-unsubscribed ("call subscribe next to
      // start syncing" — cairn_database.dart); the CRDT verbs gate on the
      // active subscription.
      await db.subscribeTables(const [
        CairnTableSub(name: _counterTable),
        CairnTableSub(name: _orSetTable),
      ]);
      dbs.add(db);
      return CairnKitRepository<_LiveRow>(
        db: db,
        registration: ArxaKitEntityRegistration<_LiveRow>(
          schema: table == _counterTable ? _counterSchema : _orSetSchema,
          fromJson: _LiveRow.fromJson,
          toJson: _LiveRow.toRow,
        ),
        idService: ids,
        orSetTables: const {_orSetTable},
        counterTables: const {_counterTable},
      );
    }

    setUpAll(() async {
      final env = _readLiveEnv()!;
      wsUrl = env['CAIRN_LIVE_WS_URL']!;
      token = env['CAIRN_LIVE_TOKEN_A']!;
      tmp = await Directory.systemTemp.createTemp('arxa_kit_cairn_live_');
      // cwd-relative framework symlink so FRB's default loader (running under
      // the package's own RustLib.init inside createCairnEngine) resolves the
      // hook-built dylib — see the file header.
      final frameworkDir = Directory('cairn_flutter_rust.framework');
      if (!frameworkDir.existsSync()) frameworkDir.createSync();
      final link = Link('cairn_flutter_rust.framework/cairn_flutter_rust');
      if (!link.existsSync()) {
        link.createSync('${Directory.current.path}/$_dylibPath');
      }
    });

    tearDownAll(() async {
      for (final db in dbs) {
        await db.close();
      }
      if (tmp.existsSync()) await tmp.delete(recursive: true);
      final link = Link('cairn_flutter_rust.framework/cairn_flutter_rust');
      if (link.existsSync()) link.deleteSync();
      final frameworkDir = Directory('cairn_flutter_rust.framework');
      if (frameworkDir.existsSync()) frameworkDir.deleteSync();
    });

    test(
      'kit.cairn.live-sync — counter increments from two replicas merge server-side',
      () async {
        final seed = 'live-counter-$runId';
        final pk = ids.canonicalId(_counterTable, seed);
        final sql =
            "SELECT value FROM $_counterTable WHERE id = '$pk'";

        int counterValue(String payloadJson) {
          final entries =
              (jsonDecode(payloadJson)['entries'] as List).cast<Map>();
          var sum = 0;
          for (final e in entries) {
            sum += (e['p'] as num).toInt() - (e['n'] as num).toInt();
          }
          return sum;
        }

        // Replica A comes online and bumps the counter; the write lands in
        // Postgres (server ground truth, not the client's optimistic apply).
        final repoA1 = await openRepo(_counterTable, 'a.sqlite');
        await repoA1.adjustCounter(seed, 3);
        await _untilServer('counter at 3', sql, (v) => counterValue(v) == 3);

        // Replica B (same account, second device) syncs the baseline, then
        // goes offline — B never observes A's next write before making its
        // own, so the two deltas are genuinely concurrent (independent
        // replica entries, no shared read-modify-write base).
        await openRepo(_counterTable, 'b.sqlite');
        await _untilClientSees(dbs.last, _counterTable, pk);
        await dbs.last.close();
        dbs.removeLast();

        await repoA1.adjustCounter(seed, 5); // A: 3 + 5 = 8 on its replica
        final repoB2 = await openRepo(_counterTable, 'b.sqlite');
        await repoB2.adjustCounter(seed, 4); // B: +4 on its own replica

        // The merge proof: BOTH replica entries survive and the counter reads
        // 12. A last-writer-wins server would show exactly one replica's
        // payload — 8 or 4, never 12.
        final merged = await _untilServer(
          'counter merged at 12',
          sql,
          (v) => counterValue(v) == 12,
        );
        final entries = (jsonDecode(merged)['entries'] as List).cast<Map>();
        expect(entries, hasLength(2),
            reason: 'two replica entries = merge; one = clobber. $merged');
      },
      skip: skip,
    );

    test(
      'kit.cairn.live-sync — concurrent or-set adds from two replicas both survive',
      () async {
        final seed = 'live-orset-$runId';
        final pk = ids.canonicalId(_orSetTable, seed);
        final sql = "SELECT tags FROM $_orSetTable WHERE id = '$pk'";

        Set<String> liveElements(String payloadJson) {
          final decoded = jsonDecode(payloadJson);
          final list = (decoded is Map ? decoded['elements'] : decoded) as List;
          return {
            for (final e in list.cast<Map>())
              if (_elementLive(e)) e['v'] as String,
          };
        }

        final repoA = await openRepo(_orSetTable, 'a2.sqlite');
        await repoA.orSetAdd(seed, 'apple');
        await _untilServer(
            'or-set holds apple', sql, (v) => liveElements(v).contains('apple'));

        // B syncs the baseline, goes offline, adds banana concurrently.
        await openRepo(_orSetTable, 'b2.sqlite');
        await _untilClientSees(dbs.last, _orSetTable, pk);
        await dbs.last.close();
        dbs.removeLast();

        final repoB2 = await openRepo(_orSetTable, 'b2.sqlite');
        await repoB2.orSetAdd(seed, 'banana');

        // Add-wins merge: apple AND banana both live. A clobbering server
        // keeps only B's payload — banana alone.
        final merged = await _untilServer(
          'or-set merged {apple, banana}',
          sql,
          (v) {
            final live = liveElements(v);
            return live.contains('apple') && live.contains('banana');
          },
        );
        expect(liveElements(merged), containsAll(<String>['apple', 'banana']));
      },
      skip: skip,
    );

    test(
      'kit.cairn.live-sync — a tombstone does not kill a concurrent re-add',
      () async {
        final seed = 'live-orset-revival-$runId';
        final pk = ids.canonicalId(_orSetTable, seed);
        final sql = "SELECT tags FROM $_orSetTable WHERE id = '$pk'";

        bool ghostLive(String payloadJson) {
          final decoded = jsonDecode(payloadJson);
          final list = (decoded is Map ? decoded['elements'] : decoded) as List;
          return list
              .cast<Map>()
              .any((e) => e['v'] == 'ghost' && _elementLive(e));
        }

        final repoA = await openRepo(_orSetTable, 'a3.sqlite');
        await repoA.orSetAdd(seed, 'ghost');
        await _untilServer('ghost added', sql, ghostLive);

        // B sees ghost, disconnects. A removes ghost (tombstone HLC); B —
        // not having seen the remove — re-adds ghost, minting a NEWER add-HLC
        // (cairn keeps one dot per element; presence is h > d, so the
        // tombstone stays but loses).
        await openRepo(_orSetTable, 'b3.sqlite');
        await _untilClientSees(dbs.last, _orSetTable, pk);
        await dbs.last.close();
        dbs.removeLast();

        await repoA.orSetRemove(seed, 'ghost');
        await _untilServer('ghost tombstoned', sql, (v) => !ghostLive(v));

        final repoB2 = await openRepo(_orSetTable, 'b3.sqlite');
        await repoB2.orSetAdd(seed, 'ghost');

        // Add-wins revival: the kit's documented contract ("a remove is a
        // tombstone a later re-add revives") holds on the real rail — the
        // merged element carries BOTH the tombstone and B's newer add-HLC.
        await _untilServer('ghost revived', sql, ghostLive);
      },
      skip: skip,
    );
  }, skip: skip);
}
