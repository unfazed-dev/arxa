// Task #69: starting/stopping a design server must not reap unrelated ones.
//
// The registry key used to be the artifact dir alone. That reads as narrow and
// is not: every design server in this repo serves `designs/appbox-studio`, so
// the predicate was a constant and one ^C SIGTERMed every design server on the
// machine. Measured on the live registry before the fix: 14 pidfiles, all the
// identical artifactDir. The user's studio died twice from other agents'
// restarts, with nothing on screen but an exit code.
//
// The load-bearing assertion in every test here is on the SURVIVOR — the
// server that must still be alive afterwards. A test that only checks "the new
// server came up" proves nothing about the one that should not have been
// touched, which is the exact vacuous shape this codebase keeps regressing on.

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/design_server.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final String _fixture =
    p.absolute('../skills/appbox-designer/examples/hello-hda');

/// A long-lived process whose command line satisfies the sweep's `ps` identity
/// check, standing in for a real design server. Using a REAL process (rather
/// than a fake pid) is the point: "still alive" is a fact about the OS, not
/// about our own bookkeeping.
Future<Process> _fakeServer() => Process.start(
    '/bin/sh', ['-c', 'while :; do sleep 1; done', 'appbox-design-serve-probe']);

bool _alive(int pid) =>
    Process.runSync('ps', ['-p', '$pid', '-o', 'pid=']).exitCode == 0;

/// Poll rather than sleep-once: SIGTERM delivery is asynchronous, and a fixed
/// sleep is either flaky or slow.
Future<bool> _waitDead(int pid, {Duration timeout = const Duration(seconds: 5)}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (!_alive(pid)) return true;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  return false;
}

