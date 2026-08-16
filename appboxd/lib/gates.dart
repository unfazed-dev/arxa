// Gate framework — shared infrastructure for all appbox gates.
//
// Ports gates/_common/ from bash+python to pure Dart:
//   state_reader.sh  → StateReader
//   sarif.sh          → SarifBuilder
//   design_hash.sh    → designHash()
//   porcelain_diff.sh → assertTreeClean()
//   report.sh         → GateResult
//
// Exit code convention: 0 pass / 1 FAIL / 2 env or not-applicable.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:appboxd/crypto_aead.dart' as crypto;

/// Exit codes matching the bash gate contract.
const passExit = 0;
const failExit = 1;
const envExit = 2;

/// Context passed to every gate — the Dart equivalent of sourced _common/ helpers.
class GateContext {
  final String repoRoot;
  final String? appRoot;
  final StateReader state;
  final SarifBuilder sarif;
  final bool check;
  final bool selfTest;

  /// The studio's own design, relative to the app/repo root. ONE canonical
  /// default so emit verbs, gates and the intake output default cannot drift:
  /// v2 (hub-hosted stage shells, stacked MVVM) replaced v1 as the studio
  /// design on 2026-08-16; v1 stays in-tree as the retained visual-parity
  /// reference (VISUAL PARITY LAW, designs/appbox-studio-v2/intake/registry.json).
  static const studioDesignDir = 'designs/appbox-studio-v2';

  /// The `~/.appbox/projects/<name>` shell a gate should read instead of the
  /// studio's own design root. It lives on the context rather than as a named
  /// parameter on each gate so that `gate --all` can carry it: the suite runner
  /// takes only a context, so a per-gate parameter was unreachable from there
  /// and `--all --project x` silently ignored the flag. Only gates that
  /// actually read a project shell consume it (intake, today).
  final String? project;

  /// Override for the entitlement token path (default
  /// `~/.appbox/entitlement.jwt`). Same on-the-context rationale as [project];
  /// only gates with an entitlement assertion consume it (scaffold, today).
  /// NOT a bypass — the file it names still must verify, be unexpired, and be
  /// bound to this machine's fingerprint.
  final String? entitlementPath;

  GateContext({
    required this.repoRoot,
    this.appRoot,
    StateReader? state,
    SarifBuilder? sarif,
    this.check = false,
    this.selfTest = false,
    this.project,
    this.entitlementPath,
  })  : state = state ?? StateReader(repoRoot),
        sarif = sarif ?? SarifBuilder();

  /// The design root, derived from appRoot or repoRoot.
  String get designRoot => appRoot != null
      ? '$appRoot/$studioDesignDir'
      : '$repoRoot/$studioDesignDir';

  /// Path to config/appbox.config.json.
  String get configFile => '$repoRoot/config/appbox.config.json';
}

/// Result of running a gate.
class GateResult {
  final bool passed;
  final int exitCode;
  final String summary;
  final List<String> details;

  GateResult({
    required this.passed,
    required this.exitCode,
    required this.summary,
    this.details = const [],
  });

  factory GateResult.ok(String summary, [List<String>? details]) =>
      GateResult(passed: true, exitCode: passExit, summary: summary, details: details ?? const []);

  factory GateResult.fail(String summary, [List<String>? details]) =>
      GateResult(passed: false, exitCode: failExit, summary: summary, details: details ?? const []);

  factory GateResult.env(String summary) =>
      GateResult(passed: false, exitCode: envExit, summary: summary);
}

// ── StateReader (port of state_reader.sh) ──────────────────────────

/// Reads/writes pipeline state JSON.
/// Path: APPBOX_STATE → pipeline/state/run.state.json → pipeline/state/default.state.json.
class StateReader {
  final String _repoRoot;
  final String? overridePath;

  StateReader(this._repoRoot, {this.overridePath});

  /// The active state file path.
  String get stateFile {
    if (overridePath != null && File(overridePath!).existsSync()) {
      return overridePath!;
    }
    final live = '$_repoRoot/pipeline/state/run.state.json';
    if (File(live).existsSync()) return live;
    return '$_repoRoot/pipeline/state/default.state.json';
  }

  /// Whether the state file is the tracked seed (read-only).
  bool get isReadOnly => stateFile.endsWith('default.state.json');

  /// Read a top-level field. Returns null if missing.
  dynamic get(String field) {
    final data = _read();
    return data[field];
  }

