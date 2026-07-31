// iOS-simulator capture verbs (ports probe-runner ios_shot/ios_record/
// ios_list/ios_url/ios_status_bar/ios_appearance). Capture and
// deterministic-chrome only; idb-dependent interaction is dropped (Patrol
// owns it). xcrun is spawned; tests fake the runner.
library;

import 'dart:convert';
import 'dart:io';

import '../../process.dart';
import 'adb.dart';

class LensSimctl {
  LensSimctl({
    String? udid,
    ProcessRunner? runner,
    Future<Process> Function(List<String> args)? start,
  })  : _udid = udid ?? 'booted',
        _runner = runner ?? const RealProcessRunner(),
        _start = start ?? _defaultStart;

  final String _udid;
  final ProcessRunner _runner;

  /// Injectable process starter for recordVideo (tests fake it; production
  /// shells out to xcrun via Process.start). The ProcessRunner seam is
  /// run-to-completion and cannot express a SIGINT-stopped long recording.
  final Future<Process> Function(List<String> args) _start;

  /// Run `xcrun <args>`; throw [LensNativeException] on exit != 0 with stderr.
  Future<void> _checked(List<String> args) async {
    final r = await _runner.run('xcrun', args);
    if (r.exitCode != 0) {
      throw LensNativeException('xcrun ${args.join(' ')} failed: ${r.stderr}');
    }
  }

  /// `simctl io <udid> screenshot --type png <out>`. simctl writes the file.
  Future<void> shot(String outPng) async {
    File(outPng).parent.createSync(recursive: true);
    await _checked(
        ['simctl', 'io', _udid, 'screenshot', '--type', 'png', outPng]);
  }

  /// Pin the golden-capture chrome (9:41, full battery, full bars) for
  /// deterministic evidence shots.
  Future<void> statusBarOverride() => _checked([
        'simctl', 'status_bar', _udid, 'override',
        '--time', '9:41', '--batteryLevel', '100',
        '--cellularBars', '4', '--wifiBars', '3',
      ]);

  /// Restore the real status bar.
  Future<void> statusBarClear() =>
      _checked(['simctl', 'status_bar', _udid, 'clear']);

  /// `simctl ui <udid> appearance dark|light`.
  Future<void> appearance(String mode) {
    if (mode != 'dark' && mode != 'light') {
      throw LensNativeException('appearance must be dark|light (got $mode)');
    }
    return _checked(['simctl', 'ui', _udid, 'appearance', mode]);
  }

  /// `simctl openurl <udid> <url>`.
  Future<void> openUrl(String url) =>
      _checked(['simctl', 'openurl', _udid, url]);

  /// Parse `simctl list devices --json` into `[{udid, name, state, runtime}]`,
  /// booted devices first.
  Future<List<Map<String, String?>>> devices() async {
    final r =
        await _runner.run('xcrun', ['simctl', 'list', 'devices', '--json']);
    final parsed = jsonDecode(r.stdout) as Map<String, dynamic>;
    final out = <Map<String, String?>>[];
    for (final e in (parsed['devices'] as Map).entries) {
      for (final d in e.value as List) {
        out.add({
          'udid': d['udid']?.toString(),
          'name': d['name']?.toString(),
          'state': d['state']?.toString(),
          'runtime': e.key.toString(),
        });
      }
    }
    out.sort((a, b) => (b['state'] == 'Booted' ? 1 : 0)
        .compareTo(a['state'] == 'Booted' ? 1 : 0));
    return out;
  }

  /// `recordVideo --codec h264 <out>`, run for [seconds], then SIGINT — simctl
  /// finalizes the mp4 on interrupt. The file landing is the success signal: a
  /// non-zero exit WITH a file is tolerated (interrupt path); non-zero WITHOUT a
  /// file is a real failure.
  Future<void> record(String outMp4, {int seconds = 10}) async {
    File(outMp4).parent.createSync(recursive: true);
    final proc = await _start(
        ['simctl', 'io', _udid, 'recordVideo', '--codec', 'h264', outMp4]);
    await Future.delayed(Duration(seconds: seconds));
    proc.kill(ProcessSignal.sigint);
    final code = await proc.exitCode;
    if (code != 0 && !File(outMp4).existsSync()) {
      throw LensNativeException('simctl recordVideo exited $code, no file');
    }
  }

  static Future<Process> _defaultStart(List<String> args) =>
      Process.start('xcrun', args);
}
