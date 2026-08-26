// arxa-lens — macOS Vision OCR + line diff.
//
// Thin ProcessRunner wrapper over the same Swift helper CLI
// (native/lens_native.swift, compiled by lib/lens/native/sck.dart). The `ocr`
// subcommand runs VNRecognizeTextRequest on a PNG and emits
// `{text: [...], observations: [{text, confidence, bbox}]}` JSON; the line diff
// is a pure-Dart LCS (no dependency — the probe-runner used difflib, same
// family). Tests inject a scripted fake so NO real Vision call is required.
// Plan: arxa-lens-full-port.md, Task 10.

library;

import 'dart:convert';

import '../process.dart';
import 'native/adb.dart';
import 'native/sck.dart';

/// Runs `<bin> ocr <pngPath>` and returns the parsed Vision JSON:
/// `{text: [String...], observations: [{text, confidence, bbox: [x,y,w,h]}...]}`.
/// Non-zero exit raises [LensNativeException] carrying the helper stderr.
/// [source] / [cache] override the helper source/cache paths (tests use temp).
Future<Map<String, dynamic>> ocrText(
  String pngPath, {
  ProcessRunner? runner,
  String source = kLensNativeSource,
  String cache = kLensNativeCache,
}) async {
  final r = runner ?? const RealProcessRunner();
  final bin = await ensureLensNativeBinary(runner: r, source: source, cache: cache);
  final res = await r.run(bin, ['ocr', pngPath]);
  if (res.exitCode != 0) {
    throw LensNativeException('lens_macos ocr failed: ${res.stderr}');
  }
  return jsonDecode(res.stdout) as Map<String, dynamic>;
}

/// Line-level diff of [a] vs [b] via longest-common-subsequence, emitting one
/// line per element: ` <line>` (common), `-<line>` (only in a), `+<line>`
/// (only in b). Pure function — no I/O, no dependency.
List<String> textDiffLines(List<String> a, List<String> b) {
  final n = a.length, m = b.length;
  // dp[i][j] = LCS length of a[i..] and b[j..].
  final dp = List.generate(n + 1, (_) => List.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      dp[i][j] = a[i] == b[j]
          ? dp[i + 1][j + 1] + 1
          : (dp[i + 1][j] >= dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1]);
    }
  }
  final out = <String>[];
  var i = 0, j = 0;
  while (i < n && j < m) {
    if (a[i] == b[j]) {
      out.add(' ${a[i]}');
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      out.add('-${a[i]}');
      i++;
    } else {
      out.add('+${b[j]}');
      j++;
    }
  }
  while (i < n) {
    out.add('-${a[i]}');
    i++;
  }
  while (j < m) {
    out.add('+${b[j]}');
    j++;
  }
  return out;
}

/// Runs OCR on both PNGs and returns the merged line diff of their recognized
/// text. Convenience over [ocrText] + [textDiffLines].
Future<List<String>> textDiffPngs(
  String aPng,
  String bPng, {
  ProcessRunner? runner,
  String source = kLensNativeSource,
  String cache = kLensNativeCache,
}) async {
  final r = runner ?? const RealProcessRunner();
  final a = await ocrText(aPng, runner: r, source: source, cache: cache);
  final b = await ocrText(bPng, runner: r, source: source, cache: cache);
  return textDiffLines(
    (a['text'] as List).cast<String>(),
    (b['text'] as List).cast<String>(),
  );
}
