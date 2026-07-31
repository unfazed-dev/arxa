// macOS native capture (ScreenCaptureKit) — compile-on-demand + shot wrapper,
// command-shape tests under a scripted ProcessRunner. Mirrors the
// lens_adb_test.dart faking pattern: each expectation is an (argvPrefix,
// RunnerResult) tuple; the runner asserts sck.dart issues the exact swiftc /
// helper commands in order, with NO real ScreenCaptureKit grant and NO real
// capture. Plan: appbox-lens-full-port.md, Task 10.

import 'dart:io';

import 'package:appboxd/lens/native/adb.dart';
import 'package:appboxd/lens/native/sck.dart';
import 'package:appboxd/process.dart';
import 'package:test/test.dart';

/// One scripted command expectation: the argv prefix the port must issue and
/// the result to return. [onMatch] runs when the command matches, so a faked
/// compile can leave the cached binary on disk for the port to observe.
class _Expect {
  final List<String> prefix;
  final RunnerResult result;
  final void Function(List<String> argv)? onMatch;
  const _Expect(this.prefix, this.result, [this.onMatch]);
}

/// Fake runner: asserts argv prefix in order (deploy ScriptedRunner pattern),
/// plus an optional per-match side effect (file creation) for the compile step.
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
      throw StateError('sck port issued an unexpected extra command: $argv');
    }
    final e = _expects[_i];
    if (!_prefixMatch(argv, e.prefix)) {
      throw StateError('sck port called the wrong command:\n'
          '  expected prefix ${e.prefix}\n'
          '  got                  $argv');
    }
    e.onMatch?.call(argv);
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

/// A temp source + cache pair sharing one cleaned-up temp dir.
class _Paths {
  _Paths(this.dir, this.source, this.cache);
  final Directory dir;
  final String source;
  final String cache;
}

_Paths _paths() {
  final dir = Directory.systemTemp.createTempSync('lens_sck_test');
  addTearDown(() => dir.deleteSync(recursive: true));
  return _Paths(
    dir,
    '${dir.path}/lens_native.swift',
    '${dir.path}/.dart_tool/appboxd/lens_native',
  );
}

/// Writes a source file and (optionally) a cache binary. [cacheAge] ages the
/// cache mtime backwards so the stale-check path can be exercised.
void _writeSource(_Paths p, {Duration cacheAge = Duration.zero, bool withCache = false}) {
  File(p.source).writeAsStringSync('// swift source\n');
  if (withCache) {
    File(p.cache).parent.createSync(recursive: true);
    File(p.cache).writeAsBytesSync([0]);
    if (cacheAge != Duration.zero) {
      File(p.cache).setLastModifiedSync(DateTime.now().subtract(cacheAge));
    }
  }
}

