// design_dial_serve_test.dart — the Design Dial's SERVER half, end to end:
// a real DesignServer (hello-hda fixture, real worker) proving that
//   - every full HTML page carries the dial (config + island script),
//   - --no-dial / dial:false pages do NOT,
//   - the /__dial/* API round-trips through the wire (not just the pure
//     core — the adapter, the grant resolution, the JSON),
//   - a guest token flips the caller (kanban 403), a dead token is 'invalid',
//   - mutations broadcast on /__dial/events (SSE frame observed).
//
// The island's pixels are NOT asserted here — that is the lens's job
// (appbox lens shoot), which the verification step of this slice performs.

@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appboxd/design_axes.dart';
import 'package:appboxd/design_dial.dart';
import 'package:appboxd/design_draft.dart';
import 'package:appboxd/design_server.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final String _fixture = p.absolute('../skills/appbox-designer/examples/hello-hda');

Future<(int, String)> _req(String method, String url,
    {Object? body, Map<String, String>? headers}) async {
  final http = HttpClient();
  final req = await http.openUrl(method, Uri.parse(url));
  headers?.forEach((k, v) => req.headers.set(k, v));
  if (body != null) {
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode(body));
  }
  final res = await req.close();
  final text = await res.transform(utf8.decoder).join();
  http.close();
  return (res.statusCode, text);
}

