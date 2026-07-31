import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'fabric.dart';
import 'gateway.dart' show TokenMinter;
import 'gate_runner.dart' show gateOrder;
import 'memory.dart';
import 'memory_cache.dart';
import 'memory_curate.dart';
import 'process.dart';

/// The deterministic stage-runner (decision E3,
/// docs/plans/appbox-engine-llm-fabric.md). appboxd owns the pipeline FSM:
/// stages come from gates/ on disk, each stage runs headless through the
/// Kimi CLI pointed at the loopback gateway (E2), and every run leaves a
/// manifest + a scorecard line under pipeline/state/.

/// Retryable exit code per the plan (E3, "0/1/75-retryable").
/// kimi 0.29.2 was observed to exit only 0/1; kept so a CLI build that
/// emits 75 routes to retry instead of a hard failure.
const exitRetryable = 75;

/// One pipeline stage. The single source of truth is the filesystem:
/// [loadStages] reads gates/ and gates/run_all.sh at load — nothing here is
/// a hardcoded copy of the FSM.
class Stage {
  Stage({required this.name, required this.gate, required this.tier});

  /// Gate directory name under gates/ (intake, freeze, structure, …).
  final String name;

  /// The gate command, e.g. ['bash', 'gates/intake/intake.sh'] — resolved
  /// from the entry script that actually exists in the gate dir.
  final List<String> gate;

  /// Fabric tier default for this stage, from config/model-fabric.json's
  /// stages{} table (E4). Null = the fabric pins the stage non-LLM
  /// (`gates`-style: deterministic code, no model).
  final String? tier;

  Map<String, Object?> toJson() => {'name': name, 'gate': gate, 'tier': tier};
}

/// Stage → tier lookup into the fabric catalog (E4 owns the real map).
/// Returns null when the catalog is missing/unparseable — callers then
/// fall back to `standard` per stage.
Map<String, String?>? _fabricStageTiers(String repoRoot) {
  final file = File(p.join(repoRoot, 'config', 'model-fabric.json'));
  if (!file.existsSync()) return null;
  try {
    final fabric = ModelFabric.parse(file.readAsStringSync());
    return {for (final s in fabric.stages.values) s.stage: s.tier};
  } on FormatException {
    return null;
  }
}

// kimitail: fallback is 'standard' for any stage the fabric does not name
// (and for a missing/unparseable catalog) — the middle tier keeps the
// pipeline moving without silently downgrading the E4-pinned frontier
// stages, which do have entries. Fabric stages with tier null stay null
// (non-LLM).
String? _stageTier(Map<String, String?>? fabricTiers, String name) {
  if (fabricTiers == null || !fabricTiers.containsKey(name)) return 'standard';
  return fabricTiers[name];
}

/// Loads the stage registry. Stages are the Dart gate order from
/// [gateOrder] — the gates are in-process Dart, no filesystem scan.
/// Tiers come from the fabric catalog (E4) via [_stageTier].
List<Stage> loadStages(String repoRoot) {
  final fabricTiers = _fabricStageTiers(repoRoot);
  return [
    for (final name in gateOrder)
      Stage(name: name, gate: const [], tier: _stageTier(fabricTiers, name)),
  ];
}

/// Fabric tiers ordered frontier → fast; escalation is one tier up (E4:
/// gate fail → re-run that stage one tier up, bounded once).
const _tierOrder = ['frontier', 'standard', 'fast'];

/// The tiers a stage token may request: the stage's own tier plus one tier
/// up for escalation. Frontier has nothing above it; an unknown tier mints
/// scoped to itself only.
List<String> escalationTiers(String tier) {
  final i = _tierOrder.indexOf(tier);
  if (i <= 0) return [tier];
  return [tier, _tierOrder[i - 1]];
}

/// Per-run manifest at `pipeline/state/runs/<run_id>.json` — the
/// checkpoint/resume record (E3.3).
class RunManifest {
  RunManifest({
    required this.runId,
    required this.stage,
    required this.startedAt,
    required this.finishedAt,
    required this.exitCode,
    required this.retries,
    this.sessionId,
    this.cacheHit = false,
  });

  factory RunManifest.fromJson(Map<String, Object?> json) => RunManifest(
        runId: json['run_id'] as String,
        stage: json['stage'] as String,
        startedAt: json['started_at'] as String,
        finishedAt: json['finished_at'] as String,
        exitCode: json['exit_code'] as int,
        retries: json['retries'] as int? ?? 0,
        sessionId: json['session_id'] as String?,
        cacheHit: json['cache_hit'] as bool? ?? false,
      );

