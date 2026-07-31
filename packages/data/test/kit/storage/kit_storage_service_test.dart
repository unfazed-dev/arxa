import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_data/storage/kit_storage_service.dart';
import 'package:appbox_kit_data/storage/seed/kit_seed_storage_service.dart';

/// Interface-level contract for [KitStorageService]. Any backend should
/// satisfy this; here it runs against the in-memory seed backend (the only
/// one that works without live credentials). Remote backends have their own
/// env-gated contract tests alongside this one.
void main() {
  final service = KitSeedStorageService();

  test('upload returns a ref with the given bucket and path', () async {
    final ref = await service.upload(
      bucket: 'avatars',
      path: 'usr/1.png',
      bytes: Uint8List.fromList([1, 2, 3, 4]),
      contentType: 'image/png',
    );

    expect(ref.bucket, 'avatars');
    expect(ref.path, 'usr/1.png');
    expect(ref.id, ref.path); // seed: id == path
  });

  test('upload delivers a terminal 1.0 progress event', () async {
    final progresses = <double>[];
    await service.upload(
      bucket: 'avatars',
      path: 'usr/2.png',
      bytes: Uint8List.fromList([5, 6, 7, 8]),
      contentType: 'image/png',
      onProgress: progresses.add,
    );

    expect(progresses, isNotEmpty);
    expect(progresses.last, 1.0);
    expect(progresses.first, 0.0);
  });

  test('getUrl returns a non-empty URL-ish string after upload', () async {
    final ref = await service.upload(
      bucket: 'avatars',
      path: 'usr/3.png',
      bytes: Uint8List.fromList([9, 10, 11]),
      contentType: 'image/png',
    );

    final url = await service.getUrl(ref);

    expect(url, isNotEmpty);
    expect(url, startsWith('data:image/png;base64,'));
  });

  test('delete removes the object (getUrl then throws on seed)', () async {
    final ref = await service.upload(
      bucket: 'avatars',
      path: 'usr/4.png',
      bytes: Uint8List.fromList([12, 13]),
      contentType: 'image/png',
    );

    await service.delete(ref);

    await expectLater(
      service.getUrl(ref),
      throwsA(isA<StateError>()),
    );
  });

  test('upload overwrites a prior object at the same bucket/path', () async {
    final ref = await service.upload(
      bucket: 'avatars',
      path: 'usr/5.png',
      bytes: Uint8List.fromList([1]),
      contentType: 'image/png',
    );
    await service.upload(
      bucket: ref.bucket,
      path: ref.path,
      bytes: Uint8List.fromList([2, 2, 2, 2]),
      contentType: 'image/png',
    );

    final url = await service.getUrl(ref);
    // getUrl reflects the overwritten payload, not the original 1-byte one.
    expect(url, contains(base64Encode([2, 2, 2, 2])));
    expect(url, isNot(contains(base64Encode([1]))));
  });

  test('StorageObjectRef id defaults to path and equals by value', () {
    final a = const StorageObjectRef(bucket: 'b', path: 'p');
    final b = const StorageObjectRef(bucket: 'b', path: 'p');
    final explicit = const StorageObjectRef(bucket: 'b', path: 'p', id: 'x');

    expect(a.id, 'p');
    expect(a, b);
    expect(a == explicit, isFalse);
  });
}
