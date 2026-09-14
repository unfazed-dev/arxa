/// Pixel substrate for the arxa lens: PNG decode, per-pixel diff,
/// SSIM, and CIEDE2000 colour delta. The only place arxa touches
/// package:image; everything above this file works in decoded Image
/// terms. SSIM parameters follow Wang et al.: 11x11 Gaussian window
/// (sigma 1.5), K1=0.01, K2=0.03, luma channel.
///
/// The bottom section is the palette-plane pixel probe (plan
/// arxa-palette-plane-universal §lens-pixel-probe) — NOT pure: it rides
/// the lens daemon's headless Chrome to decode an image file and bucket
/// its pixels into ColorClusters for palette_derive.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'daemon.dart';
import 'tokens.dart'; // ColorCluster — the probe returns tokens.dart's shape

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

/// Dominant exact-color share of a frame: pct in 0..100, color the rgb
/// triple that owns it.
///
/// Born 2026-08-25 out of the "washed white captures" investigation: a
/// capture that is ~99% one flat color is the signature of a page caught
/// mid-intro — the settle loop converges on the plateau because the plateau
/// is genuinely stable (measured on suczka-studio: converged at 3119ms while
/// the JS-driven intro did not paint until ~5s, evidence 99.4% white). The
/// capture verbs use this to WARN instead of writing white evidence
/// silently; it never fails a capture, because a deliberately minimal page
/// is allowed to be uniform.
({double pct, List<int> color}) uniformity(img.Image image) {
  final counts = <int, int>{};
  final reps = <int, List<int>>{};
  final n = image.width * image.height;
  for (final p in image) {
    final r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
    final k = (r << 16) | (g << 8) | b;
    counts[k] = (counts[k] ?? 0) + 1;
    reps[k] ??= [r, g, b];
  }
  var bestK = 0, bestN = 0;
  counts.forEach((k, c) {
    if (c > bestN) {
      bestN = c;
      bestK = k;
    }
  });
  return (pct: 100.0 * bestN / n, color: reps[bestK]!);
}

// --- palette-plane pixel probe (arxa-palette-plane-universal §lens-pixel-probe) ---

/// The image probe injected into the page, as an async function taking the
/// image as a data: URL (ridden through [CdpSession.evaluateFunction]).
///
/// Why data: and not the file:// document the tab is sitting on: current
/// Chrome hands file: documents OPAQUE origins, so even the same file's
/// pixels taint the canvas — measured 2026-09-10, getImageData throws
/// SecurityError on a file:// ImageDocument reading its own image. A data:
/// URL is origin-clean by HTML spec, the readback succeeds, and Chrome
/// still performs the decode (every browser format free, zero native
/// deps). The plan's file:// navigation is kept; only the byte transport
/// changed.
///
/// Downscale cap: the longer side is brought to <= 128, so a sampled read
/// never exceeds 128x128 = 16,384 pixels (~64K ints across the CDP
/// boundary) no matter the source size. Palette derivation needs colour
/// frequencies, not resolution.
///
/// Returns {width, height, pixels: [rgba...]} of the SAMPLED canvas. The
/// bucketing law lives in Dart ([clusterPixels]) — the same probe-samples /
/// Dart-clusters split as tokens.dart, so the law is unit-testable without
/// Chrome. Kept as one evaluate() round-trip (tokens.dart's shape).
const String pixelProbeJs = r'''
async (src) => {
  const MAX = 128;
  const image = await new Promise((resolve, reject) => {
    const im = new Image();
    im.onload = () => resolve(im);
    im.onerror = () =>
        reject(new Error('lens pixels: image failed to decode'));
    im.src = src;
  });
  const scale = Math.min(1, MAX / Math.max(image.naturalWidth, image.naturalHeight));
  const w = Math.max(1, Math.round(image.naturalWidth * scale));
  const h = Math.max(1, Math.round(image.naturalHeight * scale));
  const canvas = document.createElement('canvas');
  canvas.width = w;
  canvas.height = h;
  const ctx = canvas.getContext('2d', {willReadFrequently: true});
  ctx.drawImage(image, 0, 0, w, h);
  return {width: w, height: h, pixels: Array.from(ctx.getImageData(0, 0, w, h).data)};
}
''';

