// Task #31 — a transient Chrome boot failure must not be a terminal one.
//
// WHAT THIS DOES AND DOES NOT CLAIM. The flake this handling exists for — the
// worker boot dying under parallel test load — has never been reproduced on
// demand, so nothing here proves the cause. What it does prove is the half that
// was certain: the boot was attempted exactly once, so ANY transient failure
// was fatal. These tests pin the retry so it cannot be quietly removed, and
// they pin the two ways a retry loop typically rots — leaking a process per
// attempt, and losing the diagnostic Chrome printed on the way down.
//
// The failure is driven by pointing the launcher at a binary that exits
// immediately (`/bin/echo`) rather than by waiting for a real Chrome to
// misbehave. That path is the same one a Chrome-that-dies-on-startup takes:
// stderr closes without a ws:// URL, so _readWsUrl completes with an error.
// It runs in milliseconds and is deterministic — the opposite of the flake it
// guards.

import 'dart:io';

import 'package:appboxd/design_server/worker.dart';
import 'package:test/test.dart';

void main() {
  group('Chrome boot retry (task #31)', () {
    // /bin/echo exits at once and never prints a DevTools URL — a stand-in for
    // a Chrome that dies during startup.
    const deadBrowser = '/bin/echo';

    test('a boot that fails is retried, not surrendered on the first try',
        () async {
      await expectLater(
        JsWorker.boot(
          workerPageUrl: 'http://127.0.0.1:1/__worker_page',
          origin: 'http://127.0.0.1:1',
          artifactDir: Directory.systemTemp.path,
          chromePath: deadBrowser,
          launchAttempts: 2,
        ),
        throwsA(isA<StateError>()),
      );
      // The count is the contract. Asserting only that it threw would pass
      // with the retry loop deleted, which is exactly the regression to catch.
      expect(JsWorker.lastLaunchAttempts, 2);
    });

    test('the attempt budget is honoured, not ignored', () async {
      await expectLater(
        JsWorker.boot(
          workerPageUrl: 'http://127.0.0.1:1/__worker_page',
          origin: 'http://127.0.0.1:1',
          artifactDir: Directory.systemTemp.path,
          chromePath: deadBrowser,
          launchAttempts: 3,
        ),
        throwsA(isA<StateError>()),
      );
      expect(JsWorker.lastLaunchAttempts, 3);
    });

    test('the final error still carries Chrome\'s own account of the failure',
        () async {
      // Retrying must not swallow the diagnosis. Finding 16 was precisely that
      // a boot failure arrived with no cause attached; a retry loop that
      // reported only "failed after N attempts" would undo that fix.
      try {
        await JsWorker.boot(
          workerPageUrl: 'http://127.0.0.1:1/__worker_page',
          origin: 'http://127.0.0.1:1',
          artifactDir: Directory.systemTemp.path,
          chromePath: deadBrowser,
          launchAttempts: 2,
        );
        fail('expected the boot to throw');
      } on StateError catch (e) {
        expect(e.message, contains('2 attempts'));
        expect(e.message, contains('DevTools URL'),
            reason: 'the underlying cause must survive the retry wrapper');
      }
    });

    test('each failed attempt cleans up its own profile dir', () async {
      // A PREFIX ONLY THIS TEST USES. The default `appbox-design-worker-` is
      // shared by every worker on the machine, so counting it counts whatever
      // else is booting: under full-suite load this assertion passed or failed
      // on other test files' timing rather than on the retry loop. Measured
      // over repeated full-suite runs the baseline read 2, then 4, then 3, and
      // the failures were real workers appearing mid-window — never a dir this
      // test leaked. Owning the prefix makes the count exact by construction
      // instead of quiet when the machine happens to be idle.
      final prefix = 'appbox-boot-retry-test-${DateTime.now()
          .microsecondsSinceEpoch}-';
      final tmp = Directory.systemTemp;
      int ownDirs() => tmp
          .listSync()
          .whereType<Directory>()
          .where((d) => d.path.contains(prefix))
          .length;

      expect(ownDirs(), 0, reason: 'the prefix must be unused before the boot');
      try {
        await JsWorker.boot(
          workerPageUrl: 'http://127.0.0.1:1/__worker_page',
          origin: 'http://127.0.0.1:1',
          artifactDir: Directory.systemTemp.path,
          chromePath: deadBrowser,
          launchAttempts: 3,
          profilePrefix: prefix,
        );
      } catch (_) {}
      // Three attempts must not leave three profile dirs behind. A retry loop
      // that leaks per attempt manufactures the very orphans sweepOrphans
      // exists to reap — one failure becoming N strays. Exactly zero, not
      // "no more than before": these dirs are the test's own, nothing else can
      // create them, and sweepOrphans does not know this prefix, so anything
      // left here was leaked by the loop under test.
      expect(ownDirs(), 0);
    });
  });
}