  final String runId;
  final String stage;
  final String startedAt;
  final String finishedAt;
  final int exitCode;
  final int retries;

  /// True when the run was served from the response cache (M2) — the CLI
  /// was never spawned, so tokens are null, never fabricated.
  final bool cacheHit;

  /// Kimi CLI session id, from the stream-json `session.resume_hint` line —
  /// what `kimi -r` resumes.
  final String? sessionId;

  Map<String, Object?> toJson() => {
        'run_id': runId,
        'stage': stage,
        'started_at': startedAt,
        'finished_at': finishedAt,
        'exit_code': exitCode,
        'session_id': sessionId,
        'retries': retries,
        'cache_hit': cacheHit,
      };
}

File _manifestFile(String repoRoot, String runId) =>
    File(p.join(repoRoot, 'pipeline', 'state', 'runs', '$runId.json'));

Future<void> writeManifest(String repoRoot, RunManifest manifest) async {
  final file = _manifestFile(repoRoot, manifest.runId);
  await file.parent.create(recursive: true);
  await file.writeAsString('${const JsonEncoder.withIndent('  ').convert(manifest.toJson())}\n');
}

Future<RunManifest> readManifest(String repoRoot, String runId) async =>
    RunManifest.fromJson(
        jsonDecode(await _manifestFile(repoRoot, runId).readAsString())
            as Map<String, Object?>);

/// Appends one scorecard line to pipeline/state/scorecard.jsonl (E4).
/// Tokens/cost come from stream-json usage when present, else null —
/// never fabricated.
Future<void> appendScorecard(String repoRoot, Map<String, Object?> entry) async {
  final file = File(p.join(repoRoot, 'pipeline', 'state', 'scorecard.jsonl'));
  await file.parent.create(recursive: true);
  await file.writeAsString('${jsonEncode(entry)}\n', mode: FileMode.append);
}

/// The outcome of one headless stage run.
class StageRun {
  StageRun({
    required this.manifest,
    required this.stdout,
    required this.stderr,
    this.tokensIn,
    this.tokensOut,
  });

  final RunManifest manifest;

  /// Raw stream-json stdout, kept whole for debugging.
  final String stdout;

  /// stderr is captured, never swallowed.
  final String stderr;
  final int? tokensIn;
  final int? tokensOut;

  int get exitCode => manifest.exitCode;
  bool get retryable => manifest.exitCode == exitRetryable;
}

/// The headless runner adapter (E3.2): one stage =
/// `kimi -p "<skill prompt>" --output-format=stream-json`, with the CLI
/// config pointed at the loopback gateway and a stage-scoped token.
///
/// Verified against kimi 0.29.2 (2026-07-30):
/// - print mode is `-p`/`--prompt` — there is NO `--print` or `--afk`;
///   `--auto` and `-y` are both rejected with `-p` ("Cannot combine
///   --prompt with --auto/--yolo"), so headless autonomy comes from
///   `default_permission_mode = "auto"` in the pre-written config.
/// - resume is `-r <session_id>` (hidden alias of `-S`/`--session`).
/// - stream-json emits `{role:...}` NDJSON lines; the session id arrives in
///   a trailing `{"role":"meta","type":"session.resume_hint","session_id"}`
///   line. No usage/token lines observed → scorecard tokens stay null.
class Engine {
  Engine({
    required this.repoRoot,
    this.gatewayPort = 8787,
    this.kimiCommand = 'kimi',
    // The daemon's one TokenMinter, shared with the Gateway so minted stage
    // tokens verify at /llm. Null in hermetic tests → placeholder tokens.
    this._minter,
    List<Stage>? stagesOverride,
    ProcessRunner? runner,
  })  : _stages = stagesOverride,
        _runner = runner ?? const RealProcessRunner();

  final String repoRoot;
  final int gatewayPort;
  final String kimiCommand;

  final TokenMinter? _minter;

  /// Stage override seam for tests (and embedders); null reads gates/ live.
  final List<Stage>? _stages;
  final ProcessRunner _runner;

  List<Stage> get stages => _stages ?? loadStages(repoRoot);

