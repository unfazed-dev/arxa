// iOS-simulator capture wrappers — TDD port (Task 9 of the appbox lens
// full-port plan). Mirrors deploy.dart's ScriptedRunner seam: argv-prefix →
// RunnerResult expectations, asserted in FIFO order. NO simulator is booted —
// the fake runner stands in for `xcrun simctl`. recordVideo is a long-lived
// background process, so it takes an injectable Process starter that the test
// fakes to record argv, fake the mp4 landing, and assert SIGINT was issued.

import 'dart:async';
import 'dart:io';

import 'package:appboxd/lens/native/adb.dart';
import 'package:appboxd/lens/native/simctl.dart';
import 'package:appboxd/process.dart';
import 'package:test/test.dart';

/// FIFO argv-prefix scripted runner, same shape as deploy.dart's ScriptedRunner
/// (local copy: this test owns no shared lib file). Each expectation matches the
/// leading argv tokens `[executable, ...args]`; remaining tokens are the
/// command's variable tail (output paths, urls, modes).
class _ScriptedRunner implements ProcessRunner {
  _ScriptedRunner(this._expectations);
  final List<(List<String>, RunnerResult)> _expectations;
  var _i = 0;
  int get callCount => _i;

  @override
  Future<RunnerResult> run(
    String executable,
    List<String> args, {
    Map<String, String> environment = const {},
    String? workingDirectory,
  }) async {
    if (_i >= _expectations.length) {
      throw StateError('simctl issued an unexpected extra command: '
          '$executable $args (suite expected only ${_expectations.length})');
    }
    final (wantPrefix, result) = _expectations[_i];
    final argv = [executable, ...args];
    if (argv.length < wantPrefix.length) {
      throw StateError('simctl called the wrong command:\n'
          '  expected prefix $wantPrefix\n'
          '  got                  $argv');
    }
    for (var i = 0; i < wantPrefix.length; i++) {
      if (argv[i] != wantPrefix[i]) {
        throw StateError('simctl called the wrong command:\n'
            '  expected prefix $wantPrefix\n'
            '  got                  ${argv.sublist(0, wantPrefix.length)}');
      }
    }
    _i++;
    return result;
  }
}

/// Fake background `xcrun simctl io ... recordVideo` process. Records the argv
/// it was started with, fakes the mp4 landing, completes exitCode, and remembers
/// whether SIGINT was delivered via kill().
class _FakeProcess implements Process {
  _FakeProcess(this.argv, {required this.landFile, this.exit = 0});
  final List<String> argv;
  final String? landFile;
  final int exit;
  final List<ProcessSignal> kills = [];
  bool get stopped => kills.contains(ProcessSignal.sigint);

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    kills.add(signal);
    if (landFile != null) {
      File(landFile!).parent.createSync(recursive: true);
      File(landFile!).writeAsStringSync('mp4');
    }
    return true;
  }

  @override
  Future<int> get exitCode async => exit;
  @override
  int get pid => -1;
  @override
  Stream<List<int>> get stdout => const Stream.empty();
  @override
  Stream<List<int>> get stderr => const Stream.empty();
  @override
  IOSink get stdin => IOSink(StreamController<List<int>>());
}

