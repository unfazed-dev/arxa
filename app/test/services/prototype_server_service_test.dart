// Plan 09 Done-when verification — the embedded engine (Dart HttpServer +
// flutter_js / JavaScriptCore) vs the Node baseline (serve.mjs / V8).
//
// Renders every (route, state) surface under both engines and diffs the HTML
// byte-for-byte (Done-when #1), proves a POST mutation updates a fragment
// (#2), and resolves every asset URL referenced in the rendered output to a
// real file (#3). NOT a unit test of behaviour — it is the equivalence proof.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:app_box/services/prototype_server_service.dart';

final _repo = Directory.current.parent.path;
final _design = '$_repo/designs/app-box-app';
final _vendor = '$_repo/skills/app-box-designer/runtime/vendor';

// route -> states (the design's full enumerable GET set: 14 surfaces, 29 states).
const _routes = <String, List<String>>{
  '/': ['list', 'empty', 'loading'],
  '/projects/new': ['form', 'validating', 'error'],
  '/design': ['three-up', 'approved'],
  '/design/surface': ['live', 'stale'],
  '/design/approve': ['pending', 'approved'],
  '/build': ['red', 'idle', 'running', 'green'],
  '/build/finding': ['finding'],
  '/build/approve': ['pending', 'approved'],
  '/ship': ['targets'],
  '/ship/confirm': ['pending', 'confirmed'],
  '/chat': ['idle', 'streaming', 'tool-call'],
  '/settings': ['credentials'],
  '/settings/devices': ['paired', 'revoke'],
  '/settings/kits': ['kits'],
};

