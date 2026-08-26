// Task #55 — concurrent requests on ONE session must not lose each other's
// state writes.
//
// The hypothesis under test: DesignServer._dispatch reads the session (and
// timers) at request start, awaits the worker, then writes the result back.
// That read-modify-write spans an await, so two requests for the same session
// interleave and the later writer clobbers the earlier one's changes.
//
// Why this is #55's mechanism and not a curiosity: the studio re-renders the
// whole stage after a canvas mutation, and every tile is an iframe — one
// interaction fans out into ~20 concurrent GETs carrying the SAME session
// cookie. A flow move pushes onto undoStacks.canvas and returns; the iframe
// requests that were already in flight then write back their older snapshot and
// erase the push. Undo afterwards pops nothing, so redo never enables — while
// the move itself already reached disk. That is exactly the observed pair of
// symptoms: "redo never re-enabled" plus a project left mutated.
//
// The probe measures it end-to-end and flakily. This measures it directly.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:arxa/design_dial.dart';
import 'package:arxa/design_server.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final String _fixture =
    p.absolute('../skills/arxa-designer/examples/hello-hda');

Future<void> _copyDir(String src, String dst) async {
  await Directory(dst).create(recursive: true);
  for (final e in Directory(src).listSync(recursive: true)) {
    if (e is! File) continue;
    final rel = p.relative(e.path, from: src);
    final out = File(p.join(dst, rel))..createSync(recursive: true);
    await out.writeAsBytes(await e.readAsBytes());
  }
}

class _R {
  _R(this.body, this.headers);
  final String body;
  final Map<String, String> headers;
}

Future<_R> _req(String method, String url, {String? cookie}) async {
  final client = HttpClient();
  try {
    final req = method == 'POST'
        ? await client.postUrl(Uri.parse(url))
        : await client.getUrl(Uri.parse(url));
    if (method == 'POST') {
      req.headers.contentType =
          ContentType.parse('application/x-www-form-urlencoded');
      req.add(utf8.encode(''));
    }
    if (cookie != null) req.headers.add('cookie', cookie);
    final res = await req.close();
    final body = await utf8.decoder.bind(res).join();
    final h = <String, String>{};
    res.headers.forEach((k, v) => h[k] = v.join(','));
    return _R(body, h);
  } finally {
    client.close(force: true);
  }
}

String? _sid(_R r) {
  final sc = r.headers['set-cookie'];
  if (sc == null) return null;
  final m = RegExp(r'kdh_sid=([^;,]+)').firstMatch(sc);
  return m == null ? null : 'kdh_sid=${m.group(1)}';
}

int? _remaining(String body) {
  final m = RegExp(r'>(\d+)s<').firstMatch(body);
  return m == null ? null : int.parse(m.group(1)!);
}

void main() {
  group('concurrent requests on one session (task #55)', () {
    late DesignServer srv;
    late String tmp;

    setUpAll(() async {
      tmp = (await Directory.systemTemp.createTemp('session-race-')).path;
      await _copyDir(_fixture, tmp);
      srv = await DesignServer.start(
          dialStore: MemoryDialStore(), artifactDir: tmp, port: 0);
    });

    tearDownAll(() async {
      await srv.stop();
      try {
        await Directory(tmp).delete(recursive: true);
      } catch (_) {}
    });

    test('sequential extends all land (the control)', () async {
      // Establishes that the state machine itself works: 8 extends of 15s on a
      // 30s timer must accumulate. If this failed, the concurrent result below
      // would prove nothing about concurrency.
      final start = await _req('GET', '${srv.url}timer');
      final c = _sid(start)!;
      for (var i = 0; i < 8; i++) {
        await _req('POST', '${srv.url}timer/extend', cookie: c);
      }
      final got = _remaining(
          (await _req('GET', '${srv.url}timer/tick', cookie: c)).body);
      expect(got, isNotNull);
      // 30 + 8*15 = 150, minus a second or two of real elapsed time.
      expect(got, greaterThan(140), reason: 'sequential extends accumulated');
    });

    test('concurrent extends on ONE session do not lose each other', () async {
      final start = await _req('GET', '${srv.url}timer');
      final c = _sid(start)!;
      final before = _remaining(
          (await _req('GET', '${srv.url}timer/tick', cookie: c)).body)!;

      // Fired together, exactly as a stage re-render fires its iframes.
      await Future.wait([
        for (var i = 0; i < 8; i++)
          _req('POST', '${srv.url}timer/extend', cookie: c),
      ]);

      final after = _remaining(
          (await _req('GET', '${srv.url}timer/tick', cookie: c)).body)!;
      final gained = after - before;
      // Every one of the 8 must be reflected. A lost update shows up as a
      // gain well under 8*15, because a request that started before another's
      // write landed overwrites it with its own older snapshot.
      expect(gained, greaterThan(8 * 15 - 10),
          reason: 'lost update: only ${gained ~/ 15} of 8 extends survived');
    });
  });
}
