// Native adb capture verbs — command-shape tests under a scripted ProcessRunner.
//
// Mirrors deploy.dart's ScriptedRunner pattern: each expectation is an
// (argvPrefix, RunnerResult) tuple; the runner asserts the port issues the
// exact adb command shape, in order, with NO emulator and NO adb binary.
// Capture and observation only — interaction belongs to Patrol (capability-map
// Task 13). Plan: arxa-lens-full-port.md, Task 8.

import 'dart:convert';
import 'dart:io';

import 'package:arxa/lens/native/adb.dart';
import 'package:arxa/process.dart';
import 'package:test/test.dart';

/// One scripted adb command expectation: the argv prefix the port must issue
/// and the result to return. [onMatch] runs when the command matches, so the
/// `pull`/`cat` steps can leave a file on disk for the port to observe.
class _Expect {
  final List<String> prefix;
  final RunnerResult result;
  final void Function(List<String> argv)? onMatch;
  const _Expect(this.prefix, this.result, [this.onMatch]);
}

/// Fake adb: asserts argv prefix in order (deploy ScriptedRunner pattern),
/// plus an optional per-match side effect (file creation) for capture steps.
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
      throw StateError('adb port issued an unexpected extra command: $argv');
    }
    final e = _expects[_i];
    if (!_prefixMatch(argv, e.prefix)) {
      throw StateError('adb port called the wrong command:\n'
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

/// A temp path inside a fresh temp dir, cleaned up at test end.
String _tempPath(String name) {
  final dir = Directory.systemTemp.createTempSync('lens_adb_test');
  addTearDown(() => dir.deleteSync(recursive: true));
  return '${dir.path}/$name';
}

// PNG signature bytes round-tripped through a String (the seam is String-only,
// so the port re-encodes via latin1). Re-encoding must be lossless for 0–255.
const _pngMagic = [137, 80, 78, 71, 13, 10, 26, 10];
final _pngStdout = String.fromCharCodes(_pngMagic);

void main() {
  group('shot — exec-out screencap', () {
    test('runs adb -s <serial> exec-out screencap -p, writes PNG bytes', () async {
      final out = _tempPath('out.png');
      final runner = _ScriptedRunner([
        _Expect(
          ['adb', '-s', 'emulator-5554', 'exec-out', 'screencap', '-p'],
          RunnerResult(0, _pngStdout, ''),
        ),
      ]);
      await LensAdb(serial: 'emulator-5554', runner: runner).shot(out);
      expect(runner.callCount, 1, reason: 'shot issues exactly one adb command');
      final bytes = File(out).readAsBytesSync();
      expect(bytes, equals(_pngMagic));
    });

    test('creates parent dirs for the out path', () async {
      final out = _tempPath('nested/deep/out.png');
      final runner = _ScriptedRunner([
        _Expect(
          ['adb', '-s', 's1', 'exec-out', 'screencap', '-p'],
          RunnerResult(0, _pngStdout, ''),
        ),
      ]);
      await LensAdb(serial: 's1', runner: runner).shot(out);
      expect(File(out).existsSync(), isTrue);
    });

    test('non-zero exit raises LensNativeException carrying stderr', () async {
      final runner = _ScriptedRunner([
        _Expect(
          ['adb', '-s', 's1', 'exec-out', 'screencap', '-p'],
          RunnerResult(1, '', 'ERROR: device not found; boot an emulator'),
        ),
      ]);
      await expectLater(
        () => LensAdb(serial: 's1', runner: runner).shot(_tempPath('x.png')),
        throwsA(isA<LensNativeException>()
            .having((e) => e.toString(), 'msg', contains('device not found'))),
      );
    });
  });

  group('record — shell screenrecord then pull then rm', () {
    test('issues screenrecord -> pull -> rm in order', () async {
      final out = _tempPath('rec.mp4');
      final runner = _ScriptedRunner([
        _Expect(
          ['adb', '-s', 's1', 'shell', 'screenrecord', '--time-limit', '5',
           '/sdcard/lens-record.mp4'],
          const RunnerResult(0, '', ''),
        ),
        _Expect(
          ['adb', '-s', 's1', 'pull', '/sdcard/lens-record.mp4', out],
          const RunnerResult(0, '', ''),
          (argv) => File(argv.last).writeAsBytesSync([0, 0, 0]),
        ),
        _Expect(
          ['adb', '-s', 's1', 'shell', 'rm', '/sdcard/lens-record.mp4'],
          const RunnerResult(0, '', ''),
        ),
      ]);
      await LensAdb(serial: 's1', runner: runner).record(out, seconds: 5);
      expect(runner.callCount, 3, reason: 'record = screenrecord + pull + rm');
      expect(File(out).existsSync(), isTrue);
    });

    test('screenrecord failure raises LensNativeException', () async {
      final runner = _ScriptedRunner([
        _Expect(
          ['adb', '-s', 's1', 'shell', 'screenrecord', '--time-limit', '10',
           '/sdcard/lens-record.mp4'],
          const RunnerResult(1, '', 'screenrecord: video encoder init failed'),
        ),
      ]);
      await expectLater(
        () => LensAdb(serial: 's1', runner: runner).record(_tempPath('r.mp4')),
        throwsA(isA<LensNativeException>()
            .having((e) => e.toString(), 'msg', contains('video encoder'))),
      );
    });

    test('missing pulled file raises LensNativeException', () async {
      final out = _tempPath('gone.mp4');
      final runner = _ScriptedRunner([
        _Expect(
          ['adb', '-s', 's1', 'shell', 'screenrecord', '--time-limit', '10',
           '/sdcard/lens-record.mp4'],
          const RunnerResult(0, '', ''),
        ),
        // pull returns OK but (no onMatch) leaves NO file on disk.
        _Expect(
          ['adb', '-s', 's1', 'pull', '/sdcard/lens-record.mp4', out],
          const RunnerResult(0, '', ''),
        ),
        _Expect(
          ['adb', '-s', 's1', 'shell', 'rm', '/sdcard/lens-record.mp4'],
          const RunnerResult(0, '', ''),
        ),
      ]);
      await expectLater(
        () => LensAdb(serial: 's1', runner: runner).record(out),
        throwsA(isA<LensNativeException>()
            .having((e) => e.toString(), 'msg', contains('no file'))),
      );
    });

    test('seconds over the 180s platform cap is rejected before any shell', () async {
      final runner = _ScriptedRunner(const []);
      await expectLater(
        () => LensAdb(serial: 's1', runner: runner).record(_tempPath('r.mp4'),
            seconds: 181),
        throwsA(isA<LensNativeException>()
            .having((e) => e.toString(), 'msg', contains('180'))),
      );
      expect(runner.callCount, 0, reason: 'cap checked before shelling out');
    });
  });

  group('devices — adb devices parse', () {
    test('parses a single connected device', () async {
      final runner = _ScriptedRunner([
        _Expect(['adb', 'devices'],
            const RunnerResult(0, 'List of devices attached\nemulator-5554\tdevice\n', '')),
      ]);
      final d = await LensAdb(serial: 'ignored', runner: runner).devices();
      expect(d, [
        {'serial': 'emulator-5554', 'state': 'device'},
      ]);
    });

    test('flags offline/unauthorized with a warning field; ready device is clean', () async {
      final stdout = 'List of devices attached\n'
          'emulator-5554\tdevice\n'
          'emulator-5556\toffline\n'
          'emulator-5558\tunauthorized\n';
      final runner = _ScriptedRunner([
        _Expect(['adb', 'devices'], RunnerResult(0, stdout, '')),
      ]);
      final d = await LensAdb(serial: 'ignored', runner: runner).devices();
      final bySerial = {for (final e in d) e['serial']!: e};
      expect(bySerial['emulator-5554']!['state'], 'device');
      expect(bySerial['emulator-5554']!.containsKey('warning'), isFalse);
      expect(bySerial['emulator-5556']!['state'], 'offline');
      expect(bySerial['emulator-5556']!.containsKey('warning'), isTrue,
          reason: 'offline device carries a warning');
      expect(bySerial['emulator-5558']!['state'], 'unauthorized');
      expect(bySerial['emulator-5558']!.containsKey('warning'), isTrue);
    });
  });

  group('openUrl — am start VIEW', () {
    test('runs shell am start -a android.intent.action.VIEW -d <url>', () async {
      final runner = _ScriptedRunner([
        _Expect(
          ['adb', '-s', 's1', 'shell', 'am', 'start', '-a',
           'android.intent.action.VIEW', '-d', 'https://example.com'],
          const RunnerResult(0, '', ''),
        ),
      ]);
      await LensAdb(serial: 's1', runner: runner).openUrl('https://example.com');
      expect(runner.callCount, 1);
    });

    test('non-zero exit raises LensNativeException', () async {
      final runner = _ScriptedRunner([
        _Expect(
          ['adb', '-s', 's1', 'shell', 'am', 'start', '-a',
           'android.intent.action.VIEW', '-d', 'https://example.com'],
          const RunnerResult(1, '', 'Error: Activity not started'),
        ),
      ]);
      await expectLater(
        () => LensAdb(serial: 's1', runner: runner).openUrl('https://example.com'),
        throwsA(isA<LensNativeException>()
            .having((e) => e.toString(), 'msg', contains('Activity not started'))),
      );
    });
  });

  group('uiTree — uiautomator dump -> JSON node list', () {
    // uiautomator dumps a flat-nested <node> hierarchy; the port parses the
    // class/text/bounds attributes with a RegExp (no XML dependency).
    const dumpXml =
        '<?xml version=\'1.0\' encoding=\'UTF-8\' standalone=\'yes\' ?>\n'
        '<hierarchy rotation="0">\n'
        '<node index="0" text="" class="android.widget.FrameLayout" '
        'package="com.example" content-desc="" checkable="false" '
        'bounds="[0,0][1080,2400]">\n'
        '<node index="1" text="Sign in" class="android.widget.Button" '
        'content-desc="" checkable="false" bounds="[100,200][400,300]" />\n'
        '</node>\n'
        '</hierarchy>\n';

    test('parses bounds [x1,y1][x2,y2] into [x,y,w,h]', () async {
      final runner = _ScriptedRunner([
        _Expect(
          ['adb', '-s', 's1', 'shell', 'uiautomator', 'dump', '/sdcard/lens-ui.xml'],
          const RunnerResult(0, '', ''),
        ),
        _Expect(
          ['adb', '-s', 's1', 'shell', 'cat', '/sdcard/lens-ui.xml'],
          RunnerResult(0, dumpXml, ''),
        ),
      ]);
      final nodes = await LensAdb(serial: 's1', runner: runner).uiTree();
      // The outer frame and the inner button both match the node pattern.
      final frame = nodes.firstWhere((n) => n['class'] == 'android.widget.FrameLayout');
      expect(frame['bounds'], [0, 0, 1080, 2400]);
      expect(frame['text'], '');

      final btn = nodes.firstWhere((n) => n['class'] == 'android.widget.Button');
      expect(btn['text'], 'Sign in');
      expect(btn['bounds'], [100, 200, 300, 100]); // w=400-100, h=300-200
    });
  });

  group('serial resolution order', () {
    test('explicit serial wins; devices() is NOT called', () async {
      // Only one expectation: the shot command. devices() must not run.
      final runner = _ScriptedRunner([
        _Expect(
          ['adb', '-s', 'explicit-1', 'exec-out', 'screencap', '-p'],
          RunnerResult(0, _pngStdout, ''),
        ),
      ]);
      await LensAdb(serial: 'explicit-1', runner: runner).shot(_tempPath('o.png'));
      expect(runner.callCount, 1);
    });

    test('ARXA_ADB_SERIAL env resolves when no explicit serial', () async {
      final runner = _ScriptedRunner([
        _Expect(
          ['adb', '-s', 'env-serial', 'exec-out', 'screencap', '-p'],
          RunnerResult(0, _pngStdout, ''),
        ),
      ]);
      await LensAdb(
        runner: runner,
        env: const {'ARXA_ADB_SERIAL': 'env-serial'},
      ).shot(_tempPath('o.png'));
      expect(runner.callCount, 1);
    });

    test('single connected device is auto-picked', () async {
      final runner = _ScriptedRunner([
        _Expect(['adb', 'devices'],
            const RunnerResult(0, 'List of devices attached\nemulator-5554\tdevice\n', '')),
        _Expect(
          ['adb', '-s', 'emulator-5554', 'exec-out', 'screencap', '-p'],
          RunnerResult(0, _pngStdout, ''),
        ),
      ]);
      await LensAdb(runner: runner, env: const {}).shot(_tempPath('o.png'));
      expect(runner.callCount, 2, reason: 'devices() then shot()');
    });

    test('zero devices -> LensNativeException', () async {
      final runner = _ScriptedRunner([
        _Expect(['adb', 'devices'],
            const RunnerResult(0, 'List of devices attached\n', '')),
      ]);
      await expectLater(
        () => LensAdb(runner: runner, env: const {}).shot(_tempPath('o.png')),
        throwsA(isA<LensNativeException>()
            .having((e) => e.toString(), 'msg', contains('no adb device'))),
      );
    });

    test('multiple ready devices -> LensNativeException listing serials', () async {
      final stdout = 'List of devices attached\n'
          'emulator-5554\tdevice\n'
          'emulator-5556\tdevice\n';
      final runner = _ScriptedRunner([
        _Expect(['adb', 'devices'], RunnerResult(0, stdout, '')),
      ]);
      await expectLater(
        () => LensAdb(runner: runner, env: const {}).shot(_tempPath('o.png')),
        throwsA(isA<LensNativeException>()
            .having((e) => e.toString(), 'msg', allOf(
                contains('multiple'),
                contains('emulator-5554'),
                contains('emulator-5556')))),
      );
    });
  });

  // Guard: the latin1 round-trip the port relies on is lossless for 0–255.
  test('sanity: latin1 round-trips PNG signature bytes', () {
    expect(latin1.encode(String.fromCharCodes(_pngMagic)), equals(_pngMagic));
  });
}
