import 'dart:convert';
import 'dart:io';

/// The daemon's runtime config: the app-side sections of the legacy
/// `appbox.config.json` merged with `companion.config.json` into the planned
/// single-config shape (one file, companion values under a `companion`
/// section — superseded merge plan step 4; R3 forbids literals in code).
///
/// The repo-level `config/appbox.config.json` stays the pipeline's SSOT for
/// targets/kit SHA; this loader holds runtime values only (credential,
/// pipeline, harness, mcp, launch, licence, prototype, intake, companion).
class RuntimeConfig {
  RuntimeConfig(this._cfg);

  final Map<String, dynamic> _cfg;

  /// Test seam — build from an in-memory map (no file system).
  factory RuntimeConfig.fromMap(Map<String, dynamic> map) =>
      RuntimeConfig(map);

  /// Merges the app config with the companion config into the single-config
  /// shape: every top-level section of [appConfig] is kept verbatim, and the
  /// companion file's sections land under one `companion` object.
  static Map<String, dynamic> mergeMaps(
    Map<String, dynamic> appConfig,
    Map<String, dynamic>? companionConfig,
  ) {
    final merged = Map<String, dynamic>.of(appConfig);
    if (companionConfig != null) {
      final companion = Map<String, dynamic>.of(companionConfig)
        ..remove('_comment');
      merged['companion'] = companion;
    }
    return merged;
  }

  /// Loads and merges the two legacy config files. [companionPath] may be
  /// absent — the companion section is then simply missing (pre-merge repos).
  static RuntimeConfig load(String appConfigPath, {String? companionPath}) {
    final app = _readJson(appConfigPath);
    Map<String, dynamic>? companion;
    if (companionPath != null && File(companionPath).existsSync()) {
      companion = _readJson(companionPath);
    }
    return RuntimeConfig(mergeMaps(app, companion));
  }

  static Map<String, dynamic> _readJson(String path) =>
      (jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>)
          .cast<String, dynamic>();

  Map<String, dynamic> _section(String key) {
    final s = _cfg[key];
    if (s is! Map) {
      throw StateError('RuntimeConfig: missing section "$key"');
    }
    return s.cast<String, dynamic>();
  }

  bool hasSection(String key) => _cfg[key] is Map;

  // credential — the daemon holds the vault (8.6)
  String get credentialKeyPrefix => _section('credential')['keyPrefix'] as String;
  String get credentialStorageTierLabel =>
      _section('credential')['storageTierLabel'] as String;

  // pipeline (8.8) — command shape comes from config, never a literal (R3)
  String get pipelineCommand => _section('pipeline')['command'] as String;
  List<String> get pipelineArgs =>
      (_section('pipeline')['args'] as List).cast<String>();
  String get pipelineStateDir => _section('pipeline')['stateDir'] as String;
  String get pipelineRepoConfigPath =>
      _section('pipeline')['repoConfigPath'] as String;

  // harness (8.10) — an already-authenticated CLI the daemon shells out to
  String get harnessCommand => _section('harness')['command'] as String;
  String get harnessEnvHint => _section('harness')['envHint'] as String;

  // intake (10) — headless elicitation engine via the ProcessRunner seam
  String get intakeCommand => _section('intake')['command'] as String;
  String get intakeScript => _section('intake')['script'] as String;

  // licence (8.12) — a precondition, never a gate
  String get licencePreconditionMessage =>
      _section('licence')['preconditionMessage'] as String;

  // launch (8.13) — first-run flag lives in the vault, not a credential
  bool get autoLaunchDemo => _section('launch')['autoLaunchDemo'] as bool;
  String get firstRunKey => _section('launch')['firstRunKey'] as String;

  // prototype (09)
  String get prototypeHost => _section('prototype')['host'] as String;
  int get prototypePort => _section('prototype')['port'] as int;

  // mcp (8.9)
  List<Map<String, dynamic>> get mcpServers => (_section('mcp')['servers']
          as List)
      .cast<Map<dynamic, dynamic>>()
      .map((e) => e.cast<String, dynamic>())
      .toList();

  // --- companion section (from companion.config.json) -----------------------
  Map<String, dynamic> _companion(String key) =>
      _section('companion')[key] as Map<String, dynamic>;

  // channel liveness (12.x) — heartbeat cadence + dead threshold
  int get channelHeartbeatIntervalMs =>
      _companion('channel')['heartbeatIntervalMs'] as int;
  int get channelHeartbeatTimeoutMs =>
      _companion('channel')['heartbeatTimeoutMs'] as int;
  int get channelDeadAfterFailures =>
      _companion('channel')['deadAfterFailures'] as int;

  // discovery (12.5 — LAN-only pairing, no cloud relay)
  String get bonjourServiceType =>
      _companion('discovery')['bonjourServiceType'] as String;
  String get bonjourDomain => _companion('discovery')['bonjourDomain'] as String;

  // pairing (12.4 — QR-relay defense)
  int get qrRotationSeconds => _companion('pairing')['qrRotationSeconds'] as int;
  int get sessionIdleTimeoutSeconds =>
      _companion('pairing')['sessionIdleTimeoutSeconds'] as int;

  // readyLine (P09 spawn contract)
  String get readyLineTag => _companion('readyLine')['tag'] as String;
}
