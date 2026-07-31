// appbox-lens — native adb capture verbs.
//
// Ports the capture-relevant adb verbs to the appbox lens. Thin ProcessRunner
// wrappers: capture and observation only — interaction (tap/input/press)
// belongs to Patrol / native-E2E (capability-map Task 13), so those verbs are
// intentionally absent. Driven through the daemon-wide ProcessRunner seam
// (lib/process.dart); tests inject a scripted fake, no emulator required.
//
// Plan: appbox-lens-full-port.md, Task 8.

library;

import 'dart:convert';
import 'dart:io';

import '../../process.dart';

/// Raised on a non-zero adb exit or when serial resolution fails. The message
/// carries the adb stderr (often a remediation line) so the caller can surface
/// it, e.g. "device not found; boot an emulator".
class LensNativeException implements Exception {
  LensNativeException(this.message);
  final String message;
  @override
  String toString() => 'LensNativeException: $message';
}

/// Android capture/observation verbs over the [ProcessRunner] seam.
///
/// Serial resolution order: an explicit [serial] > `$APPBOX_ADB_SERIAL`
/// (read from [env], which defaults to [Platform.environment]) > a single
/// connected device in state "device" > an error listing the devices. Pass an
/// explicit [serial] in code, or rely on auto-pick when exactly one emulator
/// is booted.
class LensAdb {
  LensAdb({String? serial, ProcessRunner? runner, Map<String, String>? env})
      : _serial = serial ?? (env ?? Platform.environment)['APPBOX_ADB_SERIAL'],
        _runner = runner ?? const RealProcessRunner();

  final String? _serial;
  final ProcessRunner _runner;

  List<String> _base(String serial) => ['-s', serial];

  Future<String> _requireSerial() async {
    if (_serial != null) return _serial;
    final all = await devices();
    final up = all.where((d) => d['state'] == 'device').toList();
    if (up.length == 1) return up.first['serial']!;
    throw LensNativeException(up.isEmpty
        ? 'no adb device in state "device" — boot an emulator or pass --serial'
        : 'multiple adb devices — pass --serial '
            '(${up.map((d) => d['serial']).join(', ')})');
  }

  /// `adb devices` -> one map per attached device: `{serial, state}`, with a
  /// `warning` field added when the state is not `device` (e.g. `offline`,
  /// `unauthorized`) so callers can report why a device is unusable.
  Future<List<Map<String, String>>> devices() async {
    final r = await _runner.run('adb', ['devices']);
    final out = <Map<String, String>>[];
    for (final line in r.stdout.split('\n').skip(1)) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length == 2 && parts[0].isNotEmpty) {
        final entry = {'serial': parts[0], 'state': parts[1]};
        if (parts[1] != 'device') {
          entry['warning'] = 'device is ${parts[1]}, not ready for capture';
        }
        out.add(entry);
      }
    }
    return out;
  }

  /// `adb exec-out screencap -p` — exact PNG bytes, no sdcard round-trip.
  ///
  // kimitail: the ProcessRunner seam (lib/process.dart) is String-only — it
  // has no raw-bytes path, and we deliberately do not widen that interface
  // here. We round-trip stdout back to bytes via latin1 (lossless for 0–255).
  // Real binary capture on a UTF-8 locale may mangle bytes; if that bites in
  // production, add a `runBytes` to the seam and route screencap through it.
  Future<void> shot(String outPng) async {
    final serial = await _requireSerial();
    final r = await _runner.run('adb', [..._base(serial), 'exec-out', 'screencap', '-p']);
    if (r.exitCode != 0) {
      throw LensNativeException('adb screencap failed: ${r.stderr}');
    }
    final f = File(outPng);
    f.parent.createSync(recursive: true);
    await f.writeAsBytes(latin1.encode(r.stdout));
  }

  /// `adb shell screenrecord` to sdcard then `pull`, then `shell rm`. The
  /// platform caps a single screenrecord at 180s; [seconds] above that is
  /// rejected before any shell-out.
  Future<void> record(String outMp4, {int seconds = 10}) async {
    if (seconds > 180) {
      throw LensNativeException('screenrecord caps at 180s (got $seconds)');
    }
    final serial = await _requireSerial();
    const remote = '/sdcard/lens-record.mp4';
    final r = await _runner.run('adb', [
      ..._base(serial),
      'shell', 'screenrecord', '--time-limit', '$seconds', remote,
    ]);
    if (r.exitCode != 0) {
      throw LensNativeException('adb screenrecord failed: ${r.stderr}');
    }
    await _runner.run('adb', [..._base(serial), 'pull', remote, outMp4]);
    await _runner.run('adb', [..._base(serial), 'shell', 'rm', remote]);
    if (!File(outMp4).existsSync()) {
      throw LensNativeException('screenrecord pull produced no file at $outMp4');
    }
  }

  /// `adb shell am start -a android.intent.action.VIEW -d <url>` — opens a URL
  /// on the device. Observation-adjacent setup, not interaction truth.
  Future<void> openUrl(String url) async {
    final serial = await _requireSerial();
    final r = await _runner.run('adb', [
      ..._base(serial),
      'shell', 'am', 'start', '-a', 'android.intent.action.VIEW', '-d', url,
    ]);
    if (r.exitCode != 0) {
      throw LensNativeException('adb am start failed: ${r.stderr}');
    }
  }

  /// `adb shell uiautomator dump` + `cat`, parsed into a flat JSON node list
  /// with device-pixel bounds. uiautomator emits a flat-nested `<node>`
  /// hierarchy, so a [RegExp] over the XML is sufficient — no XML dependency.
  /// Attributes are pulled per-tag (not as one fixed-order regex): uiautomator
  /// orders them index, text, resource-id, class, …, bounds, and that order is
  /// not contractual across versions. Each node:
  /// `{class, text, bounds: [x, y, w, h]}` where bounds come from the
  /// `[x1,y1][x2,y2]` attribute (w = x2 - x1, h = y2 - y1).
  Future<List<Map<String, dynamic>>> uiTree() async {
    final serial = await _requireSerial();
    const remote = '/sdcard/lens-ui.xml';
    await _runner.run('adb', [..._base(serial), 'shell', 'uiautomator', 'dump', remote]);
    final fetched = await _runner.run('adb', [..._base(serial), 'shell', 'cat', remote]);
    final xml = fetched.stdout;
    final tagRe = RegExp(r'<node\b[^>]*>');
    final classRe = RegExp(r'class="([^"]*)"');
    final textRe = RegExp(r'text="([^"]*)"');
    final boundsRe =
        RegExp(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"');
    final nodes = <Map<String, dynamic>>[];
    for (final m in tagRe.allMatches(xml)) {
      final tag = m[0]!;
      final bm = boundsRe.firstMatch(tag);
      if (bm == null) continue; // node without device bounds — nothing to anchor
      final cm = classRe.firstMatch(tag);
      final tm = textRe.firstMatch(tag);
      final x1 = int.parse(bm[1]!), y1 = int.parse(bm[2]!);
      final x2 = int.parse(bm[3]!), y2 = int.parse(bm[4]!);
      nodes.add({
        'class': cm != null ? cm[1]! : '',
        'text': tm != null ? tm[1]! : '',
        'bounds': [x1, y1, x2 - x1, y2 - y1],
      });
    }
    return nodes;
  }
}
