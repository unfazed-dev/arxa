// repo_project — appbox law: an existing repo owns its pipeline state.
//
// When appbox runs inside a client repo that hosts one or more apps, ALL
// pipeline state lives in that repo, per app dir, never in ~/.appbox —
// ~/.appbox/projects/ is for appbox-NATIVE projects only (started by
// `appbox project init <name>` with no repo behind them). A project that
// exists in BOTH places is a fork waiting to drift, so it is a hard error,
// not a warning.
//
// Binding: each app dir carries an `appbox.json` marker (name, kind,
// targets, locales). Commands resolve by walking UP from cwd to the
// nearest marker — self-describing from any subdir, unambiguous when a
// repo hosts several apps (landing/ AND studio/).
//
// Stage layout (uniform for both kinds; the READMEs carry the per-kind
// stack differences — htmx+islands eject for sites, Flutter for apps):
//   intake/ moodboard/ design/ scaffold/ build/ test/ review/ deploy/
// Determinism: appbox.json carries no clock fields.

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/project.dart' show appboxHome, projectsDir, validProjectName;
import 'package:appboxd/stage_readmes.dart' show stageReadme;

/// The marker file name every app dir carries at its root.
const repoMarkerFile = 'appbox.json';

/// The stage folders a repo-mode app gets, in canonical order — the whole
/// pipeline, visible on day one, empty-but-promised (README explains what
/// starts each stage).
const repoStages = [
  'intake',
  'moodboard',
  'design',
  'scaffold',
  'build',
  'test',
  'review',
  'deploy',
];

/// The two product kinds. `site` = web/landing (htmx + islands, eject is
/// runnable site code); `app` = application (Flutter targets). NOT the same
/// axis as a target — a Flutter app may target `web` while being kind:app.
const repoKinds = ['site', 'app'];

/// A resolved repo-mode project.
class RepoProject {
  final String dir;
  final String name;
  final String kind;
  final List<String> targets;
  final List<String> locales;

  RepoProject(this.dir, this.name, this.kind, this.targets, this.locales);

  String stageDir(String stage) => '$dir/$stage';
}

/// Walk up from [from] (default cwd) to the nearest `appbox.json` marker.
/// Null when none is found before the filesystem root.
RepoProject? findRepoProject([String? from]) {
  var dir = Directory(from ?? Directory.current.path).absolute.path;
  while (true) {
    final marker = File('$dir/$repoMarkerFile');
    if (marker.existsSync()) {
      final p = _parseMarker(dir, marker);
      if (p != null) return p;
    }
    final parent = Directory(dir).parent.path;
    if (parent == dir) return null; // filesystem root
    dir = parent;
  }
}

/// The law's teeth: resolve the repo-mode project for [from] and REFUSE to
/// run when a same-named project shadows it in ~/.appbox/projects/. This is
/// the exact drift that produced two half-copies of energize's intake.
///
/// Returns null when no marker is found (plain ~/.appbox mode is then the
/// caller's business — this function only polices repo mode).
RepoProject? resolveRepoProject([String? from]) {
  final p = findRepoProject(from);
  if (p == null) return null;
  final shadow = Directory('${projectsDir()}/${p.name}');
  if (shadow.existsSync()) {
    throw StateError(
      'appbox law: an existing repo owns its pipeline state — project '
      '"${p.name}" exists BOTH at ${p.dir}/$repoMarkerFile and at '
      '${shadow.path}. Migrate the ~/.appbox copy into the repo (or remove '
      'it), then re-run. A project may not live in two places.',
    );
  }
  return p;
}

RepoProject? _parseMarker(String dir, File marker) {
  final Map<String, dynamic> raw;
  try {
    final v = jsonDecode(marker.readAsStringSync());
    if (v is! Map) return null;
    raw = v.cast<String, dynamic>();
  } catch (_) {
    return null; // a corrupt marker must not crash resolution
  }
  final name = raw['name'] is String ? raw['name'] as String : '';
  final kind = raw['kind'] is String ? raw['kind'] as String : '';
  if (name.isEmpty || !validProjectName(name)) return null;
  if (!repoKinds.contains(kind)) return null;
  return RepoProject(
    dir,
    name,
    kind,
    ((raw['targets'] as List?) ?? const []).cast<String>().toList(),
    ((raw['locales'] as List?) ?? const []).cast<String>().toList(),
  );
}

