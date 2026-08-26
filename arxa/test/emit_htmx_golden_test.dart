// Golden-diff regression test for emitHtmx — pins the rendered surface against
// a committed baseline so changes to the extraction pipeline are caught.
//
// The archived fixture producer is copied to a temp dir (archives/ stays
// read-only), the wall clock is frozen via frozen_clock.mjs, emitHtmx runs for
// real (boot server.js → Chrome → extract → write-on-diff), and the first
// surface is compared — after normalising timestamp-like digit runs to <TS> —
// against test/goldens/emit_htmx_surface.html.
//
// Skips gracefully when Node or Chrome is not on the machine.

import 'dart:io';

import 'package:arxa/cdp.dart';
import 'package:arxa/emit_htmx.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Timestamps the producer prints via Date.now() into .fx-clock. frozen_clock
/// pins them already, but we normalise defensively so a missing preload can
/// never flake the golden.
final _tsRe = RegExp(r'\d{10,}');
String normalize(String s) => s.replaceAll(_tsRe, '<TS>');

/// True when this machine can actually run emitHtmx (node + Chrome).
bool _envOk() {
  try {
    if (Process.runSync('node', ['--version']).exitCode != 0) return false;
  } catch (_) {
    return false;
  }
  try {
    return File(CdpClient.defaultChromePath()).existsSync();
  } catch (_) {
    return false;
  }
}

/// Recursive directory copy — dart:io has no one-liner.
Future<void> _copyDir(String from, String to) async {
  await Directory(to).create(recursive: true);
  await for (final entity in Directory(from).list()) {
    final dest = p.join(to, p.basename(entity.path));
    if (entity is Directory) {
      await _copyDir(entity.path, dest);
    } else if (entity is File) {
      await entity.copy(dest);
    }
  }
}

void main() {
  final repo = p.normalize(p.join(Directory.current.path, '..'));
  final fixtureSrc = p.join(repo, 'archives', 'tooling-pre-dart', 'tools',
      'vendor', 'emit_htmx', 'fixtures', 'app', 'design', 'new-htmx');
  final clockSrc = p.join(repo, 'archives', 'tooling-pre-dart', 'tools',
      'vendor', 'emit_htmx', 'frozen_clock.mjs');
  const goldenPath = 'test/goldens/emit_htmx_surface.html';
  const surfaceName = 'fixture_shell_home_view.html';

  test(
    'emitHtmx renders the fixture surface byte-for-byte against the golden',
    () async {
      // Copy the fixture into a temp dir so archives/ is never written to.
      final tmp = await Directory.systemTemp.createTemp('emit-htmx-golden-');
      addTearDown(() async {
        if (tmp.existsSync()) await tmp.delete(recursive: true);
      });
      await _copyDir(fixtureSrc, tmp.path);
      // Drop frozen_clock.mjs in the design root → _resolveClockPath finds it
      // locally and pins Date.now() for a deterministic render.
      File(clockSrc).copySync(p.join(tmp.path, 'frozen_clock.mjs'));

      final rc = await emitHtmx(tmp.path);
      expect(rc, 0, reason: 'emitHtmx failed with exit code $rc');

      final surface = File(p.join(tmp.path, 'surfaces', surfaceName));
      expect(surface.existsSync(), isTrue,
          reason: 'emitHtmx wrote no $surfaceName');

      final actual = normalize(surface.readAsStringSync());
      final golden = normalize(File(goldenPath).readAsStringSync());
      expect(actual, golden);
    },
    skip: _envOk() ? null : 'requires Node + Chrome on PATH',
  );
}
