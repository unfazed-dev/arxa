/// Blob storage over cairn attachments (ADR-0034 two-plane sync): the
/// metadata plane is the synced `attachments` table, the blob plane is a
/// local [BlobStore] cache + a remote [AttachmentStorageAdapter] the cairn
/// driver pumps when online. Apps see only the kit/data
/// [ArxaKitStorageService] seam — bytes, refs, URLs.
///
/// The attachment id is DERIVED as `<bucket>/<path>`: per-call buckets
/// coexist in one metadata table, and the remote adapter routes on the
/// prefix. Caller-built refs (`id` defaults to `path` on the seam) resolve
/// identically — `ref.id` is never trusted.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cairn_flutter/cairn_flutter.dart';
import 'package:arxa_kit_data/arxa_kit_data.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

class ArxaKitCairnStorageService implements ArxaKitStorageService {
  /// [attachments] is the driver built from the opened database (its blob
  /// store's `wipe` is a sign-out hook already); [blobStore] is the SAME
  /// instance the driver was built with, held so [getUrl] can read local
  /// bytes. [publicUrlFor] (supabaseBridge wires Supabase's public URL) is
  /// consulted before the local `data:` fallback.
  ArxaKitCairnStorageService({
    required this.attachments,
    required this.blobStore,
    this.publicUrlFor,
  });

  /// The driver built from the opened database (its blob store's `wipe` is a
  /// sign-out hook already).
  final Attachments attachments;

  /// The SAME instance the driver was built with — held so [getUrl] can read
  /// local bytes for the `data:` fallback.
  final BlobStore blobStore;

  /// Host URL plane (supabaseBridge wires Supabase's public URL); consulted
  /// before the local `data:` fallback.
  final String Function(String bucket, String path)? publicUrlFor;

  /// Media types seen at upload, this session — the `data:` fallback's MIME.
  /// (The synced metadata row carries it too; reading it back is a query the
  /// seam doesn't otherwise need, so v1 keeps the session map — blobs from
  /// OTHER sessions fall back to octet-stream, which browsers tolerate.)
  final Map<String, String> _mediaTypes = {};

  /// The attachment id for a seam coordinate — the single derivation both
  /// the kit and the remote adapter agree on.
  static String attachmentIdFor(String bucket, String path) => '$bucket/$path';

  @override
  Future<ArxaKitStorageObjectRef> upload({
    required String bucket,
    required String path,
    required Uint8List bytes,
    String? contentType,
    void Function(double progress)? onProgress,
  }) async {
    final id = attachmentIdFor(bucket, path);
    final mediaType = contentType ?? 'application/octet-stream';
    onProgress?.call(0);
    // queueUpload caches the bytes locally at once and enqueues the metadata
    // row through the durable outbox — crash-safe. The remote adapter leg
    // runs on the driver's next online pump (offline-first: upload returns
    // once the write is durably queued, not when the network agrees).
    await attachments.queueUpload(
      filename: path.split('/').last,
      bytes: bytes,
      mediaType: mediaType,
      id: id,
    );
    _mediaTypes[id] = mediaType;
    onProgress?.call(1);
    return ArxaKitStorageObjectRef(bucket: bucket, path: path, id: id);
  }

  @override
  Future<String> getUrl(ArxaKitStorageObjectRef ref) async {
    final custom = publicUrlFor?.call(ref.bucket, ref.path);
    if (custom != null) return custom;
    final id = attachmentIdFor(ref.bucket, ref.path);
    final bytes = await blobStore.get(id);
    if (bytes == null) {
      throw StateError(
        'ArxaKitCairnStorageService: blob "$id" is not on this device and no '
        'publicUrlFor callback was supplied — either the upload never ran '
        'here, or the host must provide a URL plane (private buckets and '
        'cross-device fetches are outside this seam).',
      );
    }
    final mime = _mediaTypes[id] ?? 'application/octet-stream';
    return 'data:$mime;base64,${base64Encode(bytes)}';
  }

  @override
  Future<void> delete(ArxaKitStorageObjectRef ref) async {
    final id = attachmentIdFor(ref.bucket, ref.path);
    // Both legs are idempotent: the local cache entry may already be gone,
    // and a queued_delete on a missing metadata row is a no-op write.
    await blobStore.remove(id);
    await attachments.remove(id);
    _mediaTypes.remove(id);
  }
}

/// The localOnly blob plane: there is no remote bucket, so upload/delete
/// converge immediately and download has no meaning (the kit seam never
/// queues one — bytes live in the [BlobStore]).
class ArxaKitCairnLocalOnlyAdapter implements AttachmentStorageAdapter {
  const ArxaKitCairnLocalOnlyAdapter();

  @override
  Future<void> upload(String path, Uint8List bytes, String mediaType) async {}

  @override
  Future<Uint8List> download(String path) => throw StateError(
        'ArxaKitCairnLocalOnlyAdapter: localOnly mode has no remote blob '
        'plane to download from',
      );

  @override
  Future<void> delete(String path) async {}
}

/// supabaseBridge's blob plane: like cairn's [SupabaseStorageAdapter] but
/// per-call buckets — the bucket is parsed from the kit's `<bucket>/<path>`
/// attachment id, so one driver serves every bucket the app names.
class ArxaKitCairnSupabaseBucketAdapter implements AttachmentStorageAdapter {
  ArxaKitCairnSupabaseBucketAdapter({required this.client});

  final sb.SupabaseClient client;

  (String bucket, String key) _split(String path) {
    final slash = path.indexOf('/');
    if (slash <= 0) {
      throw StateError(
        'ArxaKitCairnSupabaseBucketAdapter: attachment id "$path" is not in '
        'the kit\'s <bucket>/<path> form',
      );
    }
    return (path.substring(0, slash), path.substring(slash + 1));
  }

  @override
  Future<void> upload(String path, Uint8List bytes, String mediaType) async {
    final (bucket, key) = _split(path);
    // uploadBinary + upsert:true is idempotent under the driver's retries.
    await client.storage.from(bucket).uploadBinary(
          key,
          bytes,
          fileOptions: sb.FileOptions(contentType: mediaType, upsert: true),
        );
  }

  @override
  Future<Uint8List> download(String path) async {
    final (bucket, key) = _split(path);
    return client.storage.from(bucket).download(key);
  }

  @override
  Future<void> delete(String path) async {
    final (bucket, key) = _split(path);
    try {
      await client.storage.from(bucket).remove([key]);
    } on sb.StorageException catch (_) {
      // Already gone — success per the idempotent adapter contract.
    }
  }
}
