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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

@Timeout(Duration(minutes: 3))
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

    test('the island script is served from /assets/vendor/', () async {
      final (code, js) = await _req('GET', '$base/assets/vendor/dial_island.js');
      expect(code, 200);
      expect(js, contains('Design Dial'));
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

      final (scode, _) = await _req('POST', '$base/__dial/pins/status',
          body: {'id': pin['id'], 'status': 'in_progress'});
      expect(scode, 200);

      final (rcode, _) = await _req('POST', '$base/__dial/pins/reply',
          body: {'id': pin['id'], 'body': 'ack'});
      expect(rcode, 201);

      final (lcode, lbody) = await _req('GET', '$base/__dial/pins');
      expect(lcode, 200);
      final pins = (jsonDecode(lbody) as Map)['pins'] as List;
      final found = pins.singleWhere((x) => x['id'] == pin['id']);
      expect(found['status'], 'in_progress');
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
}
