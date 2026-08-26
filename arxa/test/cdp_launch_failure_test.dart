// A failed CdpClient.launch must clean up after itself and retry once.
//
// Why this exists: under CPU oversubscription (full suite + 12 spinners,
// 2026-08-21) Chrome took >30s to write DevToolsActivePort; launch() threw
// from setUp (failing the test), and its failure paths left the spawned
// Chrome and the profile dir behind. The flake and the "leaked warm Chromes"
// were the same event. The worker's launcher (_ChromeHandle.launch) had
// already fixed both for itself; this pins the same behaviour on CdpClient.
//
// The doomed launch runs in a CHILD process with a private TMPDIR, because
// the obvious in-process version — diff systemTemp's arxa-cdp- dirs before
// and after — races every concurrently running test file that launches
// Chrome, and lost that race on its very first full-suite run. A dir nothing
// else writes to makes "left nothing behind" assertable at all.
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('a launch that cannot boot throws after 2 attempts and leaves nothing',
      () async {
    final tmp = Directory.systemTemp.createTempSync('launch_failure_test_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final r = await Process.run(
      Platform.resolvedExecutable,
      ['run', 'tool/launch_failure_child.dart'],
      environment: {...Platform.environment, 'TMPDIR': tmp.path},
    );

    expect(r.stdout, contains('THREW:'),
        reason: 'the child must fail its launch, not succeed on /bin/echo');
    expect(r.stdout, contains('after 2 attempts'),
        reason: '"after 2 attempts" is also the proof the retry actually ran');
    expect(r.stdout, contains('DevTools URL'),
        reason: 'the underlying cause must survive the retry wrapper');
    expect(r.stderr, contains('attempt 1 failed'),
        reason: 'a silent retry hides a Chrome that fails every other boot');

    // Both attempts' profile dirs must be gone: a retry loop that leaks the
    // half-started attempt manufactures exactly the orphans sweepOrphans
    // exists to reap — one failure becoming N strays.
    final leaked = tmp
        .listSync()
        .map((e) => e.path)
        .where((p) => p.contains('arxa-cdp-'))
        .toList();
    expect(leaked, isEmpty,
        reason: 'failed launch attempts left profile dirs behind: $leaked');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
