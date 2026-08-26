// capability_scan.dart — deterministic audio/video playback capability gate.
//
// Port of arxa_kit/tools/capability_scan.sh. Scans a CONSUMER app (the
// Flutter app in arxa/, or a generated target) for audio/video PLAYBACK
// signals, then cross-checks them against the app's capability manifest
// (docs/capability-manifest.md). [ok] is false when playback usage is present
// but undeclared — gates fail, not warn. [ok] is true when every detected
// signal is declared, or no signal exists.
//
// Signals (see docs/capability-detection.md for the full contract):
//   Dart    lib/**/*.dart, comments stripped:
//           audio — import of just_audio/audioplayers, or AudioPlayerService use
//           video — import of video_player/chewie/media_kit, or
//                   VideoPlayerService/VideoPlayerController/ChewieController use
//   pubspec dependencies (runtime only; dev_dependencies do not ship):
//           audio — just_audio, audioplayers
//           video — video_player, chewie, media_kit, media_kit_video
//           (a bare arxa_kit_media dep is NOT flagged: the kit mixes capture
//           and playback; usage is detected at the Dart import/symbol level)
//   native  audio — ios/**/Info.plist with UIBackgroundModes containing audio
//           video — android/**/AndroidManifest*.xml referencing media3/exoplayer
//
// Declaration convention: a table row in docs/capability-manifest.md whose text
// contains "audio playback" / "video playback" (case-insensitive). A `stubbed`
// row counts as declared (the manifest's accepted not-yet-proven status).

import 'dart:io';

import 'package:path/path.dart' as p;

const _audio = 'audio';
const _video = 'video';

/// Result of [scanCapabilities]. Mirrors the shell exit-code contract:
/// [ok] is true iff every detected signal is declared (or none was detected).
class CapabilityResult {
  /// Subset of {'audio', 'video'} actually seen in the app.
  final Set<String> signals;

  /// Human-readable evidence lines ('  [audio] lib/foo.dart: …').
  final List<String> evidence;

  /// Detected signals with no matching declaration in the manifest.
  final Set<String> undeclared;

  /// True when no signal is undeclared.
  final bool ok;

  CapabilityResult({
    required this.signals,
    required this.evidence,
    required this.undeclared,
    required this.ok,
  });
}

// ── comment stripping (same approach as the shell originals) ──────────────────
// Blocks first, then lines — matches capability_scan.sh. Naive regex strip is
// deliberate; this gate reads doc honesty, not a precise Dart lexer.
final _lineComment = RegExp(r'//[^\n]*');
final _blockComment = RegExp(r'/\*.*?\*/', dotAll: true);

String _stripDartComments(String src) {
  final noBlocks = src.replaceAll(_blockComment, '');
  return noBlocks.replaceAll(_lineComment, '');
}

// ── Dart signal patterns (identical to capability_scan.sh) ────────────────────
// (kind, matcher, evidence label).
final _signals = <(String, RegExp, String)>[
  (
    _audio,
    RegExp(r'''import\s+['"]package:(just_audio|audioplayers)/'''),
    'playback plugin import',
  ),
  (
    _video,
    RegExp(r'''import\s+['"]package:(video_player|chewie|media_kit)/'''),
    'playback plugin import',
  ),
  (
    _audio,
    RegExp(r'\bAudioPlayerService\b'),
    'arxa_kit_media AudioPlayerService',
  ),
  (
    _video,
    RegExp(r'\b(VideoPlayerService|VideoPlayerController|ChewieController)\b'),
    'video playback class',
  ),
];

const _depKind = <String, String>{
  'just_audio': _audio,
  'audioplayers': _audio,
  'video_player': _video,
  'chewie': _video,
  'media_kit': _video,
  'media_kit_video': _video,
};

