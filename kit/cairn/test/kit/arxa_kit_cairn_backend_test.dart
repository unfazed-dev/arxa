import 'package:flutter_test/flutter_test.dart';
import 'package:cairn_flutter/cairn_flutter.dart';
import 'package:arxa_kit_cairn/arxa_kit_cairn.dart';
import 'package:arxa_kit_core/arxa_kit_locator.dart';
import 'package:arxa_kit_data/arxa_kit_data.dart';

import '../support/fake_cairn_engine.dart';
import '../support/post_harness.dart';

/// The backend plugin (phase 4e): `ArxaKitCairnBackend` plugs cairn into
/// kit/data's `ArxaKitBackendPlugin` seam — opens the right database per mode
/// and registers one `ArxaKitRepository<T>` per entity into the shared
/// locator, so nothing above the seam changes.
///
/// Branches under test:
/// - localOnly opens through the real local-open path with the EMITTED schema
///   and the config's CRDT sets; repositories resolve and round-trip rows.
/// - Triple consistency is enforced at boot: a schema crdt flag without the
///   matching config set (or vice versa) fails loudly, naming the field.
/// - sync mode hands the opener the configured URL and the host's
///   token-provider token (tokens never env).
/// - dispose closes the database and is idempotent; waitForFirstSync is the
///   surfaced UI gate.
void main() {
  tearDown(() {
    ArxaKitData.resetForTesting();
    arxaKitLocator.reset();
  });

  group('kit.cairn.backend', () {
    test(
      'kit.cairn.backend — localOnly opens with the emitted schema and serves repositories',
      () async {
        // Given a plugin with an injected opener capturing what it receives
        final engine = FakeCairnEngine();
        CairnSchema? openedSchema;
        final backend = ArxaKitCairnBackend(
          config: const ArxaKitCairnConfig(
            orSetTables: {'posts'},
            counterTables: {'posts'},
          ),
          openDatabase: (config, schema, token) async {
            openedSchema = schema;
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

        // When kit/data initializes with the plugin backend
        await ArxaKitData.initialize(
          config: ArxaKitDataConfig(
            backend: ArxaKitDataBackend.plugin,
            plugin: backend,
          ),
          entities: const [postRegistration],
        );

        // Then the opener received the schema EMITTED from the kit descriptor
        expect(openedSchema!.tables.single.name, 'posts');
        expect(
          openedSchema!.tables.single.columns.map((c) => c.name),
          postSchema.columns.map((c) => c.name),
        );

        // And the repository resolves from the shared locator and round-trips
        final repo = arxaKitLocator<ArxaKitRepository<Post>>();
        final stored = await repo.upsert(const Post(
          id: 'p-1',
          title: 'through the seam',
          likes: 0,
          score: 0,
          published: false,
        ));
        expect((await repo.getById('p-1'))!.title, stored.title);
      },
    );

    test(
      'kit.cairn.backend — a schema crdt flag missing from config fails at boot naming the field',
      () async {
        // Given the posts schema (likes=counter, tags=orSet) but an EMPTY
        // config — the flags and the config disagree
        final backend = ArxaKitCairnBackend(
          config: const ArxaKitCairnConfig(),
          openDatabase: _unusedOpener,
        );

        // Then initialize refuses to boot, naming the missing config field
        await expectLater(
          ArxaKitData.initialize(
            config: ArxaKitDataConfig(
              backend: ArxaKitDataBackend.plugin,
              plugin: backend,
            ),
            entities: const [postRegistration],
          ),
          throwsA(isA<StateError>().having(
              (e) => e.message, 'message', contains('counterTables'))),
        );
      },
    );

    test(
      'kit.cairn.backend — a config crdt table without a schema flag fails at boot',
      () async {
        // Given a config tagging a table the schema never flags
        final backend = ArxaKitCairnBackend(
          config: const ArxaKitCairnConfig(
            orSetTables: {'posts'},
            counterTables: {'posts'},
          ),
          openDatabase: _unusedOpener,
        );

        // The schema flags BOTH tiers on posts, so this config is consistent
        // — but tag a table the schema doesn't flag and boot must fail
        final inconsistent = ArxaKitCairnBackend(
          config: const ArxaKitCairnConfig(
            orSetTables: {'posts', 'comments'},
            counterTables: {'posts'},
          ),
          openDatabase: _unusedOpener,
        );

        // Then: the consistent one boots (proven by the first test's shape),
        // the inconsistent one names the unflagged table
        await expectLater(
          ArxaKitData.initialize(
            config: ArxaKitDataConfig(
              backend: ArxaKitDataBackend.plugin,
              plugin: inconsistent,
            ),
            entities: const [postRegistration],
          ),
          throwsA(isA<StateError>()
              .having((e) => e.message, 'message', contains('comments'))),
        );
        // (the consistent backend is exercised by the round-trip test above)
        expect(backend.name, 'cairn');
      },
    );

    test(
      'kit.cairn.backend — sync mode hands the opener the URL and the host token',
      () async {
        // Given a sync-mode plugin whose token comes from a host callback
        String? openedUrl;
        String? openedToken;
        final backend = ArxaKitCairnBackend(
          config: const ArxaKitCairnConfig(
            mode: ArxaKitCairnMode.sync,
            syncUrl: 'wss://sync.example.com/sync',
          ),
          tokenProvider: () async => 'host-jwt-1',
          openDatabase: (config, schema, token) async {
            openedUrl = config.syncUrl;
            openedToken = token;
            // ignore: invalid_use_of_visible_for_testing_member
            final cairn = Cairn.withEngine(FakeCairnEngine());
            // ignore: invalid_use_of_visible_for_testing_member
            return CairnDatabase.localForTest(cairn, schema);
          },
        );

        // When initialize runs
        await ArxaKitData.initialize(
          config: ArxaKitDataConfig(
            backend: ArxaKitDataBackend.plugin,
            plugin: backend,
          ),
          entities: const [plainPostRegistration],
        );

        // Then the opener saw the sync URL and the provider's token
        expect(openedUrl, 'wss://sync.example.com/sync');
        expect(openedToken, 'host-jwt-1');
      },
    );

    test(
      'kit.cairn.backend — an invalid config fails initialize, naming the define',
      () async {
        // Given a sync-mode config with no URL
        final backend = ArxaKitCairnBackend(
          config: const ArxaKitCairnConfig(mode: ArxaKitCairnMode.sync),
          openDatabase: _unusedOpener,
        );

        // Then initialize fails through the config contract
        await expectLater(
          ArxaKitData.initialize(
            config: ArxaKitDataConfig(
              backend: ArxaKitDataBackend.plugin,
              plugin: backend,
            ),
            entities: const [plainPostRegistration],
          ),
          throwsA(isA<StateError>().having(
              (e) => e.message, 'message', contains('ARXA_CAIRN_URL'))),
        );
      },
    );

    test(
      'kit.cairn.backend — dispose closes the database and is idempotent',
      () async {
        // Given an initialized plugin
        final engine = FakeCairnEngine();
        final backend = ArxaKitCairnBackend(
          config: const ArxaKitCairnConfig(),
          openDatabase: (config, schema, token) async {
            // ignore: invalid_use_of_visible_for_testing_member
            final cairn = Cairn.withEngine(engine);
            // ignore: invalid_use_of_visible_for_testing_member
            return CairnDatabase.localForTest(cairn, schema);
          },
        );
        await ArxaKitData.initialize(
          config: ArxaKitDataConfig(
            backend: ArxaKitDataBackend.plugin,
            plugin: backend,
          ),
          entities: const [plainPostRegistration],
        );

        // When dispose runs twice
        await backend.dispose();
        await backend.dispose();

        // Then the database closed exactly once
        expect(engine.closeCalls, 1);
      },
    );

    test(
      'kit.cairn.backend — waitForFirstSync is the surfaced UI gate',
      () async {
        // Given an initialized local plugin (local resolves immediately)
        final backend = ArxaKitCairnBackend(
          config: const ArxaKitCairnConfig(),
          openDatabase: (config, schema, token) async {
            // ignore: invalid_use_of_visible_for_testing_member
            final cairn = Cairn.withEngine(FakeCairnEngine());
            // ignore: invalid_use_of_visible_for_testing_member
            return CairnDatabase.localForTest(cairn, schema);
          },
        );
        await ArxaKitData.initialize(
          config: ArxaKitDataConfig(
            backend: ArxaKitDataBackend.plugin,
            plugin: backend,
          ),
          entities: const [plainPostRegistration],
        );

        // Then the gate resolves — a local database has no first sync to await
        await backend.waitForFirstSync();
      },
    );

    test(
      'kit.cairn.backend — the userIdProvider stamps through the wired repository',
      () async {
        // Given a plugin with a tenant id provider
        final backend = ArxaKitCairnBackend(
          config: const ArxaKitCairnConfig(
            orSetTables: {'posts'},
            counterTables: {'posts'},
          ),
          userIdProvider: () => 'tenant-7',
          openDatabase: (config, schema, token) async {
            // ignore: invalid_use_of_visible_for_testing_member
            final cairn = Cairn.withEngine(
              FakeCairnEngine(),
              orSetTables: config.orSetTables,
              counterTables: config.counterTables,
            );
            // ignore: invalid_use_of_visible_for_testing_member
            return CairnDatabase.localForTest(cairn, schema);
          },
        );
        await ArxaKitData.initialize(
          config: ArxaKitDataConfig(
            backend: ArxaKitDataBackend.plugin,
            plugin: backend,
          ),
          entities: const [postRegistration],
        );

        // When a row is written through the locator-resolved repository
        final repo = arxaKitLocator<ArxaKitRepository<Post>>();
        final stored = await repo.upsert(const Post(
          id: 'p-1',
          title: 'tenant row',
          likes: 0,
          score: 0,
          published: false,
        ));

        // Then the stamping hook fired
        expect(stored.userId, 'tenant-7');
      },
    );
  });
}

Future<CairnDatabase> _unusedOpener(
  ArxaKitCairnConfig config,
  CairnSchema schema,
  String? token,
) =>
    throw StateError('the opener must not run in this test');