void main() {
  group('design dial over a real server', () {
    late DesignServer srv;
    late DesignServer bare; // dial: false
    late Directory draftHome;
    late String base;
    late String bareBase;

    setUpAll(() async {
      // A temp-home draft store: the Draft Overlay is real file state, and a
      // test must never write into the operator's ~/.appbox/drafts.
      draftHome = Directory.systemTemp.createTempSync('dial-serve-draft');
      srv = await DesignServer.start(
          artifactDir: _fixture,
          noWatch: true,
          dialStore: MemoryDialStore(),
          draftStore:
              DraftFileStore(artifactDir: _fixture, home: draftHome.path));
      bare = await DesignServer.start(
          artifactDir: _fixture,
          noWatch: true,
          dial: false,
          dialStore: MemoryDialStore());
      base = 'http://127.0.0.1:${srv.port}';
      bareBase = 'http://127.0.0.1:${bare.port}';
    });

    tearDownAll(() async {
      await srv.stop();
      await bare.stop();
      draftHome.deleteSync(recursive: true);
    });

    test('every full page carries the dial; dial:false pages do not', () async {
      final (code, html) = await _req('GET', base);
      expect(code, 200);
      expect(html, contains('id="arxa-dial-config"'));
      expect(html, contains('/assets/vendor/dial_island.js'));
      expect(html, contains('"mode":"author"'));

      final (bcode, bhtml) = await _req('GET', bareBase);
      expect(bcode, 200);
      expect(bhtml, isNot(contains('arxa-dial')));
    });

    test('framed CSS lands in HEAD so an hx-boost swap keeps it', () async {
      // The artifact pages carry hx-boost="true": every in-site navigation
      // swaps BODY INNERHTML. Anything injected before </body> - scrollbar
      // suppression included - dies on the first tap of the home button.
      // Head is untouched by boosts, so that is where this style lives.
      final (code, html) =
          await _req('GET', base, headers: {'sec-fetch-dest': 'iframe'});
      expect(code, 200);
      expect(html, contains('__appbox_framed'));
      final headEnd = html.indexOf('</head>');
      expect(headEnd, greaterThan(0));
      expect(html.indexOf('__appbox_framed'), lessThan(headEnd),
          reason: 'a body-mounted style is swapped away by hx-boost');
    });

    test('the dial host mounts OFF the body so boosts cannot remove it',
        () async {
      final (code, js) = await _req('GET', '$base/assets/vendor/dial_island.js');
      expect(code, 200);
      expect(js, contains('documentElement.appendChild(host)'),
          reason: 'hx-boost swaps body innerHTML - a body-mounted host is '
              'gone after the first in-site navigation');
      expect(js, isNot(contains('document.body.appendChild(host)')));
    });

    test('the island script is served from /assets/vendor/', () async {
      final (code, js) = await _req('GET', '$base/assets/vendor/dial_island.js');
      expect(code, 200);
      expect(js, contains('Design Dial'));
      // Operator law (2026-08-24): the dial is NOT draggable. The dock FAB
      // toggles the fan on click and nothing else - no drag machinery may
      // ship in the island.
      expect(js, isNot(contains('dragStart')), reason: 'drag code removed');
    });

    test('rework 2026-08-24: 3-trigger fan, tray + card, dead verbs gone',
        () async {
      final (code, js) = await _req('GET', '$base/assets/vendor/dial_island.js');
      expect(code, 200);
      // The fan carries exactly the three triggers.
      expect(js, contains("id: 'edit'"));
      expect(js, contains("id: 'comment'"));
      expect(js, contains("id: 'studio'"));
      // The tray and the floating card ship.
      expect(js, contains('function openTray('));
      expect(js, contains('function openCard('));
      expect(js, contains('scroll-snap-type:x mandatory'));
      expect(js, contains('backdrop-filter'));
      // The tray swap law and the never-hide law are wired.
      expect(js, contains('function dialPark('));
      expect(js, contains('function dialUnpark('));
      // The six displaced verbs are deleted outright (operator decision):
      // pen/shade/layers/share/tokens/design-as-verb + their machinery.
      expect(js, isNot(contains('drawCanvas')));
      expect(js, isNot(contains('redrawStrokes')));
      expect(js, isNot(contains('applyShade')));
      expect(js, isNot(contains('renderLayersCtl')));
      expect(js, isNot(contains("id: 'renderShareCtl'")));
      expect(js, isNot(contains('renderTokensPanel')));
      expect(js, isNot(contains('renderDesignPanel')));
      expect(js, isNot(contains('setPanel')));
      // Kanban is the closed 3-state set.
      expect(js, isNot(contains("'triaged'")));
      expect(js, isNot(contains("'in_progress'")));
    });

    test('pin roundtrip + kanban + reply through the wire', () async {
      final (ccode, cbody) = await _req('POST', '$base/__dial/pins', body: {
        'route': '/',
        'viewport': {'w': 1280, 'h': 800},
        'anchor': {
          'el': null,
          'rect': {'x': 5, 'y': 6, 'w': 70, 'h': 30},
        },
        'body': 'wire test pin',
      });
      expect(ccode, 201, reason: cbody);
      final pin = (jsonDecode(cbody) as Map)['pin'] as Map;

      // Rework 2026-08-24: triaged/in_progress died; a legacy wire name
      // folds to open instead of 400ing old clients.
      final (fcode, fbody) = await _req('POST', '$base/__dial/pins/status',
          body: {'id': pin['id'], 'status': 'in_progress'});
      expect(fcode, 200);
      expect(((jsonDecode(fbody) as Map)['pin'] as Map)['status'], 'open');

      final (scode, _) = await _req('POST', '$base/__dial/pins/status',
          body: {'id': pin['id'], 'status': 'resolved'});
      expect(scode, 200);

      final (rcode, _) = await _req('POST', '$base/__dial/pins/reply',
          body: {'id': pin['id'], 'body': 'ack'});
      expect(rcode, 201);

      final (lcode, lbody) = await _req('GET', '$base/__dial/pins');
      expect(lcode, 200);
      final pins = (jsonDecode(lbody) as Map)['pins'] as List;
      final found = pins.singleWhere((x) => x['id'] == pin['id']);
      expect(found['status'], 'resolved');
      expect((found['replies'] as List).single['body'], 'ack');
    });

    test('share link: mint → guest can pin, cannot move kanban; dead token',
        () async {
      final (mcode, mbody) = await _req('POST', '$base/__dial/share',
          body: {'days': 7});
      expect(mcode, 201);
      final token = (jsonDecode(mbody) as Map)['token'] as String;

      // The served page with the token boots in guest mode.
      final (_, ghtml) = await _req('GET', '$base?dial=$token');
      expect(ghtml, contains('"mode":"guest"'));
      final (_, ihtml) = await _req('GET', '$base?dial=deadbeef');
      expect(ihtml, contains('"mode":"invalid"'));

      // Guest pin: allowed. Guest kanban: 403. Guest mint: 403.
      final (gcode, gbody) = await _req('POST', '$base/__dial/pins?dial=$token',
          body: {
            'route': '/',
            'viewport': {'w': 390, 'h': 844},
            'anchor': {
              'el': null,
              'rect': {'x': 1, 'y': 2, 'w': 3, 'h': 4},
            },
            'body': 'guest was here',
            'name': 'Client Claire',
          });
      expect(gcode, 201, reason: gbody);
      final gpin = (jsonDecode(gbody) as Map)['pin'] as Map;
      expect(gpin['author'], 'guest');

      final (kcode, _) = await _req(
          'POST', '$base/__dial/pins/status?dial=$token',
          body: {'id': gpin['id'], 'status': 'resolved'});
      expect(kcode, 403);
      final (scode2, _) =
          await _req('POST', '$base/__dial/share?dial=$token', body: {});
      expect(scode2, 403);
    });

    test('draft overlay: author page carries it, guests never do (decision 5)',
        () async {
      // A real rendered id from the served page (the fixture is stamped).
      final (_, html) = await _req('GET', base);
      final idm =
          RegExp('data-arxa-id="([^"]+)"').firstMatch(html);
      expect(idm, isNotNull,
          reason: 'the stamped fixture must render data-arxa-id');
      final id = idm!.group(1)!;

      final (pcode, pbody) = await _req('PUT', '$base/__dial/draft', body: {
        'tokens': {'--arxa-test-token': '#123456'},
        'patches': {
          id: {
            'style': {'outline': '3px solid rgb(1, 2, 3)'},
            'attrs': {'data-draft-test': 'yes'},
          },
        },
      });
      expect(pcode, 200, reason: pbody);

      // Author page: the overlay is applied at the seam.
      final (_, ahtml) = await _req('GET', base);
      expect(ahtml, contains('data-draft-test="yes"'));
      expect(
          ahtml,
          contains(
              '<style id="arxa-draft-tokens">:root{--arxa-test-token: #123456}</style>'));

      // Guest page (Share Link): last published state — no overlay.
      final (mcode, mbody) =
          await _req('POST', '$base/__dial/share', body: {'days': 1});
      expect(mcode, 201);
      final token = (jsonDecode(mbody) as Map)['token'] as String;
      final (_, ghtml) = await _req('GET', '$base?dial=$token');
      expect(ghtml, isNot(contains('data-draft-test')));
      expect(ghtml, isNot(contains('arxa-draft-tokens')));

      // Guests cannot touch the draft API; dead links are refused outright.
      final (gcode, _) = await _req(
          'PUT', '$base/__dial/draft?dial=$token',
          body: {'patches': {}});
      expect(gcode, 403);
      final (dcode, _) =
          await _req('GET', '$base/__dial/pins?dial=deadbeef');
      expect(dcode, 403);

      // Commit hands the studio agent structured ops, non-destructively.
      final (kcode, kbody) =
          await _req('POST', '$base/__dial/commit', body: {});
      expect(kcode, 200, reason: kbody);
      final commit = jsonDecode(kbody) as Map;
      expect(commit['artifact'], 'hello-hda');
      final ops = commit['ops'] as List;
      expect(ops.single['id'], id);
      expect((ops.single['style'] as Map)['outline'],
          '3px solid rgb(1, 2, 3)');
      expect((commit['tokens'] as Map)['--arxa-test-token'], '#123456');

      // Clear: the author page is source-clean again.
      final (xcode, _) = await _req('DELETE', '$base/__dial/draft');
      expect(xcode, 200);
      final (_, chtml) = await _req('GET', base);
      expect(chtml, isNot(contains('data-draft-test')));
      expect(chtml, isNot(contains('arxa-draft-tokens')));
    });

    test('mutations broadcast on the dial SSE stream', () async {
      final http = HttpClient();
      final req =
          await http.getUrl(Uri.parse('$base/__dial/events'));
      final res = await req.close();
      expect(res.headers.contentType?.mimeType, 'text/event-stream');
      final frames = StreamController<String>();
      res.transform(utf8.decoder).listen(frames.add);
      // Let the subscription register, then mutate.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await _req('POST', '$base/__dial/pins', body: {
        'route': '/',
        'viewport': {'w': 1280, 'h': 800},
        'anchor': {
          'el': null,
          'rect': {'x': 0, 'y': 0, 'w': 1, 'h': 1},
        },
        'body': 'sse trigger',
      });
      final seen = await frames.stream
          .firstWhere((f) => f.contains('event: dial'),
              orElse: () => '')
          .timeout(const Duration(seconds: 5));
      expect(seen, contains('event: dial'));
      await res.detachSocket().then((s) => s.destroy());
      http.close();
    });

    test('reads do NOT broadcast (a GET /pins frame storm starved the pool)', () async {
      final http = HttpClient();
      final req = await http.getUrl(Uri.parse('$base/__dial/events'));
      final res = await req.close();
      final chunks = <String>[];
      res.transform(utf8.decoder).listen(chunks.add);
      // Let the subscription register, then READ repeatedly — the 2026-08-24
      // storm: GET /pins broadcast a 'pins' frame, every island refetched,
      // each refetch broadcast again.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      for (var i = 0; i < 3; i++) {
        final (status, _) = await _req('GET', '$base/__dial/pins');
        expect(status, 200);
      }
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(chunks.join().contains('event: dial'), isFalse,
          reason: 'GET /pins must stay silent — only mutations broadcast');
      await res.detachSocket().then((s) => s.destroy());
      http.close();
    });
  });

  // The axes plane (arc 1, 2026-08-25) over the wire: author-only publish,
  // guest/dead refusal, the declaration gate (a page that declares no
  // styles serves no axes block), and the thin broadcast frame.
  group('design axes over a real server', () {
    late DesignServer axesSrv;
    late String axesBase;

    setUpAll(() async {
      axesSrv = await DesignServer.start(
          artifactDir: _fixture,
          noWatch: true,
          dialStore: MemoryDialStore(),
          marker: const ArtifactMarker(project: 'test-fixture', kind: 'app'),
          axesStore: MemoryAxesStore());
      axesBase = 'http://127.0.0.1:${axesSrv.port}';
    });

    tearDownAll(() async {
      await axesSrv.stop();
    });

    test('author publishes; guests, dead links, and garbage are refused',
        () async {
      final (code, body) = await _req('POST', '$axesBase/__dial/axes',
          body: {'style': 'glass', 'theme': 'dark'});
      expect(code, 200, reason: body);
      expect((jsonDecode(body) as Map)['axes'],
          {'style': 'glass', 'theme': 'dark'});

      final (mcode, mbody) =
          await _req('POST', '$axesBase/__dial/share', body: {});
      expect(mcode, 201, reason: mbody);
      final token = (jsonDecode(mbody) as Map)['token'] as String;

      final (gcode, _) = await _req(
          'POST', '$axesBase/__dial/axes?dial=$token',
          body: {'style': 'glass', 'theme': 'light'});
      expect(gcode, 403, reason: 'guests ride the URL, never the store');

      final (dcode, _) = await _req(
          'POST', '$axesBase/__dial/axes?dial=deadbeef',
          body: {'style': 'glass', 'theme': 'light'});
      expect(dcode, 403);

      final (bcode, _) = await _req('POST', '$axesBase/__dial/axes',
          body: {'style': 'NOT A STYLE', 'theme': 'dark'});
      expect(bcode, 400);
    });

    test('a page that declares no axes serves no axes config', () async {
      // hello-hda declares nothing — the control is capability-by-
      // declaration, so the config carries no axes block even though the
      // store is live and holds a pick.
      final (code, html) = await _req('GET', axesBase);
      expect(code, 200);
      expect(html, contains('id="arxa-dial-config"'));
      expect(html, isNot(contains('"axes"')));
    });

    test('an axes publish broadcasts one thin frame', () async {
      final http = HttpClient();
      final req = await http.getUrl(Uri.parse('$axesBase/__dial/events'));
      final res = await req.close();
      final frames = StreamController<String>();
      res.transform(utf8.decoder).listen(frames.add);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await _req('POST', '$axesBase/__dial/axes',
          body: {'style': 'm3e', 'theme': 'system'});
      final seen = await frames.stream
          .firstWhere((f) => f.contains('"kind":"axes"'), orElse: () => '')
          .timeout(const Duration(seconds: 5));
      expect(seen, contains('"style":"m3e"'));
      await res.detachSocket().then((s) => s.destroy());
      http.close();
    });
  });

  // The identity plane (arc 2, 2026-08-26) over the wire: the author
  // registers a guest and mints their PERSONAL link; the page carries the
  // guest identity; pins attribute by construction; revoke kills the link
  // and scrubs the email while the feedback survives.
  group('guest identity over a real server', () {
    late DesignServer gstSrv;
    late String gstBase;

    setUpAll(() async {
      gstSrv = await DesignServer.start(
          artifactDir: _fixture,
          noWatch: true,
          dialStore: MemoryDialStore(),
          marker: const ArtifactMarker(project: 'test-fixture', kind: 'app'),
          axesStore: MemoryAxesStore());
      gstBase = 'http://127.0.0.1:${gstSrv.port}';
    });

    tearDownAll(() async {
      await gstSrv.stop();
    });

    test('mint → guest page → attributed pin → roster', () async {
      final (mcode, mbody) =
          await _req('POST', '$gstBase/__dial/guests',
          body: {'email': 'Client@Energize.mu', 'name': 'Mira'});
      expect(mcode, 201, reason: mbody);
      final mj = jsonDecode(mbody) as Map;
      expect(mj['email'], 'client@energize.mu');
      final token = mj['token'] as String;

      // The guest's page boots with the identity, not a name prompt.
      final (pcode, html) = await _req('GET', '$gstBase/?dial=$token');
      expect(pcode, 200);
      expect(html, contains('"mode":"guest"'));
      expect(html, contains('"guest":{"email":"client@energize.mu"'));

      // Their pin carries attribution the link proved — not the typed name.
      final (pinCode, pinBodyText) =
          await _req('POST', '$gstBase/__dial/pins?dial=$token',
          body: {
            'route': '/',
            'body': 'the CTA is too quiet',
            'name': 'whatever they type',
            'viewport': {'w': 1280, 'h': 800},
            'anchor': {'el': null, 'rect': {'x': 0, 'y': 0, 'w': 1, 'h': 1}},
          });
      expect(pinCode, 201, reason: pinBodyText);
      final pj = (jsonDecode(pinBodyText) as Map)['pin'] as Map;
      expect(pj['guestEmail'], 'client@energize.mu');
      expect(pj['name'], 'Mira');

      // The roster is author-only truth.
      final (rcode, rbody) = await _req('GET', '$gstBase/__dial/guests');
      expect(rcode, 200, reason: rbody);
      expect((jsonDecode(rbody) as Map)['guests'], isNotEmpty);
      final (gcode, _) =
          await _req('GET', '$gstBase/__dial/guests?dial=$token');
      expect(gcode, 403);
    });

    test('revoke: the link dies, the feedback survives scrubbed', () async {
      final (_, mbody) = await _req('POST', '$gstBase/__dial/guests',
          body: {'email': 'gone@energize.mu'});
      final token = (jsonDecode(mbody) as Map)['token'] as String;
      await _req('POST', '$gstBase/__dial/pins?dial=$token', body: {
        'route': '/',
        'body': 'please keep this note',
        'viewport': {'w': 1280, 'h': 800},
        'anchor': {'el': null, 'rect': {'x': 0, 'y': 0, 'w': 1, 'h': 1}},
      });

      final (vcode, vbody) =
          await _req('POST', '$gstBase/__dial/guests/revoke',
          body: {'email': 'gone@energize.mu'});
      expect(vcode, 200, reason: vbody);

      final (dcode, dhtml) = await _req('GET', '$gstBase/?dial=$token');
      expect(dcode, 200);
      expect(dhtml, contains('"mode":"invalid"'),
          reason: 'a revoked link is a dead link');

      final (lcode, lbody) = await _req('GET', '$gstBase/__dial/pins');
      expect(lcode, 200);
      final pins = (jsonDecode(lbody) as Map)['pins'] as List;
      final kept = pins.where(
          (row) => (row as Map)['body'] == 'please keep this note');
      expect(kept, isNotEmpty);
      expect((kept.first as Map).containsKey('guestEmail'), isFalse);
    });

    test('a mint broadcasts one thin guests frame', () async {
      final http = HttpClient();
      final req =
          await http.getUrl(Uri.parse('$gstBase/__dial/events'));
      final res = await req.close();
      final frames = StreamController<String>();
      res.transform(utf8.decoder).listen(frames.add);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await _req('POST', '$gstBase/__dial/guests',
          body: {'email': 'sse@energize.mu'});
      final seen = await frames.stream
          .firstWhere((f) => f.contains('"kind":"guests"'), orElse: () => '')
          .timeout(const Duration(seconds: 5));
      expect(seen, contains('event: dial'));
      await res.detachSocket().then((s) => s.destroy());
      http.close();
    });
  });

  // ── The quiet-mirror branch (design_server.dart, 2026-08-26) ────────────
  //
  // A sandboxed gen_ui frame posts an opaque origin: the browser sends either
  // NO Origin header or the literal string "null". The trust guard refuses
  // both, but a REFUSAL is worse than useless for a read — Chrome console-logs
  // every non-2xx fetch and JS cannot suppress it, so a 403 here spams the
  // operator's console on every mirror frame. GETs are therefore softened to
  // 200 {"mirror":true}. Writes are NOT: the softening is the whole security
  // question, so the PUT case below is the one that must never regress.
  group('opaque-origin reads are mirrored, writes are still refused', () {
    late DesignServer mirrorSrv;
    late String mirrorBase;
    late Directory mirrorHome;

    setUpAll(() async {
      mirrorHome = Directory.systemTemp.createTempSync('dial-mirror-draft');
      mirrorSrv = await DesignServer.start(
          artifactDir: _fixture,
          noWatch: true,
          dialStore: MemoryDialStore(),
          draftStore:
              DraftFileStore(artifactDir: _fixture, home: mirrorHome.path));
      mirrorBase = 'http://127.0.0.1:${mirrorSrv.port}';
    });

    tearDownAll(() async {
      await mirrorSrv.stop();
      if (mirrorHome.existsSync()) mirrorHome.deleteSync(recursive: true);
    });

    /// Like [_req], but hands back the CORS header too — the mirror answer is
    /// only useful to a frame if it carries `Access-Control-Allow-Origin`.
    Future<(int, String, String?)> reqWithCors(String method, String url,
        {Map<String, String>? headers}) async {
      final http = HttpClient();
      final req = await http.openUrl(method, Uri.parse(url));
      headers?.forEach((k, v) => req.headers.set(k, v));
      final res = await req.close();
      final text = await res.transform(utf8.decoder).join();
      final cors = res.headers.value('Access-Control-Allow-Origin');
      http.close();
      return (res.statusCode, text, cors);
    }

    // Both legs of `originHeader == null || originHeader == 'null'`. They are
    // genuinely different wire shapes: a no-cors GET omits Origin entirely,
    // while a CORS-mode GET from a sandboxed frame sends the four characters
    // n-u-l-l. Testing one would leave the other free to regress.
    test('a GET with NO Origin header is mirrored, not refused', () async {
      final (status, body, cors) = await reqWithCors(
          'GET', '$mirrorBase/__dial/draft',
          headers: {'Sec-Fetch-Site': 'cross-site', 'Sec-Fetch-Dest': 'empty'});
      expect(status, 200, reason: 'an opaque-origin read must not 4xx — a '
          'non-2xx is console-logged by Chrome and cannot be suppressed');
      expect(body, contains('"mirror":true'));
      expect(cors, '*', reason: 'without ACAO the frame cannot read the answer');
    });

    test('a GET with the literal Origin "null" is mirrored too', () async {
      final (status, body, cors) = await reqWithCors(
          'GET', '$mirrorBase/__dial/draft',
          headers: {
            'Origin': 'null',
            'Sec-Fetch-Site': 'cross-site',
            'Sec-Fetch-Dest': 'empty'
          });
      expect(status, 200);
      expect(body, contains('"mirror":true'));
      expect(cors, '*');
    });

    // The mirror softening once swallowed this one. A DNS-rebinding probe is
    // a GET with a forged Host and no Origin — the exact shape of an opaque
    // frame's read — so it matched the softening and got 200 instead of 421.
    // The refusal reasons are different questions: Host asks "is this
    // connection even for me", Origin asks "may that page read me".
    test('a foreign Host is refused with 421, never mirrored', () async {
      final (status, body, cors) = await reqWithCors(
          'GET', '$mirrorBase/__projects',
          headers: {'Host': 'evil.example.com'});
      expect(status, 421, reason: 'the DNS-rebinding defence was softened '
          'into a 200 by the opaque-origin mirror branch');
      expect(body, isNot(contains('"mirror":true')));
      expect(cors, isNull);
    });

    // The security invariant. If this ever goes green on a 200, the softening
    // has leaked from reads into writes and any sandboxed frame on the machine
    // can mutate the operator's draft.
    test('a WRITE from an opaque origin is still refused', () async {
      for (final method in ['PUT', 'POST']) {
        final (status, body, cors) = await reqWithCors(
            method, '$mirrorBase/__dial/draft',
            headers: {
              'Origin': 'null',
              'Sec-Fetch-Site': 'cross-site',
              'Sec-Fetch-Dest': 'empty'
            });
        expect(status, 403, reason: '$method from an opaque origin was not '
            'refused — the GET-only softening has leaked into writes');
        expect(body, isNot(contains('"mirror":true')));
        expect(cors, isNull, reason: 'a refusal must not hand out CORS access');
      }
    });
  });

  // ── Regression guard for the fix that pinned 16 call sites ──────────────
  //
  // `DesignServer.start` builds its dial store from ~/.appbox/supabase when
  // the caller passes none (design_server.dart, the `..dialStore = dialStore ??
  // SupabaseDialStore.fromConfig(...)` cascade). That default is right for a
  // real server and wrong for a test: on any machine with credentials on disk,
  // an unpinned test server holds a service-key client — full RLS bypass —
  // against the shared client-facing project. Nothing today drives traffic
  // through it, so this never fired; the first test that touches a /__dial
  // route would be the one that discovers it, by writing to production.
  //
  // Pinning is the fix and this is what keeps it pinned.
  group('no test may build a live dial store', () {
    test('every DesignServer.start in test/ passes dialStore', () {
      // Span-based, not line-based: a correctly pinned call routinely puts
      // `dialStore:` several lines below the opening call, so a
      // line-oriented grep would flag every multi-line call in this very file.
      final offenders = <String>[];
      for (final f in Directory('test')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('_test.dart'))) {
        final src = f.readAsStringSync();
        // Split so the pattern cannot match its own source: this file is in
        // the scanned set, and a whole literal here would flag the guard.
        final call = RegExp('DesignServer' r'\.start\(');
        for (final m in call.allMatches(src)) {
          var i = m.end - 1, depth = 0;
          while (i < src.length) {
            final c = src[i];
            if (c == '(') {
              depth++;
            } else if (c == ')') {
              depth--;
              if (depth == 0) break;
            } else if (c == '"' || c == "'") {
              final q = c;
              i++;
              while (i < src.length && src[i] != q) {
                if (src[i] == r'\') i++;
                i++;
              }
            }
            i++;
          }
          // An unbalanced span means the match was prose, not a call (a
          // comment naming the method). Skip it rather than crashing: a guard
          // that throws hides the offender list it exists to print.
          if (i >= src.length) continue;
          if (!src.substring(m.end, i).contains('dialStore')) {
            final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
            offenders.add('${p.basename(f.path)}:$line');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'these DesignServer.start calls fall back to the real '
              'Supabase dial store — add `dialStore: MemoryDialStore()`:\n'
              '  ${offenders.join('\n  ')}');
    });
  });
}
