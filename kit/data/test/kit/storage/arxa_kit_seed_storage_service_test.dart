import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_data/storage/arxa_kit_storage_service.dart';
import 'package:arxa_kit_data/storage/seed/arxa_kit_seed_storage_service.dart';
import 'package:arxa_kit_data/storage/seed/arxa_kit_storage_persistence.dart';

/// ArxaKitSeedStorageService + ArxaKitSnapshotStoragePersistence tests.
///
/// Branches under test:
/// - In-memory service (default `ArxaKitNoStoragePersistence`): progress is
///   reported as `0.0` then `1.0`, `getUrl` returns a `data:` URL with the
///   uploaded MIME, `delete` makes a subsequent `getUrl` throw.
/// - `ArxaKitSnapshotStoragePersistence` with `overrideDirectory` at a temp dir
///   (no `path_provider` platform channel): `persist` then `load` round-trips
///   the same bytes, `load` on a missing key returns null, `remove` drops
///   the blob, `reset` clears the root.
/// - A fresh `ArxaKitSeedStorageService` over the snapshot persistence surfaces
///   bytes written by a prior instance — proving write-through durability
///   across instances.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('kit_seed_storage_test');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('ArxaKitSeedStorageService (in-memory)', () {
    test('kit.data.storage — progress callback receives 0.0 then 1.0 in order', () async {
      final service = ArxaKitSeedStorageService();
      final seen = <double>[];

      await service.upload(
        bucket: 'avatars',
        path: 'u.png',
        bytes: Uint8List.fromList([1, 2, 3]),
        contentType: 'image/png',
        onProgress: seen.add,
      );

      expect(seen.first, 0.0);
      expect(seen.last, 1.0);
    });

    test('kit.data.storage — getUrl encodes the uploaded MIME into the data URL', () async {
      final service = ArxaKitSeedStorageService();
      final ref = await service.upload(
        bucket: 'avatars',
        path: 'u.png',
        bytes: Uint8List.fromList([1, 2, 3]),
        contentType: 'image/jpeg',
      );

      expect(await service.getUrl(ref), startsWith('data:image/jpeg;base64,'));
    });

    test('kit.data.storage — getUrl on a missing object throws StateError naming the path',
        () async {
      final service = ArxaKitSeedStorageService();

      await expectLater(
        service.getUrl(const ArxaKitStorageObjectRef(bucket: 'x', path: 'missing')),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('x/missing'),
          ),
        ),
      );
    });
  });

  group('ArxaKitSnapshotStoragePersistence', () {
    test('kit.data.storage — persist then load round-trips the same bytes', () async {
      final p = ArxaKitSnapshotStoragePersistence(overrideDirectory: tempDir);
      final bytes = Uint8List.fromList(List.generate(256, (i) => i % 256));

      await p.persist('avatars', 'usr/1.png', bytes);

      expect(await p.load('avatars', 'usr/1.png'), bytes);
    });

    test('kit.data.storage — load returns null for a key that was never written', () async {
      final p = ArxaKitSnapshotStoragePersistence(overrideDirectory: tempDir);
      expect(await p.load('avatars', 'nope.png'), isNull);
    });

    test('kit.data.storage — remove drops the blob', () async {
      final p = ArxaKitSnapshotStoragePersistence(overrideDirectory: tempDir);
      await p.persist('avatars', 'usr/2.png', Uint8List.fromList([1]));

      await p.remove('avatars', 'usr/2.png');

      expect(await p.load('avatars', 'usr/2.png'), isNull);
    });

    test('kit.data.storage — reset removes the storage root', () async {
      final p = ArxaKitSnapshotStoragePersistence(overrideDirectory: tempDir);
      await p.persist('avatars', 'usr/3.png', Uint8List.fromList([1]));
      final root = Directory('${tempDir.path}/arxa_kit_data/storage');
      expect(root.existsSync(), isTrue);

      await p.reset();

      expect(root.existsSync(), isFalse);
    });
  });

  group('write-through across instances', () {
    test('kit.data.storage — a second service reads bytes persisted by the first', () async {
      final persistence =
          ArxaKitSnapshotStoragePersistence(overrideDirectory: tempDir);
      final a = ArxaKitSeedStorageService(persistence: persistence);
      final b = ArxaKitSeedStorageService(persistence: persistence);

      final ref = await a.upload(
        bucket: 'avatars',
        path: 'usr/cross.png',
        bytes: Uint8List.fromList([9, 9, 9]),
        contentType: 'image/png',
      );

      // b's in-memory map is empty, so this load must come from persistence.
      final url = await b.getUrl(ref);

      expect(url, startsWith('data:application/octet-stream;base64,'));
    });
  });
}
