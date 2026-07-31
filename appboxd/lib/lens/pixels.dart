/// Pixel substrate for the appbox lens: PNG decode, per-pixel diff,
/// SSIM, and CIEDE2000 colour delta. The only place appboxd touches
/// package:image; everything above this file works in decoded Image
/// terms. SSIM parameters follow Wang et al.: 11x11 Gaussian window
/// (sigma 1.5), K1=0.01, K2=0.03, luma channel.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

class LensPixelException implements Exception {
  LensPixelException(this.message);
  final String message;
  @override
  String toString() => 'LensPixelException: $message';
}

/// Decode PNG bytes (as returned by CDP screenshots / simctl / adb).
img.Image decodePng(List<int> bytes) {
  final im = img.decodePng(bytes is Uint8List ? bytes : Uint8List.fromList(bytes));
  if (im == null) throw LensPixelException('not a decodable PNG (${bytes.length} bytes)');
  return im;
}

class PixelDiff {
  PixelDiff(this.diffPixels, this.totalPixels, this.diffImage);
  final int diffPixels;
  final int totalPixels;
  final img.Image? diffImage; // red where different, null when identical
  double get similarity => totalPixels == 0 ? 1.0 : 1 - diffPixels / totalPixels;
}

/// Per-pixel compare. A pixel differs when any channel delta exceeds
/// [tolerance] (0 = exact). Dimension mismatch counts every pixel.
PixelDiff pixelDiff(img.Image a, img.Image b, {int tolerance = 0}) {
  if (a.width != b.width || a.height != b.height) {
    return PixelDiff(a.width * a.height, a.width * a.height, null);
  }
  var diff = 0;
  img.Image? marks;
  void mark(int x, int y) {
    marks ??= a.clone();
    marks!.setPixelRgb(x, y, 255, 0, 0);
  }

  for (var y = 0; y < a.height; y++) {
    for (var x = 0; x < a.width; x++) {
      final pa = a.getPixel(x, y);
      final pb = b.getPixel(x, y);
      if ((pa.r - pb.r).abs() > tolerance ||
          (pa.g - pb.g).abs() > tolerance ||
          (pa.b - pb.b).abs() > tolerance) {
        diff++;
        mark(x, y);
      }
    }
  }
  return PixelDiff(diff, a.width * a.height, diff == 0 ? null : marks);
}

/// Mean per-channel similarity in [0,1]; 1.0 = identical. Cheap mode.
double meanSimilarity(img.Image a, img.Image b) {
  if (a.width != b.width || a.height != b.height) return 0.0;
  var acc = 0.0;
  final n = a.width * a.height;
  final ia = a.iterator, ib = b.iterator;
  while (ia.moveNext() && ib.moveNext()) {
    acc += (255 * 3 -
            ((ia.current.r - ib.current.r).abs() +
                (ia.current.g - ib.current.g).abs() +
                (ia.current.b - ib.current.b).abs())) /
        (255 * 3);
  }
  return n == 0 ? 1.0 : acc / n;
}

// --- SSIM (luma, 11x11 Gaussian sigma 1.5, C1/C2 for L=255) ---

const double _c1 = 6.5025; // (0.01 * 255)^2
const double _c2 = 58.5225; // (0.03 * 255)^2

List<double> _gaussianKernel() {
  final k = List<double>.filled(11, 0);
  var sum = 0.0;
  for (var i = 0; i < 11; i++) {
    final d = i - 5;
    k[i] = math.exp(-(d * d) / (2 * 1.5 * 1.5));
    sum += k[i];
  }
  return [for (final v in k) v / sum];
}

Float64List _luma(img.Image im) {
  final out = Float64List(im.width * im.height);
  var i = 0;
  for (final p in im) {
    out[i++] = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
  }
  return out;
}

/// Separable Gaussian convolution with edge clamping.
Float64List _convolve(Float64List src, int w, int h, List<double> k) {
  final tmp = Float64List(w * h);
  final out = Float64List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var acc = 0.0;
      for (var i = -5; i <= 5; i++) {
        acc += src[y * w + (x + i).clamp(0, w - 1)] * k[i + 5];
      }
      tmp[y * w + x] = acc;
    }
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var acc = 0.0;
      for (var i = -5; i <= 5; i++) {
        acc += tmp[(y + i).clamp(0, h - 1) * w + x] * k[i + 5];
      }
      out[y * w + x] = acc;
    }
  }
  return out;
}

/// Structural similarity in [0,1]; 1.0 = identical. Dimension mismatch
/// scores 0. Degenerate flat fields: when both local variances and the
/// covariance are ~0 the map term is 1 by construction.
double ssimSimilarity(img.Image a, img.Image b) {
  if (a.width != b.width || a.height != b.height) return 0.0;
  final w = a.width, h = a.height, n = w * h;
  final k = _gaussianKernel();
  final la = _luma(a), lb = _luma(b);
  final la2 = Float64List(n), lb2 = Float64List(n), lab = Float64List(n);
  for (var i = 0; i < n; i++) {
    la2[i] = la[i] * la[i];
    lb2[i] = lb[i] * lb[i];
    lab[i] = la[i] * lb[i];
  }
  final mua = _convolve(la, w, h, k), mub = _convolve(lb, w, h, k);
  final va = _convolve(la2, w, h, k), vb = _convolve(lb2, w, h, k);
  final cab = _convolve(lab, w, h, k);
  var sum = 0.0;
  for (var i = 0; i < n; i++) {
    final ma = mua[i], mb = mub[i];
    final sa = va[i] - ma * ma, sb = vb[i] - mb * mb, sc = cab[i] - ma * mb;
    sum += ((2 * ma * mb + _c1) * (2 * sc + _c2)) /
        ((ma * ma + mb * mb + _c1) * (sa + sb + _c2));
  }
  return sum / n;
}

