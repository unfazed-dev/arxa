// The design server's browser-trust guard, tested as pure decisions — no
// socket, no Chrome. The wire-level proof (a real request refused on a real
// port) lives in design_server_test.dart; this file is where the header FORMS
// get covered, because that is where allowlists actually fail: mlflow #22095
// rejected valid clients over `Host: localhost` vs `Host: localhost:5000` and
// the "fix" people reach for is turning the check off.

library;

import 'package:appboxd/design_server/browser_trust.dart';
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
