import 'dart:convert';
import 'dart:typed_data';

import '../arxa_kit_storage_service.dart';
import 'arxa_kit_storage_persistence.dart';

/// In-memory [ArxaKitStorageService] with optional write-through durability,
/// mirroring how [ArxaKitSeedRepository] layers over [ArxaKitSeedStore].
///
/// One process-local map keyed by `bucket/path` is the source of truth;
/// every mutation write-throughs to [persistence] after the in-memory write
/// lands. [getUrl] returns a `data:` URL (no HTTP origin on this backend),
/// encoding the stored [Uint8List] and the upload-time content type.
class ArxaKitSeedStorageService implements ArxaKitStorageService {
  final ArxaKitStoragePersistence persistence;

  ArxaKitSeedStorageService({this.persistence = const ArxaKitNoStoragePersistence()});

  final Map<String, _Stored> _objects = {};

  static String _key(String bucket, String path) => '$bucket/$path';

  @override
  Future<ArxaKitStorageObjectRef> upload({
    required String bucket,
    required String path,
    required Uint8List bytes,
    String? contentType,
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0.0);
    _objects[_key(bucket, path)] = _Stored(bytes, contentType);
    await persistence.persist(bucket, path, bytes);
    onProgress?.call(1.0);
    return ArxaKitStorageObjectRef(bucket: bucket, path: path);
  }

  @override
  Future<String> getUrl(ArxaKitStorageObjectRef ref) async {
    final stored = _objects[_key(ref.bucket, ref.path)] ??
        (await _loadFromPersistence(ref.bucket, ref.path));
    if (stored == null) {
      throw StateError(
        'ArxaKitSeedStorageService: no object at ${ref.bucket}/${ref.path}',
      );
    }
    return _dataUrl(stored);
  }

  @override
  Future<void> delete(ArxaKitStorageObjectRef ref) async {
    _objects.remove(_key(ref.bucket, ref.path));
    await persistence.remove(ref.bucket, ref.path);
  }

  Future<_Stored?> _loadFromPersistence(String bucket, String path) async {
    final bytes = await persistence.load(bucket, path);
    if (bytes == null) return null;
    // Cold-load: MIME unknown after restart (see class doc).
    return _Stored(bytes, null);
  }

  static String _dataUrl(_Stored stored) {
    final mime = (stored.contentType == null || stored.contentType!.isEmpty)
        ? 'application/octet-stream'
        : stored.contentType!;
    return 'data:$mime;base64,${base64Encode(stored.bytes)}';
  }
}

class _Stored {
  final Uint8List bytes;
  final String? contentType;

  const _Stored(this.bytes, this.contentType);
}
