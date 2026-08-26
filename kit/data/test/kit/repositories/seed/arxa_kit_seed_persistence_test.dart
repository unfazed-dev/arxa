import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_data/repositories/seed/arxa_kit_seed_persistence.dart';

/// ArxaKitSeedPersistence tests.
///
/// Branches under test:
/// - [ArxaKitSnapshotPersistence] with `overrideDirectory` pointing at a temp
///   dir (so no `path_provider` platform channel is touched): roundtrip
///   (`persistTable` then `load` returns the same nested map), `load` with
///   no directory yet returns `null`, a corrupt JSON file makes `load`
///   throw a [FormatException] whose message names the offending file
///   path, and `reset` removes the directory entirely.
/// - [ArxaKitNoPersistence].`load` always returns `null`.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('kit_seed_persistence_test');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('ArxaKitSnapshotPersistence', () {
    test('kit.data.seed-repos — persistTable then load roundtrips the same nested map', () async {
      final persistence = ArxaKitSnapshotPersistence(overrideDirectory: tempDir);
      final rows = {
        'row-1': {'id': 'row-1', 'name': 'Alpha'},
        'row-2': {'id': 'row-2', 'name': 'Beta'},
      };

      await persistence.persistTable('widgets', rows);
      final loaded = await persistence.load();

      expect(loaded, isNotNull);
      expect(loaded!['widgets'], rows);
    });

    test('kit.data.seed-repos — load with no directory yet returns null', () async {
      final persistence = ArxaKitSnapshotPersistence(overrideDirectory: tempDir);

      expect(await persistence.load(), isNull);
    });

    test('kit.data.seed-repos — corrupt JSON file throws FormatException naming the file path', () async {
      final persistence = ArxaKitSnapshotPersistence(overrideDirectory: tempDir);
      final seedDir = Directory('${tempDir.path}/arxa_kit_data/seed')
        ..createSync(recursive: true);
      final corruptFile = File('${seedDir.path}/widgets.json')
        ..writeAsStringSync('{not valid json');

      await expectLater(
        persistence.load(),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains(corruptFile.path),
          ),
        ),
      );
    });

    test('kit.data.seed-repos — reset removes the directory', () async {
      final persistence = ArxaKitSnapshotPersistence(overrideDirectory: tempDir);
      await persistence.persistTable('widgets', {
        'row-1': {'id': 'row-1'},
      });
      final seedDir = Directory('${tempDir.path}/arxa_kit_data/seed');
      expect(seedDir.existsSync(), isTrue);

      await persistence.reset();

      expect(seedDir.existsSync(), isFalse);
    });
  });

  group('ArxaKitNoPersistence', () {
    test('kit.data.seed-repos — load always returns null', () async {
      final persistence = ArxaKitNoPersistence();
      expect(await persistence.load(), isNull);
    });
  });

  group('fixture fingerprints sidecar', () {
    test('kit.data.seed-repos — loadFixtureFingerprints returns null before any persist', () async {
      final persistence = ArxaKitSnapshotPersistence(overrideDirectory: tempDir);
      expect(await persistence.loadFixtureFingerprints(), isNull);
    });

    test('kit.data.seed-repos — persist then load roundtrips, and the sidecar is not a table', () async {
      final persistence = ArxaKitSnapshotPersistence(overrideDirectory: tempDir);

      await persistence.persistFixtureFingerprints({'notes': 'abcd1234'});

      expect(await persistence.loadFixtureFingerprints(), {'notes': 'abcd1234'});
      // The sidecar lives in the same dir as table snapshots but must not
      // surface as a table named ".fixture_fingerprints".
      expect(await persistence.load(), isNull);
    });

    test('kit.data.seed-repos — corrupt sidecar degrades to null (re-seed) instead of throwing', () async {
      final persistence = ArxaKitSnapshotPersistence(overrideDirectory: tempDir);
      Directory('${tempDir.path}/arxa_kit_data/seed').createSync(recursive: true);
      File('${tempDir.path}/arxa_kit_data/seed/.fixture_fingerprints.json')
          .writeAsStringSync('{not valid json');

      expect(await persistence.loadFixtureFingerprints(), isNull);
    });
  });

  group('arxaKitFixtureFingerprint', () {
    test('kit.data.seed-repos — is stable across map key ordering', () {
      final a = {
        'n-1': {'id': 'n-1', 'body': 'seeded note'},
      };
      final b = {
        'n-1': {'body': 'seeded note', 'id': 'n-1'},
      };
      expect(arxaKitFixtureFingerprint(a), arxaKitFixtureFingerprint(b));
    });

    test('kit.data.seed-repos — changes when any row content changes', () {
      final a = {
        'n-1': {'id': 'n-1', 'body': 'seeded note'},
      };
      final b = {
        'n-1': {'id': 'n-1', 'body': 'edited note'},
      };
      expect(arxaKitFixtureFingerprint(a), isNot(arxaKitFixtureFingerprint(b)));
    });
  });

  group('arxaKitResolveBootTables', () {
    final fixtures = {
      'notes': {
        'n-1': {'id': 'n-1', 'body': 'seeded note'},
      },
      'notes_folders': {
        'f-1': {'id': 'f-1', 'name': 'Notes'},
      },
    };
    Map<String, String> fingerprintsOf(
      Map<String, Map<String, Map<String, dynamic>>> tables,
    ) =>
        {for (final e in tables.entries) e.key: arxaKitFixtureFingerprint(e.value)};

    test('kit.data.seed-repos — no snapshot (first boot) → fixtures verbatim, nothing re-seeded', () {
      final resolution = arxaKitResolveBootTables(fixtures: fixtures, snapshot: null);

      expect(resolution.tables, fixtures);
      expect(resolution.reseededTables, isEmpty);
      expect(resolution.fingerprints, fingerprintsOf(fixtures));
    });

    test(
        'kit.data.seed-repos — rule 1: partial snapshot must not shadow '
        'never-persisted fixture tables (regression: fake-auth boot persists '
        'only kit_auth_users, second boot then showed empty notes)', () async {
      final persistence = ArxaKitSnapshotPersistence(overrideDirectory: tempDir);

      // Boot 1: nothing persisted → fixtures. Fake-auth initialize then
      // write-throughs ONLY the reserved users table.
      expect(await persistence.load(), isNull);
      await persistence.persistTable('kit_auth_users', {
        'u-1': {'id': 'u-1', 'email': 'evan@seed.local'},
      });

      // Boot 2: snapshot exists but covers one table.
      final resolution = arxaKitResolveBootTables(
        fixtures: fixtures,
        snapshot: await persistence.load(),
      );

      expect(resolution.tables['notes'], fixtures['notes']);
      expect(resolution.tables['notes_folders'], fixtures['notes_folders']);
      expect(resolution.tables['kit_auth_users']?.keys, ['u-1']);
    });

    test(
        'kit.data.seed-repos — rule 2: matching fingerprint → snapshot '
        'verbatim (user edits and deletions survive reboot)', () {
      final resolution = arxaKitResolveBootTables(
        fixtures: fixtures,
        snapshot: {'notes': {}}, // user deleted the seeded note
        recordedFingerprints: fingerprintsOf(fixtures),
      );

      expect(resolution.tables['notes'], isEmpty);
      expect(resolution.tables['notes_folders'], fixtures['notes_folders']);
      expect(resolution.reseededTables, isEmpty);
    });

    test(
        'kit.data.seed-repos — rule 3: changed fixtures re-seed a stale '
        'snapshot, preserving user-created rows (regression: updated seed '
        'data never reached devices that already persisted a snapshot)', () {
      final snapshot = {
        'notes': {
          'n-1': {'id': 'n-1', 'body': 'OLD seeded generation'},
          'user-note': {'id': 'user-note', 'body': 'written in-app'},
        },
      };
      // Recorded fingerprints describe the OLD fixture generation.
      final oldFingerprints = {
        'notes': arxaKitFixtureFingerprint(snapshot['notes']!..remove('user-note')),
      };
      snapshot['notes']!['user-note'] = {'id': 'user-note', 'body': 'written in-app'};

      final resolution = arxaKitResolveBootTables(
        fixtures: fixtures,
        snapshot: snapshot,
        recordedFingerprints: oldFingerprints,
      );

      expect(resolution.tables['notes']?['n-1'], fixtures['notes']!['n-1']);
      expect(resolution.tables['notes']?['user-note'],
          {'id': 'user-note', 'body': 'written in-app'});
      expect(resolution.reseededTables, {'notes'});
      expect(resolution.fingerprints, fingerprintsOf(fixtures));
    });

    test(
        'kit.data.seed-repos — rule 3: snapshot that predates fingerprinting '
        '(no sidecar) re-seeds fixture rows', () {
      final resolution = arxaKitResolveBootTables(
        fixtures: fixtures,
        snapshot: {
          'notes': {
            'n-1': {'id': 'n-1', 'body': 'OLD seeded generation'},
          },
        },
        recordedFingerprints: null,
      );

      expect(resolution.tables['notes']?['n-1'], fixtures['notes']!['n-1']);
      expect(resolution.reseededTables, {'notes'});
    });
  });
}