/// Create or refresh the repo-mode project at [dir]: marker + 8 stage dirs
/// + kind-aware READMEs. Idempotent — an existing marker is UPDATED to the
/// passed values (repo mode has one home, so there is nothing to clobber
/// across homes; `name` from an existing marker wins unless [name] is
/// passed explicitly). READMEs are rewritten every run (tool-owned).
///
/// Throws [ArgumentError] on a bad name/kind, and [StateError] on the
/// ~/.appbox shadow (same law as [resolveRepoProject]).
RepoProject ensureRepoProject(
  String dir, {
  String? name,
  String? kind,
  List<String> targets = const [],
  List<String> locales = const [],
}) {
  final k = kind ?? 'app';
  if (!repoKinds.contains(k)) {
    throw ArgumentError('bad kind "$k" — one of: ${repoKinds.join(', ')}');
  }
  final d = Directory(dir).absolute.path;
  final existing = _parseMarker(d, File('$d/$repoMarkerFile'));
  final n = name ?? existing?.name ?? _basename(d);
  if (!validProjectName(n)) {
    throw ArgumentError(
      'bad project name "$n" — lowercase alnum + dash, like a surface id',
    );
  }
  final shadow = Directory('${projectsDir()}/$n');
  if (shadow.existsSync()) {
    throw StateError(
      'appbox law: an existing repo owns its pipeline state — project "$n" '
      'already exists at ${shadow.path}. Migrate it into $d (or remove it) '
      'before initializing repo mode here.',
    );
  }
  const encoder = JsonEncoder.withIndent('  ');
  File('$d/$repoMarkerFile')
    ..createSync(recursive: true)
    ..writeAsStringSync('${encoder.convert({
      'name': n,
      'kind': k,
      'targets': targets,
      'locales': locales,
    })}\n');
  for (final stage in repoStages) {
    final sd = Directory('$d/$stage')..createSync(recursive: true);
    File('${sd.path}/README.md').writeAsStringSync(stageReadme(stage, k, n));
  }
  return RepoProject(d, n, k, targets, locales);
}

/// Sync kind/targets/locales from intake answers into the marker at [dir].
/// Partial like [updateProjectSettings]: only passed fields are written;
/// `name` is preserved. Creates nothing (the marker must exist — sync is
/// not init).
void updateRepoProject(
  String dir, {
  String? kind,
  List<String>? targets,
  List<String>? locales,
}) {
  final d = Directory(dir).absolute.path;
  final marker = File('$d/$repoMarkerFile');
  final existing = _parseMarker(d, marker);
  if (existing == null) {
    throw ArgumentError('no $repoMarkerFile at $d — run project init --repo first');
  }
  if (kind != null && !repoKinds.contains(kind)) {
    throw ArgumentError('bad kind "$kind" — one of: ${repoKinds.join(', ')}');
  }
  final updated = <String, dynamic>{
    'name': existing.name,
    'kind': kind ?? existing.kind,
    'targets': targets ?? existing.targets,
    'locales': locales ?? existing.locales,
  };
  const encoder = JsonEncoder.withIndent('  ');
  marker.writeAsStringSync('${encoder.convert(updated)}\n');
}

String _basename(String path) =>
    path.endsWith('/') ? path.substring(0, path.length - 1).split('/').last : path.split('/').last;

/// Exposed for tests/diagnostics: where repo-mode state would shadow.
String shadowPathFor(String name) => '${projectsDir()}/$name';

/// Human-readable resolution report for `appbox project resolve`.
String resolutionReport([String? from]) {
  final p = resolveRepoProject(from);
  if (p == null) {
    return 'repo mode: none (no $repoMarkerFile above ${from ?? Directory.current.path}) '
        '— ~/.appbox mode, current project resolution applies; home=${appboxHome()}';
  }
  return 'repo mode: ${p.name} (kind ${p.kind}) at ${p.dir} — '
      'targets=${p.targets.join(',')} locales=${p.locales.join(',')}';
}
