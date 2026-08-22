// The design server's browser-trust guard, tested as pure decisions — no
// socket, no Chrome. The wire-level proof (a real request refused on a real
// port) lives in design_server_test.dart; this file is where the header FORMS
// get covered, because that is where allowlists actually fail: mlflow #22095
// rejected valid clients over `Host: localhost` vs `Host: localhost:5000` and
// the "fix" people reach for is turning the check off.

library;

import 'dart:io';

import 'package:appboxd/design_server.dart' show readTrustedOriginsFile;
import 'package:appboxd/design_server/browser_trust.dart';
import 'package:appboxd/project.dart' show appboxHomeOverride;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

BrowserTrust _loopback({
  List<String> hosts = const [],
  List<String> origins = const [],
}) =>
    BrowserTrust(
      boundHost: '127.0.0.1',
      port: 4319,
      trustedHosts: hosts,
      trustedOrigins: origins,
    );

void main() {
  group('normalizeHost — every form a Host header arrives in', () {
    for (final (raw, want) in const [
      ('localhost', 'localhost'),
      ('localhost:4319', 'localhost'),
      ('LocalHost:4319', 'localhost'),
      ('127.0.0.1:4319', '127.0.0.1'),
      ('[::1]:4319', '::1'),
      ('[::1]', '::1'),
      // A bare IPv6 literal has colons but no port; it must survive whole.
      ('::1', '::1'),
      ('arxa.studio.localhost:7891', 'arxa.studio.localhost'),
      ('  evil.example.com  ', 'evil.example.com'),
      // ":not-a-number" is part of the name, not a port.
      ('host:abc', 'host:abc'),
    ]) {
      test('$raw -> $want', () => expect(normalizeHost(raw), want));
    }
  });

  group('hostAllowed — the DNS-rebinding gate', () {
    final t = _loopback();
    test('loopback names pass in all their forms', () {
      for (final h in [
        'localhost',
        'localhost:4319',
        '127.0.0.1:4319',
        '127.0.0.53',
        '[::1]:4319',
        'anything.localhost:4319',
      ]) {
        expect(t.hostAllowed(h), isTrue, reason: h);
      }
    });

    test('a rebinding attacker\'s own name is refused', () {
      for (final h in [
        'evil.example.com',
        'evil.example.com:4319',
        // The classic near-miss: a name that merely CONTAINS a loopback label.
        'localhost.evil.example.com',
        '127.0.0.1.evil.example.com',
      ]) {
        expect(t.hostAllowed(h), isFalse, reason: h);
      }
    });

    test('--trusted-host adds a name, with or without the port', () {
      final t = _loopback(hosts: ['studio.lan']);
      expect(t.hostAllowed('studio.lan:4319'), isTrue);
      expect(t.hostAllowed('other.lan'), isFalse);
    });

    test('absent Host is allowed — the attack requires the header', () {
      expect(t.hostAllowed(null), isTrue);
      expect(t.hostAllowed(''), isTrue);
    });

    test('a wildcard bind stands the check down', () {
      final wide = BrowserTrust(boundHost: '0.0.0.0', port: 4319);
      expect(wide.wildcardBind, isTrue);
      expect(wide.hostAllowed('evil.example.com'), isTrue);
      expect(_loopback().wildcardBind, isFalse);
    });
  });

  group('originAllowed — who may talk to us cross-origin', () {
    test('our own server under any loopback alias, at OUR port', () {
      final t = _loopback();
      expect(t.originAllowed('http://127.0.0.1:4319'), isTrue);
      expect(t.originAllowed('http://localhost:4319'), isTrue);
      expect(t.originAllowed('http://[::1]:4319'), isTrue);
    });

    test('another local dev server on another port is NOT us', () {
      // The springboard case: a local tool that renders untrusted HTML
      // (a notebook, a mail preview) must not inherit our trust.
      expect(_loopback().originAllowed('http://localhost:8888'), isFalse);
    });

    test('a public origin is refused however it is spelled', () {
      final t = _loopback();
      for (final o in [
        'https://evil.example',
        'http://evil.example:4319',
        'http://localhost.evil.example:4319',
        'null',
      ]) {
        expect(t.originAllowed(o), isFalse, reason: o);
      }
    });

    test('--trusted-origin admits one exactly', () {
      final t = _loopback(origins: ['http://arxa.studio.localhost:7891']);
      expect(t.originAllowed('http://arxa.studio.localhost:7891'), isTrue);
      // Same host, different port — a different origin, still refused.
      expect(t.originAllowed('http://arxa.studio.localhost:9999'), isFalse);
    });
  });

  group('frameAncestors — who may iframe us', () {
    test('our own origin under each loopback spelling, at OUR port', () {
      final v = _loopback().frameAncestors;
      expect(v, startsWith("'self'"));
      expect(v, contains('http://127.0.0.1:4319'));
      expect(v, contains('http://localhost:4319'));
    });

    test('never emits a bracketed IPv6 literal — CSP cannot express one', () {
      // CSP3 §2.3.1: host-char = ALPHA / DIGIT / "-". No brackets and no
      // colons, so `http://[::1]:4319` parses as no production at all: the
      // browser drops it and logs "does not support the source expression"
      // on EVERY document load. This group used to assert that token was
      // PRESENT, which pinned the noise in place. `'self'` already covers a
      // document actually served over [::1].
      expect(_loopback().frameAncestors, isNot(contains('[')));
      // An operator who puts one in ~/.appbox/trusted-origins is NOT
      // filtered here, deliberately: the browser then names the exact bad
      // token in the console, which is a louder failure than us dropping it
      // silently and leaving them with framing that just does not work.
      expect(_loopback(origins: ['http://[::1]:7891']).frameAncestors,
          contains('[::1]'));
    });

    test('a trusted origin is admitted — this is the arxa panel', () {
      expect(_loopback(origins: ['http://arxa.studio.localhost:7891'])
          .frameAncestors, contains('http://arxa.studio.localhost:7891'));
    });

    test('nothing else is, and it is never a wildcard', () {
      final v = _loopback().frameAncestors;
      expect(v, isNot(contains('*')));
      expect(v, isNot(contains('arxa')));
      // The port matters: another local server is not us.
      expect(v, isNot(contains('http://localhost:8888')));
    });
  });

  group('guardedRequest — the resource-isolation surface', () {
    test('every state-changing method, anywhere', () {
      expect(BrowserTrust.guardedRequest('POST', '/prefs/lang'), isTrue);
      expect(BrowserTrust.guardedRequest('DELETE', '/anything'), isTrue);
    });
    test('every /__* endpoint, even on GET', () {
      expect(BrowserTrust.guardedRequest('GET', '/__projects'), isTrue);
      expect(BrowserTrust.guardedRequest('GET', '/__events'), isTrue);
    });
    test('the iframe and a typed URL stay unguarded', () {
      expect(BrowserTrust.guardedRequest('GET', '/'), isFalse);
      expect(BrowserTrust.guardedRequest('GET', '/design'), isFalse);
      expect(BrowserTrust.guardedRequest('GET', '/app.routes.js'), isFalse);
    });
  });

  group('~/.appbox/trusted-origins — the operator-level allowlist', () {
    late Directory home;

    setUp(() {
      home = Directory.systemTemp.createTempSync('appbox-home-');
      // Never the operator's real ~/.appbox: this test writes here.
      appboxHomeOverride = home.path;
    });
    tearDown(() {
      appboxHomeOverride = null;
      home.deleteSync(recursive: true);
    });

    void write(String body) =>
        File(p.join(home.path, 'trusted-origins')).writeAsStringSync(body);

    test('no file at all is not an error', () {
      expect(readTrustedOriginsFile(), isEmpty);
    });

    test('one origin per line, blanks and # comments ignored', () {
      write('# written by arxa\n'
          'http://arxa.studio.localhost:7891\n'
          '\n'
          'http://other.localhost:9000  # trailing comment\n');
      expect(readTrustedOriginsFile(), [
        'http://arxa.studio.localhost:7891',
        'http://other.localhost:9000',
      ]);
    });

    test('a line with no scheme is dropped, not silently un-matchable', () {
      // The 2am failure: it would pass normalizeOrigin's raw fallback, match
      // nothing, and read as "the flag didn't work".
      write('arxa.studio.localhost:7891\nhttp://good.localhost:1\n');
      expect(readTrustedOriginsFile(), ['http://good.localhost:1']);
    });

    test('what the file yields actually admits an origin', () {
      write('http://arxa.studio.localhost:7891\n');
      final t = BrowserTrust(
          boundHost: '127.0.0.1',
          port: 4319,
          trustedOrigins: readTrustedOriginsFile());
      expect(t.originAllowed('http://arxa.studio.localhost:7891'), isTrue);
      expect(t.originAllowed('https://evil.example'), isFalse);
    });
  });

  group('check — the whole decision', () {
    final t = _loopback(origins: ['http://arxa.studio.localhost:7891']);

    TrustVerdict post(String path,
            {String? origin, String? site, String host = '127.0.0.1:4319'}) =>
        t.check(
            method: 'POST',
            path: path,
            host: host,
            origin: origin,
            secFetchSite: site);

    test('THE CSRF THAT WAS OPEN: a cross-site POST to /__project_write', () {
      final v = post('/__project_write',
          origin: 'https://evil.example', site: 'cross-site');
      expect(v.allowed, isFalse);
      expect(v.status, 403);
    });

    test('rebinding is refused before the route is even looked at', () {
      final v = post('/__project_write',
          host: 'evil.example.com', origin: 'http://evil.example.com');
      expect(v.status, 421);
    });

    test('the worker page and its own writes pass', () {
      // Chrome navigating the worker tab: Sec-Fetch-Site: none.
      expect(
          t
              .check(
                  method: 'GET',
                  path: '/__worker_page',
                  host: '127.0.0.1:4319',
                  secFetchSite: 'none')
              .allowed,
          isTrue);
      // The worker page writing back into the project: same-origin.
      expect(
          post('/__project_write',
                  origin: 'http://127.0.0.1:4319', site: 'same-origin')
              .allowed,
          isTrue);
    });

    test('the CLI, probes and lens keep working — no browser headers', () {
      final v = post('/__project_write');
      expect(v.allowed, isTrue);
      expect(v.corsOrigin, isNull);
    });

    test('an allowlisted panel gets its origin echoed, never a wildcard', () {
      final v = t.check(
        method: 'GET',
        path: '/__events',
        host: '127.0.0.1:4319',
        origin: 'http://arxa.studio.localhost:7891',
        secFetchSite: 'cross-site',
      );
      expect(v.allowed, isTrue);
      expect(v.corsOrigin, 'http://arxa.studio.localhost:7891');
      expect(v.corsOrigin, isNot('*'));
    });

    test('a sandboxed frame gets Origin null echoed on asset GETs only', () {
      // The gen_ui RungLadder's deliberate strict sandbox (same-host URLs
      // stay opaque per the cookie threat model): module scripts are
      // CORS-mode, so unguarded assets must answer with the header…
      final v = t.check(
        method: 'GET',
        path: '/assets/vendor/htmx4.min.js',
        host: '127.0.0.1:4319',
        origin: 'null',
        secFetchSite: 'cross-site',
      );
      expect(v.allowed, isTrue);
      expect(v.corsOrigin, 'null');
      // …but a guarded route still refuses an unverifiable origin — the
      // sandboxed frame cannot call /__* or write anything.
      final g = t.check(
        method: 'GET',
        path: '/__events',
        host: '127.0.0.1:4319',
        origin: 'null',
        secFetchSite: 'cross-site',
      );
      expect(g.allowed, isFalse);
      expect(g.status, 403);
    });

    test('an un-allowlisted panel is refused the stream', () {
      final v = t.check(
        method: 'GET',
        path: '/__events',
        host: '127.0.0.1:4319',
        origin: 'http://someone.else:3000',
        secFetchSite: 'cross-site',
      );
      expect(v.status, 403);
    });

    test('a legacy browser with Origin but no fetch metadata is still held', () {
      expect(post('/prefs/lang', origin: 'https://evil.example').status, 403);
      expect(post('/prefs/lang', origin: 'http://127.0.0.1:4319').allowed,
          isTrue);
    });

    test('an unguarded GET is allowed even cross-site (the panel iframe)', () {
      final v = t.check(
        method: 'GET',
        path: '/design',
        host: '127.0.0.1:4319',
        secFetchSite: 'cross-site',
      );
      expect(v.allowed, isTrue);
    });
  });
}
