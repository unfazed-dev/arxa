import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_core/arxa_kit_locator.dart';
import 'package:arxa_kit_data/arxa_kit_data.dart';
import 'package:arxa_kit_data/arxa_kit_testing.dart';

/// The `ArxaKitDataBackend.plugin` seam (phase 1 of the cairn kit chain):
/// kit/data cannot name cairn types (no optional deps in Dart), so a backend
/// that ships outside this package plugs in through [ArxaKitBackendPlugin].
///
/// Branches under test:
/// - `validate()` fails loudly — naming the missing plugin — when the backend
///   is `plugin` but no plugin was provided (same contract as the supabase /
///   appwrite credential checks).
/// - `ArxaKitData.initialize` hands the plugin the config, the entity
///   registrations, and the SAME `ArxaKitIdService` / `ArxaKitSchemaRegistry`
///   instances it registered into the shared arxaKitLocator — the plugin builds
///   its repositories on exactly the services every other backend gets.
/// - A repository the plugin registers during `initialize` resolves from the
///   arxaKitLocator and round-trips a row (the seam is real, not decorative).
class _TestEntity {
  final String id;
  final String name;

  const _TestEntity({required this.id, required this.name});
}

final _schema = ArxaKitTableSchema(
  table: 'test_entities',
  columns: const [ArxaKitColumn.id(), ArxaKitColumn('name', ArxaKitColumnType.text)],
);

final _registration = ArxaKitEntityRegistration<_TestEntity>(
  schema: _schema,
  fromJson: (json) => _TestEntity(
    id: json['id'] as String,
    name: json['name'] as String,
  ),
  toJson: (e) => {'id': e.id, 'name': e.name},
);

/// A plugin double that records what `initialize` received and registers a
/// [FakeArxaKitRepository] the way a real out-of-package backend would.
class _RecordingPlugin implements ArxaKitBackendPlugin {
  ArxaKitDataConfig? receivedConfig;
  List<ArxaKitEntityRegistration<dynamic>>? receivedEntities;
  ArxaKitIdService? receivedIdService;
  ArxaKitSchemaRegistry? receivedRegistry;
  List<String>? receivedFixtureAssets;
  ArxaKitAssetReader? receivedAssetReader;
  int disposeCallCount = 0;

  @override
  String get name => 'recording';

  @override
  Future<void> initialize(
    ArxaKitDataConfig config,
    List<ArxaKitEntityRegistration<dynamic>> entities,
    ArxaKitIdService idService,
    ArxaKitSchemaRegistry registry, {
    List<String> fixtureAssets = const [],
    ArxaKitAssetReader? assetReader,
  }) async {
    receivedConfig = config;
    receivedEntities = entities;
    receivedIdService = idService;
    receivedRegistry = registry;
    receivedFixtureAssets = fixtureAssets;
    receivedAssetReader = assetReader;
    arxaKitLocator.registerLazySingleton<ArxaKitRepository<_TestEntity>>(
      () => FakeArxaKitRepository<_TestEntity>(
        registration: _registration,
        idService: idService,
      ),
    );
  }

  @override
  Future<void> dispose() async {
    disposeCallCount++;
  }
}

/// A plugin double that also implements the optional seeding capability —
/// the seam `ArxaKitDataSeeder.push` delegates through when the plugin's
/// package owns its writes.
class _SeedablePlugin extends _RecordingPlugin implements ArxaKitPluginSeeder {
  int seedCallCount = 0;
  List<String>? seededFixtureAssets;
  ArxaKitAssetReader? seededAssetReader;

  @override
  Future<void> seedFixtures(
    List<String> fixtureAssets, {
    ArxaKitAssetReader? assetReader,
  }) async {
    seedCallCount++;
    seededFixtureAssets = fixtureAssets;
    seededAssetReader = assetReader;
  }
}

