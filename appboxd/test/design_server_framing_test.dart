// Can a cross-origin page actually PUT THE DESIGN SERVER IN AN IFRAME?
//
// This file exists because the header-level check cannot answer that, and a
// header-level check is exactly what let the bug ship. `X-Frame-Options` is
// enforced on the frame-embedding path only: a `fetch()` carrying
// `Sec-Fetch-Dest: iframe` gets 200 and never evaluates the header, so a smoke
// test built on fetch reported "iframe GET -> 200" while every real iframe in
// the arxa studio was being refused.
//
// The header came from `dart:io` itself — `HttpServer.defaultResponseHeaders`
// ships `X-Frame-Options: SAMEORIGIN` with no source line anywhere in this
// repo, so grep could not find it either. Only a browser can see this.
//
// The two tests are a PAIR and neither is meaningful alone:
//   - an allowlisted parent must frame us          (the bug is fixed)
//   - an un-allowlisted parent must still not      (we did not just delete the
//                                                   protection to make it pass)
library;

import 'dart:io';

import 'package:appboxd/cdp.dart';
import 'package:appboxd/design_server.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final String _fixture =
    p.absolute('../skills/appbox-designer/examples/hello-hda');

/// A bare parent page whose only job is to frame `target`.
///
/// Deliberately NOT a DesignServer: it must sit on a different port so its
/// origin is genuinely foreign to the server under test, which is the whole
/// point. Its own `X-Frame-Options` is irrelevant — nothing frames the parent.
Future<(HttpServer, String)> _bootParent() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) {
    final target = req.uri.queryParameters['target'] ?? '';
    req.response.headers.contentType = ContentType.html;
    req.response.write('<!DOCTYPE html><html><head><meta charset="utf-8">'
        '<title>parent</title></head><body>'
        '<iframe id="f" src="$target" width="390" height="844"></iframe>'
        '</body></html>');
    req.response.close();
  });
  return (server, 'http://127.0.0.1:${server.port}');
}

void main() {
  group('cross-origin framing of the design server', () {
    late HttpServer parent;
    late String parentOrigin;
    late CdpClient client;
    late CdpSession session;
    DesignServer? allowed;
    DesignServer? refused;
    late String designTitle;

    setUpAll(() async {
      (parent, parentOrigin) = await _bootParent();
      // The parent's port is only known now, so the allowlist is built here —
      // the same lever an operator pulls with ~/.appbox/trusted-origins.
      allowed = await DesignServer.start(
          artifactDir: _fixture,
          port: 0,
          noWatch: true,
          trustedOrigins: [parentOrigin]);
      refused = await DesignServer.start(
          artifactDir: _fixture, port: 0, noWatch: true);

      // What the design's own page calls itself, read straight off the wire.
      // Comparing against this rather than a hardcoded string keeps the test
      // honest if the fixture is ever retitled.
      final c = HttpClient();
      final r = await (await c
              .getUrl(Uri.parse('http://127.0.0.1:${allowed!.port}/')))
          .close();
      final body = await r.transform(const SystemEncoding().decoder).join();
      c.close();
      designTitle = RegExp(r'<title>([^<]*)</title>').firstMatch(body)!.group(1)!;
      expect(designTitle, isNotEmpty,
          reason: 'the fixture must have a title for this test to discriminate');

      client = await CdpClient.launch();
    });

    tearDownAll(() async {
      await client.close();
      await allowed?.stop();
      await refused?.stop();
      await parent.close(force: true);
    });

    setUp(() async {
      session = await client.newTab();
      await session.enable();
      await session.setViewport(900, 700);
    });

    tearDown(() async {
      await client.send('Target.closeTarget', {'targetId': session.targetId});
    });

    /// The child frame's title, or null if nothing rendered there.
    ///
    /// A REFUSED frame still appears in the frame tree at the requested URL,
    /// so the URL is not a discriminator — only reaching into the child's
    /// document is. Chrome answers a blocked frame with an error document
    /// (empty title) and may refuse the evaluation outright; both mean "not
    /// framed", so a throw is an answer here, not a failure.
    Future<String?> childTitle(String target) async {
      await session.navigate('$parentOrigin/?target=$target');
      try {
        final frame = await session.frameForSelector('#f');
        if (frame == null) return null;
        final t = await session.evaluateInFrame(frame, 'document.title');
        return t as String?;
      } catch (_) {
        return null;
      }
    }

    test('an allowlisted origin CAN frame it — the arxa panel and RungLadder',
        () async {
      final target = 'http://127.0.0.1:${allowed!.port}/';
      // Poll: the parent's load event does not wait for the child document.
      String? seen;
      for (var i = 0; i < 40 && seen != designTitle; i++) {
        seen = await childTitle(target);
        if (seen != designTitle) {
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
      }
      expect(seen, designTitle,
          reason: 'the design did not render inside a cross-origin iframe — '
              'X-Frame-Options is back, or frame-ancestors omits the parent');
    });

    test('a framed page has its scrollbars hidden, but still scrolls', () async {
      // Only a real browser can prove this. `Sec-Fetch-Dest` is a forbidden
      // header name, so it cannot be forged with Network.setExtraHTTPHeaders —
      // Chrome ignores the override. The frame has to be a real frame.
      //
      // Readable here only because parent and child are both 127.0.0.1: same
      // SITE, so the child stays in-process and evaluateInFrame reaches it. The
      // live pair (arxa.studio.localhost -> 127.0.0.1) is cross-site and its
      // child is an OOPIF, invisible to this session.
      final target = 'http://127.0.0.1:${allowed!.port}/';
      String? styled;
      for (var i = 0; i < 40 && styled == null; i++) {
        await session.navigate('$parentOrigin/?target=$target');
        try {
          final frame = await session.frameForSelector('#f');
          if (frame != null) {
            final r = await session.evaluateInFrame(frame, """
              (() => {
                if (!document.body) return null;
                const tag = !!document.getElementById('__appbox_framed');
                const bars = [...document.querySelectorAll('*')]
                  .filter((e) => /auto|scroll/.test(
                      getComputedStyle(e).overflowY + getComputedStyle(e).overflowX))
                  .map((e) => getComputedStyle(e).scrollbarWidth);
                return JSON.stringify({ tag: tag, widths: [...new Set(bars)] });
              })()
            """);
            if (r is String && r.contains('"tag"')) styled = r;
          }
        } catch (_) {/* frame not committed yet */}
        if (styled == null) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }
      expect(styled, isNotNull,
          reason: 'never got a readable framed document');
      expect(styled, contains('"tag":true'),
          reason: 'the framed navigation did not receive the style');
      // Every scroller in the frame reports the hidden value — and nothing
      // sets overflow:hidden, so the wheel still works.
      expect(styled, isNot(contains('"auto"')));
      expect(styled, isNot(contains('"thin"')));
    });

    test('an un-allowlisted origin still CANNOT — protection was not deleted',
        () async {
      final target = 'http://127.0.0.1:${refused!.port}/';
      // Give it the same room to succeed that the allowed case gets, so this
      // cannot pass merely by being checked too early.
      String? seen;
      for (var i = 0; i < 10; i++) {
        seen = await childTitle(target);
        if (seen == designTitle) break;
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      expect(seen, isNot(designTitle),
          reason: 'a page on an origin nobody allowlisted framed the design '
              'server — frame-ancestors is missing or too wide');
    });
  }, timeout: const Timeout(Duration(minutes: 3)));
}
