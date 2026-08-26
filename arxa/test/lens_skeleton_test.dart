// Skeleton capture + diff — structural (content-free) compare.
//
// Exercises captureSkeleton (lens-skeleton/1: per-element bbox/role/z/fontSize/
// sizing, no text) and diffSkeleton (match-by-id deltas: tree/pos/size/z).
import 'dart:async';
import 'dart:io';

import 'package:arxa/lens/skeleton.dart';
import 'package:test/test.dart';

/// Boots an ephemeral fixture page with a header/nav/main/two-button structure.
/// [extraCss]/[extraHtml] inject variants for the diff tests (width change, insert).
Future<(HttpServer, String)> bootSkeletonServer({
  String extraCss = '',
  String extraHtml = '',
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final base = 'http://${server.address.address}:${server.port}';
  server.listen((req) {
    req.response.headers.contentType = ContentType.html;
    req.response.write('''
<!DOCTYPE html><html><head><style>
  * { box-sizing: border-box; margin: 0; }
  body { font-family: sans-serif; }
  #hdr { height: 60px; background: #eee; display: block; }
  #nav { height: 44px; background: #ddd; display: block; }
  #main { padding: 16px; display: block; min-height: 200px; }
  .btn { width: 120px; height: 40px; margin: 8px; display: inline-block; background: #c33; }
  #b1 { width: 200px; }
  $extraCss
</style></head><body>
  <header id="hdr"></header>
  <nav id="nav"></nav>
  <main id="main">
    <button id="b1" class="btn"></button>
    <button id="b2" class="btn"></button>
  </main>
  $extraHtml
</body></html>
''');
    req.response.close();
  });
  return (server, base);
}

void main() {
  group('skeleton', () {
    test('captureSkeleton returns lens-skeleton/1 nodes with bbox/role/sizing', () async {
      final (server, base) = await bootSkeletonServer();
      try {
        final sk = await captureSkeleton(base, width: 390, height: 844, settleMs: 400);

        expect(sk['format'], 'lens-skeleton/1');
        expect(sk['url'], base);
        expect(sk['viewport'], [390, 844]);
        expect(sk['certified'], isTrue);

        final nodes = sk['nodes'] as List;
        expect(nodes, isNotEmpty);
        for (final n in nodes) {
          final m = n as Map;
          expect(m, contains('id'));
          expect(m, contains('role'));
          expect(m, contains('bbox'));
          expect(m, contains('z'));
          expect(m, contains('fontSize'));
          expect(m, contains('sizing'));
          expect((m['bbox'] as List).length, 4);
        }

        // The known button #b1 (200px wide) bbox width matches its CSS geometry ±1px.
        final b1 = nodes.cast<Map>().firstWhere(
          (n) => n['id'] == '#b1',
          orElse: () => <String, dynamic>{},
        );
        expect(b1['id'], '#b1', reason: '#b1 should be captured');
        final bbox = (b1['bbox'] as List).map((v) => (v as num).toDouble()).toList();
        expect((bbox[2] - 200).abs(), lessThanOrEqualTo(1)); // width within 1px
      } finally {
        await server.close();
      }
    });

    test('diffSkeleton self-diff is certified with no deltas (2px floor)', () async {
      // Two fresh captures of the same deterministic page: layout is identical,
      // so every matched node falls within the 2px floor and deltas is empty.
      final (serverA, baseA) = await bootSkeletonServer();
      final (serverB, baseB) = await bootSkeletonServer();
      try {
        final a = await captureSkeleton(baseA, width: 390, height: 844, settleMs: 400);
        final b = await captureSkeleton(baseB, width: 390, height: 844, settleMs: 400);
        final d = diffSkeleton(a, b);
        expect(d['certified'], isTrue);
        expect(d['deltas'] as List, isEmpty);
      } finally {
        await serverA.close();
        await serverB.close();
      }
    });

    test('diffSkeleton reports a size delta on button width change', () async {
      final (serverA, baseA) = await bootSkeletonServer();
      // Override #b1 width 200px -> 280px.
      final (serverB, baseB) = await bootSkeletonServer(extraCss: '#b1 { width: 280px; }');
      try {
        final a = await captureSkeleton(baseA, width: 390, height: 844, settleMs: 400);
        final b = await captureSkeleton(baseB, width: 390, height: 844, settleMs: 400);
        final d = diffSkeleton(a, b);

        expect(d['certified'], isFalse);
        final deltas = d['deltas'] as List;
        final sizeDeltas = deltas.where((x) => x['type'] == 'size').toList();
        expect(sizeDeltas, isNotEmpty);
        expect(sizeDeltas.any((x) => x['id'] == '#b1'), isTrue,
            reason: 'the size delta should name #b1');
      } finally {
        await serverA.close();
        await serverB.close();
      }
    });

    test('diffSkeleton reports a tree delta on node insert', () async {
      final (serverA, baseA) = await bootSkeletonServer();
      // Append a new landmark <footer> not present in capture a.
      final (serverB, baseB) = await bootSkeletonServer(
        extraHtml: '<footer id="ftr" style="height:30px;background:#bbb;display:block;"></footer>',
      );
      try {
        final a = await captureSkeleton(baseA, width: 390, height: 844, settleMs: 400);
        final b = await captureSkeleton(baseB, width: 390, height: 844, settleMs: 400);
        final d = diffSkeleton(a, b);

        expect(d['certified'], isFalse);
        final deltas = d['deltas'] as List;
        final treeDeltas = deltas.where((x) => x['type'] == 'tree').toList();
        expect(treeDeltas, isNotEmpty);
        expect(treeDeltas.any((x) => x['id'] == '#ftr'), isTrue,
            reason: 'the tree delta should name the inserted #ftr');
      } finally {
        await serverA.close();
        await serverB.close();
      }
    });
  });
}
