import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:uuid/uuid.dart';

import 'package:appbox_kit_data/storage/supabase/appbox_kit_supabase_storage_service.dart';

/// Live-credentials contract test for [AppBoxKitSupabaseStorageService].
///
/// The kit's existing tests have no remote-backend precedent, so this file
/// establishes the env-var skip convention: set `SUPABASE_URL` and
/// `SUPABASE_PUBLISHABLE_KEY` (and a `KIT_STORAGE_BUCKET` that already exists
/// on your project) to exercise the round trip; otherwise the suite reports
/// Skip with the reason. This mirrors how the kit gates other would-be-live
/// integration points behind explicit operator opt-in.
void main() {
  final url = Platform.environment['SUPABASE_URL'];
  final key = Platform.environment['SUPABASE_PUBLISHABLE_KEY'];
  final bucket = Platform.environment['KIT_STORAGE_BUCKET'] ?? 'kit_storage_test';
  final enabled = url != null && key != null;

  group(
    'AppBoxKitSupabaseStorageService contract',
    () {
      late sb.SupabaseClient client;

      setUpAll(() {
        sb.Supabase.initialize(url: url!, publishableKey: key!);
        client = sb.Supabase.instance.client;
      });

      test('upload → getUrl → delete round trip', () async {
        final service = AppBoxKitSupabaseStorageService(client: client);
        final id = const Uuid().v4();
        final path = 'contract/$id.txt';
        final payload = Uint8List.fromList([1, 2, 3, 4, 5]);

        final ref = await service.upload(
          bucket: bucket,
          path: path,
          bytes: payload,
          contentType: 'text/plain',
        );

        expect(ref.bucket, bucket);
        expect(ref.path, path);
        expect(ref.id, path);

        final publicUrl = await service.getUrl(ref);
        expect(publicUrl, contains(url));
        expect(publicUrl, contains(path));

        // Supabase public URLs are synthetic and still resolve after delete,
        // so the contract asserts only that delete completes cleanly.
        await expectLater(service.delete(ref), completes);
      });

      test('upload delivers a terminal 1.0 progress event', () async {
        final service = AppBoxKitSupabaseStorageService(client: client);
        final id = const Uuid().v4();
        final seen = <double>[];

        await service.upload(
          bucket: bucket,
          path: 'progress/$id.txt',
          bytes: Uint8List.fromList([9]),
          contentType: 'text/plain',
          onProgress: seen.add,
        );

        expect(seen, isNotEmpty);
        expect(seen.last, 1.0);
      });
    },
    skip: enabled
        ? false
        : 'Requires live Supabase credentials (SUPABASE_URL, '
            'SUPABASE_PUBLISHABLE_KEY, optional KIT_STORAGE_BUCKET).',
  );
}
