import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_data/assets/appbox_kit_asset_reader.dart';
import 'package:appbox_kit_data/auth/appbox_kit_auth_types.dart';
import 'package:appbox_kit_data/ids/appbox_kit_id_service.dart';
import 'package:appbox_kit_data/models/appbox_kit_entity_registration.dart';
import 'package:appbox_kit_data/query/appbox_kit_query.dart';
import 'package:appbox_kit_data/repositories/seed/appbox_kit_seed_persistence.dart';
import 'package:appbox_kit_data/repositories/seed/appbox_kit_seed_repository.dart';
import 'package:appbox_kit_data/repositories/seed/appbox_kit_seed_store.dart';
import 'package:appbox_kit_data/schema/appbox_kit_table_schema.dart';
import 'package:appbox_kit_data/seeding/appbox_kit_fixture_loader.dart';

/// Integration test for the seed-backend boot path that the showcase app
/// exercises at runtime: `AppBoxKitSnapshotPersistence` (write-through JSON, one
/// file per table) + `AppBoxKitFixtureLoader` + `appBoxKitResolveBootTables` + `AppBoxKitSeedStore`
/// + `AppBoxKitSeedRepository`.
///
/// The gap this closes: `appbox_kit_data_initialize_test.dart` boots with
/// `AppBoxKitSeedPersistenceMode.none` (so `load()` is always null and
/// `appBoxKitResolveBootTables` is a no-op), and `appbox_kit_seed_persistence_test.dart` tests
/// `appBoxKitResolveBootTables` as a pure function. Neither wires the resolution
/// through the store + repository read path against a real snapshot on disk —
/// which is exactly the runtime shape that regressed twice: (a) a prior
/// boot's write-through of only `kit_auth_users` shadowed every fixture table
/// on the next boot, emptying the showcase app's notes; (b) once a snapshot
/// existed, updated bundled fixtures (new seed users' notes) never loaded
/// again — no rebuild/reinstall helped because snapshots live in app
/// documents, not the bundle.
///
/// These tests reconstruct that runtime shape directly against the public
/// components (no `AppBoxKitData.initialize` — it constructs `AppBoxKitSnapshotPersistence`
/// with no override directory, so it can't be pointed at a temp dir) and
/// assert the fixtures survive a partial snapshot through `watchAll`.
void main() {
  late Directory tempDir;
  late AppBoxKitIdService idService;

  // Minimal schemas mirroring the showcase app's notes slice: a notes table
  // whose `owner` references the reserved auth-users table, and a folders
  // table. Canonicalization is what makes owner-matching work, so the schemas
  // must mark `owner` as a reference — same as note.dart/note_folder.dart.
  const notesTable = 'notes';
  const foldersTable = 'notes_folders';

  final notesSchema = AppBoxKitTableSchema(
    table: notesTable,
    columns: [
      AppBoxKitColumn.id(),
      AppBoxKitColumn('folder_id', AppBoxKitColumnType.reference,
          references: foldersTable),
      AppBoxKitColumn('owner', AppBoxKitColumnType.reference,
          references: kAppBoxKitAuthUsersTable),
      AppBoxKitColumn('body', AppBoxKitColumnType.text),
    ],
  );
  final foldersSchema = AppBoxKitTableSchema(
    table: foldersTable,
    columns: [
      AppBoxKitColumn.id(),
      AppBoxKitColumn('name', AppBoxKitColumnType.text),
      AppBoxKitColumn('owner', AppBoxKitColumnType.reference,
          references: kAppBoxKitAuthUsersTable),
    ],
  );

  // Fixtures in the same hand-authored shape as the showcase app's
  // assets/seed/*.json — seed keys, not UUIDs; the loader canonicalizes them.
  // `jsonEncode` isn't const, so this is a final, not a const.
  final fixturesJson = {
    'assets/seed/notes.json': jsonEncode([
      {
        'id': 'note-groceries',
        'folder_id': 'folder-personal',
        'owner': 'user-1',
        'body': 'Oat milk\nEggs',
      },
      {
        'id': 'note-standup',
        'folder_id': 'folder-work',
        'owner': 'user-1',
        'body': 'Shipped the data layer',
      },
    ]),
    'assets/seed/notes_folders.json': jsonEncode([
      {'id': 'folder-work', 'name': 'Work', 'owner': 'user-1'},
      {'id': 'folder-personal', 'name': 'Personal', 'owner': 'user-1'},
    ]),
  };

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('kit_seed_boot_merge_test');
    idService = AppBoxKitIdService();
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  /// Boots the seed backend the way `AppBoxKitData._initializeSeed` does, but with
  /// a snapshot directory we control: load fixtures, load the snapshot +
  /// recorded fingerprints, resolve per-table, load into the store, and
  /// write-through re-seeded tables + current fingerprints — the same
  /// sequence as `appbox_kit_data.dart`, minus `AppBoxKitData.initialize`'s static-state
  /// wiring (which can't accept an override directory).
  Future<AppBoxKitSeedStore> boot({
    required Map<String, String> fixtureAssets,
  }) async {
    final persistence = AppBoxKitSnapshotPersistence(overrideDirectory: tempDir);
    final fixtures = await AppBoxKitFixtureLoader(
      idService: idService,
      assetReader: AppBoxKitMemoryAssetReader(fixtureAssets),
    ).load(
      assetPaths: fixtureAssets.keys.toList(),
      schemasByTable: {
        notesTable: notesSchema,
        foldersTable: foldersSchema,
      },
    );
    final resolution = appBoxKitResolveBootTables(
      fixtures: fixtures,
      snapshot: await persistence.load(),
      recordedFingerprints: await persistence.loadFixtureFingerprints(),
    );
    final store = AppBoxKitSeedStore(persistence: persistence);
    store.loadTables(resolution.tables);
    for (final table in resolution.reseededTables) {
      await persistence.persistTable(table, resolution.tables[table]!);
    }
    await persistence.persistFixtureFingerprints(resolution.fingerprints);
    return store;
  }

  group('seed boot with snapshot persistence', () {
    test(
        'kit.data.seed-repos — first boot (no snapshot) → fixtures reach the '
        'repository read path', () async {
      final store = boot(fixtureAssets: fixturesJson);
      final repo = AppBoxKitSeedRepository<Map<String, dynamic>>(
        store: await store,
        registration: _mapRegistration(notesSchema),
        idService: idService,
      );

      final ownerCanonical =
          idService.canonicalId(kAppBoxKitAuthUsersTable, 'user-1');
      final notes = await repo.getAll(
        AppBoxKitQuery(filters: [AppBoxKitFilter.eq('owner', ownerCanonical)]),
      );

      expect(notes.length, 2,
          reason: 'both fixture notes belong to user-1');
    });

    test(
        'kit.data.seed-repos — REGRESSION: partial snapshot (only '
        'kit_auth_users persisted) must not shadow fixture tables on the '
        'next boot — the showcase app rendered empty notes because of this',
        () async {
      // Boot 1: nothing persisted yet → fixtures load. Simulate the auth
      // service's write-through of only the reserved users table (the real
      // AppBoxKitSeedAuthService.initialize upserts each fake user, which
      // persists kit_auth_users and nothing else on first boot).
      final store1 = await boot(fixtureAssets: fixturesJson);
      await store1.upsertRow(kAppBoxKitAuthUsersTable, {
        'id': idService.canonicalId(kAppBoxKitAuthUsersTable, 'user-1'),
        'email': 'evan@seed.local',
      });

      // The on-disk snapshot now has ONLY kit_auth_users (plus the boot
      // fingerprints sidecar, which is metadata, not a table) — same shape
      // as the simulator containers that showed empty notes.
      final seedDir = Directory('${tempDir.path}/appbox_kit_data/seed');
      expect(seedDir.existsSync(), isTrue);
      expect(
        seedDir
            .listSync()
            .whereType<File>()
            .map((f) => f.uri.pathSegments.last)
            .where((name) => name != '.fixture_fingerprints.json'),
        ['kit_auth_users.json'],
        reason: 'the regression is specifically a PARTIAL snapshot',
      );

      // Boot 2: the snapshot exists but covers one table. Before the
      // per-table resolution fix, `snapshot ?? fixtures` returned the partial
      // snapshot and dropped notes/notes_folders entirely.
      final store2 = await boot(fixtureAssets: fixturesJson);
      final notesRepo = AppBoxKitSeedRepository<Map<String, dynamic>>(
        store: store2,
        registration: _mapRegistration(notesSchema),
        idService: idService,
      );
      final foldersRepo = AppBoxKitSeedRepository<Map<String, dynamic>>(
        store: store2,
        registration: _mapRegistration(foldersSchema),
        idService: idService,
      );

      final ownerCanonical =
          idService.canonicalId(kAppBoxKitAuthUsersTable, 'user-1');
      final notes = await notesRepo.getAll(
        AppBoxKitQuery(filters: [AppBoxKitFilter.eq('owner', ownerCanonical)]),
      );
      final folders = await foldersRepo.getAll(
        AppBoxKitQuery(filters: [AppBoxKitFilter.eq('owner', ownerCanonical)]),
      );

      expect(notes.length, 2, reason: 'fixture notes must survive reboot');
      expect(folders.length, 2, reason: 'fixture folders must survive reboot');
    });

    test(
        'kit.data.seed-repos — a deliberately-empty persisted table shadows '
        'its fixtures (user deletes survive reboot)', () async {
      // Boot 1: fixtures load (notes table populated).
      await boot(fixtureAssets: fixturesJson);
      // Simulate "user deleted every note then rebooted" by persisting an
      // empty map for the notes table directly through the persistence layer
      // (the store's removeRow would do this one-by-one; this is equivalent
      // and clearer for the test).
      final persistence = AppBoxKitSnapshotPersistence(overrideDirectory: tempDir);
      await persistence.persistTable('notes', {});

      // Boot 2: notes table is persisted-and-empty → must stay empty (not
      // refill from fixtures), while folders still come from fixtures.
      final store2 = await boot(fixtureAssets: fixturesJson);
      final notesRepo = AppBoxKitSeedRepository<Map<String, dynamic>>(
        store: store2,
        registration: _mapRegistration(notesSchema),
        idService: idService,
      );

      final notes = await notesRepo.getAll();
      expect(notes, isEmpty,
          reason: 'a persisted empty table is a deliberate delete, not a miss');
    });

    test(
        'kit.data.seed-repos — REGRESSION: shipped fixture update re-seeds '
        'an already-snapshotted install — new seed rows appear, user-created '
        'rows survive (the showcase app kept serving first-generation demo '
        'data forever)', () async {
      // Boot 1: first fixture generation loads and is snapshotted (the store
      // write-throughs the notes table when the user writes to it).
      final store1 = await boot(fixtureAssets: fixturesJson);
      await store1.upsertRow(notesTable, {
        'id': idService.canonicalId(notesTable, 'note-mine'),
        'folder_id': idService.canonicalId(foldersTable, 'folder-personal'),
        'owner': idService.canonicalId(kAppBoxKitAuthUsersTable, 'user-1'),
        'body': 'written in-app',
      });

      // The app ships a new fixture generation: one edited seed note and one
      // brand-new seed note (this is exactly "added seed data for more users
      // and their notes" that never reached devices).
      final fixturesJsonV2 = {
        'assets/seed/notes.json': jsonEncode([
          {
            'id': 'note-groceries',
            'folder_id': 'folder-personal',
            'owner': 'user-1',
            'body': 'Oat milk\nEggs\nBeans', // edited
          },
          {
            'id': 'note-standup',
            'folder_id': 'folder-work',
            'owner': 'user-1',
            'body': 'Shipped the data layer',
          },
          {
            'id': 'note-retro',
            'folder_id': 'folder-work',
            'owner': 'user-1',
            'body': 'Retro notes', // new seed row
          },
        ]),
        'assets/seed/notes_folders.json':
            fixturesJson['assets/seed/notes_folders.json']!,
      };

      // Boot 2 against the SAME on-disk snapshot but new bundled fixtures.
      final store2 = await boot(fixtureAssets: fixturesJsonV2);
      final notesRepo = AppBoxKitSeedRepository<Map<String, dynamic>>(
        store: store2,
        registration: _mapRegistration(notesSchema),
        idService: idService,
      );

      final notes = await notesRepo.getAll();
      final bodies = notes.map((n) => n['body']).toSet();
      expect(bodies, {
        'Oat milk\nEggs\nBeans', // seed edit won over the stale snapshot row
        'Shipped the data layer',
        'Retro notes', // new seed row reached the snapshotted install
        'written in-app', // user-created row survived the re-seed
      });

      // Boot 3 with the same generation: idempotent — fingerprints now match,
      // so the (re-seeded) snapshot is the truth and nothing changes.
      final store3 = await boot(fixtureAssets: fixturesJsonV2);
      final notes3 = await AppBoxKitSeedRepository<Map<String, dynamic>>(
        store: store3,
        registration: _mapRegistration(notesSchema),
        idService: idService,
      ).getAll();
      expect(notes3.length, 4);
    });
  });
}

/// A registration that passes rows through as-is, so the tests can assert on
/// raw canonicalized rows without a domain model.
AppBoxKitEntityRegistration<Map<String, dynamic>> _mapRegistration(
  AppBoxKitTableSchema schema,
) =>
    AppBoxKitEntityRegistration<Map<String, dynamic>>(
      schema: schema,
      fromJson: (json) => Map<String, dynamic>.from(json),
      toJson: (e) => e,
    );