void main() {
  tearDown(() {
    ArxaKitData.resetForTesting();
    arxaKitLocator.reset();
  });

  test('kit.data.backend-plugin — validate fails loudly, naming the missing plugin, when backend is plugin but none was provided', () {
    // given
    const config = ArxaKitDataConfig(backend: ArxaKitDataBackend.plugin);

    // when / then
    expect(
      () => config.validate(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('plugin'), contains('ArxaKitBackendPlugin')),
        ),
      ),
    );
  });

  test('kit.data.backend-plugin — initialize hands the plugin the config, entities, and the locator-registered id service + schema registry', () async {
    // given
    final plugin = _RecordingPlugin();

    // when
    await ArxaKitData.initialize(
      config: ArxaKitDataConfig(
        backend: ArxaKitDataBackend.plugin,
        plugin: plugin,
      ),
      entities: [_registration],
    );

    // then
    expect(plugin.receivedConfig?.backend, ArxaKitDataBackend.plugin);
    expect(plugin.receivedEntities, hasLength(1));
    expect(
      plugin.receivedIdService,
      same(arxaKitLocator<ArxaKitIdService>()),
      reason: 'the plugin builds on the same id service every backend gets',
    );
    expect(
      plugin.receivedRegistry,
      same(arxaKitLocator<ArxaKitSchemaRegistry>()),
    );
  });

  test('kit.data.backend-plugin — a repository the plugin registers resolves from arxaKitLocator and round-trips a row', () async {
    // given
    await ArxaKitData.initialize(
      config: ArxaKitDataConfig(
        backend: ArxaKitDataBackend.plugin,
        plugin: _RecordingPlugin(),
      ),
      entities: [_registration],
    );

    // when
    final repo = arxaKitLocator<ArxaKitRepository<_TestEntity>>();
    await repo.upsert(const _TestEntity(id: 'e-1', name: 'Alpha'));

    // then
    expect((await repo.getById('e-1'))!.name, 'Alpha');
  });

  test('kit.data.backend-plugin — initialize hands the plugin the fixture assets and asset reader', () async {
    // given
    final plugin = _RecordingPlugin();
    final reader = ArxaKitMemoryAssetReader({
      'assets/seed/test_entities.json': '[]',
    });

    // when
    await ArxaKitData.initialize(
      config: ArxaKitDataConfig(
        backend: ArxaKitDataBackend.plugin,
        plugin: plugin,
      ),
      entities: [_registration],
      fixtureAssets: const ['assets/seed/test_entities.json'],
      assetReader: reader,
    );

    // then the plugin received the SAME seeding inputs the caller gave
    expect(plugin.receivedFixtureAssets, ['assets/seed/test_entities.json']);
    expect(plugin.receivedAssetReader, same(reader));
  });

  test('kit.data.backend-plugin — the seeder delegates to a plugin implementing ArxaKitPluginSeeder', () async {
    // given a plugin with the seeding capability
    final plugin = _SeedablePlugin();
    await ArxaKitData.initialize(
      config: ArxaKitDataConfig(
        backend: ArxaKitDataBackend.plugin,
        plugin: plugin,
      ),
      entities: [_registration],
    );

    // when the operator pushes fixtures
    final reader = ArxaKitMemoryAssetReader({
      'assets/seed/test_entities.json': '[]',
    });
    await ArxaKitDataSeeder().push(
      fixtureAssets: const ['assets/seed/test_entities.json'],
      assetReader: reader,
    );

    // then the plugin owned the seeding — kit/data never names its types
    expect(plugin.seedCallCount, 1);
    expect(plugin.seededFixtureAssets, ['assets/seed/test_entities.json']);
    expect(plugin.seededAssetReader, same(reader));
  });

  test('kit.data.backend-plugin — the seeder still refuses a plugin without the seeding capability', () async {
    // given a plugin that does NOT implement ArxaKitPluginSeeder
    await ArxaKitData.initialize(
      config: ArxaKitDataConfig(
        backend: ArxaKitDataBackend.plugin,
        plugin: _RecordingPlugin(),
      ),
      entities: [_registration],
    );

    // when / then push fails loudly naming the plugin
    await expectLater(
      ArxaKitDataSeeder().push(
        fixtureAssets: const ['assets/seed/test_entities.json'],
        assetReader: ArxaKitMemoryAssetReader({
          'assets/seed/test_entities.json': '[]',
        }),
      ),
      throwsA(isA<StateError>().having(
          (e) => e.message, 'message', contains('recording'))),
    );
  });
}
