// Lens glow overlay — the opt-in --visible status glow.
//
// Proves injectLensGlow/removeLensGlow reach the page, that the overlay is
// parented to documentElement (so body-scoped token probes never see it),
// and that navigateAndSettle leaves the page clean — the glow is injected
// during the settle window and removed before any capture/data-read.
import 'dart:async';
import 'dart:io';

import 'package:arxa/cdp.dart';
import 'package:test/test.dart';

Future<(HttpServer, String)> _bootGlowServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final base = 'http://${server.address.address}:${server.port}';
  server.listen((req) {
    req.response.headers.contentType = ContentType.html;
    req.response.write(
        '<!DOCTYPE html><html><body><p>glow fixture</p></body></html>');
    req.response.close();
  });
  return (server, base);
}

void main() {
  group('lens glow', () {
    late CdpClient client;
    late HttpServer server;
    late String baseUrl;

    setUp(() async {
      (server, baseUrl) = await _bootGlowServer();
      client = await CdpClient.launch();
    });
    tearDown(() async {
      await client.close();
      await server.close();
      // Never leak visible mode into sibling tests — headless is the default.
      LensSession.visible = false;
      LensSession.verb = null;
      LensSession.detail = null;
    });

    test('injectLensGlow adds the overlay; removeLensGlow clears it', () async {
      LensSession.visible = true;
      LensSession.verb = 'tokens';
      final tab = await client.newTab();
      await tab.enable();
      await tab.navigateAndSettle(baseUrl, settleMs: 200);

      await tab.injectLensGlow();
      expect(await tab.evaluate('!!document.getElementById("arxa-lens-glow")'),
          true);
      expect(
          await tab.evaluate('!!document.getElementById("arxa-lens-glow-label")'),
          true);

      await tab.removeLensGlow();
      expect(await tab.evaluate('!!document.getElementById("arxa-lens-glow")'),
          false);
      expect(
          await tab.evaluate('!!document.getElementById("arxa-lens-glow-label")'),
          false);
    });

    test('glow is parented to documentElement, not body', () async {
      LensSession.visible = true;
      LensSession.verb = 'shot';
      final tab = await client.newTab();
      await tab.enable();
      await tab.navigateAndSettle(baseUrl, settleMs: 200);
      await tab.injectLensGlow();
      // extractTokens probes `body, body *` — the glow MUST live outside body.
      expect(
          await tab.evaluate(
              'document.getElementById("arxa-lens-glow") && '
              '!document.body.contains(document.getElementById("arxa-lens-glow"))'),
          true);
    });

    test('visible: navigateAndSettle removes the glow before returning',
        () async {
      LensSession.visible = true;
      LensSession.verb = 'tokens';
      final tab = await client.newTab();
      await tab.enable();
      await tab.navigateAndSettle(baseUrl, settleMs: 300);
      // Injected during settle, removed at the end — capture/data-read is clean.
      expect(await tab.evaluate('!!document.getElementById("arxa-lens-glow")'),
          false);
    });

    test('headless default: navigateAndSettle never injects', () async {
      LensSession.visible = false;
      final tab = await client.newTab();
      await tab.enable();
      await tab.navigateAndSettle(baseUrl, settleMs: 300);
      expect(await tab.evaluate('!!document.getElementById("arxa-lens-glow")'),
          false);
    });
  });
}
