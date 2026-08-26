// arxa project — the ~/.arxa layout resolver.
//
// One convention, every consumer: user projects live in
// `~/.arxa/projects/<name>/` with four self-contained shell dirs —
// intake/ (answers, brief, registry, flows, story-map outputs),
// design/ (seeds, surfaces/partials, l10n), build/ (evidence),
// settings/ (project.json). The studio design server live-reads the
// current project; the pipeline emits into it. The studio's OWN design
// stays in the repo — ~/.arxa holds user projects only.
//
// ARXA_HOME overrides ~/.arxa (tests, sandboxes). `current` is a
// one-line file naming the active project (default 'portalo').
// Determinism: project.json carries no clock fields — emitted artifacts
// must be byte-identical for identical inputs.

import 'dart:convert';
import 'dart:io';

/// The shell dirs every project gets, in canonical order.
const projectShells = ['intake', 'design', 'build', 'settings'];

/// The fallback project when no `current` file exists.
const defaultProject = 'portalo';

String _homeDir() =>
    Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';

/// Test hook: when set, wins over ARXA_HOME and ~/.arxa.
String? arxaHomeOverride;

/// The arxa home (`~/.arxa` or $ARXA_HOME).
String arxaHome() => arxaHomeOverride ??
    Platform.environment['ARXA_HOME'] ??
    '${_homeDir()}/.arxa';

String projectsDir() => '${arxaHome()}/projects';

String projectDir(String name) => '${projectsDir()}/$name';

String shellDir(String name, String shell) => '${projectDir(name)}/$shell';

String projectSettingsPath(String name) => '${shellDir(name, 'settings')}/project.json';

/// Project ids are directory names: lowercase alnum + dash, like surface ids.
final _nameRe = RegExp(r'^[a-z][a-z0-9]*(-[a-z0-9]+)*$');

bool validProjectName(String name) => _nameRe.hasMatch(name);

/// Every project directory name, sorted (deterministic listing).
List<String> listProjects() {
  final dir = Directory(projectsDir());
  if (!dir.existsSync()) return const [];
  final names = dir
      .listSync()
      .whereType<Directory>()
      .map((d) => d.uri.pathSegments.where((s) => s.isNotEmpty).last)
      .toList()
    ..sort();
  return names;
}

/// The active project: the `current` file's contents, else [defaultProject].
String currentProject() {
  final f = File('${arxaHome()}/current');
  final name = f.existsSync() ? f.readAsStringSync().trim() : '';
  return name.isNotEmpty ? name : defaultProject;
}

/// Point `current` at an existing project. Throws ArgumentError otherwise.
void useProject(String name) {
  if (!Directory(projectDir(name)).existsSync()) {
    throw ArgumentError('no such project: $name (init it first)');
  }
  File('${arxaHome()}/current')
    ..createSync(recursive: true)
    ..writeAsStringSync('$name\n');
}

/// Create the project layout + settings/project.json. Idempotent: existing
/// dirs are kept, a missing project.json is (re)written, an existing one is
/// left untouched (init never clobbers project state).
void ensureProject(String name, {List<String> targets = const ['ios', 'android'], List<String> locales = const ['en']}) {
  if (!validProjectName(name)) {
    throw ArgumentError('bad project name "$name" — lowercase alnum + dash, like a surface id');
  }
  for (final shell in projectShells) {
    Directory(shellDir(name, shell)).createSync(recursive: true);
  }
  final settings = File(projectSettingsPath(name));
  if (!settings.existsSync()) {
    // Deterministic content: no created/timestamp fields.
    const encoder = JsonEncoder.withIndent('  ');
    settings.writeAsStringSync('${encoder.convert({
      'name': name,
      'targets': targets,
      'locales': locales,
    })}\n');
  }
}

/// Sync targets/locales into settings/project.json from the elicited intake
/// answers. Init flags are a guess made BEFORE any conversation; the answers
/// are the founder-stated SSOT, so `intake emit --project` overwrites with
/// them (emit syncs — unlike init, which never clobbers). Partial: only the
/// fields passed are written; `name` and any other keys are preserved.
/// Creates the project first when missing (emit on a fresh ARXA_HOME).
void updateProjectSettings(String name, {List<String>? targets, List<String>? locales}) {
  ensureProject(name);
  final settings = readProjectSettings(name) ?? <String, dynamic>{};
  if (targets != null) settings['targets'] = targets;
  if (locales != null) settings['locales'] = locales;
  const encoder = JsonEncoder.withIndent('  ');
  File(projectSettingsPath(name))
      .writeAsStringSync('${encoder.convert(settings)}\n');
}

/// Read settings/project.json; null when absent (a pre-init or foreign dir).
Map<String, dynamic>? readProjectSettings(String name) {
  final f = File(projectSettingsPath(name));
  if (!f.existsSync()) return null;
  return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
}

/// The stage a project has reached, derived DETERMINISTICALLY from which
/// outputs exist (never stored, never guessed):
///   build/ holds any evidence json          -> gates
///   design/models/design_model/run.en.json  -> build
///   intake/registry.json                    -> design
///   otherwise                               -> intake
String projectStage(String name) {
  final dir = projectDir(name);
  final buildDir = Directory('$dir/build');
  if (buildDir.existsSync() &&
      buildDir
          .listSync(recursive: true)
          .whereType<File>()
          .any((f) => f.path.endsWith('.json'))) {
    return 'gates';
  }
  if (File('$dir/design/models/design_model/run.en.json').existsSync()) {
    return 'build';
  }
  if (File('$dir/intake/registry.json').existsSync()) return 'design';
  return 'intake';
}

/// One dashboard card per project: name/targets/locales from settings, the
/// derived stage, and honest output counts (surfaces/flows) — no timestamps,
/// no fabricated activity.
List<Map<String, dynamic>> projectCards() {
  return [
    for (final name in listProjects())
      <String, dynamic>{
        'name': name,
        'targets':
            (readProjectSettings(name)?['targets'] as List?)?.cast<String>() ??
                const [],
        'stage': projectStage(name),
        'surfaces': _countJsonList('${projectDir(name)}/intake/registry.json'),
        'flows': _countJsonList('${projectDir(name)}/intake/flows.json'),
      },
  ];
}

int _countJsonList(String path) {
  final f = File(path);
  if (!f.existsSync()) return 0;
  try {
    final v = jsonDecode(f.readAsStringSync());
    return v is List ? v.length : 0;
  } catch (_) {
    return 0;
  }
}