Future<String> _get(HttpClient client, String url) async {
  final req = await client.getUrl(Uri.parse(url));
  final res = await req.close();
  final body = await res.transform(const Utf8Decoder()).join();
  expect(res.statusCode, 200, reason: url);
  return body;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test mocks HttpClient to return 400; this suite needs real
  // loopback sockets to talk to the embedded + Node servers.
  HttpOverrides.global = null;

  test('embedded engine renders all surfaces byte-for-byte identical to Node', () async {
    final service = PrototypeServerService();
    final emb = await service.start(
      designDir: _design,
      vendorDir: _vendor,
      runtime: 'embedded',
    );
    addTearDown(emb.stop);

    // Node baseline.
    final nodeProc = await Process.start(
      'node',
      ['$_repo/skills/app-box-designer/runtime/serve.mjs', 'app-box-app', '--port', '0', '--json'],
      workingDirectory: _repo,
    );
    addTearDown(() => nodeProc.kill());
    final ready = StringBuffer();
    final readyDone = await nodeProc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first;
    ready.write(readyDone);
    final nodeInfo = jsonDecode(ready.toString()) as Map<String, dynamic>;
    final nodeUrl = nodeInfo['url'] as String;

    final client = HttpClient();
    addTearDown(client.close);

    var identical = 0, differing = 0;
    final diffs = <String>[];
    final embBase = Uri.parse(emb.url);
    final nodeBase = Uri.parse(nodeUrl);
    for (final entry in _routes.entries) {
      for (final state in entry.value) {
        final nodeHtml = await _get(client,
            nodeBase.replace(path: entry.key, queryParameters: {'state': state}).toString());
        final embHtml = await _get(client,
            embBase.replace(path: entry.key, queryParameters: {'state': state}).toString());
        if (nodeHtml == embHtml) {
          identical++;
        } else {
          differing++;
          diffs.add('${entry.key}?state=$state :: ${_firstDiff(nodeHtml, embHtml)}');
        }
      }
    }

    // Self-check the counts: 29 surface-states across 14 surfaces (the design's
    // own README confirms "14 surfaces and 29 surface-states").
    expect(_routes.length, 14, reason: 'surface count');
    expect(_routes.values.expand((s) => s).length, 29, reason: 'surface-state count');

    if (diffs.isNotEmpty) {
      // Honest reporting — surface the exact diffs, do not fake identical.
      // ignore: avoid_print
      print('DIFFERING SURFACES:\n${diffs.join('\n')}');
    }
    expect(
      differing,
      0,
      reason: '$differing surface(s) differ between JSC and Node; '
          '$identical/$identical+ identical. See printed diffs.',
    );
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('POST mutation updates a fragment (Done-when #2)', () async {
    final service = PrototypeServerService();
    final emb = await service.start(
      designDir: _design,
      vendorDir: _vendor,
      runtime: 'embedded',
    );
    addTearDown(emb.stop);
    final client = HttpClient();
    addTearDown(client.close);

    // GET /design/approve on a fresh session -> "pending". Then POST the approve
    // mutation -> the #gate fragment re-renders as "approved". (design.approve.)
    final before = await _get(client, '${emb.url}design/approve?state=pending');
    expect(before, contains('Gate 1 · your decision'));

    // The approve POST sets session.designApproved and returns the gate fragment.
    final res = await client.postUrl(Uri.parse('${emb.url}design/approve/approve'));
    res.headers.contentType = ContentType.parse('application/x-www-form-urlencoded');
    final httpRes = await res.close();
    final setCookies = httpRes.headers[HttpHeaders.setCookieHeader] ?? [];
    final gate = await httpRes.transform(const Utf8Decoder()).join();
    expect(httpRes.statusCode, 200);
    expect(gate, contains('Gate 1 · approved by you'),
        reason: 'POST must return the approved gate fragment');
    expect(setCookies.any((c) => c.contains('kdh_sid')),
        true, reason: 'a session cookie is minted on first contact');

    // Session persists: a follow-up default GET (no ?state=) now reads
    // session.designApproved and renders "approved" — the write landed.
    final sid = RegExp(r'kdh_sid=([^;]+)')
        .firstMatch(setCookies.firstWhere((c) => c.contains('kdh_sid')))!
        .group(1)!;
    // Re-issue the default GET carrying the sid — the mutation must persist.
    final req2 = await client.getUrl(Uri.parse('${emb.url}design/approve'));
    req2.headers.set('Cookie', 'kdh_sid=$sid');
    final res2 = await req2.close();
    final persisted = await res2.transform(const Utf8Decoder()).join();
    expect(persisted, contains('Gate 1 · approved by you'),
        reason: 'the mutation must persist across the session');
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('every asset URL resolves to a real file (Done-when #3)', () async {
    final service = PrototypeServerService();
    final emb = await service.start(
      designDir: _design,
      vendorDir: _vendor,
      runtime: 'embedded',
    );
    addTearDown(emb.stop);
    final client = HttpClient();
    addTearDown(client.close);

    // Collect every src=/href= asset URL across all rendered surfaces.
    final urls = <String>{};
    for (final entry in _routes.entries) {
      for (final state in entry.value) {
        final html = await _get(client, '${emb.url}${entry.key.substring(1)}?state=$state');
        for (final m in RegExp(r'''(?:src|href)="(/[^"]*)"''').allMatches(html)) {
          final u = m.group(1)!;
          // Skip in-app route links (no extension) — those are pages, not assets.
          if (!u.startsWith('/assets/') && !u.startsWith('/_ds/')) continue;
          if (u.contains('{{')) continue; // templated, resolved at render
          urls.add(u);
        }
      }
    }

    expect(urls, isNotEmpty, reason: 'expected some asset URLs');
    final missing = <String>[];
    for (final u in urls) {
      final req = await client.getUrl(Uri.parse('${emb.url}${u.substring(1)}'));
      final res = await req.close();
      final data = <int>[];
      await for (final c in res) {
        data.addAll(c);
      }
      if (res.statusCode != 200 || data.isEmpty) {
        missing.add('$u -> ${res.statusCode} (${data.length} bytes)');
      }
    }
    // ignore: avoid_print
    print('resolved ${urls.length} distinct asset URL(s): ${urls.toList()..sort()}');
    expect(missing, isEmpty,
        reason:
            '${missing.length} asset(s) failed to resolve to a real file:\n${missing.join('\n')}');
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('embedded server serves a surface (the no-Node path)', () async {
    // The embedded path is Dart HttpServer + flutter_js (JavaScriptCore, a
    // system framework). It spawns no process and consults PATH for nothing.
    // Done-when #6 (no Node on PATH -> app still serves) is proven by running
    // THIS test under a PATH with node stripped — see the orchestrator report
    // and the shell-level check in this plan's verification.
    final service = PrototypeServerService();
    final emb = await service.start(
      designDir: _design,
      vendorDir: _vendor,
      runtime: 'embedded',
    );
    addTearDown(emb.stop);
    final client = HttpClient();
    addTearDown(client.close);

    final req = await client.getUrl(Uri.parse('${emb.url}?state=list'));
    final res = await req.close();
    final data = <int>[];
    await for (final c in res) {
      data.addAll(c);
    }
    final html = utf8.decode(data);
    expect(res.statusCode, 200);
    expect(html, contains('Projects — app_box'));
    expect(html, contains('Ledgerly'));
    final assetReq = await client.getUrl(Uri.parse('${emb.url}assets/css/app.css'));
    final assetRes = await assetReq.close();
    expect(assetRes.statusCode, 200);
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('node fallback (9.8): runtime=node spawns serve.mjs', () async {
    final nodeOnPath = (await Process.run('node', ['-v'])).exitCode == 0;
    if (!nodeOnPath) {
      // ignore: avoid_print
      print('node not on PATH — skipping node-fallback test');
      return;
    }
    final service = PrototypeServerService();
    final handle = await service.start(
      designDir: _design,
      vendorDir: _vendor,
      runtime: 'node',
    );
    addTearDown(handle.stop);
    final client = HttpClient();
    addTearDown(client.close);

    final req = await client.getUrl(Uri.parse('${handle.url}?state=list'));
    final res = await req.close();
    expect(res.statusCode, 200);
  }, timeout: const Timeout(Duration(seconds: 30)));
}

String _firstDiff(String a, String b) {
  final n = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    if (a[i] != b[i]) {
      final s = i > 25 ? i - 25 : 0;
      return 'byte @$i: node=${jsonEncode(a.substring(s, i + 25))} emb=${jsonEncode(b.substring(s, i + 25))}';
    }
  }
  return 'length: node=${a.length} emb=${b.length}';
}
