import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_core/arxa_kit_locator.dart';
import 'package:arxa_kit_data/arxa_kit_data.dart';

/// ArxaKitData.initialize integration test, seed backend only.
///
/// Registers one entity, boots from fixtures served by a [ArxaKitMemoryAssetReader]
/// (`initialize`'s `assetReader:` parameter), then asserts the shared arxaKitLocator
/// (`arxa_kit`'s `arxaKitLocator`, a `StackedLocator`/GetIt singleton) resolves
/// `ArxaKitRepository<TestEntity>` and that `watchAll` emits the fixture rows.
///
/// Kept to a single test: `ArxaKitData` itself is static/global state (guarded
/// by `ArxaKitData.initialize called twice`), and `arxaKitLocator` is the same
/// process-wide `StackedLocator.instance` every other arxa_kit test
/// shares. `ArxaKitData.resetForTesting()` clears the static config/registry,
/// and `arxaKitLocator.reset()` (already used by
/// ui_library/test/kit/services/arxa_kit_notification_service_test.dart
/// for the same GetIt singleton) clears registered singletons — between the
/// two, teardown is clean, but running more than one `initialize` scenario
/// per file would still risk cross-test ordering flakiness that isn't worth
/// chasing for a single integration smoke test.
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
  tearDown(() {
    ArxaKitData.resetForTesting();
    arxaKitLocator.reset();
  });

  test('kit.data.initialize — seed backend: arxaKitLocator resolves ArxaKitRepository<T> and watchAll emits fixture rows',
      () async {
    final assetReader = ArxaKitMemoryAssetReader({
      'assets/seed/test_entities.json': jsonEncode([
        {'id': 'e-1', 'name': 'Alpha'},
        {'id': 'e-2', 'name': 'Beta'},
      ]),
    });

    await ArxaKitData.initialize(
      config: const ArxaKitDataConfig(backend: ArxaKitDataBackend.seed),
      entities: [_registration],
      fixtureAssets: ['assets/seed/test_entities.json'],
      assetReader: assetReader,
    );

    final repo = arxaKitLocator<ArxaKitRepository<_TestEntity>>();

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