/// Frequency-cluster raw RGBA bytes: pixels with alpha < 128 are skipped
/// (translucent pixels pollute palettes with compositing noise), each
/// remaining channel is quantised >>5 to 8 levels (32-wide bands), and a
/// bucket reports its band CENTER ((q<<5)+16) — the least-biased
/// representative for the <=12 RGB-euclidean merge, which lives downstream
/// in palette_derive (one merge law, one home).
///
/// Sort: count desc, then packed-rgb asc. Dart's List.sort is unstable, so
/// equal-count buckets would otherwise order by scan position — the output
/// would depend on image LAYOUT, not the colour set. The tie-break makes it
/// canonical (determinism law).
List<ColorCluster> clusterPixels(List<int> rgba) {
  final counts = <int, int>{};
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    if (rgba[i + 3] < 128) continue;
    final q =
        ((rgba[i] >> 5) << 6) | ((rgba[i + 1] >> 5) << 3) | (rgba[i + 2] >> 5);
    counts[q] = (counts[q] ?? 0) + 1;
  }
  final out = <ColorCluster>[];
  for (final e in counts.entries) {
    out.add(ColorCluster(
      ((e.key >> 6) << 5) + 16,
      (((e.key >> 3) & 7) << 5) + 16,
      ((e.key & 7) << 5) + 16,
      e.value,
    ));
  }
  out.sort((a, b) => b.count != a.count
      ? b.count.compareTo(a.count)
      : (a.r << 16 | a.g << 8 | a.b).compareTo(b.r << 16 | b.g << 8 | b.b));
  return out;
}

/// Extension → data: URL mime for the probe's transport. The browser's
/// decoder sniffs magic bytes anyway (application/octet-stream still
/// decodes); the precise type is courtesy, not load-bearing.
String _mimeFor(String path) {
  final dot = path.lastIndexOf('.');
  final ext = dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
  return switch (ext) {
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    'avif' => 'image/avif',
    'bmp' => 'image/bmp',
    'svg' => 'image/svg+xml',
    _ => 'application/octet-stream',
  };
}

/// Shared core behind [extractPixels] and [extractPixelClusters]: navigate
/// the daemon's tab to the image's file:// document (plan §lens-pixel-probe),
/// then run [pixelProbeJs] over the bytes as a data: URL (see the probe's
/// doc for why the canvas cannot read the file:// document directly) and
/// bucket the readback. Errors ride as data because the two wrappers
/// disagree on what to do with them (extractPixels records, per the
/// observation-JSON doctrine; extractPixelClusters fails).
Future<({int width, int height, List<ColorCluster> clusters, List<String> errors})>
    _readImagePixels(String imagePath, int settleMs) async {
  final file = File(imagePath);
  if (!file.existsSync()) {
    throw ArgumentError('lens pixels: image not found: $imagePath');
  }
  final dataUrl =
      'data:${_mimeFor(imagePath)};base64,${base64Encode(await file.readAsBytes())}';
  final client = await LensDaemon.acquire();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.navigateAndSettle(file.absolute.uri.toString(),
        settleMs: settleMs);
    final raw = await tab.evaluateFunction(pixelProbeJs, dataUrl) as Map;
    return (
      width: (raw['width'] as num).toInt(),
      height: (raw['height'] as num).toInt(),
      clusters: clusterPixels(
          [for (final n in (raw['pixels'] as List).cast<num>()) n.toInt()]),
      errors: [...tab.consoleErrors, ...tab.pageErrors],
    );
  } finally {
    await client.close();
  }
}

/// Extract the dominant colour clusters of an image file as observation
/// JSON (same envelope doctrine as extractTokens): the lens daemon's
/// headless Chrome decodes the image (file:// URL — every browser format
/// free), the probe samples it bounded, [clusterPixels] buckets. Console/
/// page errors are returned in the result; the caller treats non-empty as
/// a failure.
///
/// settleMs defaults low (300): the probe itself awaits the image's load
/// event, so the settle window only covers the viewer document.
Future<Map<String, dynamic>> extractPixels(String imagePath,
    {int settleMs = 300}) async {
  final r = await _readImagePixels(imagePath, settleMs);
  return {
    'image': imagePath,
    'sampled': [r.width, r.height],
    'clusters': [for (final c in r.clusters) c.toJson()],
    'consoleErrors': r.errors,
    'certified': r.errors.isEmpty,
  };
}

/// The palette engine's contract (plan §lens-pixel-probe): clusters in
/// tokens.dart's ColorCluster shape. Console/page errors FAIL the
/// extraction (lens doctrine) — a throw, because a [List<ColorCluster>] has
/// no in-band channel to carry them and a poisoned palette must never read
/// as an empty one.
Future<List<ColorCluster>> extractPixelClusters(String imagePath) async {
  final r = await _readImagePixels(imagePath, 300);
  if (r.errors.isNotEmpty) {
    throw StateError('lens pixels: ${r.errors.length} console/page error(s) '
        'reading $imagePath — ${r.errors.first}');
  }
  return r.clusters;
}