/// Scan [appRoot] for audio/video playback capability signals and cross-check
/// them against the manifest at [manifestPath] (default
/// `$appRoot/docs/capability-manifest.md`).
CapabilityResult scanCapabilities(String appRoot, {String? manifestPath}) {
  final signals = <String>{};
  final evidence = <String>[];

  void hit(String kind, String where, String what) {
    signals.add(kind);
    evidence.add('  [$kind] $where: $what');
  }

  // --- 1. Dart signals in lib/ (comments stripped) ---
  for (final f in _dartFilesIn(p.join(appRoot, 'lib'))) {
    final code = _stripDartComments(_readOrEmpty(f));
    final rel = p.relative(f.path, from: appRoot);
    for (final (kind, rx, what) in _signals) {
      if (rx.hasMatch(code)) hit(kind, rel, what);
    }
  }

  // --- 2. pubspec runtime dependencies (dev_dependencies do not ship) ---
  _scanPubspec(appRoot, hit);

  // --- 3. native manifests ---
  _scanIos(appRoot, hit);
  _scanAndroid(appRoot, hit);

  // --- cross-check against the capability manifest ---
  final declared = _declaredCapabilities(
      manifestPath ?? p.join(appRoot, 'docs', 'capability-manifest.md'));
  final undeclared = signals.difference(declared);

  return CapabilityResult(
    signals: signals,
    evidence: evidence,
    undeclared: undeclared,
    ok: undeclared.isEmpty,
  );
}

/// Walk `dependencies:` (not dev_dependencies) of `$appRoot/pubspec.yaml`.
void _scanPubspec(String appRoot, void Function(String, String, String) hit) {
  final pub = File(p.join(appRoot, 'pubspec.yaml'));
  if (!pub.existsSync()) return;
  String? section; // 'deps' inside dependencies:, null elsewhere
  for (final line in pub.readAsLinesSync()) {
    if (RegExp(r'^dependencies:\s*$').hasMatch(line)) {
      section = 'deps';
    } else if (RegExp(r'^\S').hasMatch(line)) {
      // A top-level key (any non-whitespace in column 0) closes the section.
      section = null;
    } else if (section == 'deps') {
      final m = RegExp(r'^\s+([A-Za-z0-9_]+):').firstMatch(line);
      if (m != null) {
        final dep = m.group(1)!;
        final kind = _depKind[dep];
        if (kind != null) hit(kind, 'pubspec.yaml', "dependency '$dep'");
      }
    }
  }
}

void _scanIos(String appRoot, void Function(String, String, String) hit) {
  final ios = Directory(p.join(appRoot, 'ios'));
  if (!ios.existsSync()) return;
  for (final entry in ios.listSync(recursive: true)) {
    if (entry is! File) continue;
    if (entry.uri.pathSegments.last != 'Info.plist') continue;
    final txt = _readOrEmpty(entry);
    if (txt.contains('UIBackgroundModes') &&
        RegExp(r'<string>audio</string>').hasMatch(txt)) {
      hit(_audio, p.relative(entry.path, from: appRoot), 'UIBackgroundModes audio');
    }
  }
}

void _scanAndroid(String appRoot, void Function(String, String, String) hit) {
  final android = Directory(p.join(appRoot, 'android'));
  if (!android.existsSync()) return;
  for (final entry in android.listSync(recursive: true)) {
    if (entry is! File) continue;
    final name = entry.uri.pathSegments.last;
    if (!name.startsWith('AndroidManifest')) continue;
    final txt = _readOrEmpty(entry);
    if (RegExp(r'media3|exoplayer', caseSensitive: false).hasMatch(txt)) {
      hit(_video, p.relative(entry.path, from: appRoot),
          'ExoPlayer/media3 manifest reference');
    }
  }
}

/// Capabilities declared in the manifest: a `|`-table row containing
/// "audio playback" / "video playback" (case-insensitive).
Set<String> _declaredCapabilities(String manifestPath) {
  final f = File(manifestPath);
  if (!f.existsSync()) return <String>{};
  final body = f.readAsStringSync();
  final declared = <String>{};
  if (RegExp(r'^\|.*audio playback', caseSensitive: false, multiLine: true)
      .hasMatch(body)) {
    declared.add(_audio);
  }
  if (RegExp(r'^\|.*video playback', caseSensitive: false, multiLine: true)
      .hasMatch(body)) {
    declared.add(_video);
  }
  return declared;
}

// ── filesystem helpers ────────────────────────────────────────────────────────

List<File> _dartFilesIn(String dir) {
  final d = Directory(dir);
  if (!d.existsSync()) return const [];
  final out = <File>[];
  for (final entry in d.listSync(recursive: true)) {
    if (entry is File && entry.path.endsWith('.dart')) out.add(entry);
  }
  out.sort((a, b) => a.path.compareTo(b.path));
  return out;
}

String _readOrEmpty(File f) {
  try {
    return f.readAsStringSync();
  } catch (_) {
    return '';
  }
}
