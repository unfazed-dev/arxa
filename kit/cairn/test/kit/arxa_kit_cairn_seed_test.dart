import 'package:flutter_test/flutter_test.dart';
import 'package:cairn_flutter/cairn_flutter.dart';
import 'package:arxa_kit_core/arxa_kit_locator.dart';
import 'package:arxa_kit_cairn/arxa_kit_cairn.dart';
import 'package:arxa_kit_cairn/arxa_kit_cairn_testing.dart';
import 'package:arxa_kit_data/arxa_kit_data.dart';

import '../support/post_harness.dart';

/// Fixture seeding under the plugin backend: the seed backend boots from
/// bundled fixtures, but a plugin backend's package owns its writes — kit/data
/// hands the plugin the fixture assets and asset reader at initialize, and
/// `ArxaKitDataSeeder.push` delegates through `ArxaKitPluginSeeder`.
///
/// Branches under test:
/// - localOnly auto-seeds at boot (no server to seed from — bundled fixtures
///   boot the content, seed-backend parity).
/// - Seeding is always-upsert: canonical ids are deterministic, so a re-seed
///   never duplicates and heals deleted rows.
/// - Server modes never auto-seed (server-bound writes per boot are wrong);
///   the operator pushes explicitly through `ArxaKitDataSeeder.push`.
/// - A fixture targeting a CRDT-tagged table is refused — a plain upsert
///   would clobber merge state.
void main() {
  tearDown(() {
    ArxaKitData.resetForTesting();
    arxaKitLocator.reset();
  });

  const fixtureAsset = 'assets/seed/posts.json';
  const fixtureJson = '''
[
  {"id": "hello", "title": "Hello", "likes": 1, "score": 0.5, "published": true},
  {"id": "world", "title": "World", "likes": 2, "score": 1.5, "published": false}
]
''';
  final reader = ArxaKitMemoryAssetReader({fixtureAsset: fixtureJson});

  ArxaKitCairnBackend backendWith(
    FakeCairnEngine engine, {
    ArxaKitCairnConfig config = const ArxaKitCairnConfig(),
  }) =>
      ArxaKitCairnBackend(
        config: config,
        openDatabase: (config, schema, token) async {
          // ignore: invalid_use_of_visible_for_testing_member
          final cairn = Cairn.withEngine(
            engine,
            orSetTables: config.orSetTables,
            counterTables: config.counterTables,
          );
          // ignore: invalid_use_of_visible_for_testing_member
          return CairnDatabase.localForTest(cairn, schema);
        },
      );

  group('kit.cairn.seed', () {
    test(
      'kit.cairn.seed — localOnly boots seeded from the bundled fixtures',
      () async {
        // Given a localOnly plugin and a bundled posts fixture
        await ArxaKitData.initialize(
          config: ArxaKitDataConfig(
            backend: ArxaKitDataBackend.plugin,
            plugin: backendWith(FakeCairnEngine()),
          ),
          entities: const [postRegistration],
          fixtureAssets: const [fixtureAsset],
          assetReader: reader,
        );

        // Then the fixture rows are readable through the repository
        final repo = arxaKitLocator<ArxaKitRepository<Post>>();
        final all = await repo.getAll();
        expect(all.map((p) => p.title), containsAll(['Hello', 'World']));
        expect((await repo.getById('hello'))!.likes, 1);
      },
    );

    test(
      'kit.cairn.seed — re-seeding upserts the same canonical rows and heals deletes',
      () async {
        // Given a seeded boot
        final backend = backendWith(FakeCairnEngine());
        await ArxaKitData.initialize(
          config: ArxaKitDataConfig(
            backend: ArxaKitDataBackend.plugin,
            plugin: backend,
          ),
          entities: const [postRegistration],
          fixtureAssets: const [fixtureAsset],
          assetReader: reader,
        );
        final repo = arxaKitLocator<ArxaKitRepository<Post>>();
        expect((await repo.getAll()).length, 2);

        // When the same fixtures seed again AND one row was deleted
        await repo.delete('hello');
        await backend.seedFixtures(const [fixtureAsset], assetReader: reader);

        // Then the table still holds exactly the two fixture rows — the
        // deterministic canonical ids make every re-seed an upsert
        final after = await repo.getAll();
        expect(after.length, 2);
        expect(after.map((p) => p.title), containsAll(['Hello', 'World']));
      },
    );

    test(
      'kit.cairn.seed — server modes never auto-seed; the operator pushes explicitly',
      () async {
        // Given a sync-mode plugin booted with fixtures declared
        final backend = backendWith(
          FakeCairnEngine(),
          config: const ArxaKitCairnConfig(
            mode: ArxaKitCairnMode.sync,
            syncUrl: 'ws://localhost:0/sync',
          ),
        );
        await ArxaKitData.initialize(
          config: ArxaKitDataConfig(
            backend: ArxaKitDataBackend.plugin,
            plugin: backend,
          ),
          entities: const [postRegistration],
          fixtureAssets: const [fixtureAsset],
          assetReader: reader,
        );

        // Then nothing was seeded at boot — server-bound writes per boot are
        // the operator's call, not the library's
        final repo = arxaKitLocator<ArxaKitRepository<Post>>();
        expect(await repo.getAll(), isEmpty);

        // When the operator pushes the fixtures (they would flow upstream
        // through the ordinary outbox)
        await ArxaKitDataSeeder().push(
          fixtureAssets: const [fixtureAsset],
          assetReader: reader,
        );

        // Then the rows land in the local database
        expect((await repo.getAll()).length, 2);
      },
    );

    test(
      'kit.cairn.seed — a CRDT-tagged fixture fails the localOnly boot loudly',
      () async {
        // Given counter_posts declared as a counter table and a fixture for it
        const counterFixture = 'assets/seed/counter_posts.json';
        final counterReader = ArxaKitMemoryAssetReader({
          counterFixture: '[{"id": "c-1", "title": "x", "likes": 0}]',
        });

        // Then boot refuses: a plain upsert would clobber the merge state
        await expectLater(
          ArxaKitData.initialize(
            config: ArxaKitDataConfig(
              backend: ArxaKitDataBackend.plugin,
              plugin: backendWith(
                FakeCairnEngine(),
                config:
                    const ArxaKitCairnConfig(counterTables: {'counter_posts'}),
              ),
            ),
            entities: const [counterPostRegistration],
            fixtureAssets: const [counterFixture],
            assetReader: counterReader,
          ),
          throwsA(isA<StateError>().having(
              (e) => e.message, 'message', contains('counter_posts'))),
        );
      },
    );

    test(
      'kit.cairn.seed — an explicit seed into a CRDT-tagged table is refused',
      () async {
        // Given a booted counter-tagged backend with NO fixtures at boot
        final backend = backendWith(
          FakeCairnEngine(),
          config: const ArxaKitCairnConfig(counterTables: {'counter_posts'}),
        );
        await ArxaKitData.initialize(
          config: ArxaKitDataConfig(
            backend: ArxaKitDataBackend.plugin,
            plugin: backend,
          ),
          entities: const [counterPostRegistration],
        );

        // When / then the operator seed names the table in its refusal
        await expectLater(
          backend.seedFixtures(
            const ['assets/seed/counter_posts.json'],
            assetReader: ArxaKitMemoryAssetReader({
              'assets/seed/counter_posts.json':
                  '[{"id": "c-1", "title": "x", "likes": 0}]',
            }),
          ),
          throwsA(isA<StateError>().having(
              (e) => e.message, 'message', contains('counter_posts'))),
        );
      },
    );
  });
}
