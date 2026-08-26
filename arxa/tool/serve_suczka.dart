// Operator launcher: serve the suczka-studio design artifact on
// 127.0.0.1:4319 with watch ON and the Arxa Dial enabled. Draft overlay
// state persists under ~/.arxa/drafts (the real store - this is the
// operator-facing process, not a test).
//
//   dart run tool/serve_suczka.dart
import 'dart:io';

import 'package:arxa/design_draft.dart';
import 'package:arxa/design_server.dart';

Future<void> main() async {
  final srv = await DesignServer.start(
    artifactDir:
        '/Volumes/developer_ssd/Developer/totem_labs/clients/architect-gallore/design/suczka-studio',
    port: 4319,
    dial: true,
    draftStore: DraftFileStore(
      artifactDir:
          '/Volumes/developer_ssd/Developer/totem_labs/clients/architect-gallore/design/suczka-studio',
    ),
    // Dial store: NOT pinned here (was MemoryDialStore until 2026-08-25 —
    // the Supabase rewire). DesignServer.start resolves
    // SupabaseDialStore.fromConfig(~/.arxa/supabase) first and falls back
    // to memory only when unconfigured, so clients and the operator share
    // the central store (project nqvzhxcldntyayilykfy).
    // The panel iframes this server from arxa.studio.localhost:7891 - cross
    // origin - so the machine-wide allowlist (~/.arxa/trusted-origins,
    // which arxa studio registers itself into) must ride along. The CLI
    // merges it; a bare library call would not.
    trustedOrigins: readTrustedOriginsFile(),
  );
  stdout.writeln('suczka-studio design server on '
      'http://127.0.0.1:${srv.port} (watch on, dial on)');
}
