// The 15-behavior contract for the Dart design server (plan Task 20.3), tested
// in-process: boot the server (HttpServer on loopback port 0) and assert. The
// process/signal behaviors (8, 14) are exercised via the stop()/registry paths
// rather than real signal delivery, per the in-process constraint.

library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appboxd/design_server.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final String _fixture =
    p.absolute('../skills/appbox-designer/examples/hello-hda');

/// Make `__boot`'s module import slow, so the reload window is wide enough to
/// hit on purpose instead of by luck (task #19).
///
/// A reload passes through two distinct broken states, and only the second is
/// the defect under test:
///   1. navigated, shim not yet injected — `__dispatch` is undefined. The
///      task-#64 self-heal already catches this and reboots, so requests here
///      are answered correctly.
///   2. shim injected, `__boot` still importing — `__dispatch` EXISTS and
///      `routesTable` is still `[]`, so every request 404s and nothing
///      notices. This is #19.
///
/// State 2's width is the artifact's import cost. `hello-hda` boots almost
/// instantly, so sampling a live reload lands in state 1 and passes while the
/// defect is fully present — verified: this group's first test passed against
/// the unfixed server before this helper existed. The real studio's module
/// graph makes state 2 ~950ms wide, which is why production 404s.
///
/// Top-level `await` (not a busy-wait) so the tab's main thread stays
/// responsive: the point is that the worker ANSWERS during the window, wrongly.
Future<void> _widenBootWindow(String artifactDir, {int ms = 2500}) async {
  final slow = File(p.join(artifactDir, '_slow_boot.js'));
  await slow.writeAsString(
      '// test-only: widens the __boot window (see _widenBootWindow)\n'
      'await new Promise((r) => setTimeout(r, $ms));\n'
      'export const slowBoot = true;\n');
  final routes = File(p.join(artifactDir, 'app.routes.js'));
  await routes.writeAsString(
      "import './_slow_boot.js';\n${await routes.readAsString()}");
}

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
  final int status;
  final String body;
  final Map<String, String> headers;
  _Resp(this.status, this.body, this.headers);
}

/// The `kdh_sid` cookie from a response, formatted to send straight back as a
/// `cookie:` header. Needed because [_get]/[_post] open a fresh HttpClient per
/// call and keep no cookie jar — so without this, every request is a NEW
/// session, and any test about per-session state is really testing global state.
String? _sidCookie(_Resp r) {
  final sc = r.headers['set-cookie'];
  if (sc == null) return null;
  final m = RegExp(r'kdh_sid=([^;,]+)').firstMatch(sc);
  return m == null ? null : 'kdh_sid=${m.group(1)}';
}

Future<_Resp> _get(String url, {Map<String, String>? headers}) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    headers?.forEach((k, v) => req.headers.add(k, v));
    final res = await req.close();
    final body = await utf8.decoder.bind(res).join();
    final h = <String, String>{};
    res.headers.forEach((k, v) => h[k] = v.join(','));
    return _Resp(res.statusCode, body, h);
  } finally {
    client.close(force: true);
  }
}

Future<_Resp> _post(String url, String body,
    {Map<String, String>? headers}) async {
  final client = HttpClient();
  try {
    final req = await client.postUrl(Uri.parse(url));
    req.headers.contentType =
        ContentType.parse('application/x-www-form-urlencoded');
    headers?.forEach((k, v) => req.headers.add(k, v));
    req.add(utf8.encode(body));
    final res = await req.close();
    final b = await utf8.decoder.bind(res).join();
    final h = <String, String>{};
    res.headers.forEach((k, v) => h[k] = v.join(','));
    return _Resp(res.statusCode, b, h);
  } finally {
    client.close(force: true);
  }
}

