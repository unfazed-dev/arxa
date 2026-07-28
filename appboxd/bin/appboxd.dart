import 'dart:io';

import 'package:appboxd/config.dart';
import 'package:appboxd/server.dart';

Future<void> main(List<String> args) async {
  // appboxd runs from the repo root (or a subdirectory of it).
  var root = Directory.current.path;
  while (!File('$root/pipeline/pipeline.sh').existsSync()) {
    final parent = Directory(root).parent.path;
    if (parent == root) {
      stderr.writeln('appboxd: pipeline/pipeline.sh not found — run from the repo root.');
      exit(64);
    }
    root = parent;
  }

  var portOverride = 0;
  final portIdx = args.indexOf('--port');
  if (portIdx >= 0 && portIdx + 1 < args.length) {
    portOverride = int.tryParse(args[portIdx + 1]) ?? 0;
  }

  final config = AppboxdConfig.load(
    root,
    port: portOverride > 0 ? portOverride : null,
  );
  final server = await startServer(config);
  stdout.writeln('appboxd listening on http://${server.address.host}:${server.port}');
  stdout.writeln('  web root: ${config.webRoot}');
  stdout.writeln('  repo root: ${config.repoRoot}');
}