void main() {
  group('ensureLensNativeBinary — compile-on-demand', () {
    test('missing cache: which swiftc -> swiftc -O <src> -o <cache>', () async {
      final p = _paths();
      _writeSource(p); // no cache -> compile path
      final runner = _ScriptedRunner([
        _Expect(['which', 'swiftc'],
            const RunnerResult(0, '/usr/bin/swiftc\n', '')),
        _Expect(['swiftc', '-O', p.source, '-o', p.cache],
            const RunnerResult(0, '', '')),
      ]);
      final bin = await ensureLensNativeBinary(
          runner: runner, source: p.source, cache: p.cache);
      expect(bin, p.cache);
      expect(runner.callCount, 2, reason: 'which + compile');
    });

    test('fresh cache present: no runner calls, returns cache immediately', () async {
      final p = _paths();
      _writeSource(p, withCache: true); // cache newer than source -> skip
      final runner = _ScriptedRunner(const []); // any call = failure
      final bin = await ensureLensNativeBinary(
          runner: runner, source: p.source, cache: p.cache);
      expect(bin, p.cache);
      expect(runner.callCount, 0);
    });

    test('stale cache (older than source): recompiles', () async {
      final p = _paths();
      _writeSource(p, withCache: true, cacheAge: const Duration(hours: 1));
      final runner = _ScriptedRunner([
        _Expect(['which', 'swiftc'], const RunnerResult(0, '/usr/bin/swiftc\n', '')),
        _Expect(['swiftc', '-O', p.source, '-o', p.cache], const RunnerResult(0, '', '')),
      ]);
      await ensureLensNativeBinary(runner: runner, source: p.source, cache: p.cache);
      expect(runner.callCount, 2);
    });

    test('swiftc absent: which rc!=0 -> LensNativeException with Xcode CLT remediation',
        () async {
      final p = _paths();
      _writeSource(p);
      final runner = _ScriptedRunner([
        _Expect(['which', 'swiftc'], const RunnerResult(1, '', 'not found')),
      ]);
      await expectLater(
        ensureLensNativeBinary(runner: runner, source: p.source, cache: p.cache),
        throwsA(isA<LensNativeException>()
            .having((e) => e.toString(), 'msg', contains('xcode-select'))),
      );
    });

    test('swiftc compile failure -> LensNativeException carrying stderr', () async {
      final p = _paths();
      _writeSource(p);
      final runner = _ScriptedRunner([
        _Expect(['which', 'swiftc'], const RunnerResult(0, '/usr/bin/swiftc\n', '')),
        _Expect(['swiftc', '-O', p.source, '-o', p.cache],
            const RunnerResult(1, '', 'error: cannot find type')),
      ]);
      await expectLater(
        ensureLensNativeBinary(runner: runner, source: p.source, cache: p.cache),
        throwsA(isA<LensNativeException>()
            .having((e) => e.toString(), 'msg', contains('cannot find type'))),
      );
    });
  });

  group('LensSck.tccOk', () {
    test('rc 0 -> true', () async {
      final p = _paths();
      _writeSource(p, withCache: true);
      final runner = _ScriptedRunner([
        _Expect([p.cache, 'tcc-check'], const RunnerResult(0, '', '')),
      ]);
      expect(await LensSck(runner: runner, source: p.source, cache: p.cache).tccOk(), isTrue);
    });

    test('rc 3 -> false', () async {
      final p = _paths();
      _writeSource(p, withCache: true);
      final runner = _ScriptedRunner([
        _Expect([p.cache, 'tcc-check'], const RunnerResult(3, '', 'denied')),
      ]);
      expect(await LensSck(runner: runner, source: p.source, cache: p.cache).tccOk(), isFalse);
    });
  });

  group('LensSck.shot', () {
    test('preflights tcc-check (rc 0) then shot <out> rc 0', () async {
      final p = _paths();
      _writeSource(p, withCache: true);
      final out = '${p.dir.path}/out.png';
      final runner = _ScriptedRunner([
        _Expect([p.cache, 'tcc-check'], const RunnerResult(0, '', '')),
        _Expect([p.cache, 'shot', out], const RunnerResult(0, '', ''),
            (argv) => File(argv[2]).writeAsBytesSync([137, 80, 78, 71])),
      ]);
      await LensSck(runner: runner, source: p.source, cache: p.cache).shot(out);
      expect(File(out).existsSync(), isTrue);
    });

    test('--window-id N is passed through', () async {
      final p = _paths();
      _writeSource(p, withCache: true);
      final out = '${p.dir.path}/w.png';
      final runner = _ScriptedRunner([
        _Expect([p.cache, 'tcc-check'], const RunnerResult(0, '', '')),
        _Expect([p.cache, 'shot', out, '--window-id', '42'],
            const RunnerResult(0, '', ''),
            (argv) => File(argv[2]).writeAsBytesSync([0])),
      ]);
      await LensSck(runner: runner, source: p.source, cache: p.cache)
          .shot(out, windowId: 42);
      expect(runner.callCount, 2);
    });

    test('tcc-check rc 3 -> LensNativeException with Screen Recording remediation',
        () async {
      final p = _paths();
      _writeSource(p, withCache: true);
      final runner = _ScriptedRunner([
        _Expect([p.cache, 'tcc-check'], const RunnerResult(3, '', 'denied')),
      ]);
      await expectLater(
        LensSck(runner: runner, source: p.source, cache: p.cache).shot('out.png'),
        throwsA(isA<LensNativeException>()
            .having((e) => e.toString(), 'msg', allOf(
                contains('Screen Recording'),
                contains('Privacy & Security')))),
      );
      expect(runner.callCount, 1, reason: 'shot not attempted when tcc denied');
    });

    test('shot rc != 0 -> LensNativeException carrying stderr', () async {
      final p = _paths();
      _writeSource(p, withCache: true);
      final runner = _ScriptedRunner([
        _Expect([p.cache, 'tcc-check'], const RunnerResult(0, '', '')),
        _Expect([p.cache, 'shot', 'out.png'], const RunnerResult(1, '', 'shot failed')),
      ]);
      await expectLater(
        LensSck(runner: runner, source: p.source, cache: p.cache).shot('out.png'),
        throwsA(isA<LensNativeException>()
            .having((e) => e.toString(), 'msg', contains('shot failed'))),
      );
    });
  });
}
