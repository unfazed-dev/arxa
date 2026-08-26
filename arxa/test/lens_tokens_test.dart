// Design-token extraction: known palette/type/spacing scale → cluster output.
import 'dart:io';

import 'package:arxa/lens/pixels.dart';
import 'package:arxa/lens/tokens.dart';
import 'package:test/test.dart';

Future<(HttpServer, String)> bootTokensServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final base = 'http://${server.address.address}:${server.port}';
  server.listen((req) {
    req.response.headers.contentType = ContentType.html;
    req.response.write('''
<!DOCTYPE html><html><head><style>
  body { background: #ffffff; color: #202124; font-size: 16px; margin: 0; }
  .big { font-size: 24px; }
  .btn { background: #1a73e8; color: #ffffff; padding: 4px 8px 16px; border: 0; }
  .p4 { padding: 4px; }
  .p8 { padding: 8px; }
  .p16 { padding: 16px; }
</style></head><body>
  <p class="big">Heading text</p>
  <button class="btn">Save</button>
  <div class="p4">a</div>
  <div class="p8">b</div>
  <div class="p16">c</div>
</body></html>
''');
    req.response.close();
  });
  return (server, base);
}

List<int> hexToRgb(String hex) {
  final h = hex.replaceFirst('#', '');
  return [
    int.parse(h.substring(0, 2), radix: 16),
    int.parse(h.substring(2, 4), radix: 16),
    int.parse(h.substring(4, 6), radix: 16),
  ];
}

/// True when some palette entry is within ΔE2000 [tol] of [hex].
bool paletteHas(List palette, String hex, {double tol = 3}) {
  final rgb = hexToRgb(hex);
  final lab = rgbToLab(rgb[0], rgb[1], rgb[2]);
  return palette.any((p) {
    final prgb = hexToRgb(p['hex'] as String);
    final plab = rgbToLab(prgb[0], prgb[1], prgb[2]);
    return deltaE2000Lab(lab[0], lab[1], lab[2], plab[0], plab[1], plab[2]) < tol;
  });
}

void main() {
  group('extractTokens', () {
    late HttpServer server;
    late String baseUrl;

    setUp(() async {
      (server, baseUrl) = await bootTokensServer();
    });
    tearDown(() => server.close());

    test('clusters palette, type scale, and spacing', () async {
      final result = await extractTokens(baseUrl, 390, 844, settleMs: 600);

      final palette = result['palette'] as List;
      expect(paletteHas(palette, '#1a73e8'), isTrue);
      expect(paletteHas(palette, '#ffffff'), isTrue);
      expect(paletteHas(palette, '#202124'), isTrue);

      final type =
          (result['type'] as List).map((t) => (t as Map)['value']).toSet();
      expect(type.contains(16), isTrue);
      expect(type.contains(24), isTrue);

      final spacing =
          (result['spacing'] as List).map((s) => (s as Map)['value']).toSet();
      expect(spacing.contains(4), isTrue);
      expect(spacing.contains(8), isTrue);
      expect(spacing.contains(16), isTrue);

      expect(result['consoleErrors'] as List, isEmpty);
      expect(result['certified'], isTrue);
    });
  });
}
