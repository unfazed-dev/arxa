import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Daemon configuration: port + web root, with sane defaults.
class AppboxdConfig {
  AppboxdConfig({
    required this.repoRoot,
    required this.port,
    required this.webRoot,
  });

  final String repoRoot;
  final int port;

  /// Absolute path of the directory served as the static web builder UI.
  final String webRoot;

  static const defaultPort = 8787;

  /// Loads config/appbox.config.json under [repoRoot] when present; the
  /// optional `daemon` object may carry `port` and `webRoot` (relative to the
  /// repo root). Anything missing falls back to defaults.
  static AppboxdConfig load(String repoRoot, {int? port, String? webRoot}) {
    repoRoot = p.canonicalize(repoRoot);
    var cfgPort = defaultPort;
    var cfgRoot = p.join(repoRoot, 'appbox-studio', 'build', 'web');

    final file = File(p.join(repoRoot, 'config', 'appbox.config.json'));
    if (file.existsSync()) {
      try {
        final json = jsonDecode(file.readAsStringSync());
        final daemon = (json as Map)['daemon'];
        if (daemon is Map) {
          if (daemon['port'] is int) cfgPort = daemon['port'] as int;
          if (daemon['webRoot'] is String) {
            cfgRoot = p.normalize(p.join(repoRoot, daemon['webRoot'] as String));
          }
        }
      } on FormatException {
        // Unparseable config is not fatal: fall back to defaults.
      }
    }

    return AppboxdConfig(
      repoRoot: repoRoot,
      port: port ?? cfgPort,
      webRoot: p.normalize(webRoot ?? cfgRoot),
    );
  }
}
