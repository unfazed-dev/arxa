import 'dart:io';
import 'dart:typed_data';

import 'package:appwrite/appwrite.dart' as aw;
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:appbox_kit_data/storage/appwrite/appbox_kit_appwrite_storage_service.dart';

/// Live-credentials contract test for [AppBoxKitAppwriteStorageService].
///
/// Env-var skip convention (see appbox_kit_supabase_storage_service_test.dart):
/// set `APPWRITE_ENDPOINT`, `APPWRITE_PROJECT`, and `KIT_STORAGE_BUCKET`
/// (an existing Appwrite bucket id) to run; otherwise Skip.
void main() {
  final endpoint = Platform.environment['APPWRITE_ENDPOINT'];
  final project = Platform.environment['APPWRITE_PROJECT'];
  final bucket = Platform.environment['KIT_STORAGE_BUCKET'] ?? 'kit_storage_test';
  final enabled = endpoint != null && project != null;

  group(
    'AppBoxKitAppwriteStorageService contract',
    () {
      late aw.Client client;
      late aw.Storage storage;

      setUpAll(() {
        client = aw.Client().setEndpoint(endpoint!).setProject(project!);
        storage = aw.Storage(client);
      });

      test('upload → getUrl → delete round trip', () async {
        final service =
            AppBoxKitAppwriteStorageService(storage: storage, client: client);
        final path = 'contract/${const Uuid().v4()}.txt';
        final payload = Uint8List.fromList([1, 2, 3, 4, 5]);

        final ref = await service.upload(
          bucket: bucket,
          path: path,
          bytes: payload,
          contentType: 'text/plain',
        );

        expect(ref.bucket, bucket);
        expect(ref.path, path);
        // Appwrite allocates a fileId distinct from the path.
        expect(ref.id, isNot(path));
        expect(ref.id, isNotEmpty);

        final url = await service.getUrl(ref);
        expect(url, contains(endpoint));
        expect(url, contains(ref.id));

        await expectLater(service.delete(ref), completes);
      });

      test('upload streams real progress toward 1.0', () async {
        final service =
            AppBoxKitAppwriteStorageService(storage: storage, client: client);
        final path = 'progress/${const Uuid().v4()}.bin';
        final seen = <double>[];

        await service.upload(
          bucket: bucket,
          path: path,
          // ~256 KB so Appwrite's chunked uploader actually reports progress.
          bytes: Uint8List.fromList(List.generate(256 * 1024, (i) => i % 256)),
          contentType: 'application/octet-stream',
          onProgress: seen.add,
        );

        expect(seen, isNotEmpty);
        expect(seen.last, greaterThanOrEqualTo(0.0));
        expect(seen.last, lessThanOrEqualTo(1.0));
      });
    },
    skip: enabled
        ? false
        : 'Requires live Appwrite credentials (APPWRITE_ENDPOINT, '
            'APPWRITE_PROJECT, optional KIT_STORAGE_BUCKET).',
  );
}
