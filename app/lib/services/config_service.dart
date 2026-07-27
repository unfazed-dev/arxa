import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Loads the app's bundled runtime config (`assets/config/app_box.config.json`).
///
/// R3: every project-varying value comes from here or pipeline state — never a
/// literal in code. The repo-level `config/app-box.config.json` is the pipeline's
/// SSOT for targets/kit SHA; this file holds app-side runtime values only.
class ConfigService {
  Map<String, dynamic>? _cfg;
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    final raw =
        await rootBundle.loadString('assets/config/app_box.config.json');
    _cfg = jsonDecode(raw) as Map<String, dynamic>;
    _loaded = true;
  }

  /// Test seam — load config from an in-memory map (no asset bundle).
  @visibleForTesting
  void loadMap(Map<String, dynamic> map) {
    _cfg = map;
    _loaded = true;
  }

  Map<String, dynamic> _section(String key) {
    if (!_loaded || _cfg == null) {
      throw StateError('ConfigService.load() must be awaited before read');
    }
    return (_cfg![key] as Map<String, dynamic>).cast<String, dynamic>();
  }

  // credential (8.6)
  String get credentialStorageTierLabel =>
      _section('credential')['storageTierLabel'] as String;
  String get credentialKeyPrefix => _section('credential')['keyPrefix'] as String;

  // pipeline (8.8)
  String get pipelineCommand => _section('pipeline')['command'] as String;
  List<String> get pipelineArgs =>
      (_section('pipeline')['args'] as List).cast<String>();
  String get pipelineStateDir => _section('pipeline')['stateDir'] as String;
  String get pipelineRepoConfigPath =>
      _section('pipeline')['repoConfigPath'] as String;

  // harness (8.10)
  String get harnessCommand => _section('harness')['command'] as String;
  String get harnessEnvHint => _section('harness')['envHint'] as String;

  // mcp (8.9)
  List<Map<String, dynamic>> get mcpServers => (_section('mcp')['servers']
          as List)
      .cast<Map<dynamic, dynamic>>()
      .map((e) => e.cast<String, dynamic>())
      .toList();

  // launch (8.13)
  bool get autoLaunchShowcase =>
      _section('launch')['autoLaunchShowcase'] as bool;
  String get firstRunKey => _section('launch')['firstRunKey'] as String;

  // licence (8.12)
  String get licencePreconditionMessage =>
      _section('licence')['preconditionMessage'] as String;
}
