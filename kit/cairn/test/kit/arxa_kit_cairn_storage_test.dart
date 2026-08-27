import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cairn_flutter/cairn_flutter.dart';
import 'package:arxa_kit_cairn/arxa_kit_cairn.dart';
import 'package:arxa_kit_core/arxa_kit_locator.dart';
import 'package:arxa_kit_data/arxa_kit_data.dart';

import '../support/fake_cairn_engine.dart';
import '../support/post_harness.dart';

/// The storage service (phase 4f): `ArxaKitCairnStorageService` maps the
/// kit/data blob seam onto cairn attachments — the metadata plane is the
/// synced `attachments` table, the blob plane is a local cache + a remote
/// [AttachmentStorageAdapter] cairn's driver pumps when online.
///
/// Branches under test:
/// - upload caches bytes + enqueues a `queued_upload` row under the kit's
///   `bucket/path` attachment id; progress reports 0 then 1; re-upload
///   overwrites (upsert on the same id).
/// - getUrl prefers the host's URL callback; without one it falls back to a
///   `data:` URL from the local blob (local-only parity with the seed
///   backend); a blob absent from this device fails loudly.
/// - delete drops the local blob and enqueues the remote delete; a caller-
///   built ref (no `id`) still resolves — the id is derived, never trusted.
/// - the backend appends the `attachments` table to the emitted schema (it is
///   what the driver writes), registers the service, and fails loudly on a
///   table-name collision; sync mode demands a host adapter.
/// - the emitter ships the attachments table declaration and documents the
///   server-side CAIRN_WRITE_TABLES requirement.
void main() {
  tearDown(() {
    ArxaKitData.resetForTesting();
    arxaKitLocator.reset();
  });

  group('kit.cairn.storage', () {
    test(
      'kit.cairn.storage — upload caches bytes and enqueues the metadata row under bucket/path',
      () async {
        // Given a service over a real attachments driver on the fake engine
        final h = await _storageHarness();
        final progress = <double>[];

        // When a blob uploads with an explicit content type
        final ref = await h.service.upload(
          bucket: 'avatars',
          path: 'users/u-1.png',
          bytes: Uint8List.fromList(utf8.encode('png-bytes')),
          contentType: 'image/png',
          onProgress: progress.add,
        );

        // Then the ref carries the derived attachment id
        expect(ref.bucket, 'avatars');
        expect(ref.path, 'users/u-1.png');
        expect(ref.id, 'avatars/users/u-1.png');

        // And the bytes are cached locally (readable offline at once)
        expect(
          utf8.decode((await h.blobStore.get('avatars/users/u-1.png'))!),
          'png-bytes',
        );

        // And the metadata row sits queued for the driver's next online pump
        final rows = h.engine.rowsFor('attachments');
        expect(rows.single['id'], 'avatars/users/u-1.png');
        expect(rows.single['state'], 'queued_upload');
        expect(rows.single['media_type'], 'image/png');
        expect(rows.single['filename'], 'u-1.png');
        expect(rows.single['size'], 9);

        // And progress ran start-to-terminal
        expect(progress.first, 0.0);
        expect(progress.last, 1.0);
      },
    );

    test(
      'kit.cairn.storage — upload defaults the media type and overwrites on the same path',
      () async {
        // Given a prior upload at a path
        final h = await _storageHarness();
        await h.service.upload(
          bucket: 'docs',
          path: 'a.bin',
          bytes: Uint8List.fromList([1]),
        );

        // When the same path uploads again without a content type
        await h.service.upload(
          bucket: 'docs',
          path: 'a.bin',
          bytes: Uint8List.fromList([2, 2]),
        );

        // Then the row upserts (still one) and the new bytes win
        final rows = h.engine.rowsFor('attachments');
        expect(rows.length, 1);
        expect(rows.single['media_type'], 'application/octet-stream');
        expect(rows.single['size'], 2);
        expect((await h.blobStore.get('docs/a.bin'))!, [2, 2]);
      },
    );

    test(
      'kit.cairn.storage — a queued upload reaches the remote adapter under the kit id on pump',
      () async {
        // Given a recording remote adapter and an ONLINE driver
        final engine = FakeCairnEngine();
        // ignore: invalid_use_of_visible_for_testing_member
        final cairn = Cairn.withEngine(engine);
        final db = await CairnDatabase.localForTest(
          // ignore: invalid_use_of_visible_for_testing_member
          cairn,
          CairnSchema(tables: [CairnSchemaEmitter.attachmentsTable()]),
        );
        final adapter = _RecordingAdapter();
        final blobStore = _MemoryBlobStore();
        final attachments = Attachments(
          db: db,
          adapter: adapter,
          blobStore: blobStore,
          isOnline: () async => true,
        );
        final service = ArxaKitCairnStorageService(
          attachments: attachments,
          blobStore: blobStore,
        );

        // When an upload queues and the driver pumps online
        await service.upload(
          bucket: 'avatars',
          path: 'u-2.png',
          bytes: Uint8List.fromList([7]),
          contentType: 'image/png',
        );
        await attachments.pump();

        // Then the adapter received the bytes under the kit's attachment id
        expect(adapter.uploaded.single.key, 'avatars/u-2.png');
        expect(adapter.uploaded.single.bytes, [7]);
        expect(adapter.uploaded.single.mediaType, 'image/png');

        // And the metadata row converged to synced
        expect(engine.rowsFor('attachments').single['state'], 'synced');
      },
    );

    test(
      'kit.cairn.storage — getUrl prefers the host callback, falls back to a data URL, fails loud when absent',
      () async {
        // Given a service WITH a host URL callback and one uploaded blob
        final h = await _storageHarness(
          publicUrlFor: (bucket, path) => 'https://cdn.example/$bucket/$path',
        );
        final ref = await h.service.upload(
          bucket: 'avatars',
          path: 'u-3.png',
          bytes: Uint8List.fromList(utf8.encode('xyz')),
        );

        // Then the callback wins
        expect(await h.service.getUrl(ref), 'https://cdn.example/avatars/u-3.png');

        // Given a service WITHOUT a callback (local-only parity)
        final plain = await _storageHarness();
        final plainRef = await plain.service.upload(
          bucket: 'avatars',
          path: 'u-4.png',
          bytes: Uint8List.fromList(utf8.encode('local-bytes')),
        );

        // Then the data URL carries the blob (seed-backend parity)
        final url = await plain.service.getUrl(plainRef);
        expect(url, startsWith('data:'));
        expect(
          utf8.decode(base64Decode(url.split(',').last)),
          'local-bytes',
        );

        // And a blob that never reached this device fails loudly, naming it
        expect(
          () => plain.service.getUrl(const ArxaKitStorageObjectRef(
            bucket: 'avatars',
            path: 'never-uploaded.png',
          )),
          throwsA(isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('avatars/never-uploaded.png'),
          )),
        );
      },
    );

    test(
      'kit.cairn.storage — delete drops the local blob, enqueues the remote delete, and resolves caller-built refs',
      () async {
        // Given an uploaded blob
        final h = await _storageHarness();
        await h.service.upload(
          bucket: 'avatars',
          path: 'u-5.png',
          bytes: Uint8List.fromList([5]),
        );

        // When delete runs with a CALLER-BUILT ref (id defaults to path — the
        // service must derive the attachment id, never trust ref.id)
        await h.service.delete(
          const ArxaKitStorageObjectRef(bucket: 'avatars', path: 'u-5.png'),
        );

        // Then the local blob is gone and the row queued its remote delete
        expect(await h.blobStore.get('avatars/u-5.png'), isNull);
        expect(
          h.engine.rowsFor('attachments').single['state'],
          'queued_delete',
        );

        // And deleting what is already gone is a no-op success (seam contract)
        await h.service.delete(
          const ArxaKitStorageObjectRef(bucket: 'avatars', path: 'ghost.png'),
        );
      },
    );

    test(
      'kit.cairn.storage — backend appends the attachments table and registers the service',
      () async {
        // Given a storage-enabled localOnly plugin with an injected opener
        CairnSchema? openedSchema;
        final blobStore = _MemoryBlobStore();
        final backend = ArxaKitCairnBackend(
          config: const ArxaKitCairnConfig(),
          storage: true,
          storageBlobStore: blobStore,
          openDatabase: (config, schema, token) async {
            openedSchema = schema;
            // ignore: invalid_use_of_visible_for_testing_member
            final cairn = Cairn.withEngine(FakeCairnEngine());
            // ignore: invalid_use_of_visible_for_testing_member
            return CairnDatabase.localForTest(cairn, schema);
          },
        );

        // When kit/data initializes
        await ArxaKitData.initialize(
          config: ArxaKitDataConfig(
            backend: ArxaKitDataBackend.plugin,
            plugin: backend,
          ),
          entities: const [plainPostRegistration],
        );

        // Then the emitted schema carries the driver's metadata table LAST
        expect(openedSchema!.tables.map((t) => t.name), ['posts', 'attachments']);

        // And the storage seam resolves and round-trips a blob
        final storage = arxaKitLocator<ArxaKitStorageService>();
        final ref = await storage.upload(
          bucket: 'b',
          path: 'p.bin',
          bytes: Uint8List.fromList([1, 2, 3]),
        );
        expect((await blobStore.get(ref.id))!, [1, 2, 3]);
      },
    );

    test(
      'kit.cairn.storage — an app table named attachments collides loudly at boot',
      () async {
        // Given a storage-enabled plugin but an entity that squats the name
        final backend = ArxaKitCairnBackend(
          config: const ArxaKitCairnConfig(),
          storage: true,
          storageBlobStore: _MemoryBlobStore(),
          openDatabase: _unusedOpen,
        );

        // Then boot refuses, naming the collision (the driver would fight the
        // app's own writes to that table)
        await expectLater(
          ArxaKitData.initialize(
            config: ArxaKitDataConfig(
              backend: ArxaKitDataBackend.plugin,
              plugin: backend,
            ),
            entities: const [
              ArxaKitEntityRegistration<Post>(
                schema: ArxaKitTableSchema(
                  table: 'attachments',
                  columns: [
                    ArxaKitColumn.id(),
                    ArxaKitColumn('title', ArxaKitColumnType.text),
                  ],
                ),
                fromJson: plainPostFromJson,
                toJson: plainPostToRow,
              ),
            ],
          ),
          throwsA(isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('attachments'),
          )),
        );
      },
    );

    test(
      'kit.cairn.storage — sync mode with storage demands a host adapter',
      () async {
        // Given a sync-mode plugin that enables storage but supplies no adapter
        final backend = ArxaKitCairnBackend(
          config: const ArxaKitCairnConfig(
            mode: ArxaKitCairnMode.sync,
            syncUrl: 'wss://sync.example.com/sync',
          ),
          tokenProvider: () async => 'host-jwt',
          storage: true,
          storageBlobStore: _MemoryBlobStore(),
          openDatabase: (config, schema, token) async {
            // ignore: invalid_use_of_visible_for_testing_member
            final cairn = Cairn.withEngine(FakeCairnEngine());
            // ignore: invalid_use_of_visible_for_testing_member
            return CairnDatabase.localForTest(cairn, schema);
          },
        );

        // Then initialize fails, naming the missing ctor param — the blob
        // plane has nowhere to go
        await expectLater(
          ArxaKitData.initialize(
            config: ArxaKitDataConfig(
              backend: ArxaKitDataBackend.plugin,
              plugin: backend,
            ),
            entities: const [plainPostRegistration],
          ),
          throwsA(isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('storageAdapter'),
          )),
        );
      },
    );

    test(
      'kit.cairn.storage — the emitter declares the attachments table and documents CAIRN_WRITE_TABLES',
      () {
        // Given the emitter's attachments declaration
        final table = CairnSchemaEmitter.attachmentsTable();

        // Then it mirrors cairn's AttachmentSchema contract exactly
        expect(table.name, AttachmentSchema.table);
        expect(table.primaryKey, ['id']);
        expect(
          table.columns.map((c) => c.name),
          ['id', 'filename', 'size', 'media_type', 'state', 'timestamp'],
        );

        // And the server env snippet documents the write-allowlist requirement
        final env = CairnSchemaEmitter()
            .emitServerCrdtEnv(const [], includeAttachments: true);
        expect(env, contains('CAIRN_WRITE_TABLES'));
        expect(env, contains('attachments'));
      },
    );
  });
}

