import 'package:appboxd/lens/pixels.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

void main() {
  test('uniform frame reports 100% of its color', () {
    final im = img.Image(width: 4, height: 4);
    for (var y = 0; y < im.height; y++) {
      for (var x = 0; x < im.width; x++) {
        im.setPixelRgb(x, y, 250, 251, 252);
      }
    }
    final u = uniformity(im);
    expect(u.pct, 100.0);
    expect(u.color, [250, 251, 252]);
  });

  test('two-color frame splits by dominant share', () {
    final im = img.Image(width: 2, height: 1);
    im.setPixelRgb(0, 0, 0, 0, 0);
    im.setPixelRgb(1, 0, 255, 255, 255);
    final u = uniformity(im);
    expect(u.pct, closeTo(50.0, 0.001));
  });
}
