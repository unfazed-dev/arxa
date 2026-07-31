// capability_scan test — verifies the Dart port matches capability_scan.sh.
// Covers Dart import/symbol signals, pubspec runtime deps (dev deps excluded),
// undeclared-signal failure, comment stripping, and the clean-app pass.

import 'dart:io';

import 'package:appboxd/capability_scan.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('cap-scan-test-');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('clean app with no playback signals passes', () {
    _file(tmp, 'lib/main.dart',
        "import 'package:flutter/material.dart';\nvoid main() {}\n");
    final r = scanCapabilities(tmp.path);
    expect(r.ok, isTrue);
    expect(r.signals, isEmpty);
    expect(r.undeclared, isEmpty);
  });

  test('just_audio import signals audio; declared in manifest → ok', () {
    _file(tmp, 'lib/audio.dart',
        "import 'package:just_audio/just_audio.dart';\n");
    _manifest(tmp, '| audio playback | just_audio | stubbed |\n');
    final r = scanCapabilities(tmp.path);
    expect(r.signals, contains('audio'));
    expect(r.undeclared, isEmpty);
    expect(r.ok, isTrue);
    expect(r.evidence.any((e) => e.contains('playback plugin import')), isTrue);
  });

  test('ChewieController symbol signals video; declared → ok', () {
    _file(tmp, 'lib/video.dart', 'class C extends ChewieController {}\n');
    _manifest(tmp, '| video playback | chewie | stubbed |\n');
    final r = scanCapabilities(tmp.path);
    expect(r.signals, contains('video'));
    expect(r.ok, isTrue);
  });

  test('audio signal present but undeclared → fails', () {
    _file(tmp, 'lib/audio.dart',
        "import 'package:audioplayers/audioplayers.dart';\n");
    // Manifest declares only video; audio is missing.
    _manifest(tmp, '| video playback | video_player | declared |\n');
    final r = scanCapabilities(tmp.path);
    expect(r.signals, contains('audio'));
    expect(r.undeclared, contains('audio'));
    expect(r.ok, isFalse);
  });

  test('pubspec runtime dependency signals audio; dev_dependencies do NOT', () {
    _file(tmp, 'lib/x.dart', '// nothing playback-related here\n');
    _pubspec(tmp, [
      'dependencies:',
      '  just_audio: ^0.9.0',
      'dev_dependencies:',
      '  video_player: ^2.0.0', // dev — must not count as a shipped signal
      '',
    ]);
    _manifest(tmp, '| audio playback | just_audio | stubbed |\n');
    final r = scanCapabilities(tmp.path);
    expect(r.signals, contains('audio'));
    expect(r.signals, isNot(contains('video')),
        reason: 'dev_dependencies are not shipped signals');
    expect(r.ok, isTrue);
  });

  test('Dart comments are stripped — banned import in a comment is not a signal',
      () {
    _file(
      tmp,
      'lib/main.dart',
      "// import 'package:just_audio/just_audio.dart';\n"
      '/* class Foo extends AudioPlayerService {} */\n'
      '// uses VideoPlayerController in docs only\n'
      'void main() {}\n',
    );
    final r = scanCapabilities(tmp.path);
    expect(r.signals, isEmpty, reason: 'all references live inside comments');
    expect(r.ok, isTrue);
  });
}

/// Create a file (with parent dirs) and write [content].
void _file(Directory tmp, String relPath, String content) {
  final f = File('${tmp.path}/$relPath');
  f.createSync(recursive: true);
  f.writeAsStringSync(content);
}

void _manifest(Directory tmp, String content) =>
    _file(tmp, 'docs/capability-manifest.md', content);

void _pubspec(Directory tmp, List<String> lines) =>
    _file(tmp, 'pubspec.yaml', '${lines.join('\n')}\n');
