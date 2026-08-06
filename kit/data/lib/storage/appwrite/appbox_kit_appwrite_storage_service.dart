/// [AppBoxKitStorageService] backed by Appwrite Storage.
library;

import 'dart:typed_data';

import 'package:appwrite/appwrite.dart';
import 'package:uuid/uuid.dart';

import '../appbox_kit_storage_service.dart';

/// Appwrite implementation of [AppBoxKitStorageService].
///
/// Mirrors [AppBoxKitAppwriteRepository]'s pattern of taking the Appwrite service
/// + client. Appwrite addresses objects by `(bucketId, fileId)` rather than
/// by path; the per-call [bucket] is the Appwrite `bucketId`, and a UUID
/// `fileId` is allocated per upload. The returned [AppBoxKitStorageObjectRef.id]
/// carries that `fileId` so [getUrl] / [delete] address the right object.
class AppBoxKitAppwriteStorageService implements AppBoxKitStorageService {
  AppBoxKitAppwriteStorageService({
    required Storage storage,
    required Client client,
    Uuid? idGenerator,
  })  : _storage = storage,
        _client = client,
        _idGenerator = idGenerator ?? const Uuid();

  final Storage _storage;
  final Client _client;
  final Uuid _idGenerator;

  @override
  Future<AppBoxKitStorageObjectRef> upload({
    required String bucket,
    required String path,
    required Uint8List bytes,
    String? contentType,
    void Function(double progress)? onProgress,
  }) async {
    final fileId = _idGenerator.v4();
    final file = await _storage.createFile(
      bucketId: bucket,
      fileId: fileId,
      file: InputFile.fromBytes(
        bytes: bytes,
        filename: _basename(path),
        contentType: contentType,
      ),
      onProgress: onProgress == null
          ? null
          : (UploadProgress p) => onProgress(p.progress),
    );
    return AppBoxKitStorageObjectRef(bucket: bucket, path: path, id: file.$id);
  }

  @override
  Future<String> getUrl(AppBoxKitStorageObjectRef ref) async {
    final project = _client.config['project'] ?? '';
    return '${_client.endPoint}/storage/buckets/${ref.bucket}/files/${ref.id}/view?project=$project';
  }

  @override
  Future<void> delete(AppBoxKitStorageObjectRef ref) async {
    await _storage.deleteFile(bucketId: ref.bucket, fileId: ref.id);
  }

  static String _basename(String path) {
    final i = path.lastIndexOf('/');
    return i < 0 ? path : path.substring(i + 1);
  }
}
