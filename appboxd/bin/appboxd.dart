import 'dart:io';

import 'package:appboxd/config.dart';
import 'package:appboxd/engine.dart';
import 'package:appboxd/gateway.dart';
import 'package:appboxd/server.dart';
import 'package:appboxd/vault.dart';

Future<void> main(List<String> args) async {
  // appboxd runs from the repo root (or a subdirectory of it).
  var root = Directory.current.path;
  while (!File('$root/config/appbox.config.json').existsSync()) {
    final parent = Directory(root).parent.path;
    if (parent == root) {
      stderr.writeln('appboxd: config/appbox.config.json not found — run from the repo root.');
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
  // One minter for the daemon: the gateway verifies tokens, the engine
  // mints stage-scoped ones (E2/E3) — sharing the instance is what makes
  // stage tokens verify at /llm.
  final minter = TokenMinter();
  // The /llm gateway needs the OS vault for provider keys; without a vault
  // backend for this platform the rest of the daemon still boots.
  Gateway? gateway;
  try {
    gateway = Gateway(
        repoRoot: config.repoRoot, vault: platformVault(), minter: minter);
  } on UnsupportedError catch (e) {
    stderr.writeln('appboxd: /llm gateway disabled — $e');
  }
  final engine = Engine(
    repoRoot: config.repoRoot,
    gatewayPort: config.port,
    minter: minter,
  );
  final server = await startServer(config, gateway: gateway);
  stdout.writeln('appboxd listening on http://${server.address.host}:${server.port}');
  stdout.writeln('  web root: ${config.webRoot}');
  stdout.writeln('  repo root: ${config.repoRoot}');
  stdout.writeln('  engine stages: ${engine.stages.map((s) => s.name).join(', ')}');
}