  /// The stage-scoped token seam (E2/E3): mints a token scoped to the
  /// stage's tier plus one tier up (gate-fail escalation, E4). The
  /// APPBOX_STAGE_TOKEN env override wins (manual runs); without a minter
  /// (or for a non-LLM stage) the placeholder keeps hermetic runs working.
  /// This is the ONE place token injection lives — swap the body, not callers.
  String stageToken(Stage stage) {
    final override = Platform.environment['APPBOX_STAGE_TOKEN'];
    if (override != null) return override;
    final minter = _minter;
    final tier = stage.tier;
    if (minter == null || tier == null) return 'appbox-stage-token-TODO';
    return minter.mint(
      consumer: 'pipeline-stage:${stage.name}',
      tiers: escalationTiers(tier),
    );
  }

  /// Runs [stageName] headless, writes the run manifest, and appends the
  /// scorecard line. With [resume], continues the stage's most recent
  /// recorded session (`-r <session_id>`). [gatePass] is the deterministic
  /// gate's verdict when it has already run, else null.
  ///
  /// M2: before spawning, the exact-match response cache (keyed stage,
  /// model-or-tier, prompt) is consulted — a hit skips the CLI entirely and
  /// records `cache_hit` on the manifest/scorecard with null tokens (never
  /// fabricated). Successful runs (exit 0) are cached; failures never are.
  Future<StageRun> runStage(
    String stageName, {
    required String prompt,
    bool resume = false,
    int retries = 0,
    bool? gatePass,
    String? provider,
    String? model,
    Map<String, String> environment = const {},
  }) async {
    final stage = stages.firstWhere(
      (s) => s.name == stageName,
      orElse: () => throw ArgumentError('unknown stage: $stageName'),
    );
    final sessionId = resume ? _lastSessionId(stageName) : null;
    final startedAt = DateTime.now().toUtc().toIso8601String();
    final runId =
        '${stage.name}-${DateTime.now().toUtc().microsecondsSinceEpoch}';

    // M2: the cache key uses the run's model, else the stage's fabric tier
    // (a tier pins a model per the E4 catalog), else a non-LLM marker.
    final cache = ResponseCache(repoRoot: repoRoot);
    final cacheModel = model ?? stage.tier ?? 'none';
    final cached = cache.get(stage.name, cacheModel, prompt);
    final cacheHit = cached != null;

    String runStdout;
    var runStderr = '';
    var exitCode = 0;
    String? parsedSessionId;
    int? tokensIn;
    int? tokensOut;

    if (cached != null) {
      runStdout = cached;
    } else {
      final kimiHome = _writeKimiHome(stageToken(stage));
      try {
        final result = await _runner.run(
          kimiCommand,
          [
            if (sessionId != null) ...['-r', sessionId],
            '-p', prompt,
            '--output-format=stream-json',
          ],
          environment: {'KIMI_CODE_HOME': kimiHome.path, ...environment},
          workingDirectory: repoRoot,
        );
        runStdout = result.stdout;
        runStderr = result.stderr;
        exitCode = result.exitCode;
        final parsed = _parseStreamJson(result.stdout);
        parsedSessionId = parsed.sessionId;
        tokensIn = parsed.tokensIn;
        tokensOut = parsed.tokensOut;
        // Only exit-0 runs are cached; a cache write failure warns,
        // never fails the stage run.
        if (result.exitCode == 0) {
          try {
            cache.put(stage.name, cacheModel, prompt, result.stdout);
          } catch (e) {
            stderr.writeln('engine: WARN response cache put failed: $e');
          }
        }
      } finally {
        try {
          kimiHome.deleteSync(recursive: true);
        } on FileSystemException {
          // Temp-dir cleanup is best-effort.
        }
      }
    }

    final manifest = RunManifest(
      runId: runId,
      stage: stage.name,
      startedAt: startedAt,
      finishedAt: DateTime.now().toUtc().toIso8601String(),
      exitCode: exitCode,
      retries: retries,
      sessionId: parsedSessionId ?? sessionId,
      cacheHit: cacheHit,
    );
    await writeManifest(repoRoot, manifest);
    await appendScorecard(repoRoot, {
      'stage': stage.name,
      'tier': stage.tier,
      'provider': provider,
      'model': model,
      'tokens_in': tokensIn,
      'tokens_out': tokensOut,
      // kimitail: pricing lives in the E4 fabric catalog — null until
      // that wiring lands, never estimated here.
      'cost': null,
      'gate_pass': gatePass,
      'retries': retries,
      'cache_hit': cacheHit,
    });
    // M1: the engine is a deterministic writer of raw memory events.
    // Best-effort — a logging failure warns, never fails the stage run.
    try {
      await EventLog(p.join(repoRoot, 'pipeline', 'state'))
          .append(MemoryEvent(
        kind: MemoryKinds.stageRun,
        actor: 'engine',
        payload: {
          'stage': stage.name,
          'exit_code': manifest.exitCode,
          'retries': retries,
          'session_id': manifest.sessionId,
          'cache_hit': cacheHit,
          // gate_pass only when the gate verdict is already known.
          'gate_pass': ?gatePass,
        },
      ));
    } catch (e) {
      stderr.writeln('engine: WARN memory event append failed: $e');
    }
    // M1: an observed gate failure is the sole lesson-write trigger
    // (memory_curate.dart refuses anything else). Best-effort — a missing
    // LESSONS.md or other curation failure warns, never fails the run.
    if (gatePass == false) {
      try {
        final firstStderr = runStderr
            .split('\n')
            .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
        MemoryCurator(Directory(p.join(repoRoot, 'memory'))).appendLesson(
          stage.name,
          'gate ${stage.name} failed (exit $exitCode)'
          '${firstStderr.isEmpty ? '' : '; stderr: $firstStderr'}',
          gateFailed: true,
        );
      } catch (e) {
        stderr.writeln('engine: WARN lesson append failed: $e');
      }
    }
    return StageRun(
      manifest: manifest,
      stdout: runStdout,
      stderr: runStderr,
      tokensIn: tokensIn,
      tokensOut: tokensOut,
    );
  }

