// Browser-context isolation, against real Chrome.
//
// The property under test is the one a shared-browser probe runner needs and
// cannot check for itself: two tabs in different contexts do not share a cookie
// jar, so they do not share a server session.
//
// This is not abstract tidiness. The studio keys its session off a `kdh_sid`
// cookie, so which viewer lens is showing, where a flow walk has advanced to,
// and whether the inspector is locked all travel with that cookie. The `.mjs`
// suite isolated probes by accident — one `node` process each, so one browser
// each. A Dart runner sharing one browser across `probe all` loses that, and
// the first casualty was real: the retired `explode` probe left the viewer on
// the flows lens, and `flowwalk`'s opening section then read flows-lens
// toolbars while asserting about the views lens.

import 'dart:io';

import 'package:appboxd/cdp.dart';
import 'package:test/test.dart';

/// A server that echoes the session cookie it set, minting one per fresh
/// client — the shape the studio's `kdh_sid` handling has.
Future<(HttpServer, String)> bootSessionServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final base = 'http://${server.address.address}:${server.port}';
  var minted = 0;

  server.listen((req) {
    final raw = req.headers.value('cookie') ?? '';
    var sid = '';
    for (final part in raw.split(';')) {
      final kv = part.trim().split('=');
      if (kv.length == 2 && kv[0] == 'sid') sid = kv[1];
    }
    if (sid.isEmpty) {
      sid = 's${++minted}';
      req.response.headers.add('Set-Cookie', 'sid=$sid; Path=/');
    }
    req.response.headers.contentType = ContentType.html;
    req.response.write('<!DOCTYPE html><html><head>'
        '<meta charset="utf-8"><title>sid</title></head>'
        '<body><span id="sid">$sid</span></body></html>');
    req.response.close();
  });

  return (server, base);
}

void main() {
  group('CdpClient browser contexts', () {
    late CdpClient client;
    late HttpServer server;
    late String base;

    // One browser for the group. Chrome is the scarce resource in this suite,
    // and a launch per test turned into `DevToolsActivePort` timeouts under
    // contention — a failure mode with nothing to say about contexts.
    // Sharing is safe here precisely because the thing under test is
    // isolation: each case makes its own context, and the default-context
    // case only ever asserts that two tabs AGREE.
    setUpAll(() async {
      (server, base) = await bootSessionServer();
      client = await CdpClient.launch();
    });

    tearDownAll(() async {
      await client.close();
      await server.close(force: true);
    });

    Future<String> sidOf(CdpSession session) async {
      await session.navigate(base);
      return await session.evaluate(
          "document.getElementById('sid').textContent") as String;
    }

    test('two tabs in the default context share one session', () async {
      final a = await client.newTab();
      await a.enable();
      final b = await client.newTab();
      await b.enable();

      final sidA = await sidOf(a);
      expect(await sidOf(b), sidA,
          reason: 'if this ever fails, tabs isolate on their own and the '
              'context plumbing below is unnecessary — but so long as it '
              'passes, a shared-browser runner shares server state');
    });

    test('a tab in its own context gets its own session', () async {
      final shared = await client.newTab();
      await shared.enable();
      final sidShared = await sidOf(shared);

      final ctxId = await client.createBrowserContext();
      final isolated = await client.newTab(browserContextId: ctxId);
      await isolated.enable();

      expect(await sidOf(isolated), isNot(sidShared));
      await client.disposeBrowserContext(ctxId);
    });

    test('two isolated contexts do not share with each other', () async {
      final one = await client.createBrowserContext();
      final two = await client.createBrowserContext();
      final a = await client.newTab(browserContextId: one);
      await a.enable();
      final b = await client.newTab(browserContextId: two);
      await b.enable();

      expect(await sidOf(a), isNot(await sidOf(b)));
      await client.disposeBrowserContext(one);
      await client.disposeBrowserContext(two);
    });

    test('disposing a context twice is not an error', () async {
      final ctxId = await client.createBrowserContext();
      final tab = await client.newTab(browserContextId: ctxId);
      await tab.enable();
      await sidOf(tab);

      await client.disposeBrowserContext(ctxId);
      // Teardown order is not always knowable at the call site; a second
      // dispose must not become the failure a probe reports.
      await client.disposeBrowserContext(ctxId);
    });
  }, timeout: const Timeout(Duration(minutes: 3)));
}
