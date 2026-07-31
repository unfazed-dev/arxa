import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_core/kit_locator.dart';
import 'package:appbox_kit_data/assets/kit_asset_reader.dart';
import 'package:appbox_kit_data/config/kit_data_config.dart';
import 'package:appbox_kit_data/config/kit_seed_profile.dart';
import 'package:appbox_kit_data/kit_data.dart';
import 'package:appbox_kit_data/models/kit_entity_registration.dart';
import 'package:appbox_kit_data/repositories/kit_repository.dart';
import 'package:appbox_kit_data/schema/kit_table_schema.dart';

/// Seed Profile plumbing: `KitDataConfig.seedProfile` must reach every
/// `KitSeedRepository` `KitData.initialize` registers. One test only —
/// `KitData` is static/global state and `locator` is the process-wide
/// `StackedLocator` (see kit_data_initialize_test.dart for the rationale).
class _TestEntity {
  final String id;
  final String name;

  const _TestEntity({required this.id, required this.name});
}

final _schema = KitTableSchema(
  table: 'test_entities',
  columns: const [KitColumn.id(), KitColumn('name', KitColumnType.text)],
);

final _registration = KitEntityRegistration<_TestEntity>(
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
    await KitData.initialize(
      config: const KitDataConfig(
        backend: KitDataBackend.seed,
        seedProfile: KitSeedProfile.failing(
          KitSeedException('booted failing'),
        ),
      ),
      entities: [_registration],
      fixtureAssets: const [],
      assetReader: KitMemoryAssetReader(const {}),
    );
    addTearDown(() async {
      await locator.reset();
      KitData.resetForTesting();
    });

    final repo = locator<KitRepository<_TestEntity>>();
    await expectLater(repo.getAll(), throwsA(isA<KitSeedException>()));
  });
}