  /// The most recent manifest for [stage] that recorded a resumable
  /// session, or null.
  String? _lastSessionId(String stage) {
    final runsDir = Directory(p.join(repoRoot, 'pipeline', 'state', 'runs'));
    if (!runsDir.existsSync()) return null;
    RunManifest? latest;
    for (final file in runsDir.listSync().whereType<File>()) {
      if (!file.path.endsWith('.json')) continue;
      try {
        final manifest = RunManifest.fromJson(
            jsonDecode(file.readAsStringSync()) as Map<String, Object?>);
        if (manifest.stage == stage && manifest.sessionId != null) {
          if (latest == null ||
              manifest.startedAt.compareTo(latest.startedAt) > 0) {
            latest = manifest;
          }
        }
      } on FormatException {
        // A corrupt manifest must not break resume — skip it.
      }
    }
    return latest?.sessionId;
  }

  /// Pre-writes a throwaway KIMI_CODE_HOME whose config.toml points the CLI
  /// at the loopback gateway (E2). There is no `--config` flag;
  /// KIMI_CODE_HOME is the documented relocation mechanism.
  Directory _writeKimiHome(String token) {
    final dir = Directory.systemTemp.createTempSync('appbox-kimi-');
    File(p.join(dir.path, 'config.toml')).writeAsStringSync('''
default_model = "appbox/stage"
default_permission_mode = "auto"

[providers.appbox]
type = "openai"
base_url = "http://127.0.0.1:$gatewayPort/llm/v1"
api_key = "$token"

[models."appbox/stage"]
provider = "appbox"
model = "appbox-stage"
max_context_size = 262144
''');
    return dir;
  }
}

({String? sessionId, int? tokensIn, int? tokensOut}) _parseStreamJson(
    String stdout) {
  String? sessionId;
  int? tokensIn;
  int? tokensOut;
  for (final line in const LineSplitter().convert(stdout)) {
    if (line.trim().isEmpty) continue;
    Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      continue; // Non-JSON noise on stdout is skipped, not fatal.
    }
    if (decoded is! Map) continue;
    if (decoded['type'] == 'session.resume_hint' &&
        decoded['session_id'] is String) {
      sessionId = decoded['session_id'] as String;
    }
    final usage = decoded['usage'];
    if (usage is Map) {
      tokensIn ??= _asInt(usage['input_tokens'] ?? usage['prompt_tokens']);
      tokensOut ??= _asInt(usage['output_tokens'] ?? usage['completion_tokens']);
    }
  }
  return (sessionId: sessionId, tokensIn: tokensIn, tokensOut: tokensOut);
}

int? _asInt(Object? value) =>
    value is int ? value : (value is num ? value.toInt() : null);
