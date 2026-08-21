// A failed CdpClient.launch must clean up after itself and retry once.
//
// Why this exists: under CPU oversubscription (full suite + 12 spinners,
// 2026-08-21) Chrome took >30s to write DevToolsActivePort; launch() threw
// from setUp and failed the test — and its failure paths left the spawned
// Chrome and the profile dir behind. The flake and the "leaked warm Chromes"
// were the same event. The worker's launcher (_ChromeHandle.launch) had
// already fixed both for itself; this pins the same behaviour on CdpClient.
//
// The stand-in binary is /bin/echo — exits instantly, prints no DevTools URL —
// via the visible-mode direct-exec path, which is the only launch path that
// takes an arbitrary executable (open -g needs an app bundle). The cleanup
// under test (`_reapFailedLaunch`) is shared by both paths.
import 'dart:io';

import 'package:appboxd/cdp.dart';
import 'package:test/test.dart';

Set<String> _cdpDirs() => Directory.systemTemp
    .listSync()
    .whereType<Directory>()
    .map((d) => d.path)
    .where((p) => p.contains('/appbox-cdp-'))
    .toSet();

void main() {
  test('a launch that cannot boot throws after 2 attempts and leaves nothing',
      () async {
    final before = _cdpDirs();
    final wasVisible = LensSession.visible;
    // Visible mode forces the direct-exec path on macOS, where chromePath is
    // exec'd as-is. /bin/echo ignores the Chrome args and exits at once.
    LensSession.visible = true;
    addTearDown(() => LensSession.visible = wasVisible);

    await expectLater(
        CdpClient.launch(chromePath: '/bin/echo'),
        throwsA(predicate((e) =>
            '$e'.contains('after 2 attempts') &&
            '$e'.contains('DevTools URL'))),
        reason: 'the failure must name both the retry and the cause — '
            '"after 2 attempts" is also the proof the retry actually ran');

    // Both attempts' profile dirs must be gone: a retry loop that leaks the
    // half-started attempt manufactures exactly the orphans sweepOrphans
    // exists to reap — one failure becoming N strays.
    final leaked = _cdpDirs().difference(before);
    expect(leaked, isEmpty,
        reason: 'failed launch attempts left profile dirs behind: $leaked');
  });
}
