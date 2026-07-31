import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_core/kit_locator.dart';
import 'package:appbox_kit_data/assets/kit_asset_reader.dart';
import 'package:appbox_kit_data/config/kit_data_config.dart';
import 'package:appbox_kit_data/kit_data.dart';
import 'package:appbox_kit_data/models/kit_entity_registration.dart';
import 'package:appbox_kit_data/repositories/kit_repository.dart';
import 'package:appbox_kit_data/schema/kit_table_schema.dart';

/// KitData.initialize integration test, seed backend only.
///
/// Registers one entity, boots from fixtures served by a [KitMemoryAssetReader]
/// (`initialize`'s `assetReader:` parameter), then asserts the shared locator
/// (`stacked_kit`'s `locator`, a `StackedLocator`/GetIt singleton) resolves
/// `KitRepository<TestEntity>` and that `watchAll` emits the fixture rows.
///
/// Kept to a single test: `KitData` itself is static/global state (guarded
/// by `KitData.initialize called twice`), and `locator` is the same
/// process-wide `StackedLocator.instance` every other stacked_kit test
/// shares. `KitData.resetForTesting()` clears the static config/registry,
/// and `locator.reset()` (already used by
/// ui_library/test/kit/services/kit_notification_service_test.dart
/// for the same GetIt singleton) clears registered singletons — between the
/// two, teardown is clean, but running more than one `initialize` scenario
/// per file would still risk cross-test ordering flakiness that isn't worth
/// chasing for a single integration smoke test.
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
  tearDown(() {
    KitData.resetForTesting();
    locator.reset();
  });

  test('seed backend: locator resolves KitRepository<T> and watchAll emits fixture rows',
      () async {
    final assetReader = KitMemoryAssetReader({
      'assets/seed/test_entities.json': jsonEncode([
        {'id': 'e-1', 'name': 'Alpha'},
        {'id': 'e-2', 'name': 'Beta'},
      ]),
    });

    await KitData.initialize(
      config: const KitDataConfig(backend: KitDataBackend.seed),
      entities: [_registration],
      fixtureAssets: ['assets/seed/test_entities.json'],
      assetReader: assetReader,
    );

    final repo = locator<KitRepository<_TestEntity>>();

    await expectLater(
      repo.watchAll(),
      emits(
        containsAll([
          isA<_TestEntity>().having((e) => e.name, 'name', 'Alpha'),
          isA<_TestEntity>().having((e) => e.name, 'name', 'Beta'),
        ]),
      ),
    );
  });
}
