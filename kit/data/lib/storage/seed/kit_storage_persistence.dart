import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Write-through durability contract for [KitSeedStorageService] — the
/// in-memory map stays the source of truth; implementations only mirror
/// writes to durable storage. Mirrors [KitSeedPersistence] (the table
/// persistence seam), with the same `overrideDirectory` test escape hatch.
abstract interface class KitStoragePersistence {
  /// `null` when nothing is persisted for the key.
  Future<Uint8List?> load(String bucket, String path);

  Future<void> persist(String bucket, String path, Uint8List bytes);

  Future<void> remove(String bucket, String path);

  /// Clears all persisted state.
  Future<void> reset();
}

/// Pure in-memory (`KitSeedPersistenceMode.none`): nothing survives a
/// restart.
class KitNoStoragePersistence implements KitStoragePersistence {
  const KitNoStoragePersistence();

  @override
  Future<Uint8List?> load(String bucket, String path) async => null;

  @override
  Future<void> persist(String bucket, String path, Uint8List bytes) async {}

  @override
  Future<void> remove(String bucket, String path) async {}

  @override
  Future<void> reset() async {}
}

/// Write-through blob snapshot to the app-documents directory, mirroring
/// [KitSnapshotPersistence]. Each object lands at
/// `<dir>/appbox_kit_data/storage/<bucket>/<path>`. [overrideDirectory]
/// keeps tests off the `path_provider` platform channel.
///
/// Only bytes are persisted; `contentType` is not (the in-memory map keeps
/// it for the running session). A cold boot therefore surfaces stored blobs
/// as `application/octet-stream` until they are overwritten — acceptable for
/// a demo backend.
class KitSnapshotStoragePersistence implements KitStoragePersistence {
  final Directory? _overrideDirectory;

  const KitSnapshotStoragePersistence({Directory? overrideDirectory})
      : _overrideDirectory = overrideDirectory;

  Future<Directory> _root() async {
    final base =
        _overrideDirectory ?? await getApplicationDocumentsDirectory();
    return Directory('${base.path}/appbox_kit_data/storage');
  }

  File _file(Directory root, String bucket, String path) =>
      File('${root.path}/$bucket/$path');

  @override
  Future<Uint8List?> load(String bucket, String path) async {
    final root = await _root();
    final file = _file(root, bucket, path);
    if (!file.existsSync()) return null;
    return file.readAsBytes();
  }

  @override
  Future<void> persist(String bucket, String path, Uint8List bytes) async {
    final root = await _root();
    final file = _file(root, bucket, path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> remove(String bucket, String path) async {
    final root = await _root();
    final file = _file(root, bucket, path);
    if (file.existsSync()) await file.delete();
  }

  @override
  Future<void> reset() async {
    final root = await _root();
    if (root.existsSync()) await root.delete(recursive: true);
  }
}