  /// Read the targets array.
  List<String> get targets {
    final data = _read();
    final raw = data['targets'];
    if (raw is List) return raw.cast<String>();
    return [];
  }

  /// Write a top-level scalar field to LIVE state. No-op on the seed.
  /// Returns false if the seed is active (callers note-and-skip).
  bool set(String field, String value) {
    if (isReadOnly) return false;
    final data = _read();
    data[field] = value;
    _write(data);
    return true;
  }

  Map<String, dynamic> _read() {
    final f = File(stateFile);
    if (!f.existsSync()) return {};
    return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  }

  void _write(Map<String, dynamic> data) {
    File(stateFile).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(data)}\n',
    );
  }
}

// ── SarifBuilder (port of sarif.sh) ────────────────────────────────

/// Accumulates SARIF 2.1 results for machine-readable gate output.
class SarifBuilder {
  final results = <Map<String, dynamic>>[];

  void result(String ruleId, String level, String file, String message) {
    results.add({
      'ruleId': ruleId,
      'level': level,
      'locations': [
        {
          'physicalLocation': {
            'artifactLocation': {'uri': file},
          }
        }
      ],
      'message': {'text': message},
    });
  }

  /// Flush as a complete SARIF 2.1 document.
  String flush() {
    final doc = {
      r'$schema': 'https://json.schemastore.org/sarif-2.1.0.json',
      'version': '2.1.0',
      'runs': [
        {
          'tool': {
            'driver': {
              'name': 'appbox-gates',
              'informationUri': 'https://example.invalid',
            }
          },
          'results': results,
        }
      ],
    };
    return const JsonEncoder.withIndent('  ').convert(doc);
  }
}

// ── DesignHash (port of design_hash.sh) ────────────────────────────

/// SHA-256 of a design tree: sorted relative paths + NUL + raw contents.
/// Excludes .DS_Store and approval.lock (volatile).
String designHash(String designDir) {
  final dir = Directory(designDir);
  if (!dir.existsSync()) {
    throw ArgumentError('designHash: no design dir at $designDir');
  }

  final exclude = {'.DS_Store', 'approval.lock'};
  final paths = <String>[];

  void walk(Directory d, String prefix) {
    final entries = d.listSync()..sort((a, b) => a.path.compareTo(b.path));
    for (final entry in entries) {
      // entry.uri.pathSegments.last returns '' for directories on macOS
      // (Directory URIs carry a trailing slash → empty trailing segment), so
      // derive the name from the path itself.
      final name = entry.path.substring(entry.path.lastIndexOf('/') + 1);
      if (entry is Directory) {
        walk(entry, '$prefix$name/');
      } else if (entry is File && !exclude.contains(name)) {
        paths.add(prefix + name);
      }
    }
  }

  walk(dir, '');
  paths.sort();

  // Concatenate path + NUL + file contents for every file, then hash once.
  // Same result as incremental updates — SHA-256 is over the concatenation.
  final buf = <int>[];
  for (final rel in paths) {
    buf.addAll(utf8.encode(rel));
    buf.add(0); // NUL
    buf.addAll(File('${dir.path}/$rel').readAsBytesSync());
  }
  final digest = crypto.sha256(Uint8List.fromList(buf));
  return digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Assert the design tree matches the frozen hash. Returns null if fresh,
/// or an error message if moved. Fail-open on empty/missing hash (legacy).
String? assertDesignFresh(GateContext ctx) {
  final stored = ctx.state.get('designHash') as String?;
  if (stored == null || stored.isEmpty) {
    return null; // legacy — fail-open
  }
  final dir = Directory(ctx.designRoot);
  if (!dir.existsSync()) return null; // gate's own input checks apply

  final current = designHash(ctx.designRoot);
  if (current == stored) return null; // fresh

  return 'designHash: the design moved after freeze — state has '
      '${stored.substring(0, 12)}…, the tree hashes to '
      '${current.substring(0, 12)}… (§6 hash-bound approval). Re-freeze or restore.';}

// ── PorcelainDiff (port of porcelain_diff.sh) ──────────────────────

/// Check git working tree is clean via `git status --porcelain`.
/// Returns null if clean, or a list of dirty paths if not.
List<String>? assertTreeClean(String repoRoot) {
  final result = Process.runSync('git', ['status', '--porcelain'], workingDirectory: repoRoot);
  final output = (result.stdout as String).trim();
  if (output.isEmpty) return null;
  return output.split('\n');
}