/// Service-level harness: a real [Attachments] driver (offline is fine — the
/// kit verbs never depend on a pump) over the fake engine, with the
/// attachments table subscribed exactly like the backend wires it.
Future<({ArxaKitCairnStorageService service, _MemoryBlobStore blobStore, FakeCairnEngine engine})>
    _storageHarness({
  String Function(String bucket, String path)? publicUrlFor,
}) async {
  final engine = FakeCairnEngine();
  // ignore: invalid_use_of_visible_for_testing_member
  final cairn = Cairn.withEngine(engine);
  final db = await CairnDatabase.localForTest(
    // ignore: invalid_use_of_visible_for_testing_member
    cairn,
    CairnSchema(tables: [CairnSchemaEmitter.attachmentsTable()]),
  );
  final blobStore = _MemoryBlobStore();
  final attachments = db.attachments(
    adapter: _RecordingAdapter(),
    blobStore: blobStore,
  );
  return (
    service: ArxaKitCairnStorageService(
      attachments: attachments,
      blobStore: blobStore,
      publicUrlFor: publicUrlFor,
    ),
    blobStore: blobStore,
    engine: engine,
  );
}

class _MemoryBlobStore implements BlobStore {
  final _blobs = <String, Uint8List>{};
  var wipeCalls = 0;

  @override
  Future<void> put(String id, Uint8List bytes) async => _blobs[id] = bytes;

  @override
  Future<Uint8List?> get(String id) async => _blobs[id];

  @override
  Future<void> remove(String id) async => _blobs.remove(id);

  @override
  Future<void> wipe() async {
    wipeCalls++;
    _blobs.clear();
  }
}

class _RecordingAdapter implements AttachmentStorageAdapter {
  final uploaded = <({String key, Uint8List bytes, String mediaType})>[];
  final deleted = <String>[];

  @override
  Future<void> upload(String path, Uint8List bytes, String mediaType) async =>
      uploaded.add((key: path, bytes: bytes, mediaType: mediaType));

  @override
  Future<Uint8List> download(String path) =>
      throw StateError('no downloads in this harness');

  @override
  Future<void> delete(String path) async => deleted.add(path);
}

Future<CairnDatabase> _unusedOpen(
  ArxaKitCairnConfig config,
  CairnSchema schema,
  String? token,
) =>
    throw StateError('the opener must not run in this test');