Future<int?> _statusOf(String url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final req = await client.getUrl(Uri.parse(url));
    // The response needs its own deadline: connectionTimeout only bounds the
    // connect. A wedged server that ACCEPTS and never answers — measured
    // 2026-08-21, a zombie serve process from a killed suite run squatting
    // 4371 — turns an unbounded req.close() into the test's full 5-minute
    // ceiling, reported as a mystery timeout instead of "server not healthy".
    final res = await req.close().timeout(const Duration(seconds: 5));
    await res.drain<void>();
    return res.statusCode;
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

void main() {
  group('sweep scope (registry, no Chrome)', () {
    final started = <Process>[];
    final registered = <int>[];

    tearDown(() async {
      // By pid only. A pattern kill here would take out other agents' servers
      // and the user's live studio — the very failure under test.
      for (final proc in started) {
        Process.killPid(proc.pid, ProcessSignal.sigkill);
      }
      started.clear();
      for (final pid in registered) {
        deregisterServeInstance(pid);
      }
      registered.clear();
    });

    test('69: a server on a different PORT of the same design survives',
        () async {
      final victim = await _fakeServer(); // same dir, same port → replaced
      final survivor = await _fakeServer(); // same dir, OTHER port → untouched
      started.addAll([victim, survivor]);

      registerServeInstance(victim.pid, '/tmp/art-69', port: 4371);
      registerServeInstance(survivor.pid, '/tmp/art-69', port: 4372);
      registered.addAll([victim.pid, survivor.pid]);

      final announced = <String>[];
      final killed = sweepSiblingInstances(pid, '/tmp/art-69',
          port: 4371, announce: announced.add);

      // THE load-bearing assertion, asserted FIRST so a regression reads as
      // "the survivor died" rather than as some bookkeeping mismatch.
      expect(await _waitDead(victim.pid), isTrue,
          reason: 'the instance actually being replaced must stop');
      expect(_alive(survivor.pid), isTrue,
          reason: 'same design on another port is a legitimate side-by-side '
              'comparison and must survive');
      expect(File(p.join(serveRegistryDir.path, '${survivor.pid}.json')).existsSync(),
          isTrue, reason: 'the survivor stays registered, not reaped');
      expect(killed, [victim.pid], reason: 'only the same dir+port instance');

      // The kill is narrated — a silently reaped server is the invisible
      // failure that made this bug cost two studios and a day.
      expect(announced.single, contains('${victim.pid}'));
      expect(announced.single, contains('4371'));
      expect(announced.single, contains('/tmp/art-69'));
    });

    test('69: a server on a different DESIGN survives', () async {
      final survivor = await _fakeServer();
      started.add(survivor);
      registerServeInstance(survivor.pid, '/tmp/art-69-other', port: 4371);
      registered.add(survivor.pid);

      final killed =
          sweepSiblingInstances(pid, '/tmp/art-69', port: 4371);

      expect(killed, isEmpty);
      expect(_alive(survivor.pid), isTrue,
          reason: 'a different design on the same port is not ours to stop');
    });

    test('69: a legacy portless pidfile is never signalled', () async {
      // Pre-#69 pidfiles carry no port. They cannot be PROVEN to be the
      // instance being replaced, and guessing wrong kills a live server, so
      // they are left alone rather than swept.
      final survivor = await _fakeServer();
      started.add(survivor);
      serveRegistryDir.createSync(recursive: true);
      File(p.join(serveRegistryDir.path, '${survivor.pid}.json'))
          .writeAsStringSync(jsonEncode({'artifactDir': '/tmp/art-69'}));
      registered.add(survivor.pid);

      final killed =
          sweepSiblingInstances(pid, '/tmp/art-69', port: 4371);

      expect(killed, isEmpty);
      expect(_alive(survivor.pid), isTrue);
    });
  });

  // Real `appbox design serve` subprocesses on spare ports (4370+). 4319 is the
  // user's live studio and is never touched.
  group('real design servers coexist', () {
    late Directory dirX;
    late Directory dirY;
    final procs = <Process>[];

    Future<Process> serve(String dir, int port) async {
      final proc = await Process.start(
          Platform.resolvedExecutable, ['run', 'bin/appbox.dart', 'design', 'serve', dir, '--port', '$port'],
          workingDirectory: p.absolute('.'));
      procs.add(proc);
      proc.stdout.drain<void>();
      proc.stderr.drain<void>();
      return proc;
    }

    Future<bool> waitUp(int port) async {
      final deadline = DateTime.now().add(const Duration(seconds: 90));
      while (DateTime.now().isBefore(deadline)) {
        if (await _statusOf('http://127.0.0.1:$port/') != null) return true;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      return false;
    }

    setUpAll(() async {
      dirX = await Directory.systemTemp.createTemp('s69-x-');
      dirY = await Directory.systemTemp.createTemp('s69-y-');
      for (final d in [dirX, dirY]) {
        // Assert the copy: a silently failed fixture surfaces later as a
        // "must boot" timeout, which sends the reader debugging Chrome
        // instead of a missing app.routes.js.
        final r = await Process.run('cp', ['-R', '$_fixture/', d.path]);
        expect(r.exitCode, 0, reason: 'fixture copy failed: ${r.stderr}');
        expect(File(p.join(d.path, 'app.routes.js')).existsSync(), isTrue,
            reason: 'resolveArtifact needs app.routes.js in the dir');
      }
    });

    tearDownAll(() async {
      for (final proc in procs) {
        Process.killPid(proc.pid, ProcessSignal.sigkill);
      }
      for (final d in [dirX, dirY]) {
        try {
          await d.delete(recursive: true);
        } catch (_) {}
      }
    });

    test('69: booting B leaves A alive; C replaces A and leaves B alive',
        () async {
      final a = await serve(dirX.path, 4371);
      expect(await waitUp(4371), isTrue, reason: 'A must boot');

      // B is the SAME design on another port — deliberately the case a
      // dir-only key cannot distinguish, and the one a user hits when
      // comparing a design before/after a change side by side. A different
      // design dir would be a weaker probe: it survives even the old key.
      final b = await serve(dirX.path, 4372);
      expect(await waitUp(4372), isTrue, reason: 'B must boot');

      // Load-bearing: B booting must not have reaped A.
      expect(await _statusOf('http://127.0.0.1:4371/'), isNotNull,
          reason: 'A must survive B booting on another port of the same design');
      expect(_alive(a.pid), isTrue);

      // A third server on a different design entirely, as a second survivor.
      final d = await serve(dirY.path, 4373);
      expect(await waitUp(4373), isTrue, reason: 'D must boot');

      // The legitimate case: C takes over A's exact (dir, port).
      await serve(dirX.path, 4371);
      expect(await _waitDead(a.pid, timeout: const Duration(seconds: 30)), isTrue,
          reason: 'C replaces the instance on the same dir+port');
      expect(await waitUp(4371), isTrue, reason: 'C must serve on the port');

      // THE load-bearing assertions: the replacement must not have widened
      // past its own key. Under the old artifactDir-only key, B dies here.
      expect(_alive(b.pid), isTrue,
          reason: 'B (same design, port 4372) is untouched by C replacing A');
      expect(await _statusOf('http://127.0.0.1:4372/'), isNotNull,
          reason: 'B still answers after C replaced A');
      expect(_alive(d.pid), isTrue,
          reason: 'D (different design) is untouched by C replacing A');
      expect(await _statusOf('http://127.0.0.1:4373/'), isNotNull,
          reason: 'D still answers after C replaced A');
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}
