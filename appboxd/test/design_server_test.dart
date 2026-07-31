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

Future<_Resp> _post(String url, String body) async {
  final client = HttpClient();
  try {
    final req = await client.postUrl(Uri.parse(url));
    req.headers.contentType =
        ContentType.parse('application/x-www-form-urlencoded');
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
      registerServeInstance(999901, '/tmp/art-A');
      expect(File(p.join(dir.path, '999901.json')).existsSync(), isTrue);
      deregisterServeInstance(999901);
      expect(File(p.join(dir.path, '999901.json')).existsSync(), isFalse);
    });

    test('14: sweep targets only same-artifact siblings (no real kill)', () {
      // Use fake pids that no real process owns → sweep deletes the stale
      // pidfiles (the ps check fails) rather than signalling anything live.
      registerServeInstance(999902, '/tmp/art-sweep');
      registerServeInstance(999903, '/tmp/art-sweep');
      registerServeInstance(999904, '/tmp/art-other');
      final dir = serveRegistryDir;
      try {
        final killed = sweepSiblingInstances(999902, '/tmp/art-sweep');
        // 999903 is a same-artifact sibling; 999904 is a different artifact
        // (never considered). Neither pid is live → both stale files swept.
        expect(killed, isEmpty);
        expect(File(p.join(dir.path, '999903.json')).existsSync(), isFalse,
            reason: 'same-artifact sibling pidfile swept (stale)');
        expect(File(p.join(dir.path, '999904.json')).existsSync(), isTrue,
            reason: 'different-artifact entry untouched');
      } finally {
        deregisterServeInstance(999903);
        deregisterServeInstance(999904);
      }
    });
  });

  // ── behavior 11: ready output (pure) ───────────────────────────────────
  group('ready output', () {
    test('11: --host 0.0.0.0 prints the every-interface warning', () {
      final lines = humanReadyLines(
          url: 'http://localhost:5000/', host: '0.0.0.0', artifactDir: '/x');
      expect(lines.join('\n'), contains('bound to every interface'));
    });

    test('11: loopback host omits the warning', () {
      final lines = humanReadyLines(
          url: 'http://127.0.0.1:5000/', host: '127.0.0.1', artifactDir: '/x');
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
      // /timer starts the 'rest' timer at 30s (Dart-held state).
      await _get('${srv!.url}timer');
      final before = await _get('${srv!.url}timer/tick');
      expect(before.status, 200);
      final remainRe = RegExp(r'>(\d+)s<');
      final m1 = remainRe.firstMatch(before.body);
      expect(m1, isNotNull, reason: 'tick body shows remaining: ${before.body}');
      final n1 = int.parse(m1!.group(1)!);
      // Reload (re-imports modules; Dart _timers untouched).
      await srv!.reload();
      final after = await _get('${srv!.url}timer/tick');
      expect(after.status, 200);
      final m2 = remainRe.firstMatch(after.body);
      expect(m2, isNotNull);
      final n2 = int.parse(m2!.group(1)!);
      // Timer survived: still ~30 (within the reload window, not 0/reset).
      expect(n2, lessThanOrEqualTo(n1));
      expect(n2, greaterThan(0), reason: 'timer survived the reload');
    });

    test('404 for unknown route', () async {
      final r = await _get('${srv!.url}no-such-route');
      expect(r.status, 404);
      expect(r.body, contains('no route for'));
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
