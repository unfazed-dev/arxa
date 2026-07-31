// gen_freshness.dart — the generated-layer freshness gate. Port of
// gen_freshness.py.
//
// Pure code, no analyzer. flutter_crew commits the GENERATED layer
// (`app.router.dart`, `app.locator.dart`, `*.gen.dart`) to VCS as a
// reproducibility proof (byte-identical-within-platform across runs). But a
// committed generated file can go STALE: a build_runner run against
// out-of-date source regenerates it wrong, and nothing re-verifies. This gate
// regenerates the layer from source into a TEMP copy, then diffs each committed
// generated file against its fresh output. Any diff → FAIL (drift detected).
//
// The temp copy exists so build_runner's writes never touch the real target
// (the gate is side-effect-free on the tree it inspects). It does NOT gitignore
// generated files — that would break the reproducibility guarantee; instead it
// VERIFIES the committed layer equals a fresh regeneration.
//
// Usage (via the CLI): appbox gate gen-freshness --target <dir>

import 'dart:io';

import 'package:appboxd/crypto_aead.dart' as crypto;
import 'package:path/path.dart' as p;

/// The committed generated suffixes that must equal a fresh regeneration.
/// `*.gen.dart` is the build_runner output for @StackedApp VMs;
/// router/locator are @StackedApp.
const genSuffixes = ['.router.dart', '.locator.dart', '.gen.dart'];

/// A build_runner invocation: regenerates generated files into `<workDir>/lib`.
/// Returns (ok, log). Injected in tests so the comparator half runs offline
/// (build_runner needs Flutter and cannot run in CI) — the default shells out
/// via [_buildRunner]. Same seam pattern as process.dart's ProcessRunner.
typedef BuildRunnerFn = Future<({bool ok, String log})> Function(
    String targetDir, String workDir);

/// Result of running [genFreshness]. Mirrors the Python dict shape:
/// `{passed, drifted:[{file, reason?, committedSha?, freshSha?}],
/// freshN, logTail, buildFailed?}`.
class GenFreshnessResult {
  final bool passed;
  final List<Map<String, String>> drifted;
  final int freshN;
  final String logTail;
  final bool? buildFailed;

  GenFreshnessResult({
    required this.passed,
    required this.drifted,
    required this.freshN,
    required this.logTail,
    this.buildFailed,
  });
}

/// Diff committed generated files vs a fresh `build_runner` regeneration.
///
/// `passed` is false iff any committed generated file differs from its fresh
/// output — the drift this gate exists to catch. Side-effect-free: the
/// regeneration runs in a temp copy so the real target is never written.
///
/// [buildRunner] is injectable for tests; the default runs
/// `dart run build_runner build --delete-conflicting-outputs`.
Future<GenFreshnessResult> genFreshness(
  String targetDir, {
  BuildRunnerFn? buildRunner,
}) async {
  final gen = _genFiles(targetDir)..sort();
  if (gen.isEmpty) {
    return GenFreshnessResult(
      passed: true,
      drifted: const [],
      freshN: 0,
      logTail: '',
    );
  }

  final work = await Directory.systemTemp.createTemp('gen_fresh_');
  try {
    final built = await (buildRunner ?? _buildRunner)(targetDir, work.path);
    if (!built.ok) {
      return GenFreshnessResult(
        passed: false,
        drifted: const [],
        freshN: 0,
        logTail: _tail(built.log, 2000),
        buildFailed: true,
      );
    }
    final drifted = <Map<String, String>>[];
    for (final rel in gen) {
      final committed = p.join(targetDir, 'lib', rel);
      final fresh = p.join(work.path, 'lib', rel);
      // a committed generated file absent from fresh output = the generator
      // stopped emitting it (a stale orphan still in VCS) → drift.
      if (!File(fresh).existsSync()) {
        drifted.add({'file': rel, 'reason': 'committed but not regenerated'});
        continue;
      }
      if (!_filesEqual(committed, fresh)) {
        drifted.add({
          'file': rel,
          'committedSha': _shaFile(committed),
          'freshSha': _shaFile(fresh),
        });
      }
    }
    return GenFreshnessResult(
      passed: drifted.isEmpty,
      drifted: drifted,
      freshN: gen.length,
      logTail: _tail(built.log, 800),
    );
  } finally {
    if (work.existsSync()) work.deleteSync(recursive: true);
  }
}

