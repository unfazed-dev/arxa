/// [ArxaKitStorageService] backed by Supabase Storage.
library;

import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../arxa_kit_storage_service.dart';

/// Supabase implementation of [ArxaKitStorageService].
///
/// Mirrors [ArxaKitSupabaseRepository] — constructed with the live
/// [SupabaseClient] the kit already initializes, and thin enough that the
/// `bucket`/`path`/`bytes` triple maps 1:1 to Supabase's
/// `storage.from(bucket).uploadBinary(path, bytes)`.
class ArxaKitSupabaseStorageService implements ArxaKitStorageService {
  ArxaKitSupabaseStorageService({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  @override
  Future<ArxaKitStorageObjectRef> upload({
    required String bucket,
    required String path,
    required Uint8List bytes,
    String? contentType,
    void Function(double progress)? onProgress,
  }) async {
    // Supabase's stable `uploadBinary` exposes no per-chunk callback
    // (retry/progress plumbing lives behind StorageRetryController, which is
    // out of scope for this minimal seam) — report completion honestly.
    await _client.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType),
        );
    onProgress?.call(1.0);
    return ArxaKitStorageObjectRef(bucket: bucket, path: path);
  }

  @override
  Future<String> getUrl(ArxaKitStorageObjectRef ref) {
    return Future.value(_client.storage.from(ref.bucket).getPublicUrl(ref.path));
  }

  @override
  Future<void> delete(ArxaKitStorageObjectRef ref) async {
    await _client.storage.from(ref.bucket).remove([ref.path]);
  }
}
