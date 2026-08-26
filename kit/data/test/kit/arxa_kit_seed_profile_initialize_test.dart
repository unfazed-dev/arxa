import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_core/arxa_kit_locator.dart';
import 'package:arxa_kit_data/arxa_kit_data.dart';

/// Seed Profile plumbing: `ArxaKitDataConfig.seedProfile` must reach every
/// `ArxaKitSeedRepository` `ArxaKitData.initialize` registers. One test only —
/// `ArxaKitData` is static/global state and `arxaKitLocator` is the process-wide
/// `StackedLocator` (see arxa_kit_data_initialize_test.dart for the rationale).
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

void main() {
  test('kit.data.initialize — initialize wires config.seedProfile into the registered repository',
      () async {
    await ArxaKitData.initialize(
      config: const ArxaKitDataConfig(
        backend: ArxaKitDataBackend.seed,
        seedProfile: ArxaKitSeedProfile.failing(
          ArxaKitSeedException('booted failing'),
        ),
      ),
      entities: [_registration],
      fixtureAssets: const [],
      assetReader: ArxaKitMemoryAssetReader(const {}),
    );
    addTearDown(() async {
      await arxaKitLocator.reset();
      ArxaKitData.resetForTesting();
    });

    final repo = arxaKitLocator<ArxaKitRepository<_TestEntity>>();
    await expectLater(repo.getAll(), throwsA(isA<ArxaKitSeedException>()));
  });
}
