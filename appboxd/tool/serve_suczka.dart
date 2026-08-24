// Operator launcher: serve the suczka-studio design artifact on
// 127.0.0.1:4319 with watch ON and the Design Dial enabled. Draft overlay
// state persists under ~/.appbox/drafts (the real store - this is the
// operator-facing process, not a test).
//
//   dart run tool/serve_suczka.dart
import 'dart:io';

import 'package:appboxd/design_dial.dart';
import 'package:appboxd/design_draft.dart';
import 'package:appboxd/design_server.dart';

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
    dialStore: MemoryDialStore(),
    // The panel iframes this server from arxa.studio.localhost:7891 - cross
    // origin - so the machine-wide allowlist (~/.appbox/trusted-origins,
    // which arxa studio registers itself into) must ride along. The CLI
    // merges it; a bare library call would not.
    trustedOrigins: readTrustedOriginsFile(),
  );
  stdout.writeln('suczka-studio design server on '
      'http://127.0.0.1:${srv.port} (watch on, dial on)');
}
