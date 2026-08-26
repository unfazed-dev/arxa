// macOS Vision OCR + line diff — command-shape tests under a scripted
// ProcessRunner. The runner returns canned Vision JSON for `ocr` invocations;
// ocr.dart parses it and runs a pure-Dart LCS diff over the text lines. No real
// Vision call. Plan: arxa-lens-full-port.md, Task 10.

import 'dart:convert';
import 'dart:io';

import 'package:arxa/lens/native/adb.dart';
import 'package:arxa/lens/ocr.dart';
import 'package:arxa/process.dart';
import 'package:test/test.dart';

/// One scripted command expectation: argv prefix + the result to return.
class _Expect {
  final List<String> prefix;
  final RunnerResult result;
  const _Expect(this.prefix, this.result);
}

/// Fake runner: asserts argv prefix in order (lens_adb_test.dart pattern).
class _ScriptedRunner implements ProcessRunner {
  _ScriptedRunner(this._expects);
  final List<_Expect> _expects;
  var _i = 0;
  int get callCount => _i;

  @override
  Future<RunnerResult> run(
    String executable,
    List<String> args, {
    Map<String, String> environment = const {},
    String? workingDirectory,
  }) async {
    final argv = [executable, ...args];
    if (_i >= _expects.length) {
      throw StateError('ocr port issued an unexpected extra command: $argv');
    }
    final e = _expects[_i];
    if (!_prefixMatch(argv, e.prefix)) {
      throw StateError('ocr port called the wrong command:\n'
          '  expected prefix ${e.prefix}\n'
          '  got                  $argv');
    }
    _i++;
    return e.result;
  }
}

bool _prefixMatch(List<String> argv, List<String> prefix) {
  if (argv.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (argv[i] != prefix[i]) return false;
  }
  return true;
}

/// A temp source + cache pair sharing one cleaned-up temp dir, with a fresh
/// cache so ensureLensNativeBinary returns without compiling.
class _Paths {
  _Paths(this.source, this.cache);
  final String source;
  final String cache;
}

_Paths _paths() {
  final dir = Directory.systemTemp.createTempSync('lens_ocr_test');
  addTearDown(() => dir.deleteSync(recursive: true));
  final source = '${dir.path}/lens_native.swift';
  final cache = '${dir.path}/.dart_tool/arxa/lens_native';
  File(source).writeAsStringSync('// src\n');
  File(cache).parent.createSync(recursive: true);
  File(cache).writeAsBytesSync([0]); // fresh -> skip compile
  return _Paths(source, cache);
}

String _ocrJson(List<String> texts, [List<List<double>>? boxes]) {
  final observations = <Map<String, dynamic>>[];
  for (var i = 0; i < texts.length; i++) {
    observations.add({
      'text': texts[i],
      'confidence': 0.9,
      'bbox': boxes?[i] ?? [0.1, 0.2, 0.3, 0.4],
    });
  }
  return jsonEncode({'text': texts, 'observations': observations});
}

void main() {
  group('ocrText — <bin> ocr <png> -> JSON', () {
    test('parses {text, observations} from stdout', () async {
      final p = _paths();
      final runner = _ScriptedRunner([
        _Expect([p.cache, 'ocr', 'page.png'],
            RunnerResult(0, _ocrJson(['Hello', 'World']), '')),
      ]);
      final res = await ocrText('page.png', runner: runner, source: p.source, cache: p.cache);
      expect(res['text'], ['Hello', 'World']);
      final obs = (res['observations'] as List).cast<Map<String, dynamic>>();
      expect(obs.first['text'], 'Hello');
      expect(obs.first['confidence'], 0.9);
      expect(obs.first['bbox'], [0.1, 0.2, 0.3, 0.4]);
    });

    test('non-zero exit raises LensNativeException carrying stderr', () async {
      final p = _paths();
      final runner = _ScriptedRunner([
        _Expect([p.cache, 'ocr', 'bad.png'],
            const RunnerResult(2, '', 'unreadable image')),
      ]);
      await expectLater(
        ocrText('bad.png', runner: runner, source: p.source, cache: p.cache),
        throwsA(isA<LensNativeException>()
            .having((e) => e.toString(), 'msg', contains('unreadable image'))),
      );
    });
  });

  group('textDiffLines — pure-Dart LCS over lines', () {
    test('identical lines: all context (space-prefixed)', () {
      expect(textDiffLines(['a', 'b'], ['a', 'b']), [' a', ' b']);
    });

    test('line added in b: + prefixed', () {
      expect(textDiffLines(['a'], ['a', 'b']), [' a', '+b']);
    });

    test('line removed from b: - prefixed', () {
      expect(textDiffLines(['a', 'b'], ['a']), [' a', '-b']);
    });

    test('reordered lines emit both - and +', () {
      final d = textDiffLines(['a', 'b', 'c'], ['a', 'c', 'b']);
      expect(d.where((l) => l.startsWith('-')), isNotEmpty);
      expect(d.where((l) => l.startsWith('+')), isNotEmpty);
      // Common line `a` is preserved as context.
      expect(d.any((l) => l == ' a'), isTrue);
    });

    test('empty inputs produce empty diff', () {
      expect(textDiffLines([], []), isEmpty);
    });
  });

  group('textDiffPngs — OCR both then diff', () {
    test('runs ocr on both PNGs and returns the merged line diff', () async {
      final p = _paths();
      final runner = _ScriptedRunner([
        _Expect([p.cache, 'ocr', 'a.png'], RunnerResult(0, _ocrJson(['one', 'two']), '')),
        _Expect([p.cache, 'ocr', 'b.png'], RunnerResult(0, _ocrJson(['one', 'three']), '')),
      ]);
      final diff = await textDiffPngs('a.png', 'b.png',
          runner: runner, source: p.source, cache: p.cache);
      // `one` common, `two` removed (-), `three` added (+).
      expect(diff, containsAll([' one', '-two', '+three']));
      expect(runner.callCount, 2, reason: 'ocr a then ocr b');
    });

    test('identical text -> only context lines (no +/-)', () async {
      final p = _paths();
      final runner = _ScriptedRunner([
        _Expect([p.cache, 'ocr', 'a.png'], RunnerResult(0, _ocrJson(['x']), '')),
        _Expect([p.cache, 'ocr', 'b.png'], RunnerResult(0, _ocrJson(['x']), '')),
      ]);
      final diff = await textDiffPngs('a.png', 'b.png',
          runner: runner, source: p.source, cache: p.cache);
      expect(diff, [' x']);
      expect(diff.every((l) => !l.startsWith('-') && !l.startsWith('+')), isTrue);
    });
  });
}
