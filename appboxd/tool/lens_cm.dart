import 'dart:io';
import 'package:image/image.dart' as img;
Future<void> main(List<String> args) async {
  final im = img.decodeImage(File(args[0]).readAsBytesSync())!;
  print('size: ${im.width}x${im.height}');
  var dark = 0, white = 0, mid = 0, green = 0, total = 0;
  for (var y = 0; y < im.height; y += 4) {
    for (var x = 0; x < im.width; x += 4) {
      final p = im.getPixel(x, y);
      final r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
      total++;
      final max = r > g ? (r > b ? r : b) : (g > b ? g : b);
      final min = r < g ? (r < b ? r : b) : (g < b ? g : b);
      if (max - min > 40 && g > r && g > b) green++;
      if (r > 215 && g > 215 && b > 205) {
        white++;
      } else if (r < 70 && g < 70 && b < 70) {
        dark++;
      } else {
        mid++;
      }
    }
  }
  print('white ${white * 100 ~/ total}% dark ${dark * 100 ~/ total}% mid ${mid * 100 ~/ total}% greenish $green samples');
}
