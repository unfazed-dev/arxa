// Interaction-state capture — click-toggle and hover-reveal.
//
// captureStates dispatches per-trigger input (click/hover/focus) and reports,
// per trigger, whether the surface changed (pixelDiff of before/after shots),
// plus WAAPI transition metadata. changed:false is an observation, not a failure.
import 'dart:async';
import 'dart:io';

import 'package:appboxd/lens/states.dart';
import 'package:test/test.dart';

Future<(HttpServer, String)> bootStatesServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final base = 'http://${server.address.address}:${server.port}';
  server.listen((req) {
    req.response.headers.contentType = ContentType.html;
    req.response.write(r'''
<!DOCTYPE html><html><head><style>
  body { margin: 0; font-family: sans-serif; }
  #toggle { width: 160px; height: 44px; display: block; background: #eee; }
  #panel { display: none; height: 120px; background: #c33; }
  body.open #panel { display: block; }
  #reveal { width: 160px; height: 44px; display: block; background: #eee; }
  #reveal .tip { display: none; height: 80px; background: #36c; }
  #reveal:hover .tip { display: block; }
</style></head><body>
  <button id="toggle">toggle</button>
  <div id="panel"></div>
  <div id="reveal"><span class="tip"></span></div>
  <script>
    document.getElementById('toggle').addEventListener('click', function () {
      document.body.classList.toggle('open');
    });
  </script>
</body></html>
''');
    req.response.close();
  });
  return (server, base);
}

void main() {
  test('captureStates: click-toggle and hover-reveal change the surface', () async {
    final (server, base) = await bootStatesServer();
    try {
      final res = await captureStates(
        base,
        triggers: const [
          StateTrigger('#toggle', 'click'),
          StateTrigger('#reveal', 'hover'),
        ],
        width: 390,
        height: 844,
        settleMs: 400,
        settleAfterMs: 400,
      );

      expect(res['url'], base);
      expect(res['certified'], isTrue, reason: 'no console/page errors expected');

      final states = res['states'] as List;
      expect(states.length, 2);

      final click = states.cast<Map>().firstWhere((s) => s['selector'] == '#toggle');
      final hover = states.cast<Map>().firstWhere((s) => s['selector'] == '#reveal');

      // Click toggles the panel open -> pixels differ.
      expect(click['action'], 'click');
      expect(click['changed'], isTrue);
      expect(click['diffPixels'] as int, greaterThan(0));
      expect(click['before'] != click['after'], isTrue);

      // Hover reveals .tip -> pixels differ.
      expect(hover['action'], 'hover');
      expect(hover['changed'], isTrue);
      expect(hover['diffPixels'] as int, greaterThan(0));

      // Transition metadata is null (nothing active) or a metadata map.
      for (final s in states) {
        final t = (s as Map)['transition'];
        expect(t == null || t is Map, isTrue);
      }
    } finally {
      await server.close();
    }
  });
}
