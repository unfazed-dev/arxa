import 'dart:typed_data';

/// Reference to a stored blob — the only handle a caller needs to read,
/// delete, or share an object previously written through [AppBoxKitStorageService].
///
/// [id] is the backend-native immutable key. It equals [path] on the seed
/// and Supabase backends (both path-addressed) and is the Appwrite-allocated
/// `fileId` on the Appwrite backend. Each backend populates all three fields
/// so callers never branch on which backend is active.
class AppBoxKitStorageObjectRef {
  final String bucket;
  final String path;

  /// Backend-native immutable key (`== path` on seed/Supabase, Appwrite
  /// `fileId` on Appwrite). Defaults to [path] when not supplied.
  final String id;

  const AppBoxKitStorageObjectRef({
    required this.bucket,
    required this.path,
    String? id,
  }) : id = id ?? path;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppBoxKitStorageObjectRef &&
          other.bucket == bucket &&
          other.path == path &&
          other.id == id;

  @override
  int get hashCode => Object.hash(bucket, path, id);

  @override
  String toString() => 'AppBoxKitStorageObjectRef(bucket: $bucket, path: $path, id: $id)';
}

/// Blob-storage seam mirroring [AppBoxKitRepository] — one swap surface, three
/// backends (seed / supabase / appwrite), selected by the same
/// [AppBoxKitDataBackend] as the repositories.
///
/// Contract (mirrors the repository swap rules):
/// - [upload] is idempotent on the seed backend (in-memory overwrite) and
///   best-effort on remote backends (Supabase rejects a duplicate path
///   unless the bucket is configured to upsert — callers overwrite by
///   writing to a fresh path, or delete first).
/// - [onProgress] reports a `0.0..1.0` inclusive fraction. The seed backend
///   reports `0.0` then `1.0` synchronously (no network). Supabase reports
///   `1.0` after the HTTP round-trip (the stable `uploadBinary` API exposes
///   no per-chunk callback). Appwrite streams real per-chunk progress.
///   Progress is best-effort: callers must not rely on a specific call
///   sequence beyond the terminal `1.0`.
/// - [getUrl] returns a URL that resolves without an auth header for *public*
///   buckets; private buckets will refuse it (a signed-URL flow is outside
///   this minimal seam). The seed backend returns a `data:` URL because it
///   has no HTTP origin.
abstract interface class AppBoxKitStorageService {
  /// Stores [bytes] at `bucket/path`. Returns the canonical [AppBoxKitStorageObjectRef]
  /// the caller hands back to [getUrl] / [delete]. [contentType] is honored
  /// by the seed (data-URL MIME) and Appwrite backends; Supabase forwards it
  /// via `FileOptions.contentType`. [onProgress], when supplied, receives
  /// best-effort `0.0..1.0` updates.
  Future<AppBoxKitStorageObjectRef> upload({
    required String bucket,
    required String path,
    required Uint8List bytes,
    String? contentType,
    void Function(double progress)? onProgress,
  });

  /// Returns a URL for [ref]. See the class-level contract for the
  /// public-vs-private bucket caveat.
  Future<String> getUrl(AppBoxKitStorageObjectRef ref);

  /// Permanently removes the object. No-op when [ref] is already gone.
  Future<void> delete(AppBoxKitStorageObjectRef ref);
}
