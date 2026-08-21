// The lens daemon — does a warm browser actually get reused, and does the
// absence of one still work?
//
// The trap this file is written against: every assertion here has a shape
// where "the daemon worked" and "the daemon was never involved" can look
// identical. `lens shot` succeeds either way — with a daemon, without one,
// and with a daemon that silently launched a second browser. So the tests
// below assert on the BROWSER IDENTITY (pid owning a known profile dir), not
// on the verb's exit code, and the reuse test counts Chromes.
//
// Chrome is required; these are integration tests.
import 'dart:io';

import 'package:appboxd/cdp.dart';
import 'package:appboxd/lens/daemon.dart';
import 'package:test/test.dart';

bool get _chromeOk => File(CdpClient.defaultChromePath()).existsSync();

/// Independent of the production scan on purpose — a test calling back into
/// the code under test could agree with it while both were wrong.
/// [browserOnly] drops Chrome's helper processes, which all carry `--type=`.
/// It matters: opening a tab spawns a renderer, so a raw count of everything
/// owning the profile changes for reasons that have nothing to do with how
/// many BROWSERS exist — which is the only question the reuse test is asking.
List<int> pidsOwning(String dir, {bool browserOnly = false}) {
  final ps = Process.runSync('ps', ['-eo', 'pid=,command=']);
  if (ps.exitCode != 0) return const [];
  final needle = '--user-data-dir=$dir';
  final out = <int>[];
  for (final line in (ps.stdout as String).split('\n')) {
    final at = line.indexOf(needle);
    if (at < 0) continue;
    final rest = line.substring(at + needle.length);
    if (rest.isNotEmpty && !rest.startsWith(' ')) continue;
    if (browserOnly && line.contains('--type=')) continue;
    final pid = int.tryParse(line.trimLeft().split(RegExp(r'\s+')).first);
    if (pid != null) out.add(pid);
  }
  return out;
}

