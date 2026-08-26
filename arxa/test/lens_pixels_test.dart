// Pixel substrate: decode, per-pixel diff, SSIM, CIEDE2000.
import 'dart:convert';

import 'package:arxa/lens/pixels.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

img.Image solid(int w, int h, int r, int g, int b) {
  final im = img.Image(width: w, height: h);
  for (final p in im) {
    p..r = r ..g = g ..b = b ..a = 255;
  }
  return im;
}

void main() {
  group('decodePng', () {
    test('round-trips bytes written by CDP screenshot', () {
      final png = img.encodePng(solid(8, 8, 10, 20, 30));
      final im = decodePng(png);
      expect(im.width, 8);
      expect(im.height, 8);
    });
    test('throws LensPixelException on non-PNG bytes', () {
      expect(() => decodePng(utf8.encode('not a png')),
          throwsA(isA<LensPixelException>()));
    });
  });

  group('pixelDiff', () {
    test('identical images: 0 diff pixels, similarity 1.0', () {
      final d = pixelDiff(solid(16, 16, 255, 0, 0), solid(16, 16, 255, 0, 0));
      expect(d.diffPixels, 0);
      expect(d.similarity, 1.0);
    });
    test('one changed pixel is counted; diff image marks it', () {
      final a = solid(16, 16, 0, 0, 0);
      final b = solid(16, 16, 0, 0, 0);
      b.setPixelRgb(3, 4, 255, 255, 255);
      final d = pixelDiff(a, b);
      expect(d.diffPixels, 1);
      expect(d.similarity, closeTo(255 / 256, 1e-9));
      expect(d.diffImage, isNotNull);
    });
    test('tolerance absorbs sub-threshold channel jitter', () {
      final a = solid(16, 16, 100, 100, 100);
      final b = solid(16, 16, 102, 100, 100);
      expect(pixelDiff(a, b, tolerance: 4).diffPixels, 0);
      expect(pixelDiff(a, b, tolerance: 1).diffPixels, 256);
    });
  });

  group('ssimSimilarity', () {
    test('identical images score 1.0', () {
      // Non-uniform content: SSIM is degenerate on flat fields by design.
      final a = img.Image(width: 64, height: 64);
      for (var y = 0; y < 64; y++) {
        for (var x = 0; x < 64; x++) {
          a.setPixelRgb(x, y, (x * 4) % 256, (y * 4) % 256, ((x + y) * 2) % 256);
        }
      }
      expect(ssimSimilarity(a, a), closeTo(1.0, 1e-6));
    });
    test('blurred copy scores below 1 but above noise', () {
      final a = img.Image(width: 64, height: 64);
      for (var y = 0; y < 64; y++) {
        for (var x = 0; x < 64; x++) {
          a.setPixelRgb(x, y, (x * 4) % 256, (y * 4) % 256, 128);
        }
      }
      final blurred = img.gaussianBlur(a.clone(), radius: 4);
      final noise = img.Image(width: 64, height: 64);
      var seed = 7;
      for (final p in noise) {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        p..r = seed % 256 ..g = (seed >> 8) % 256 ..b = (seed >> 16) % 256 ..a = 255;
      }
      final sBlur = ssimSimilarity(a, blurred);
      final sNoise = ssimSimilarity(a, noise);
      expect(sBlur, greaterThan(0.7));
      expect(sBlur, lessThan(1.0));
      expect(sNoise, lessThan(0.2));
    });
  });

  group('deltaE2000', () {
    // Sharma et al. reference pairs (CIEDE2000 test data).
    test('reference pair 1 = 2.0425', () {
      expect(deltaE2000Lab(50, 2.6772, -79.7751, 50, 0, -82.7485),
          closeTo(2.0425, 1e-3));
    });
    test('reference pair 2 = 2.8615', () {
      expect(deltaE2000Lab(50, 3.1571, -77.2803, 50, 0, -82.7485),
          closeTo(2.8615, 1e-3));
    });
    test('rgbToLab: white is L=100 a~0 b~0', () {
      final lab = rgbToLab(255, 255, 255);
      expect(lab[0], closeTo(100, 1e-3));
      expect(lab[1].abs(), lessThan(0.01));
      expect(lab[2].abs(), lessThan(0.01));
    });
    test('regionMeanLab of a solid field equals its point Lab', () {
      final lab = regionMeanLab(solid(8, 8, 200, 30, 60), 0, 0, 8, 8);
      final point = rgbToLab(200, 30, 60);
      expect(lab[0], closeTo(point[0], 1e-6));
      expect(lab[1], closeTo(point[1], 1e-6));
      expect(lab[2], closeTo(point[2], 1e-6));
    });
  });
}