// --- CIEDE2000 ---

/// sRGB (0-255) -> CIE L*a*b* (D65/2°).
List<double> rgbToLab(int r, int g, int b) {
  double lin(int c) {
    final v = c / 255.0;
    return v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  final rr = lin(r), gg = lin(g), bb = lin(b);
  // Canonical sRGB→XYZ D65 matrix (Lindbloom / IEC 61966-2-1). The rows sum
  // exactly to the D65 white point (0.95047, 1.0, 1.08883), so pure white maps
  // to (1,1,1) → a=0, b=0. Lower precision (0.4124…) leaks ~0.01 into `a`.
  var x = (rr * 0.4124564 + gg * 0.3575761 + bb * 0.1804375) / 0.95047;
  var y = rr * 0.2126729 + gg * 0.7151522 + bb * 0.0721750;
  var z = (rr * 0.0193339 + gg * 0.1191920 + bb * 0.9503041) / 1.08883;
  double f(double t) =>
      t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;
  x = f(x);
  y = f(y);
  z = f(z);
  return [116 * y - 16, 500 * (x - y), 200 * (y - z)];
}

/// Mean Lab over a pixel region (the color_assert region probe).
List<double> regionMeanLab(img.Image im, int x, int y, int w, int h) {
  var l = 0.0, a = 0.0, b = 0.0, n = 0;
  for (var yy = y; yy < y + h; yy++) {
    for (var xx = x; xx < x + w; xx++) {
      final p = im.getPixel(xx.clamp(0, im.width - 1), yy.clamp(0, im.height - 1));
      final lab = rgbToLab(p.r.toInt(), p.g.toInt(), p.b.toInt());
      l += lab[0];
      a += lab[1];
      b += lab[2];
      n++;
    }
  }
  return n == 0 ? [0, 0, 0] : [l / n, a / n, b / n];
}

/// CIEDE2000 between two Lab colours. Reference: Sharma et al. 2005.
double deltaE2000Lab(num l1, num a1, num b1, num l2, num a2, num b2) {
  const deg = math.pi / 180;
  final c1 = math.sqrt(a1 * a1 + b1 * b1);
  final c2 = math.sqrt(a2 * a2 + b2 * b2);
  final cBar = (c1 + c2) / 2;
  final cBar7 = math.pow(cBar, 7);
  final g = 0.5 * (1 - math.sqrt(cBar7 / (cBar7 + math.pow(25, 7))));
  final a1p = a1 * (1 + g);
  final a2p = a2 * (1 + g);
  final c1p = math.sqrt(a1p * a1p + b1 * b1);
  final c2p = math.sqrt(a2p * a2p + b2 * b2);
  double hp(num a, num b) {
    if (a == 0 && b == 0) return 0;
    final h = math.atan2(b, a) / deg;
    return h >= 0 ? h : h + 360;
  }

  final h1p = hp(a1p, b1), h2p = hp(a2p, b2);
  final dLp = l2 - l1, dCp = c2p - c1p;
  double dHp;
  if (c1p * c2p == 0) {
    dHp = 0;
  } else if ((h2p - h1p).abs() <= 180) {
    dHp = h2p - h1p;
  } else if (h2p - h1p > 180) {
    dHp = h2p - h1p - 360;
  } else {
    dHp = h2p - h1p + 360;
  }
  final dHP = 2 * math.sqrt(c1p * c2p) * math.sin(dHp / 2 * deg);
  final lBarP = (l1 + l2) / 2, cBarP = (c1p + c2p) / 2;
  double hBarP;
  if (c1p * c2p == 0) {
    hBarP = h1p + h2p;
  } else if ((h1p - h2p).abs() <= 180) {
    hBarP = (h1p + h2p) / 2;
  } else if (h1p + h2p < 360) {
    hBarP = (h1p + h2p + 360) / 2;
  } else {
    hBarP = (h1p + h2p - 360) / 2;
  }
  final t = 1 -
      0.17 * math.cos((hBarP - 30) * deg) +
      0.24 * math.cos(2 * hBarP * deg) +
      0.32 * math.cos((3 * hBarP + 6) * deg) -
      0.20 * math.cos((4 * hBarP - 63) * deg);
  final dTheta = 30 * math.exp(-math.pow((hBarP - 275) / 25, 2));
  final cBarP7 = math.pow(cBarP, 7);
  final rc = 2 * math.sqrt(cBarP7 / (cBarP7 + math.pow(25, 7)));
  final sl = 1 + (0.015 * math.pow(lBarP - 50, 2)) / math.sqrt(20 + math.pow(lBarP - 50, 2));
  final sc = 1 + 0.045 * cBarP;
  final sh = 1 + 0.015 * cBarP * t;
  final rt = -math.sin(2 * dTheta * deg) * rc;
  return math.sqrt(math.pow(dLp / sl, 2) +
      math.pow(dCp / sc, 2) +
      math.pow(dHP / sh, 2) +
      rt * (dCp / sc) * (dHP / sh));
}
