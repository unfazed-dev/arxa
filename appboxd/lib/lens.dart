// appbox lens — the design-vs-built visual gate.
//
// Uses the CDP client to capture screenshots of rendered surfaces and
// compare them against frozen golden images. Three comparison modes:
//   - byte:   exact PNG byte match (strictest, anti-aliasing sensitive)
//   - pixel:  per-pixel diff percentage (tolerant of sub-pixel shifts)
//   - ssim:   structural similarity index (perceptual, future)
//
// The lens is the promoted probe-runner — from underused vendored skill
// to a first-class gate. See plan §6.

import 'dart:io';

import 'package:appboxd/cdp.dart';

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

/// Capture a screenshot of [url] at [width]×[height] and save as the golden
/// at [goldenPath]. Creates the golden on first run.
///
/// Returns the PNG bytes.
Future<List<int>> captureGolden(
  String url,
  int width,
  int height, {
  String? goldenPath,
  int settleMs = 1500,
}) async {
  final client = await CdpClient.launch();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(width, height);
    await tab.navigateAndSettle(url, settleMs: settleMs);
    final png = await tab.screenshot();

    if (goldenPath != null) {
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

  final client = await CdpClient.launch();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(width, height);
    await tab.navigateAndSettle(url, settleMs: settleMs);

    // Capture console/page errors as quality signals.
    final errors = [...tab.consoleErrors, ...tab.pageErrors];
    final png = await tab.screenshot();

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
        // Compare PNG dimensions + basic structural check.
        // Full per-pixel comparison requires PNG decode — deferred to when
        // the `image` package is added or CDP canvas comparison is wired.
        final dimsMatch = _pngDimensions(png) == _pngDimensions(goldenBytes);
        if (!dimsMatch) {
          return LensResult(
            surface: url,
            passed: false,
            note: 'dimensions differ: live=${_pngDimensions(png)} golden=${_pngDimensions(goldenBytes)}',
          );
        }
        // kimitail: byte-level fallback until per-pixel SSIM is wired.
        // Ceiling: anti-aliased text or sub-pixel font hinting will cause
        // false negatives in byte mode. Upgrade: add `image` package for
        // per-pixel delta, or compute SSIM via CDP canvas + Runtime.evaluate.
        final match = _bytesEqual(png, goldenBytes);
        return LensResult(
          surface: url,
          passed: match,
          similarity: match ? 1.0 : 0.0,
          note: match ? 'pixel-identical to golden' : 'pixels differ (byte-level check; per-pixel delta coming)',
        );

      case LensMode.ssim:
        // TODO: implement SSIM via CDP canvas comparison or `image` package.
        return LensResult(
          surface: url,
          passed: false,
          note: 'ssim mode not yet implemented — use byte or pixel',
        );
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

/// Extract width×height from PNG IHDR (bytes 16–23).
(String, String) _pngDimensions(List<int> png) {
  if (png.length < 24) return ('?', '?');
  final w = (png[16] << 24) | (png[17] << 16) | (png[18] << 8) | png[19];
  final h = (png[20] << 24) | (png[21] << 16) | (png[22] << 8) | png[23];
  return ('$w', '$h');
}
