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
      final tmp = Directory.systemTemp;
      int workerDirs() => tmp
          .listSync()
          .whereType<Directory>()
          .where((d) => d.path.contains('appbox-design-worker-'))
          .length;

      final before = workerDirs();
      try {
        await JsWorker.boot(
          workerPageUrl: 'http://127.0.0.1:1/__worker_page',
          origin: 'http://127.0.0.1:1',
          artifactDir: Directory.systemTemp.path,
          chromePath: deadBrowser,
          launchAttempts: 3,
        );
      } catch (_) {}
      // Three attempts must not leave three profile dirs behind. A retry loop
      // that leaks per attempt manufactures the very orphans sweepOrphans
      // exists to reap — one failure becoming N strays.
      expect(workerDirs(), lessThanOrEqualTo(before));
    });
  });
}
