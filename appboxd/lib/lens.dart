// appbox lens — the design-vs-built visual gate.
//
// Uses the CDP client to capture screenshots of rendered surfaces and
// compare them against frozen golden images. Three comparison modes:
//   - byte:   exact PNG byte match (strictest, anti-aliasing sensitive)
//   - pixel:  per-pixel diff percentage (tolerant of sub-pixel shifts)
//   - ssim:   structural similarity index (perceptual, luma 11x11 Gaussian)
//
// Pixel/SSIM decode both captures via package:image (lib/lens/pixels.dart)
// and compare in decoded terms. Console/page errors auto-fail before any
// pixel work. The lens is the promoted probe-runner — from underused
// vendored skill to a first-class gate. See plan §6.

import 'dart:io';

import 'package:appboxd/lens/pixels.dart';
import 'package:appboxd/lens/daemon.dart';

export 'lens/pixels.dart';
export 'lens/tokens.dart';
export 'lens/dom.dart';
export 'lens/a11y.dart';
export 'lens/net.dart';
export 'lens/motion.dart';
export 'lens/skeleton.dart';
export 'lens/states.dart';
export 'lens/crawl.dart';
export 'lens/ocr.dart';

/// Comparison method for the visual gate.
enum LensMode { byte, pixel, ssim }

/// Result of a single surface comparison.
class LensResult {
  final String surface;
  final bool passed;
  final double? similarity; // 0.0–1.0 (1.0 = identical); null for byte mode
  final int? diffPixels; // pixel count that differs; null for byte mode
  final String? note;

  LensResult({
    required this.surface,
    required this.passed,
    this.similarity,
    this.diffPixels,
    this.note,
  });
}

/// Thrown when a capture that would become a GOLDEN did not settle.
///
/// Only golden-*writing* raises this. Reading pixels from an unstable page is
/// merely unreliable; writing them to disk as the reference every future run is
/// compared against is corrupting, and it corrupts silently — the bad golden
/// then passes against itself on the next run and fails against everything else.
class LensUnstableCapture implements Exception {
  const LensUnstableCapture(this.url, this.goldenPath, this.elapsedMs);
  final String url;
  final String goldenPath;
  final int elapsedMs;

  @override
  String toString() =>
      'LensUnstableCapture: $url never stopped changing (${elapsedMs}ms), so '
      'refusing to write it as the golden at $goldenPath. Freeze the source of '
      'motion, or pass allowUnstable: true if a nondeterministic golden is '
      'genuinely what you want.';
}

/// Capture a screenshot of [url] at [width]×[height] and save as the golden
/// at [goldenPath]. Creates the golden on first run.
///
/// Throws [LensUnstableCapture] if [goldenPath] is set and the page never
/// settled — see that class for why this one case is fatal rather than a
/// warning. [allowUnstable] opts out.
///
/// Returns the PNG bytes.
Future<List<int>> captureGolden(
  String url,
  int width,
  int height, {
  String? goldenPath,
  int settleMs = 1500,
  bool fullPage = false,
  bool allowUnstable = false,
  Map<String, String> cookies = const {},
}) async {
  final client = await LensDaemon.acquire();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.seedCookies(
        Uri.parse(url).replace(path: '/', query: '', fragment: ''), cookies);
    await tab.setViewport(width, height);
    // Capture path: freeze + floor + stability loop, not a flat timer. Measured
    // on an animated page, 5 fresh-Chrome captures: flat timer 5 distinct
    // images, this 1. `settleMs` becomes the FLOOR, so this never captures
    // earlier than the old path did.
    final settle = await tab.navigateAndSettleForCapture(url,
        settleMs: settleMs, fullPage: fullPage);
    final png = await tab.screenshot(fullPage: fullPage);

    if (goldenPath != null) {
      if (!settle.converged && !allowUnstable) {
        throw LensUnstableCapture(url, goldenPath, settle.elapsedMs);
      }
      final f = File(goldenPath);
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync(png);
    }
    return png;
  } finally {
    await client.close();
  }
}