/// The committed generated files under `<targetDir>/lib`. Returns posix
/// relpaths (relative to `lib/`). Skips `build/` dirs (regenerable, never
/// source) and anything outside lib/. Port of Python `_gen_files`.
List<String> _genFiles(String targetDir) {
  final lib = Directory(p.join(targetDir, 'lib'));
  if (!lib.existsSync()) return const [];
  final out = <String>[];
  void walk(Directory d) {
    for (final entry in d.listSync()) {
      if (entry is Directory) {
        // never descend into a build dir (regenerable artifacts, never source)
        if (p.basename(entry.path) == 'build') continue;
        walk(entry);
      } else if (entry is File) {
        final name = p.basename(entry.path);
        if (genSuffixes.any(name.endsWith)) {
          out.add(p
              .relative(entry.path, from: lib.path)
              .replaceAll('\\', '/'));
        }
      }
    }
  }

  walk(lib);
  return out;
}

/// Copy lib + pubspec + analysis_options + .dart_tool (deps cache) into
/// [workDir], then run build_runner there so its writes never touch the real
/// target. lib is copied (build_runner rewrites *.gen.dart there). Returns
/// (ok, log). Port of Python `_build_runner`.
Future<({bool ok, String log})> _buildRunner(
    String targetDir, String workDir) async {
  const names = [
    'lib',
    'pubspec.yaml',
    'pubspec.lock',
    'analysis_options.yaml',
    '.dart_tool',
  ];
  for (final name in names) {
    final src = p.join(targetDir, name);
    final dst = p.join(workDir, name);
    final type = FileSystemEntity.typeSync(src);
    if (type == FileSystemEntityType.directory) {
      _copyTree(Directory(src), Directory(dst));
    } else if (type == FileSystemEntityType.file) {
      File(src).copySync(dst);
    }
  }
  try {
    final r = await Process.run(
      'dart',
      ['run', 'build_runner', 'build', '--delete-conflicting-outputs'],
      workingDirectory: workDir,
      runInShell: true,
    );
    return (ok: r.exitCode == 0, log: '${r.stdout}${r.stderr}');
  } catch (e) {
    return (ok: false, log: e.toString());
  }
}

/// Recursive copy that skips `build/` subtrees (regenerable, never source).
void _copyTree(Directory src, Directory dst) {
  dst.createSync(recursive: true);
  for (final entry in src.listSync()) {
    if (entry is Directory) {
      if (p.basename(entry.path) == 'build') continue;
      _copyTree(entry, Directory(p.join(dst.path, p.basename(entry.path))));
    } else if (entry is File) {
      entry.copySync(p.join(dst.path, p.basename(entry.path)));
    }
  }
}

/// Byte-exact file comparison (mirrors Python's `filecmp.cmp(shallow=False)`).
bool _filesEqual(String a, String b) {
  final ab = File(a).readAsBytesSync();
  final bb = File(b).readAsBytesSync();
  if (ab.length != bb.length) return false;
  for (var i = 0; i < ab.length; i++) {
    if (ab[i] != bb[i]) return false;
  }
  return true;
}

/// SHA-256 hex of a file, truncated to 12 chars (the report fingerprint).
/// Reuses the zero-dependency SHA-256 already shipped in crypto_aead.dart.
String _shaFile(String path) {
  final digest = crypto.sha256(File(path).readAsBytesSync());
  return digest
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .substring(0, 12);
}

String _tail(String s, int n) => s.length > n ? s.substring(s.length - n) : s;