void main() {
  // ── behaviors 1, 9: target resolution (pure, no Chrome) ────────────────
  group('resolution', () {
    test('1: bare design name resolves to designs/<name>', () {
      final r = resolveArtifact('appbox-studio');
      expect(r, isNotNull);
      expect(r!.dir.split(p.separator).last, 'appbox-studio');
      expect(r.dir, contains('designs'));
      // the walk-up must have considered several candidates
      expect(r.tried.length, greaterThan(2));
    });

    test('9: unknown design name → resolveArtifact is null', () {
      expect(resolveArtifact('no-such-design-zzz'), isNull);
    });

    test('9: designServe unknown name → exit 66', () async {
      // Returns before serving (no Chrome boot) — safe to call directly.
      expect(await designServe(['no-such-design-zzz', '--port', '0']), 66);
    });

    test('9: candidate walk considers > 3 paths (probes app.routes.js)', () {
      // resolveArtifact probes app.routes.js in each candidate; a miss leaves a
      // tried-list longer than 3 (cwd, cwd/designs, and the walk-up chain).
      final r = resolveArtifact('appbox-studio');
      expect(r, isNotNull);
      expect(r!.tried.where((c) => c.endsWith('appbox-studio')).length,
          greaterThan(2));
    });
  });

  // ── usage / exit-code parsing (pure, returns before serving) ───────────
  group('CLI usage', () {
    test('no target → exit 64', () async {
      expect(await designServe(['--port', '0']), 64);
    });
    test('unknown flag → exit 64', () async {
      expect(await designServe([_fixture, '--bogus']), 64);
    });
    test('bad port → exit 64', () async {
      expect(await designServe([_fixture, '--port', '99999']), 64);
      expect(await designServe([_fixture, '--port', 'notaport']), 64);
    });
  });

  // ── behavior 7: port collision (no Chrome needed for the throw) ────────
  group('bind errors', () {
    test('7: bindExitCode maps EADDRINUSE → 69', () {
      final e = SocketException('Address already in use (errno = 48)',
          osError: OSError('Address already in use', 48));
      expect(bindExitCode(e), 69);
    });
    test('7: bindExitCode maps EACCES → 77', () {
      final e = SocketException('Permission denied (errno = 13)',
          osError: OSError('Permission denied', 13));
      expect(bindExitCode(e), 77);
    });
    test('7: bindExitCode maps other → 70', () {
      final e = SocketException('weird', osError: OSError('x', 99));
      expect(bindExitCode(e), 70);
    });

    test('7: start on an occupied port throws → maps to 69', () async {
      final holder = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      try {
        // await expectLater holds holder open for the duration of the bind
        // attempt (closing it early would free the port and let bind succeed).
        await expectLater(
          DesignServer.start(artifactDir: _fixture, port: holder.port),
          throwsA(isA<SocketException>()),
        );
      } finally {
        await holder.close();
      }
    });
  });

  // ── behaviors 14, 15: pidfile registry (pure) ──────────────────────────
  group('pidfile registry', () {
    test('15: register then deregister sweeps the file', () {
      final dir = serveRegistryDir;
      // clean any stale entries for this test pid
      deregisterServeInstance(999901);
      registerServeInstance(999901, '/tmp/art-A', port: 4001);
      expect(File(p.join(dir.path, '999901.json')).existsSync(), isTrue);
      deregisterServeInstance(999901);
      expect(File(p.join(dir.path, '999901.json')).existsSync(), isFalse);
    });

    test('14: sweep targets only same-artifact siblings (no real kill)', () {
      // Use fake pids that no real process owns → sweep deletes the stale
      // pidfiles (the ps check fails) rather than signalling anything live.
      registerServeInstance(999902, '/tmp/art-sweep', port: 4001);
      registerServeInstance(999903, '/tmp/art-sweep', port: 4001);
      registerServeInstance(999904, '/tmp/art-other', port: 4001);
      final dir = serveRegistryDir;
      try {
        final killed =
            sweepSiblingInstances(999902, '/tmp/art-sweep', port: 4001);
        // 999903 is a same-artifact sibling; 999904 is a different artifact
        // (never considered). Neither pid is live → both stale files swept.
        expect(killed, isEmpty);
        expect(File(p.join(dir.path, '999903.json')).existsSync(), isFalse,
            reason: 'same-artifact sibling pidfile swept (stale)');
        expect(File(p.join(dir.path, '999904.json')).existsSync(), isTrue,
            reason: 'different-artifact entry untouched');
      } finally {
        // 999902 is the sweep's own selfPid, so the sweep skips it and it was
        // being left behind in the shared registry dir on every run.
        deregisterServeInstance(999902);
        deregisterServeInstance(999903);
        deregisterServeInstance(999904);
      }
    });
  });

  // ── behavior 11: ready output (pure) ───────────────────────────────────
  group('ready output', () {
    test('11: --host 0.0.0.0 prints the every-interface warning', () {
      final lines = humanReadyLines(
          url: 'http://localhost:5000/',
          host: '0.0.0.0',
          artifactDir: '/x',
          port: 5000);
      expect(lines.join('\n'), contains('bound to every interface'));
    });

    test('11: loopback host omits the warning', () {
      final lines = humanReadyLines(
          url: 'http://127.0.0.1:5000/',
          host: '127.0.0.1',
          artifactDir: '/x',
          port: 5000);
      expect(lines.join('\n'), isNot(contains('bound to every interface')));
    });
  });

  // ── Chrome-backed serving behaviors (boot once) ────────────────────────
  group('serving (Chrome worker)', () {
    DesignServer? srv;
    late String tempDir;

    setUpAll(() async {
      tempDir = (await Directory.systemTemp.createTemp('design-server-test-')).path;
      await _copyDir(_fixture, tempDir);
      srv = await DesignServer.start(artifactDir: tempDir, port: 0);
    });

    tearDownAll(() async {
      await srv?.stop();
      if (tempDir != '') {
        try {
          await Directory(tempDir).delete(recursive: true);
        } catch (_) {}
      }
    });

    test('2: --port 0 reports the OS-bound port', () {
      expect(srv!.port, greaterThan(0));
    });

    test('3: ready record carries url/port/host/pid/artifact/workerPid', () {
      expect(srv!.url, startsWith('http://'));
      expect(srv!.port, greaterThan(0));
      expect(srv!.host, '127.0.0.1');
      expect(srv!.pid, greaterThan(0));
      expect(srv!.artifactDir, tempDir);
      expect(srv!.workerPid, greaterThan(0));
    });

    test('4: pid (supervisor) != workerPid (Chrome)', () {
      expect(srv!.pid, isNot(equals(srv!.workerPid)));
    });

    // ── task #51: a worker tab that lost its globals must heal ────────────
    // Before this, a tab whose realm was replaced (the concurrent-reload race
    // below) answered every subsequent request with a 500 forever: nothing in
    // JsWorker reboots except reload(), and reload() only runs on a file
    // change. The server stayed up and stayed dead, which is why it read as
    // "the studio crashed" rather than "one request failed".
    test('51: a lost __dispatch is rebooted and the request still succeeds',
        () async {
      final before = await _get(srv!.url);
      expect(before.status, 200, reason: 'sanity: healthy before the break');

      await srv!.breakWorkerForTest();

      final after = await _get(srv!.url);
      expect(after.status, 200, reason: 'the worker must self-heal, not 500');
      expect(after.body.toLowerCase(), contains('<html'));
      // Healed for good, not just for the one retry.
      expect((await _get(srv!.url)).status, 200);
    });

    // The race that produces the lost realm in the first place: two reloads in
    // flight on one tab interleave navigate/inject/__boot, and A's __boot can
    // run against B's half-loaded page.
    //
    // This asserts the COUNT, not "the tab still works afterwards". The
    // outcome-shaped version of this test passed with the single-flight guard
    // deleted — three concurrent reloads on an idle machine interleave benignly
    // often enough to be useless as evidence. The count is the contract and
    // cannot pass by luck: 3 calls must produce 2 runs (the one in flight, plus
    // exactly one trailing re-run so an edit that landed mid-reload is not
    // silently dropped), never 3.
    test('51: concurrent reloads coalesce to one in-flight run + one trailing',
        () async {
      final before = srv!.workerReloadRunsForTest;
      await Future.wait([srv!.reload(), srv!.reload(), srv!.reload()]);
      expect(srv!.workerReloadRunsForTest - before, 2);

      final r = await _get(srv!.url);
      expect(r.status, 200);
      expect(r.body, contains('hello-hda'),
          reason: 'templates + l10n survived the coalesced reload');
    });

    test('5: record URL answers 200 + renders <html>', () async {
      final r = await _get(srv!.url);
      expect(r.status, 200);
      expect(r.body.toLowerCase(), contains('<html'));
      // l10n + Nunjucks rendered: the title carries the en catalog text.
      expect(r.body, contains('hello-hda'));
    });

    test('Vary: HX-Request always present; Accept-Language for HTML', () async {
      final r = await _get(srv!.url);
      expect(r.headers['vary']?.toLowerCase(), contains('hx-request'));
      expect(r.headers['vary']?.toLowerCase(), contains('accept-language'));
    });

    test('6: not reachable from a LAN IP by default (loopback bind)',
        () async {
      final lan = await _lanIp();
      if (lan == null) {
        // CI / no-LAN environments: the loopback bind is the contract; skip.
        return;
      }
      expect(
        Socket.connect(lan, srv!.port, timeout: const Duration(seconds: 2)),
        throwsA(anyOf(isA<SocketException>(), isA<TimeoutException>())),
      );
    });

    test('10: a served viewmodel route (GET /timer) → 200', () async {
      final r = await _get('${srv!.url}timer');
      expect(r.status, 200);
      expect(r.body, contains('id="timer"'));
    });

    test('static artifact file served (app.routes.js)', () async {
      final r = await _get('${srv!.url}app.routes.js');
      expect(r.status, 200);
      expect(r.body, contains('shellRoots'));
    });

    test('assets/vendor htmx served from runtime vendor', () async {
      final r = await _get('${srv!.url}assets/vendor/htmx.min.js');
      expect(r.status, 200);
      expect(r.body, contains('htmx'));
    });

    test('prefs/lang POST sets cookie + HX-Refresh under HX-Request', () async {
      final r = await _post('${srv!.url}prefs/lang', 'lang=en');
      expect([302, 200], contains(r.status));
      expect(r.headers['set-cookie'], isNotNull);
    });

    test('12: hot reload picks up an edit (same port)', () async {
      final view = File(p.join(
          tempDir, 'ui', 'views', 'main_shell', 'home', 'home_view.html'));
      final original = view.readAsStringSync();
      // Edit a literal that actually lives in the template (not l10n text).
      const marker = 'data-reload-marker="1"';
      try {
        view.writeAsStringSync(
            original.replaceFirst('class="muted"', 'class="muted" $marker'));
        expect(original, isNot(contains(marker)),
            reason: 'fixture must not already carry the marker');
        await srv!.reload(); // re-import cache-busted + refresh prefetch
        final r = await _get(srv!.url);
        expect(r.status, 200);
        expect(r.body, contains(marker));
      } finally {
        view.writeAsStringSync(original);
        await srv!.reload();
        final r = await _get(srv!.url);
        expect(r.body, isNot(contains(marker)));
      }
    });

    test('13: server-side timers survive a reload', () async {
      // NOW CARRIES THE SESSION COOKIE, and that is the point. This test used
      // to fire cookie-less requests, each of which mints a NEW session — so it
      // only ever passed because `_timers` was a process-wide map every session
      // could read (task #53). It was asserting the bug, not the feature.
      // Keying the timers per session broke it immediately, which is exactly
      // what a test resting on a defect should do when the defect is fixed.
      final first = await _get('${srv!.url}timer');
      final cookie = _sidCookie(first);
      expect(cookie, isNotNull, reason: 'server must mint a session cookie');
      final asSessionA = {'cookie': cookie!};

      final before = await _get('${srv!.url}timer/tick', headers: asSessionA);
      expect(before.status, 200);
      final remainRe = RegExp(r'>(\d+)s<');
      final m1 = remainRe.firstMatch(before.body);
      expect(m1, isNotNull, reason: 'tick body shows remaining: ${before.body}');
      final n1 = int.parse(m1!.group(1)!);
      // Reload (re-imports modules; Dart _timers untouched).
      await srv!.reload();
      final after = await _get('${srv!.url}timer/tick', headers: asSessionA);
      expect(after.status, 200);
      final m2 = remainRe.firstMatch(after.body);
      expect(m2, isNotNull);
      final n2 = int.parse(m2!.group(1)!);
      // Timer survived: still ~30 (within the reload window, not 0/reset).
      expect(n2, lessThanOrEqualTo(n1));
      expect(n2, greaterThan(0), reason: 'timer survived the reload');
    });

    test("53: one session's request cannot wipe another session's timer",
        () async {
      // The leak had two halves and this covers the damaging one. Every
      // response used to run `_timers..clear()..addAll(resp.timers)` — replacing
      // the WHOLE process-wide map with whatever one session's worker returned.
      // Two people using the studio at once therefore deleted each other's
      // running timers on every request, continuously.
      // The assertion must discriminate by VALUE, not by presence. Checking
      // only "A still sees a timer" passes with the bug fully restored, because
      // B starts a 'rest' timer too — A then reads B's timer under the same id
      // and the check never notices the swap. Verified: that weaker version
      // stayed green when the process-wide map was put back.
      //
      // So A extends its timer to ~45s while B's stays at ~30s. Now A reading
      // 30 means A is reading B's clock.
      final remainRe = RegExp(r'>(\d+)s<');
      int remaining(_Resp r) {
        final m = remainRe.firstMatch(r.body);
        expect(m, isNotNull, reason: 'no remaining in body: ${r.body}');
        return int.parse(m!.group(1)!);
      }

      final a = await _get('${srv!.url}timer'); // starts 'rest' at 30
      final aCookie = _sidCookie(a);
      expect(aCookie, isNotNull);
      final asA = {'cookie': aCookie!};
      final aExtended = await _post('${srv!.url}timer/extend', '', headers: asA);
      final aBefore = remaining(aExtended); // ~45
      expect(aBefore, greaterThan(35), reason: "A's timer was extended");

      // Session B: a different browser (no cookie → a fresh session, 30s).
      final b = await _get('${srv!.url}timer');
      final bCookie = _sidCookie(b);
      expect(bCookie, isNot(equals(aCookie)), reason: 'B is a distinct session');
      await _get('${srv!.url}timer/tick', headers: {'cookie': bCookie!});

      // A must still be on ITS OWN clock. Under the process-wide map, B's
      // response replaced the whole map and A dropped to ~30.
      final aAfter = remaining(await _get('${srv!.url}timer/tick', headers: asA));
      expect(aAfter, greaterThan(35),
          reason: "B's traffic replaced A's timer (A now reads B's clock)");
    });

    test('404 for unknown route', () async {
      final r = await _get('${srv!.url}no-such-route');
      expect(r.status, 404);
      expect(r.body, contains('no route for'));
    });
  });

  // ── task #19: the hot-reload window ────────────────────────────────────
  //
  // `reload()` re-navigates the worker tab, which wipes the JS realm — so
  // `worker_shim.js`'s `let routesTable = []` re-runs and stays empty until
  // `__boot` re-imports app.routes.js. For ~950ms `globalThis.__dispatch`
  // still EXISTS while the table is EMPTY, and every request 404s. Dart keeps
  // dispatching because its own boot-time copy still holds all the routes, and
  // the task-#64 self-heal cannot see it: that matches "__dispatch is not a
  // function", and here dispatch works fine and has nothing to route.
  //
  // Measured live: a canvas mutation writes the project, the watcher schedules
  // a reload 200ms later, and the undo POST that follows lands inside the
  // window and 404s — so the user's undo is silently lost, not delayed. Undo
  // is only the request that always immediately follows a write; EVERY request
  // in the window is affected, which is what these tests pin.
  group('#19: the hot-reload window', () {
    late Directory tmp;
    late DesignServer srv;
    late String base;

    setUpAll(() async {
      tmp = await Directory.systemTemp.createTemp('design-reload-');
      await _copyDir(_fixture, tmp.path);
      await _widenBootWindow(tmp.path);
      // noWatch: the reload under test is triggered explicitly, so the file
      // watcher would only add nondeterminism.
      srv = await DesignServer.start(
          artifactDir: tmp.path, port: 0, noWatch: true);
      base = srv.url.substring(0, srv.url.length - 1);
    });
    tearDownAll(() async {
      await srv.stop();
      await tmp.delete(recursive: true);
    });

    test('19: requests during a hot reload are answered, never 404ed', () async {
      // Sampling starts AFTER the navigate+settle, not at reload(). A reload
      // is broken in two different ways in sequence, and only the second is
      // #19 (see _widenBootWindow). A request in the first phase throws
      // "__dispatch is not a function", which the task-#64 self-heal catches
      // and reboots — and that reboot then re-boots the whole worker, so an
      // early sample MASKS the phase under test. Verified: sampling from t=0
      // passed against the unfixed server twice.
      //
      // navigateAndSettle is 600ms, so 800ms clears it with margin, and
      // _widenBootWindow holds __boot open for 2500ms after that.
      final reloading = srv.reload();
      await Future.delayed(const Duration(milliseconds: 800));
      final codes = <int>[];
      for (var i = 0; i < 12; i++) {
        codes.add((await _get('$base/timer')).status);
        await Future.delayed(const Duration(milliseconds: 100));
      }
      await reloading;
      expect(codes.where((c) => c == 404), isEmpty,
          reason: 'a route that EXISTS 404ed while __boot was still importing: '
              'the worker answered with an empty route table — got $codes');
    });

    test('19: a genuinely unknown route still 404s — after the wait, not '
        'instead of it', () async {
      // The fix must not turn every in-window 404 into a 503: a route that
      // does not exist has to keep answering 404 once the reload settles, or
      // the deferral has swallowed a real routing bug.
      final reloading = srv.reload();
      final r = await _get('$base/no-such-route-at-all');
      await reloading;
      expect(r.status, 404);
      expect(r.body, contains('no route for'));
    });

    test('19: a reload that outlives the grace fails loudly and bounded',
        () async {
      // A 1ms grace guarantees expiry while the reload is still running. The
      // requirement is that expiry is LOUD and BOUNDED: a distinct 503 naming
      // the reload, never a silent 404, and never a hang.
      final tmp2 = await Directory.systemTemp.createTemp('design-reload-b-');
      await _copyDir(_fixture, tmp2.path);
      await _widenBootWindow(tmp2.path);
      final s = await DesignServer.start(
          artifactDir: tmp2.path,
          port: 0,
          noWatch: true,
          reloadGrace: const Duration(milliseconds: 1));
      try {
        final reloading = s.reload();
        final sw = Stopwatch()..start();
        final r = await _get('${s.url}timer');
        sw.stop();
        await reloading;
        expect(r.status, 503, reason: 'expired grace must be its own status');
        expect(r.status, isNot(404), reason: 'never a silent 404');
        expect(sw.elapsed, lessThan(const Duration(seconds: 5)),
            reason: 'the wait is bounded — a stuck reload must not hang a request');
      } finally {
        await s.stop();
        await tmp2.delete(recursive: true);
      }
    });
  });

  // ── the error surface: a failed request must SAY something, and must not
  //    say what the exception said (own boot) ─────────────────────────────
  group('error surface', () {
    late Directory tmp;
    late DesignServer srv;
    late String base;

    setUpAll(() async {
      tmp = await Directory.systemTemp.createTemp('design-err-');
      await _copyDir(_fixture, tmp.path);
      srv = await DesignServer.start(artifactDir: tmp.path, port: 0);
      // srv.url ends in '/' — a second one would make the path '//…', which
      // matches no route and lands in the 404 branch instead of the one
      // under test.
      base = srv.url.substring(0, srv.url.length - 1);
    });
    tearDownAll(() async {
      await srv.stop();
      await tmp.delete(recursive: true);
    });

    // The 500 trigger: a truncated UTF-8 percent-escape. Uri.decodeComponent
    // on the vendor path throws FormatException into the top-level catch —
    // deterministic, server-side, and needs no Chrome route.
    const throwUrl = '/assets/vendor/%E0%A4%A';

    test('a throwing handler → 500', () async {
      final r = await _get('$base$throwUrl');
      expect(r.status, 500);
    });

    // ── task #46: the error surface is translatable ──────────────────────
    // It could not be, before: design_server.dart hard-coded English consts,
    // and the obvious fix — call the worker's t() — is the wrong one, because
    // the worker is a thing that can BE the failure. ErrorCatalog reads the
    // ARB files off disk instead, sharing no state with the tab.

    test('46: an untranslated key still renders the authored English', () async {
      // hello-hda's catalogs carry no errorSurface.* keys at all, so this is
      // the miss path — and a miss must produce the real sentence, never the
      // raw key. "errorSurface.notFound" on screen would be a second failure
      // stacked on the first.
      final r = await _get('$base/design/definitely-not-a-route');
      expect(r.status, 404);
      expect(r.body, contains('no route for GET /design/definitely-not-a-route'));
      expect(r.body, isNot(contains('errorSurface.')));
    });

    test('46: a translated key wins, and lang= drives the <html lang>', () async {
      // Written AFTER the server booted, which also pins the no-cache choice:
      // ErrorCatalog re-reads on every render, so this needs no reload. If a
      // cache is ever added, this test is what fails.
      File(p.join(tmp.path, 'l10n', 'app_pl.arb')).writeAsStringSync(jsonEncode({
        '@@locale': 'pl',
        'errorSurface.notFound': 'brak trasy dla {method} {path}',
        'errorSurface.pageHint': 'Nic nie zostało utracone.',
        'errorSurface.backHome': 'Powrót do pulpitu',
      }));

      final r = await _get('$base/design/nope?lang=pl');
      expect(r.status, 404);
      expect(r.body, contains('brak trasy dla GET /design/nope'),
          reason: 'both placeholders substituted, in the Polish string');
      expect(r.body, contains('Powrót do pulpitu'));
      // A Polish page announcing lang="en" mis-pronounces every word.
      expect(r.body, contains('<html lang="pl">'));
      expect(r.body, isNot(contains('no route for')));
    });

    test('46: the locale-dependent body declares Vary: Accept-Language',
        () async {
      // Without it a shared cache serves one visitor's language to the next.
      final r = await _get('$base/design/nope');
      expect(r.headers['vary']?.toLowerCase(), contains('accept-language'));
      expect(r.headers['vary']?.toLowerCase(), contains('hx-request'));
    });

    test('46: an unreadable catalog degrades to English, it does not crash',
        () async {
      final f = File(p.join(tmp.path, 'l10n', 'app_pl.arb'));
      final good = f.readAsStringSync();
      f.writeAsStringSync('{ this is not json');
      try {
        final r = await _get('$base/design/nope?lang=pl');
        expect(r.status, 404, reason: 'a broken catalog must not become a 500');
        expect(r.body, contains('no route for GET /design/nope'));
      } finally {
        f.writeAsStringSync(good);
      }
    });

    // A malformed body is the CLIENT's mistake. /__project_write already
    // classified it 400; /__project_use reported the identical failure as a
    // 500 until this slice.
    test('a malformed body is a 400, not a 500', () async {
      for (final bad in ['not-json', 'null', '[]', '"x"']) {
        final r = await _post('$base/__project_use', bad);
        expect(r.status, 400, reason: 'body: $bad');
        expect(jsonDecode(r.body), {'ok': false, 'error': 'bad JSON body'});
        // the raw parser message must not ride along
        expect(r.body, isNot(contains('FormatException')));
      }
    });

    test('500 body carries NO raw exception text (the bad-state leak)',
        () async {
      final r = await _get('$base$throwUrl');
      // Red-first: today's `'500 — $e'` writes the exception's toString
      // straight to the client. None of it may reach the wire.
      expect(r.body, isNot(contains('FormatException')));
      expect(r.body, isNot(contains('Missing extension byte')));
      // nor any stack, if the handler is ever changed to write one
      expect(r.body, isNot(contains('package:appboxd')));
      // and it must still say something human
      expect(r.body, contains('appbox server'));
    });

    test('500: full-page request → an HTML page, HX-Request → a fragment',
        () async {
      final page = await _get('$base$throwUrl');
      expect(page.status, 500);
      expect(page.body, startsWith('<!doctype html>'));
      expect(page.body, contains('error-page'));
      expect(page.headers['content-type'], contains('text/html'));

      final frag =
          await _get('$base$throwUrl', headers: {'HX-Request': 'true'});
      expect(frag.status, 500);
      // The fragment is toast-only: no page shell, or htmx would swap a whole
      // document into the tray.
      expect(frag.body, isNot(contains('<!doctype')));
      expect(frag.body, isNot(contains('<html')));
      expect(frag.body, contains('toast-error'));
      // both shapes come off the same URL → the cache must vary on it
      expect(frag.headers['vary'], contains('HX-Request'));
    });

    test('404 uses the same surface (page vs fragment), still human',
        () async {
      final page = await _get('$base/no-such-route-zzz');
      expect(page.status, 404);
      expect(page.body, startsWith('<!doctype html>'));
      expect(page.body, contains('no route for'));

      final frag = await _get('$base/no-such-route-zzz',
          headers: {'HX-Request': 'true'});
      expect(frag.status, 404);
      expect(frag.body, contains('toast-error'));
      expect(frag.body, isNot(contains('<html')));
    });

    test('a user-controlled path cannot inject markup into the 404', () async {
      final r = await _get('$base/%3Cimg%20src=x%20onerror=alert(1)%3E');
      expect(r.status, 404);
      // The message echoes the path, so the page is only safe because the
      // path is inert: req.uri.path keeps it percent-encoded, and _esc()
      // covers it if that ever stops being true.
      expect(r.body, isNot(contains('<img')));
      expect(r.body, contains('%3Cimg'));
    });

    test('an asset miss stays plain text, not the HTML surface', () async {
      // /assets/vendor/* is fetched by <script>/<link>, never by htmx — an
      // HTML body for a missing .js would be worse than none.
      final r = await _get('$base/assets/vendor/no-such-file-zzz.js');
      expect(r.status, 404);
      expect(r.headers['content-type'], contains('text/plain'));
      expect(r.body, isNot(contains('<html')));
    });
  });

  // ── behavior 8: stop releases the port (own boot) ──────────────────────
  group('lifecycle', () {
    test('8: stop() releases the port (rebind succeeds)', () async {
      final tmp = await Directory.systemTemp.createTemp('design-stop-');
      await _copyDir(_fixture, tmp.path);
      final s = await DesignServer.start(artifactDir: tmp.path, port: 0);
      final port = s.port;
      await s.stop();
      // The port must be free again.
      final rebound = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      await rebound.close();
      await tmp.delete(recursive: true);
    });
  });
}

Future<String?> _lanIp() async {
  try {
    final addrs = await NetworkInterface.list(type: InternetAddressType.IPv4);
    for (final iface in addrs) {
      for (final a in iface.addresses) {
        if (!a.isLoopback) return a.address;
      }
    }
    return null;
  } catch (_) {
    return null;
  }
}
