// The 15-behavior contract for the Dart design server (plan Task 20.3), tested
// in-process: boot the server (HttpServer on loopback port 0) and assert. The
// process/signal behaviors (8, 14) are exercised via the stop()/registry paths
// rather than real signal delivery, per the in-process constraint.

library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:arxa/arxa_dial.dart';
import 'package:arxa/design_server.dart';
import 'package:arxa/design_server/worker.dart'
    show bundleBuildCount, findWorkerAssetsDir, packageDirFromScript;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final String _fixture =
    p.absolute('../skills/arxa-designer/examples/hello-hda');

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
    // `set`, not `add`: the browser-trust tests override Host, which dart:io
    // has already filled in from the URL.
    headers?.forEach((k, v) => req.headers.set(k, v));
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
    headers?.forEach((k, v) => req.headers.set(k, v));
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
      final r = resolveArtifact('arxa-studio');
      expect(r, isNotNull);
      expect(r!.dir.split(p.separator).last, 'arxa-studio');
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
      final r = resolveArtifact('arxa-studio');
      expect(r, isNotNull);
      expect(r!.tried.where((c) => c.endsWith('arxa-studio')).length,
          greaterThan(2));
    });
  });

  // ── serve from any cwd ─────────────────────────────────────────────────
  // Skills invoke `arxa` from wherever the engagement happens to be — a
  // client checkout, ~/.arxa — and the cwd-walk resolvers below only ever
  // find the repo when cwd is INSIDE it. From a client repo the walk goes
  // client → clients → … → / and never touches arxa, so `design serve`
  // closed its socket with StateError before serving anything (probes got
  // connection refused, not a 404). The package config of the RUNNING
  // script is the one cwd-independent anchor every invocation has.
  group('resource anchors (serve from any cwd)', () {
    test('worker assets resolve from a cwd outside the repo', () async {
      // A temp dir whose ancestor chain provably contains no arxa/.
      final foreign = await Directory.systemTemp.createTemp('foreign_cwd_');
      addTearDown(() => foreign.deleteSync(recursive: true));

      final assets = findWorkerAssetsDir(foreign.path);
      expect(assets, isNotNull,
          reason: 'design serve must boot from any cwd (client repos, '
              '~/.arxa) — the cwd walk alone never reaches arxa');
      expect(File(p.join(assets!, 'worker_page.html')).existsSync(), isTrue);
    });

    test('the compiled exe anchors the package walk when the resolver is null',
        () {
      // In the AOT binary Isolate.resolvePackageUriSync returns null (no
      // package config at runtime), which silenced BOTH cwd-independent
      // anchors and broke `arxa design serve` from any cwd outside the
      // repo — measured 2026-08-21 against the real .build/arxa. The exe
      // lives inside the repo, so its own path is the fallback anchor. This
      // drives that arm with a synthetic exe path instead of an AOT build.
      final repoRoot = p.dirname(p.absolute('.')); // …/arxa
      final pkg =
          packageDirFromScript(Uri.file(p.join(repoRoot, '.build', 'arxa')));
      expect(pkg, isNotNull,
          reason: 'walking up from <repo>/.build/arxa must find '
              'arxa/pubspec.yaml');
      expect(File(p.join(pkg!, 'pubspec.yaml')).existsSync(), isTrue);

      // And from a path with no arxa/ ancestor, the walk reports failure
      // instead of guessing.
      final foreignExe = Uri.file(
          p.join(Directory.systemTemp.path, 'nowhere', 'arxa'));
      expect(packageDirFromScript(foreignExe), isNull);
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
          DesignServer.start(
              dialStore: MemoryDialStore(),
              artifactDir: _fixture,
              port: holder.port),
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

  // ── P3b regression: a RELATIVE artifactDir must boot the same as an
  // absolute one. The worker fetches app.routes.js from the server origin and
  // the server resolves artifact files against the process cwd at REQUEST
  // time — a relative dir only works while that cwd never moves. start()
  // absolutizes the dir before the worker boots.
  group('relative artifactDir', () {
    test('boot + app.routes.js + a route all answer with a relative path',
        () async {
      final rel = p.relative(_fixture);
      expect(p.isRelative(rel), isTrue, reason: 'the test needs a relative form');
      final s = await DesignServer.start(
          dialStore: MemoryDialStore(),
          artifactDir: rel,
          port: 0,
          noWatch: true);
      try {
        expect(s.artifactDir, p.normalize(_fixture));
        final routes = await _get('${s.url}app.routes.js');
        expect(routes.status, 200);
        final home = await _get(s.url);
        expect(home.status, 200);
        expect(home.body, contains('hello-hda'));
      } finally {
        await s.stop();
      }
    });
  });

  // ── Chrome-backed serving behaviors (boot once) ────────────────────────
  group('serving (Chrome worker)', () {
    DesignServer? srv;
    late String tempDir;

    setUpAll(() async {
      tempDir = (await Directory.systemTemp.createTemp('design-server-test-')).path;
      await _copyDir(_fixture, tempDir);
      srv = await DesignServer.start(
          dialStore: MemoryDialStore(), artifactDir: tempDir, port: 0);
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
          reason: 'TSX bundle + l10n survived the coalesced reload');
    });

    test('5: record URL answers 200 + renders <html>', () async {
      final r = await _get(srv!.url);
      expect(r.status, 200);
      expect(r.body.toLowerCase(), contains('<html'));
      // l10n + TSX rendered: the title carries the en catalog text.
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
      // The stated view mounts its three factor variants (five-file law),
    // each with a rung-suffixed timer id (timer--desktop/tablet/mobile) — a
    // bare id would collide across the tripled copies.
    expect(r.body, contains('id="timer--desktop"'));
    });

    // Task #21: contract probes derive their targets from the design instead
    // of hard-coding studio routes, so the server has to be able to say what
    // it serves. These pin the shape they depend on.
    test('21: /__routes lists the served routes as method/path JSON', () async {
      final r = await _get('${srv!.url}__routes');
      expect(r.status, 200);
      expect(r.headers['content-type'], contains('application/json'));
      final routes = (jsonDecode(r.body) as Map)['routes'] as List;
      expect(routes, isNotEmpty);
      for (final e in routes) {
        expect(e, isA<Map>());
        expect((e as Map)['method'], isNotEmpty);
        expect(e['path'], startsWith('/'));
      }
    });

    test('21: /__routes reports THIS design, not a hard-coded set', () async {
      // The hello-hda fixture serves `/` and `/timer`; it has no `/design`.
      // A contract probe pointed at it must discover those and nothing
      // studio-shaped, which is the whole basis of design-agnosticism.
      final routes =
          (jsonDecode((await _get('${srv!.url}__routes')).body) as Map)['routes']
              as List;
      final paths = [for (final e in routes) (e as Map)['path'] as String];
      expect(paths, contains('/timer'));
      expect(paths.where((p) => p.startsWith('/design')), isEmpty,
          reason: 'hello-hda has no design shell — a route list that claims '
              'otherwise is reporting the engine, not the design');
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
      // `class="muted"` lives in the composition widget since W1 (composition
      // files left the views; the body — and its literals — are defined once
      // in the widget library's home_body.tsx, invoked by every rung).
      final view = File(p.join(tempDir, 'ui', 'widgets', 'hello_home_widgets',
          'home_body.tsx'));
      final original = view.readAsStringSync();
      // Edit a literal that actually reaches the DOM (not l10n text). The
      // Txt widget forwards name/class/id only — an unknown prop would be
      // dropped and the assertion would fail even though the reload worked.
      const marker = 'id="reload-marker"';
      try {
        view.writeAsStringSync(
            original.replaceFirst('class="muted"', 'class="muted" $marker'));
        expect(original, isNot(contains(marker)),
            reason: 'fixture must not already carry the marker');
        await srv!.reload(); // re-bundle TSX + re-inject
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
          dialStore: MemoryDialStore(),
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

    test('19: a SELF-HEAL reboot also defers — not just the watcher\'s reload',
        () async {
      // The window opens on two paths, and this is the second. `JsWorker`
      // reboots itself when it finds a lost realm (task #64), and that reboot
      // re-navigates the tab exactly as a watcher reload does. The request
      // that TRIGGERS the reboot is safe — dispatch awaits the reboot before
      // retrying — but any OTHER request arriving during it hits the same
      // empty table.
      //
      // An earlier version of this fix tracked the reload in DesignServer
      // itself, which could only ever see the watcher's; this case is why the
      // wait is on JsWorker.reloadInFlight, the one signal both paths set.
      await _get('$base/timer'); // control: worker is healthy
      await srv.breakWorkerForTest();

      // First request finds the lost realm and starts the self-heal; the
      // others pile in while the tab is mid-reboot.
      final all = await Future.wait([
        _get('$base/timer'),
        Future.delayed(const Duration(milliseconds: 120))
            .then((_) => _get('$base/timer')),
        Future.delayed(const Duration(milliseconds: 400))
            .then((_) => _get('$base/timer')),
        Future.delayed(const Duration(milliseconds: 900))
            .then((_) => _get('$base/timer')),
      ]);

      expect(all.map((r) => r.status).where((c) => c == 404), isEmpty,
          reason: 'a request concurrent with a self-heal reboot got a 404 from '
              'an empty route table — got ${all.map((r) => r.status).toList()}');
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
          dialStore: MemoryDialStore(),
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

  // ── M9: a broken TSX bundle surfaces on every route, not just stderr ────
  group('tsx bundle error surface', () {
    late Directory tmp;
    late DesignServer srv;

    setUpAll(() async {
      tmp = await Directory.systemTemp.createTemp('design-tsxerr-');
      await _copyDir(_fixture, tmp.path);
      // Break one view: esbuild cannot bundle the render module.
      final view = File(p.join(
          tmp.path, 'ui', 'views', 'main_shell', 'timer', 'timer_view.tsx'));
      await view.writeAsString(
          '${await view.readAsString()}\nexport const Broken = () => (<div>{oops</div>);\n');
      // Boot must SURVIVE a broken bundle — the error rides the 5xx surface.
      srv = await DesignServer.start(
          dialStore: MemoryDialStore(),
          artifactDir: tmp.path, port: 0, noWatch: true);
    });
    tearDownAll(() async {
      await srv.stop();
      await tmp.delete(recursive: true);
    });

    test('every route answers 500 with the esbuild diagnosis', () async {
      final r = await _get(srv.url);
      expect(r.status, 500);
      expect(r.body, contains('esbuild failed to bundle render.tsx'));
    });

    test('an htmx request gets the toast fragment with the diagnosis', () async {
      final r = await _get(srv.url, headers: {'HX-Request': 'true'});
      expect(r.status, 500);
      expect(r.body, contains('toast-error'));
      expect(r.body, contains('esbuild failed to bundle render.tsx'));
    });

    test('a clean rebuild clears the error and routes serve again', () async {
      final view = File(p.join(
          tmp.path, 'ui', 'views', 'main_shell', 'timer', 'timer_view.tsx'));
      final src = await view.readAsString();
      await view.writeAsString(src.split('\nexport const Broken').first);
      await srv.reload();
      final r = await _get(srv.url);
      expect(r.status, 200);
      expect(r.body, contains('hello-hda'));
    });
  });

  // ── the render bundle cache: esbuild reruns only when the .tsx tree moves ─
  group('render bundle cache', () {
    late Directory tmp;
    late DesignServer srv;

    setUpAll(() async {
      tmp = await Directory.systemTemp.createTemp('design-bundles-');
      await _copyDir(_fixture, tmp.path);
      srv = await DesignServer.start(
          dialStore: MemoryDialStore(),
          artifactDir: tmp.path, port: 0, noWatch: true);
    });
    tearDownAll(() async {
      await srv.stop();
      await tmp.delete(recursive: true);
    });

    test('a fixture-only reload reuses the bundle; a tsx edit rebuilds',
        () async {
      final afterBoot = bundleBuildCount;
      // JSON fixture edit: the bundle does not depend on it.
      final fixture = File(p.join(tmp.path, 'models', 'greeting_model',
          'greeting_fixtures.json'));
      await fixture.writeAsString('${await fixture.readAsString()}\n');
      await srv.reload();
      expect(bundleBuildCount, afterBoot,
          reason: 'a fixture-only edit must not rebundle');

      // A .tsx edit changes the render bundle's inputs.
      final view = File(p.join(tmp.path, 'ui', 'views', 'main_shell', 'timer',
          'timer_view.tsx'));
      await view.writeAsString('${await view.readAsString()}\n// touched\n');
      await srv.reload();
      expect(bundleBuildCount, afterBoot + 1,
          reason: 'a tsx edit must rebundle');

      final r = await _get(srv.url);
      expect(r.status, 200);
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
      srv = await DesignServer.start(
          dialStore: MemoryDialStore(), artifactDir: tmp.path, port: 0);
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
      expect(r.body, isNot(contains('package:arxa')));
      // and it must still say something human
      expect(r.body, contains('arxa server'));
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

  // ── 404 catch-all: the artifact's own unknown surface ──────────────────
  // An artifact that registers a GET /unknown route (arxa-studio's
  // app.unknown surface) has authored its not-found page, so a whole-page
  // miss renders THAT under a 404 — dispatched internally to the registered
  // route, not redirected. The fallback for an artifact WITHOUT such a route
  // (hello-hda) is pinned by the 'error surface' group above: its unmatched
  // GETs still get the server's own _errorPage.
  group('404 catch-all (artifact unknown surface)', () {
    late DesignServer srv;
    late String base;

    setUpAll(() async {
      // The real studio design, not a fixture: the wiring only matters if
      // the shipped artifact's surface actually renders through it.
      srv = await DesignServer.start(
          dialStore: MemoryDialStore(),
          artifactDir: p.absolute('../designs/arxa-studio'),
          port: 0,
          noWatch: true);
      // srv.url ends in '/' — see the 'error surface' group.
      base = srv.url.substring(0, srv.url.length - 1);
    });
    tearDownAll(() async {
      await srv.stop();
    });

    test('an unmatched GET renders the artifact surface, status 404',
        () async {
      final r = await _get('$base/definitely-not-a-studio-route');
      expect(r.status, 404);
      // The surface's own authored strings (l10n app_en.arb unknown.*), not
      // the server's errorSurface.* page.
      expect(r.body, contains('No route for this path.'));
      expect(r.body, isNot(contains('no route for GET')));
      expect(r.headers['content-type'], contains('text/html'));
    });

    test('GET /unknown itself still answers 200', () async {
      final r = await _get('$base/unknown');
      expect(r.status, 200);
      expect(r.body, contains('No route for this path.'));
    });

    test('an htmx fragment miss keeps the toast, not the page', () async {
      // The catch-all is for whole-page GETs only; a fragment fetch that
      // misses must still land in #toasts via the 404 retarget in base.html.
      final r = await _get('$base/definitely-not-a-studio-route',
          headers: {'HX-Request': 'true'});
      expect(r.status, 404);
      expect(r.body, contains('toast-error'));
      expect(r.body, isNot(contains('<html')));
      expect(r.body, isNot(contains('No route for this path.')));
    });
  });

  // ── behavior 8: stop releases the port (own boot) ──────────────────────
  group('lifecycle', () {
    test('8: stop() releases the port (rebind succeeds)', () async {
      final tmp = await Directory.systemTemp.createTemp('design-stop-');
      await _copyDir(_fixture, tmp.path);
      final s = await DesignServer.start(
          dialStore: MemoryDialStore(), artifactDir: tmp.path, port: 0);
      final port = s.port;
      await s.stop();
      // The port must be free again.
      final rebound = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      await rebound.close();
      await tmp.delete(recursive: true);
    });
  });

  // ── the browser-trust guard + the live-reload stream, on the wire ────────
  // browser_trust_test.dart covers the decision table; this group proves the
  // decision is actually WIRED — that a refused request never reaches a
  // handler, and that an allowed one gets its CORS header.
  group('browser trust + /__events', () {
    DesignServer? srv;
    late String tempDir;
    const panel = 'http://arxa.studio.localhost:7891';
    String base() => 'http://127.0.0.1:${srv!.port}';

    setUpAll(() async {
      tempDir =
          (await Directory.systemTemp.createTemp('design-events-test-')).path;
      await _copyDir(_fixture, tempDir);
      srv = await DesignServer.start(
        dialStore: MemoryDialStore(),
        artifactDir: tempDir,
        port: 0,
        trustedOrigins: const [panel],
        // The heartbeat is also the reaper (see _eventHeartbeat) — at the
        // 20s default the departed-subscriber test would sit there waiting.
        eventHeartbeat: const Duration(milliseconds: 150),
      );
    });

    tearDownAll(() async {
      await srv?.stop();
      try {
        await Directory(tempDir).delete(recursive: true);
      } catch (_) {}
    });

    // dart:io ships X-Frame-Options: SAMEORIGIN in defaultResponseHeaders, so
    // this asserts a header is GONE that no line of this repo ever set. The
    // browser-level proof that framing actually commits is in
    // design_server_framing_test.dart — a fetch cannot see X-Frame-Options at
    // all, which is precisely how this shipped broken.
    test('the dart:io X-Frame-Options default is gone, CSP replaces it',
        () async {
      final r = await _get('${base()}/');
      expect(r.status, 200);
      expect(r.headers['x-frame-options'], isNull,
          reason: 'SAMEORIGIN refuses every cross-origin iframe, and the '
              'header has no allowlist form (ALLOW-FROM is obsolete)');
      final csp = r.headers['content-security-policy'];
      expect(csp, isNotNull);
      expect(csp, contains('frame-ancestors'));
      expect(csp, contains(panel), reason: 'the trusted origin must be able '
          'to frame us, or the panel iframe stays blank');
      expect(csp, isNot(contains('*')));
    });

    // A scaled-down preview shows the design's own inner scrollers as bars,
    // which read as harness artifacts. The panel and the RungLadder frame us
    // cross-origin and cannot reach this document's CSS, so the server hides
    // them — but ONLY for a framed navigation, or opening the URL in a tab
    // would silently lose its scrollbars too.
    test('a framed navigation gets the scrollbar-hiding style', () async {
      final r = await _get('${base()}/', headers: {'sec-fetch-dest': 'iframe'});
      expect(r.status, 200);
      expect(r.body, contains('__arxa_framed'));
      expect(r.body, contains('scrollbar-width:none'));
      // Hidden, not disabled: neither property stops the wheel.
      expect(r.body, isNot(contains('overflow:hidden!important')));
    });

    test('a normal navigation and a sub-resource do NOT get it', () async {
      for (final dest in [null, 'document', 'script', 'empty']) {
        final r = await _get('${base()}/',
            headers: dest == null ? const {} : {'sec-fetch-dest': dest});
        expect(r.body, isNot(contains('__arxa_framed')),
            reason: 'Sec-Fetch-Dest: ${dest ?? "(absent)"}');
      }
    });

    test('DNS rebinding: a foreign Host is refused with 421', () async {
      final r = await _get('${base()}/__projects',
          headers: {'host': 'evil.example.com'});
      expect(r.status, 421);
    });

    test('the same request with an honest Host is served', () async {
      expect((await _get('${base()}/__projects')).status, 200);
    });

    test('CSRF: the cross-site POST that used to write files is refused',
        () async {
      // Exactly what a malicious page could send before this guard: a CORS
      // "simple request", so no preflight ever asked our permission.
      final r = await _post(
        '${base()}/__project_write',
        '{"path":"pwned.js","body":"x"}',
        headers: {
          'origin': 'https://evil.example',
          'sec-fetch-site': 'cross-site',
        },
      );
      expect(r.status, 403);
      expect(File(p.join(tempDir, 'pwned.js')).existsSync(), isFalse);
    });

    test('a non-browser caller (CLI, probe, lens) is untouched', () async {
      // No Origin, no Sec-Fetch-* — the documented fail-open path.
      final r = await _get('${base()}/__routes');
      expect(r.status, 200);
      expect(r.body, contains('"routes"'));
    });

    test('the stream carries the SSE headers a proxy will not eat', () async {
      final sse = await _openSse('${base()}/__events');
      addTearDown(sse.close);
      expect(sse.status, 200);
      expect(sse.headers['content-type'], contains('text/event-stream'));
      expect(sse.headers['cache-control'], contains('no-cache'));
      expect(sse.headers['cache-control'], contains('no-transform'));
      expect(sse.headers['x-accel-buffering'], 'no');
      expect(sse.headers['x-content-type-options'], 'nosniff');
      // Proof that bufferOutput is off: bytes arrive before the response ends.
      await sse.waitFor('retry: 500');
    });

    test('an allowlisted origin is echoed back, never a wildcard', () async {
      final sse = await _openSse('${base()}/__events', headers: {
        'origin': panel,
        'sec-fetch-site': 'cross-site',
      });
      addTearDown(sse.close);
      expect(sse.headers['access-control-allow-origin'], panel);
      expect(sse.headers['vary'], contains('Origin'));
      // Nothing here is cookie-authenticated, so credentials are never granted.
      expect(sse.headers.containsKey('access-control-allow-credentials'),
          isFalse);
    });

    test('an un-allowlisted origin is refused the stream', () async {
      final r = await _get('${base()}/__events', headers: {
        'origin': 'https://evil.example',
        'sec-fetch-site': 'cross-site',
      });
      expect(r.status, 403);
    });

    test('a reload fires a reload event with a rising generation', () async {
      final sse = await _openSse('${base()}/__events');
      addTearDown(sse.close);
      await sse.waitFor(': subscribed');
      await srv!.reload();
      // Fails on timeout — an empty stream must not read as a pass.
      await sse.waitFor(RegExp(r'event: reload\ndata: \{"generation":1\}'));
      await srv!.reload();
      await sse.waitFor(RegExp(r'"generation":2'));
    });

    test('a departed subscriber is dropped (no leaked socket, no timer)',
        () async {
      // A closed socket is noticed asynchronously, so settle first: this
      // wait is itself the proof that every earlier test's subscriber was
      // reaped rather than left in the set.
      Future<void> settle(int want) async {
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (srv!.eventSubscribersForTest != want &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
        expect(srv!.eventSubscribersForTest, want);
      }

      await settle(0);
      final sse = await _openSse('${base()}/__events');
      await sse.waitFor(': subscribed');
      expect(srv!.eventSubscribersForTest, 1);
      await sse.close();
      await settle(0);
    });
  });
}

/// A live SSE subscription: the response headers plus everything the server
/// has pushed so far.
class _Sse {
  _Sse(this._client, this.status, this.headers, this._buf, this._sub);
  final HttpClient _client;
  final int status;
  final Map<String, String> headers;
  final StringBuffer _buf;
  final StreamSubscription<String> _sub;

  String get text => _buf.toString();

  /// Block until [pattern] shows up in the stream, or THROW. A stream test
  /// that reads an empty buffer and moves on is a test that passes when the
  /// server never fires.
  Future<void> waitFor(Pattern pattern,
      {Duration timeout = const Duration(seconds: 8)}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (text.contains(pattern)) return;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    throw StateError('SSE: never saw $pattern. Received:\n$text');
  }

  Future<void> close() async {
    await _sub.cancel();
    _client.close(force: true);
  }
}

Future<_Sse> _openSse(String url, {Map<String, String>? headers}) async {
  final client = HttpClient();
  final req = await client.getUrl(Uri.parse(url));
  headers?.forEach((k, v) => req.headers.set(k, v));
  // Never awaited to completion — an event stream has no end.
  final res = await req.close();
  final h = <String, String>{};
  res.headers.forEach((k, v) => h[k] = v.join(','));
  final buf = StringBuffer();
  final sub = utf8.decoder
      .bind(res)
      .listen(buf.write, onError: (Object _) {}, cancelOnError: false);
  return _Sse(client, res.statusCode, h, buf, sub);
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