void main() {
  group('iosShot', () {
    test('runs xcrun simctl io <udid> screenshot --type png <out>', () async {
      final out = '${Directory.systemTemp.createTempSync('simctl_shot').path}/a.png';
      final runner = _ScriptedRunner([
        (
          ['xcrun', 'simctl', 'io', 'booted', 'screenshot', '--type', 'png'],
          const RunnerResult(0, '', ''),
        ),
      ]);
      await LensSimctl(runner: runner).shot(out);
      expect(runner.callCount, 1);
    });

    test('non-zero exit throws LensNativeException carrying stderr', () async {
      final runner = _ScriptedRunner([
        (
          ['xcrun', 'simctl', 'io', 'booted', 'screenshot'],
          const RunnerResult(1, '', 'unable to take screenshot'),
        ),
      ]);
      await expectLater(
        () => LensSimctl(runner: runner).shot('/tmp/x.png'),
        throwsA(predicate<LensNativeException>(
            (e) => e.toString().contains('unable to take screenshot'))),
      );
    });

    test('--udid override lands in the argv', () async {
      final runner = _ScriptedRunner([
        (
          ['xcrun', 'simctl', 'io', 'DEAD-BEEF', 'screenshot', '--type', 'png'],
          const RunnerResult(0, '', ''),
        ),
      ]);
      await LensSimctl(udid: 'DEAD-BEEF', runner: runner).shot('/tmp/x.png');
    });
  });

  group('iosRecord', () {
    test('starts recordVideo --codec h264, sends SIGINT, file lands', () async {
      final out = '${Directory.systemTemp.createTempSync('simctl_rec').path}/v.mp4';
      _FakeProcess? captured;
      final lens = LensSimctl(
        start: (args) async {
          captured = _FakeProcess(args, landFile: out, exit: 0);
          return captured!;
        },
      );
      await lens.record(out, seconds: 1);
      // argv prefix is the simctl recordVideo command.
      expect(
        captured!.argv.sublist(0, 6),
        ['simctl', 'io', 'booted', 'recordVideo', '--codec', 'h264'],
      );
      expect(captured!.argv.last, out);
      expect(captured!.stopped, isTrue, reason: 'recordVideo must be SIGINT-stopped');
      expect(File(out).existsSync(), isTrue, reason: 'fake must land the mp4');
    });

    test('non-zero exit with no file throws', () async {
      final out = '${Directory.systemTemp.createTempSync('simctl_rec2').path}/v.mp4';
      final lens = LensSimctl(
        start: (args) async => _FakeProcess(args, landFile: null, exit: 1),
      );
      await expectLater(
        () => lens.record(out, seconds: 1),
        throwsA(predicate<LensNativeException>(
            (e) => e.toString().contains('no file'))),
      );
    });

    test('non-zero exit but file present is tolerated (simctl finalized on interrupt)',
        () async {
      final out = '${Directory.systemTemp.createTempSync('simctl_rec3').path}/v.mp4';
      final lens = LensSimctl(
        start: (args) async => _FakeProcess(args, landFile: out, exit: 1),
      );
      // No throw — the mp4 landed despite a non-zero (interrupted) exit.
      await lens.record(out, seconds: 1);
      expect(File(out).existsSync(), isTrue);
    });
  });

  group('iosDevices', () {
    test('parses list devices --json, booted first, runtime carried', () async {
      const json = '''
{
  "devices": {
    "com.apple.CoreSimulator.SimRuntime.iOS-17-0": [
      {"udid": "AAA", "name": "iPhone 15", "state": "Shutdown"},
      {"udid": "BBB", "name": "iPhone 15 Pro", "state": "Booted"}
    ],
    "com.apple.CoreSimulator.SimRuntime.iOS-16-4": [
      {"udid": "CCC", "name": "iPhone SE", "state": "Booted"}
    ]
  }
}''';
      final runner = _ScriptedRunner([
        (
          ['xcrun', 'simctl', 'list', 'devices', '--json'],
          const RunnerResult(0, json, ''),
        ),
      ]);
      final devs = await LensSimctl(runner: runner).devices();
      expect(devs.length, 3);
      // Booted devices sort first.
      expect(devs[0]['state'], 'Booted');
      expect(devs[1]['state'], 'Booted');
      expect(devs[2]['state'], 'Shutdown');
      final pro = devs.firstWhere((d) => d['udid'] == 'BBB');
      expect(pro['name'], 'iPhone 15 Pro');
      expect(pro['runtime'], 'com.apple.CoreSimulator.SimRuntime.iOS-17-0');
    });

    test('empty device list is an empty result', () async {
      const json = '{"devices": {}}';
      final runner = _ScriptedRunner([
        (
          ['xcrun', 'simctl', 'list', 'devices', '--json'],
          const RunnerResult(0, json, ''),
        ),
      ]);
      expect(await LensSimctl(runner: runner).devices(), isEmpty);
    });
  });

  group('iosStatusBar', () {
    test('override pins the golden-capture chrome (9:41, full, 4 bars, 3 wifi)',
        () async {
      final runner = _ScriptedRunner([
        (
          [
            'xcrun', 'simctl', 'status_bar', 'booted', 'override',
            '--time', '9:41', '--batteryLevel', '100',
            '--cellularBars', '4', '--wifiBars', '3',
          ],
          const RunnerResult(0, '', ''),
        ),
      ]);
      await LensSimctl(runner: runner).statusBarOverride();
      expect(runner.callCount, 1);
    });

    test('clear restores the real status bar', () async {
      final runner = _ScriptedRunner([
        (
          ['xcrun', 'simctl', 'status_bar', 'booted', 'clear'],
          const RunnerResult(0, '', ''),
        ),
      ]);
      await LensSimctl(runner: runner).statusBarClear();
    });
  });

  group('iosAppearance', () {
    test('dark / light hit simctl ui <udid> appearance <mode>', () async {
      for (final mode in ['dark', 'light']) {
        final runner = _ScriptedRunner([
          (
            ['xcrun', 'simctl', 'ui', 'booted', 'appearance', mode],
            const RunnerResult(0, '', ''),
          ),
        ]);
        await LensSimctl(runner: runner).appearance(mode);
      }
    });

    test('an unknown mode throws before any process is spawned', () async {
      final runner = _ScriptedRunner(const []);
      await expectLater(
        () => LensSimctl(runner: runner).appearance('oled'),
        throwsA(predicate<LensNativeException>(
            (e) => e.toString().contains('dark|light'))),
      );
      expect(runner.callCount, 0, reason: 'validation must precede the shell-out');
    });
  });

  group('iosOpenUrl', () {
    test('runs simctl openurl <udid> <url>', () async {
      final runner = _ScriptedRunner([
        (
          ['xcrun', 'simctl', 'openurl', 'booted', 'appbox://stage/proof'],
          const RunnerResult(0, '', ''),
        ),
      ]);
      await LensSimctl(runner: runner).openUrl('appbox://stage/proof');
    });
  });
}