/// Compare a live screenshot of [url] against the golden at [goldenPath].
///
/// - [mode] controls the comparison algorithm.
/// - [threshold] is the minimum similarity for pixel/ssim modes (default 0.95).
///
/// Returns a [LensResult] with the verdict.
Future<LensResult> compareGolden(
  String url,
  String goldenPath,
  int width,
  int height, {
  LensMode mode = LensMode.byte,
  double threshold = 0.95,
  int settleMs = 1500,
}) async {
  final goldenFile = File(goldenPath);
  if (!goldenFile.existsSync()) {
    return LensResult(
      surface: url,
      passed: false,
      note: 'no golden at $goldenPath — run capture first',
    );
  }

  final goldenBytes = goldenFile.readAsBytesSync();

  final client = await LensDaemon.acquire();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(width, height);
    final settle = await tab.navigateAndSettleForCapture(url, settleMs: settleMs);

    // Capture console/page errors as quality signals.
    final errors = [...tab.consoleErrors, ...tab.pageErrors];
    final png = await tab.screenshot();

    // A capture that never settled cannot be compared to anything. Checked
    // BEFORE the byte/pixel verdict below, because that verdict would be an
    // accident either way: a spurious FAIL if the page moved, and a far worse
    // spurious PASS if it happened to land on the golden's frame.
    if (!settle.converged) {
      return LensResult(
        surface: url,
        passed: false,
        note: 'settle did not converge in ${settle.elapsedMs}ms — the live '
            'capture is not reproducible, so this comparison is meaningless '
            '(animated GIF/APNG, timer repaint, or video?)',
      );
    }

    // Console errors are always a lens failure — the surface has a runtime bug.
    if (errors.isNotEmpty) {
      return LensResult(
        surface: url,
        passed: false,
        note: '${errors.length} console/page error(s): ${errors.first}',
      );
    }

    switch (mode) {
      case LensMode.byte:
        final match = _bytesEqual(png, goldenBytes);
        return LensResult(
          surface: url,
          passed: match,
          note: match ? 'byte-identical to golden' : 'PNG bytes differ',
        );

      case LensMode.pixel:
      case LensMode.ssim:
        try {
          final live = decodePng(png);
          final golden = decodePng(goldenBytes);
          if (mode == LensMode.pixel) {
            final diff = pixelDiff(live, golden);
            final similarity = diff.similarity;
            final ok = similarity >= threshold;
            return LensResult(
              surface: url,
              passed: ok,
              similarity: similarity,
              diffPixels: diff.diffPixels,
              note: ok
                  ? 'pixel match (similarity ${similarity.toStringAsFixed(4)}, ${diff.diffPixels}/${diff.totalPixels} differ)'
                  : 'pixels differ (similarity ${similarity.toStringAsFixed(4)}, ${diff.diffPixels}/${diff.totalPixels})',
            );
          }
          final similarity = ssimSimilarity(live, golden);
          final ok = similarity >= threshold;
          return LensResult(
            surface: url,
            passed: ok,
            similarity: similarity,
            note: ok
                ? 'ssim match (similarity ${similarity.toStringAsFixed(4)})'
                : 'ssim below threshold (similarity ${similarity.toStringAsFixed(4)} < $threshold)',
          );
        } on LensPixelException catch (e) {
          return LensResult(
            surface: url,
            passed: false,
            note: 'decode failed: $e',
          );
        }
    }
  } finally {
    await client.close();
  }
}

/// Run the lens gate over multiple surfaces.
///
/// [surfaces] maps surface name → URL.
/// [goldenDir] is where golden PNGs are stored.
/// Returns a list of results, one per surface.
Future<List<LensResult>> runLensGate(
  Map<String, String> surfaces,
  String goldenDir,
  int width,
  int height, {
  LensMode mode = LensMode.byte,
  double threshold = 0.95,
}) async {
  final results = <LensResult>[];
  for (final entry in surfaces.entries) {
    final goldenPath = '$goldenDir/${entry.key}.png';
    final result = await compareGolden(
      entry.value,
      goldenPath,
      width,
      height,
      mode: mode,
      threshold: threshold,
    );
    results.add(result);
  }
  return results;
}

// ── helpers ────────────────────────────────────────────────────────

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
