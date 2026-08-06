import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_core/appbox_kit_locator.dart';
import 'package:appbox_kit_data/appbox_kit_data.dart';

/// Seed Profile plumbing: `AppBoxKitDataConfig.seedProfile` must reach every
/// `AppBoxKitSeedRepository` `AppBoxKitData.initialize` registers. One test only —
/// `AppBoxKitData` is static/global state and `appBoxKitLocator` is the process-wide
/// `StackedLocator` (see appbox_kit_data_initialize_test.dart for the rationale).
class _TestEntity {
  final String id;
  final String name;

  const _TestEntity({required this.id, required this.name});
}

final _schema = AppBoxKitTableSchema(
  table: 'test_entities',
  columns: const [AppBoxKitColumn.id(), AppBoxKitColumn('name', AppBoxKitColumnType.text)],
);

final _registration = AppBoxKitEntityRegistration<_TestEntity>(
  schema: _schema,
  fromJson: (json) => _TestEntity(
    id: json['id'] as String,
    name: json['name'] as String,
  ),
  toJson: (e) => {'id': e.id, 'name': e.name},
);

void main() {
  test('initialize wires config.seedProfile into the registered repository',
      () async {
    await AppBoxKitData.initialize(
      config: const AppBoxKitDataConfig(
        backend: AppBoxKitDataBackend.seed,
        seedProfile: AppBoxKitSeedProfile.failing(
          AppBoxKitSeedException('booted failing'),
        ),
      ),
      entities: [_registration],
      fixtureAssets: const [],
      assetReader: AppBoxKitMemoryAssetReader(const {}),
    );
    addTearDown(() async {
      await appBoxKitLocator.reset();
      AppBoxKitData.resetForTesting();
    });

    final repo = appBoxKitLocator<AppBoxKitRepository<_TestEntity>>();
    await expectLater(repo.getAll(), throwsA(isA<AppBoxKitSeedException>()));
  });
}