void main() {
  late Directory stateDir;

  setUp(() {
    // Each test gets its own state file. A machine-wide singleton would make
    // these fight each other and, worse, fight a daemon the developer is
    // actually using.
    stateDir = Directory.systemTemp.createTempSync('lens_daemon_test_');
    LensDaemon.statePathOverride = '${stateDir.path}/lens-daemon.json';
  });

  tearDown(() async {
    // Always reap: a leaked daemon is a warm Chrome that outlives the run.
    try {
      await LensDaemon.stop();
    } catch (_) {}
    LensDaemon.statePathOverride = null;
    try {
      stateDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('LensDaemon state', () {
    test('no state file → attach returns null, acquire still launches',
        () async {
      expect(LensDaemon.read(), isNull);
      // null is "launch your own", never an error. Every verb must work with
      // no daemon present — that is the pre-daemon behaviour, and the fallback
      // is what makes a broken daemon degrade to today rather than to nothing.
      expect(await LensDaemon.attach(), isNull);
    });

    test('a corrupt state file reads as no daemon, not as a crash', () {
      File(LensDaemon.statePath())
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('{not json');
      expect(LensDaemon.read(), isNull);
    });

    test('state round-trips, and shotsServed accumulates', () {
      const s = LensDaemonState(
          wsUrl: 'ws://x/y',
          profileDir: '/tmp/none',
          browserPid: 4242,
          startedAt: '2026-08-21T00:00:00.000',
          shotsServed: 7,
          visible: false);
      LensDaemon.write(s);
      final back = LensDaemon.read()!;
      expect(back.wsUrl, 'ws://x/y');
      expect(back.browserPid, 4242);
      expect(back.shotsServed, 7);
      expect(back.visible, isFalse);
      LensDaemon.write(back.withShots(back.shotsServed + 5));
      expect(LensDaemon.read()!.shotsServed, 12);
    });

    test('a recorded pid that owns nothing is dead, not alive', () {
      // Pids get recycled. Checking the pid alone would let an unrelated
      // process inheriting that number read as a live daemon — which is why
      // liveness is ownership of the exact profile dir, and why the dir is
      // recorded rather than derived.
      const s = LensDaemonState(
          wsUrl: 'ws://x/y',
          profileDir: '/tmp/definitely-not-a-chrome-profile',
          browserPid: 1, // launchd: certainly alive, certainly not our browser
          startedAt: '',
          shotsServed: 0,
          visible: false);
      expect(LensDaemon.isAlive(s), isFalse);
    });
  }, skip: _chromeOk ? null : 'requires Chrome');

  group('LensDaemon lifecycle', () {
    test('start records a live browser; stop kills it and clears the state',
        () async {
      final s = await LensDaemon.start();
      expect(pidsOwning(s.profileDir), contains(s.browserPid),
          reason: 'the recorded pid must be the process holding the profile');
      expect(LensDaemon.isAlive(s), isTrue);

      // The launcher exited (start() closed its client) and the browser is
      // still up — that is the whole premise of a process-less daemon.
      expect(File(LensDaemon.statePath()).existsSync(), isTrue);

      await LensDaemon.stop();
      expect(pidsOwning(s.profileDir), isEmpty,
          reason: 'stop must actually end the browser');
      expect(File(LensDaemon.statePath()).existsSync(), isFalse);
      expect(Directory(s.profileDir).existsSync(), isFalse);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('acquire REUSES the daemon browser instead of launching a second',
        () async {
      final s = await LensDaemon.start();
      try {
        // The load-bearing check, and the reason it is not "acquire returned a
        // client": a client is returned either way. Counting the Chromes that
        // own the daemon's profile is what separates "reused it" from
        // "launched its own and everything still worked".
        expect(pidsOwning(s.profileDir, browserOnly: true), hasLength(1),
            reason: 'precondition: exactly one browser owns the profile');
        final a = await LensDaemon.acquire();
        final b = await LensDaemon.acquire();
        expect(a.wsUrl, s.wsUrl);
        expect(b.wsUrl, s.wsUrl);

        final tab = await a.newTab();
        await tab.enable();
        await tab.navigate('about:blank');
        await tab.screenshot();

        await a.close();
        await b.close();
        // Two guests came and went, and there is still exactly ONE browser.
        // That is the whole claim: reuse, not a second Chrome that happened to
        // also work.
        expect(pidsOwning(s.profileDir, browserOnly: true), hasLength(1));
        expect(LensDaemon.isAlive(s), isTrue,
            reason: 'guests must not take the daemon down on close');
      } finally {
        await LensDaemon.stop();
      }
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('a guest banks its screenshots against the daemon', () async {
      final s = await LensDaemon.start();
      try {
        expect(s.shotsServed, 0);
        final client = await LensDaemon.acquire();
        final tab = await client.newTab();
        await tab.enable();
        await tab.navigate('about:blank');
        await tab.screenshot();
        await tab.screenshot();
        // Counted at the CDP chokepoint, so the number is screenshots and not
        // captures — settleForCapture takes 4-6 per capture, and a caller
        // counting captures would fire the recycle policy an order of
        // magnitude late.
        expect(client.screenshotsTaken, 2);
        await client.close();
        expect(LensDaemon.read()!.shotsServed, 2,
            reason: 'the guest close must bank its count');
      } finally {
        await LensDaemon.stop();
      }
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('past the recycle threshold, attach refuses and clears', () async {
      final s = await LensDaemon.start();
      final dir = s.profileDir;
      LensDaemon.write(s.withShots(LensDaemon.recycleAfterShots));
      // attach() must not hand out a browser that is due for recycling, and
      // must take the old one down rather than orphaning it.
      expect(await LensDaemon.attach(), isNull);
      expect(pidsOwning(dir), isEmpty);
      expect(LensDaemon.read(), isNull);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('a mismatched render mode bypasses the daemon', () async {
      final s = await LensDaemon.start();
      try {
        // Headless and visible are different Chrome launch args, so a headless
        // daemon cannot serve a visible verb. Connecting anyway would return
        // the wrong render mode with no error — silently wrong pixels, which
        // is the worst outcome the lens has.
        expect(s.visible, isFalse);
        LensSession.visible = true;
        addTearDown(() => LensSession.visible = false);
        expect(await LensDaemon.attach(), isNull,
            reason: 'a visible verb must launch its own, not reuse headless');
        // …and the daemon survives the refusal: bypassing is not reaping.
        expect(LensDaemon.isAlive(s), isTrue);
      } finally {
        LensSession.visible = false;
        await LensDaemon.stop();
      }
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('a stale state file is reaped, and acquire falls back to a launch',
        () async {
      // The case no CDP event can announce: the browser died and nothing said
      // so. Simulated by killing it behind the daemon's back, which is exactly
      // what a stray `pkill -f appbox-cdp-` does.
      final s = await LensDaemon.start();
      for (final pid in pidsOwning(s.profileDir)) {
        Process.killPid(pid, ProcessSignal.sigkill);
      }
      expect(LensDaemon.isAlive(s), isFalse);
      expect(await LensDaemon.attach(), isNull);
      expect(LensDaemon.read(), isNull, reason: 'the corpse must be cleared');

      final client = await LensDaemon.acquire();
      try {
        expect(client.wsUrl, isNot(s.wsUrl),
            reason: 'acquire must have launched a fresh browser');
      } finally {
        await client.close();
      }
    }, timeout: const Timeout(Duration(minutes: 3)));
  },
      skip: _chromeOk
          ? (LensDaemon.supported ? null : 'daemon needs the macOS launch path')
          : 'requires Chrome');
}
