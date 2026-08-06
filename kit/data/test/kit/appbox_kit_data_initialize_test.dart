import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_core/appbox_kit_locator.dart';
import 'package:appbox_kit_data/appbox_kit_data.dart';

/// AppBoxKitData.initialize integration test, seed backend only.
///
/// Registers one entity, boots from fixtures served by a [AppBoxKitMemoryAssetReader]
/// (`initialize`'s `assetReader:` parameter), then asserts the shared appBoxKitLocator
/// (`appbox_kit`'s `appBoxKitLocator`, a `StackedLocator`/GetIt singleton) resolves
/// `AppBoxKitRepository<TestEntity>` and that `watchAll` emits the fixture rows.
///
/// Kept to a single test: `AppBoxKitData` itself is static/global state (guarded
/// by `AppBoxKitData.initialize called twice`), and `appBoxKitLocator` is the same
/// process-wide `StackedLocator.instance` every other appbox_kit test
/// shares. `AppBoxKitData.resetForTesting()` clears the static config/registry,
/// and `appBoxKitLocator.reset()` (already used by
/// ui_library/test/kit/services/appbox_kit_notification_service_test.dart
/// for the same GetIt singleton) clears registered singletons — between the
/// two, teardown is clean, but running more than one `initialize` scenario
/// per file would still risk cross-test ordering flakiness that isn't worth
/// chasing for a single integration smoke test.
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
  tearDown(() {
    AppBoxKitData.resetForTesting();
    appBoxKitLocator.reset();
  });

  test('seed backend: appBoxKitLocator resolves AppBoxKitRepository<T> and watchAll emits fixture rows',
      () async {
    final assetReader = AppBoxKitMemoryAssetReader({
      'assets/seed/test_entities.json': jsonEncode([
        {'id': 'e-1', 'name': 'Alpha'},
        {'id': 'e-2', 'name': 'Beta'},
      ]),
    });

    await AppBoxKitData.initialize(
      config: const AppBoxKitDataConfig(backend: AppBoxKitDataBackend.seed),
      entities: [_registration],
      fixtureAssets: ['assets/seed/test_entities.json'],
      assetReader: assetReader,
    );

    final repo = appBoxKitLocator<AppBoxKitRepository<_TestEntity>>();

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
