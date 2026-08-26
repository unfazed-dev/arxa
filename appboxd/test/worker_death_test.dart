// Task #64 — the worker's Chrome PROCESS dying must not end the studio.
//
// The state under test is one step past task #51. #51 was the tab losing its
// globals: the page is still there, CDP still answers, and re-navigating it
// fixes everything. Here the browser itself is gone, and three separate things
// went wrong at once:
//
//   1. Nothing answers CDP any more, so what surfaces is cdp.dart's own 30s
//      "CDP command … timed out" — which the reboot-once path did not
//      recognise as a lost worker, so it rethrew and the studio served 500 to
//      every request from then on, forever.
//   2. `return _dispatch(...)` inside the request handler's try returned the
//      future BEFORE it completed, so the catch that writes the 500 surface
//      never saw the error. It escaped as an unhandled async error and killed
//      the server process.
//   3. The file watchers called `_worker.reload()` unawaited from a Timer with
//      no catch, so a failing reload was an unhandled async error with no
//      handler above it — a file save could kill the studio on its own.
//
// Each test below pins exactly one of those. They are separated because the
// dispatch that races the browser's death costs the full 30s CDP timeout and
// there is no way to shorten it from here (cdp.dart never errors its pending
// commands when the socket drops, and cdp.dart is not in scope). Stacking two
// such scenarios in one test would just make one slow test slower.
//
// Chrome is killed BY PID via a seam, never by pattern. A pattern kill matches
// every other design server's Chrome on the machine, including live ones.

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/design_dial.dart';
import 'package:appboxd/design_server.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final String _fixture =
    p.absolute('../skills/appbox-designer/examples/hello-hda');

Future<void> _copyDir(String src, String dst) async {
  await Directory(dst).create(recursive: true);
  for (final e in Directory(src).listSync(recursive: true)) {
    if (e is! File) continue;
    final rel = p.relative(e.path, from: src);
    final out = File(p.join(dst, rel))..createSync(recursive: true);
    await out.writeAsBytes(await e.readAsBytes());
  }
}

class _Resp {
  _Resp(this.status, this.body);
  final int status;
  final String body;
}

Future<_Resp> _get(String url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final res = await (await client.getUrl(Uri.parse(url))).close();
    return _Resp(res.statusCode, await utf8.decoder.bind(res).join());
  } finally {
    client.close(force: true);
  }
}

/// Wait until the killed Chrome has actually been reaped. `Process.killPid`
/// only delivers the signal; without this the test would race its own kill and
/// sometimes exercise a browser that is still answering.
Future<void> _settleAfterKill(DesignServer srv, int deadPid) async {
  for (var i = 0; i < 40; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    // Signal 0 is the portable liveness probe: it delivers nothing and returns
    // false once the pid is gone.
    if (!Process.killPid(deadPid, ProcessSignal.sigcont)) return;
  }
}

void main() {
  group('a dead worker browser (task #64)', () {
    late String tmp;
    late DesignServer srv;

    setUp(() async {
      tmp = (await Directory.systemTemp.createTemp('worker-death-')).path;
      await _copyDir(_fixture, tmp);
      srv = await DesignServer.start(
          dialStore: MemoryDialStore(), artifactDir: tmp, port: 0);
    });

    tearDown(() async {
      await srv.stop();
      try {
        await Directory(tmp).delete(recursive: true);
      } catch (_) {}
    });

    test('the studio recovers instead of serving 500 forever', () async {
      expect((await _get('${srv.url}timer')).status, 200,
          reason: 'control: the worker answers before anything is killed');
      final deadPid = srv.currentWorkerPid;
      expect(deadPid, greaterThan(0));

      expect(srv.killWorkerChromeForTest(), isTrue);
      await _settleAfterKill(srv, deadPid);

      // This request pays the 30s CDP timeout, then reboots and retries. It
      // must come back 200. Before the fix it was 500, and so was every request
      // after it until someone restarted the server by hand.
      expect((await _get('${srv.url}timer')).status, 200,
          reason: 'the worker was rebooted and the request retried');

      // "It answered" alone would also pass with the recovery deleted on any
      // run where Chrome happened to survive the signal, so the mechanism is
      // asserted directly: a NEW browser process exists.
      expect(srv.workerRelaunchRunsForTest, greaterThanOrEqualTo(1),
          reason: 'the dead browser was replaced, not just re-navigated');
      expect(srv.currentWorkerPid, isNot(deadPid));

      // And recovery is durable, not a one-shot: the next request is served by
      // the new browser with no further reboot.
      expect((await _get('${srv.url}timer')).status, 200);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('a reboot that cannot succeed is a 500, not a dead server', () async {
      expect((await _get('${srv.url}timer')).status, 200, reason: 'control');
      final deadPid = srv.currentWorkerPid;

      // Poison the replacement so the recovery path itself fails. This is the
      // branch that decides whether an unrecoverable worker degrades to an
      // error page or takes the process with it.
      srv.breakWorkerRelaunchForTest();
      expect(srv.killWorkerChromeForTest(), isTrue);
      await _settleAfterKill(srv, deadPid);

      final res = await _get('${srv.url}timer');
      expect(res.status, 500,
          reason: 'an unrecoverable worker is an error page, not a crash');

      // The point of the whole exercise: the server is still there afterwards.
      // Static routes never touch the worker, so this is a clean read of
      // "is the process still serving" independent of the worker's state.
      expect((await _get('${srv.url}__worker_page')).status, 200,
          reason: 'the server survived the failed recovery');
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('a hot reload that throws does not take the server down', () async {
      expect((await _get('${srv.url}timer')).status, 200, reason: 'control');
      final deadPid = srv.currentWorkerPid;

      srv.breakWorkerRelaunchForTest();
      expect(srv.killWorkerChromeForTest(), isTrue);
      await _settleAfterKill(srv, deadPid);

      final before = srv.workerReloadRunsForTest;
      // A save, exactly as an author would make it. The watcher debounces 200ms
      // and then reloads a worker whose browser is gone and whose replacement
      // is poisoned, so the reload throws — from inside a Timer callback, where
      // an unhandled async error has no handler above it anywhere.
      final routes = File(p.join(tmp, 'app.routes.js'));
      routes.writeAsStringSync(
          '${routes.readAsStringSync()}\n// touched by worker_death_test\n');
      await Future<void>.delayed(const Duration(seconds: 3));

      expect(srv.workerReloadRunsForTest, greaterThan(before),
          reason: 'the watcher really did fire and really did fail — without '
              'this the test would pass by never reloading at all');
      // If the throw escaped, package:test attributes the unhandled error to
      // this test and it fails before reaching here; in production it ends the
      // process outright.
      expect((await _get('${srv.url}__worker_page')).status, 200,
          reason: 'the server survived a failed background reload');
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
