// Lens gate — design-vs-built as a first-class pipeline gate. Plan §6, Task 12.
//
// Compares the frozen, design-rendered golden against the built app's live
// render, per surface × viewport. Pixel/SSIM/byte comparison (lens facade) with
// console/page-error auto-fail. The gate is exit-2 (env/skip) when there is no
// `lens` config, and exit-2 when a native capture target is configured-but-
// unavailable (no running app / tool / permission). Shape mirrors gate_freeze.
//
// Capture source per target:
//   capture.kind: same        → both sides via CDP (the web path; tested).
//   capture.kind: flutter-vm  → built side via a Flutter VM service screenshot.
//   capture.kind: macos-sck   → built side via ScreenCaptureKit (macOS window).
// The native kinds wire the capture call and env-skip when unavailable — the
// realistic headless/CI state. Goldens are written only via recaptureGoldens
// (the freeze-gate approval pattern).

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/gates.dart';
import 'package:appboxd/lens.dart';
import 'package:appboxd/lens/native/adb.dart' show LensNativeException;
import 'package:appboxd/lens/native/flutter_vm.dart';
import 'package:appboxd/lens/native/sck.dart';

/// The design-vs-built visual gate.
///
/// Reads a `lens` block from `config/appbox.config.json`; absent →
/// [GateResult.env] (skipped, not failed). For every configured surface ×
/// viewport, compares the live render against the frozen golden via
/// [compareGolden] (SSIM default, threshold 0.98). Console/page errors auto-
/// fail. Goldens are written only when [recaptureGoldens] is true.
Future<GateResult> lensGate(GateContext ctx, {bool recaptureGoldens = false}) async {
  if (ctx.selfTest) return _lensSelfTest();

  // ---- read config ----
  final configFile = File(ctx.configFile);
  if (!configFile.existsSync()) {
    return GateResult.env('lens: no config at ${ctx.configFile} — gate skipped');
  }
  Map<String, dynamic> config;
  try {
    config = jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
  } catch (e) {
    return GateResult.env('lens: config does not parse — $e');
  }
  final lens = config['lens'];
  if (lens is! Map<String, dynamic>) {
    return GateResult.env('lens: no `lens` config block — gate skipped');
  }

  // ---- resolve the lens block ----
  final goldensDir = _resolveUnder(
      ctx.repoRoot,
      (lens['goldens'] ?? '${GateContext.studioDesignDir}/goldens') as String);
  final surfaces = (lens['surfaces'] ?? const <String, dynamic>{}) as Map;
  if (surfaces.isEmpty) {
    return GateResult.fail('lens: no surfaces configured under lens.surfaces');
  }
  final serve = (lens['serve'] ?? const <String, dynamic>{}) as Map;
  final capture = (lens['capture'] ?? const {'kind': 'same'}) as Map;
  final modes = (lens['modes'] ?? const <String, dynamic>{}) as Map;
  final mode = _parseMode(modes['compare']) ?? LensMode.ssim;
  final threshold = (modes['threshold'] as num?)?.toDouble() ?? 0.98;
  final captureKind = ((capture['kind'] ?? 'same') as String).trim();
  final settleMs = (capture['settleMs'] as num?)?.toInt() ?? 800;

  final viewports = _resolveViewports(config);
  if (viewports.isEmpty) {
    return GateResult.fail('lens: no viewports in config — gate skipped');
  }

  // Native capture kinds: the built side is a running app, not a URL. Wire the
  // capture call and env-skip when the tool/app/permission is unavailable.
  if (captureKind == 'flutter-vm' || captureKind == 'macos-sck') {
    return _nativeCompare(
      ctx: ctx,
      captureKind: captureKind,
      capture: capture.cast<String, dynamic>(),
      surfaces: surfaces.cast<String, dynamic>(),
      viewports: viewports,
      goldensDir: goldensDir,
      mode: mode,
      threshold: threshold,
      settleMs: settleMs,
    );
  }

  // ---- CDP (`same`) path: both sides rendered by Chromium ----
  final evidenceDir = '${ctx.designRoot}/evidence/lens-gate';
  await Directory(evidenceDir).create(recursive: true);
  await Directory(goldensDir).create(recursive: true);

  // Resolve the serve source: a live URL, or a loopback static server.
  HttpServer? staticServer;
  String base;
  if (((serve['kind'] ?? 'url') as String) == 'static') {
    staticServer = await _bindStaticServer(ctx.designRoot);
    base = 'http://${staticServer.address.address}:${staticServer.port}';
  } else {
    final b = serve['base'];
    if (b is! String || b.isEmpty) {
      return GateResult.fail(
          'lens: serve.base is required for serve.kind "url"');
    }
    base = b.replaceAll(RegExp(r'/+$'), '');
  }

  final details = <String>[];
  var fails = 0;
  var passes = 0;
  try {
    if (recaptureGoldens) {
      final n = await _recapture(
        base: base,
        surfaces: surfaces,
        viewports: viewports,
        goldensDir: goldensDir,
        settleMs: settleMs,
        details: details,
      );
      final sum = 'lens: RECAPTURED — $n golden(s) rewritten '
          '(approve by committing the goldens dir)';
      details.add(sum);
      return GateResult.ok(sum, details);
    }

    for (final name in surfaces.keys) {
      final url = _joinUrl(base, surfaces[name].toString());
      for (final vp in viewports) {
        final goldenPath = '$goldensDir/$name-${vp.width}.png';
        final evidencePath = '$evidenceDir/$name-${vp.width}.png';
        final r = await _compareSurface(
          url: url,
          surface: name,
          vp: vp,
          goldenPath: goldenPath,
          evidencePath: evidencePath,
          mode: mode,
          threshold: threshold,
          settleMs: settleMs,
        );
        details.add(r.detail);
        if (r.passed) {
          passes++;
        } else {
          ctx.sarif.result('lens', 'error', evidencePath, r.detail.trim());
          fails++;
        }
      }
    }
  } finally {
    await staticServer?.close(force: true);
  }

  if (fails > 0) {
    return GateResult.fail(
        'lens: FAIL — $fails surface(s) below threshold ($passes passed)', details);
  }
  return GateResult.ok('lens: PASS — $passes surface(s) match goldens', details);
}

// ── CDP compare / recapture ────────────────────────────────────────────────

class _Verdict {
  final bool passed;
  final String detail;
  _Verdict(this.passed, this.detail);
}

/// Capture evidence + compare one surface@viewport against its golden.
///
/// kimitail: this launches Chromium twice per surface (once to write the
/// evidence render, once inside compareGolden). compareGolden does not surface
/// the captured bytes and we must not edit lens.dart; if the per-surface cost
/// matters in CI, extend compareGolden to return both bytes and verdict.
Future<_Verdict> _compareSurface({
  required String url,
  required String surface,
  required _Vp vp,
  required String goldenPath,
  required String evidencePath,
  required LensMode mode,
  required double threshold,
  required int settleMs,
}) async {
  await captureGolden(url, vp.width, vp.height,
      goldenPath: evidencePath, settleMs: settleMs);
  final r = await compareGolden(url, goldenPath, vp.width, vp.height,
      mode: mode, threshold: threshold, settleMs: settleMs);
  final tag = r.similarity != null
      ? ' SSIM ${r.similarity!.toStringAsFixed(4)}'
      : (mode == LensMode.pixel ? ' pixel' : '');
  if (r.passed) {
    return _Verdict(true, '  ✓ $surface@${vp.width}$tag');
  }
  final below = r.similarity != null ? ' (< $threshold)' : '';
  return _Verdict(false, '  ✗ $surface@${vp.width}$tag$below — ${r.note}');
}

Future<int> _recapture({
  required String base,
  required Map surfaces,
  required List<_Vp> viewports,
  required String goldensDir,
  required int settleMs,
  required List<String> details,
}) async {
  var n = 0;
  for (final name in surfaces.keys) {
    final url = _joinUrl(base, surfaces[name].toString());
    for (final vp in viewports) {
      final goldenPath = '$goldensDir/$name-${vp.width}.png';
      await captureGolden(url, vp.width, vp.height,
          goldenPath: goldenPath, settleMs: settleMs);
      details.add('  ✓ recaptured golden $name@${vp.width} -> $goldenPath');
      n++;
    }
  }
  return n;
}

// ── native capture (flutter-vm / macos-sck) ────────────────────────────────

/// Wire native capture of the built side, then compare against the design
/// golden file-to-file. Env-skip (exit 2) the moment the tool/app/permission is
/// unavailable — the realistic headless/CI state.
Future<GateResult> _nativeCompare({
  required GateContext ctx,
  required String captureKind,
  required Map<String, dynamic> capture,
  required Map<String, dynamic> surfaces,
  required List<_Vp> viewports,
  required String goldensDir,
  required LensMode mode,
  required double threshold,
  required int settleMs,
}) async {
  final evidenceDir = '${ctx.designRoot}/evidence/lens-gate';
  await Directory(evidenceDir).create(recursive: true);
  final details = <String>[];

  try {
    var passes = 0;
    var fails = 0;
    for (final name in surfaces.keys) {
      for (final vp in viewports) {
        final goldenPath = '$goldensDir/$name-${vp.width}.png';
        final evidencePath = '$evidenceDir/$name-${vp.width}.png';
        await _captureBuiltSide(captureKind, capture, evidencePath);
        final r = _compareFiles(goldenPath, evidencePath, name, mode, threshold);
        final tag = r.similarity != null
            ? ' SSIM ${r.similarity!.toStringAsFixed(4)}'
            : '';
        if (r.passed) {
          details.add('  ✓ $name@${vp.width}$tag (native: $captureKind)');
          passes++;
        } else {
          final below = r.similarity != null ? ' (< $threshold)' : '';
          details.add('  ✗ $name@${vp.width}$tag$below — ${r.note}');
          ctx.sarif.result('lens', 'error', evidencePath,
              '$name@${vp.width} ($captureKind) ${r.note}');
          fails++;
        }
      }
    }
    if (fails > 0) {
      return GateResult.fail(
          'lens: FAIL — $fails surface(s) below threshold ($passes passed)',
          details);
    }
    return GateResult.ok(
        'lens: PASS — $passes surface(s) match ($captureKind)', details);
  } on LensNativeException catch (e) {
    return GateResult.env(
        'lens: capture.kind $captureKind unavailable — $e');
  } on LensVmException catch (e) {
    return GateResult.env(
        'lens: capture.kind flutter-vm unavailable — $e');
  }
}

/// Capture one built-side frame to [outPng] via the configured native family.
Future<void> _captureBuiltSide(
    String kind, Map<String, dynamic> capture, String outPng) async {
  switch (kind) {
    case 'flutter-vm':
      final uri = capture['uri'] as String?;
      if (uri == null || uri.isEmpty) {
        throw LensVmException(
            'capture.kind flutter-vm needs capture.uri pointing at a running '
            'Flutter VM service (use `lens native flutter parse-uri`)');
      }
      final vm = await FlutterVm.connect(uri);
      try {
        final png = await vm.screenshot();
        File(outPng)
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(png);
      } finally {
        await vm.dispose();
      }
      break;
    case 'macos-sck':
      final windowId = (capture['windowId'] as num?)?.toInt();
      await LensSck().shot(outPng, windowId: windowId);
      break;
  }
}

/// File-vs-file compare for the native path (the built side is a PNG, not a
/// URL, so compareGolden — which captures live — cannot be used). Reuses the
/// lens pixel primitives. Native captures cannot surface DOM console errors.
LensResult _compareFiles(String goldenPath, String builtPath, String surface,
    LensMode mode, double threshold) {
  final golden = File(goldenPath);
  if (!golden.existsSync()) {
    return LensResult(
        surface: surface, passed: false, note: 'no golden at $goldenPath');
  }
  try {
    final g = decodePng(golden.readAsBytesSync());
    final b = decodePng(File(builtPath).readAsBytesSync());
    if (mode == LensMode.pixel) {
      final diff = pixelDiff(b, g);
      final ok = diff.similarity >= threshold;
      return LensResult(
        surface: surface,
        passed: ok,
        similarity: diff.similarity,
        diffPixels: diff.diffPixels,
        note: ok
            ? 'pixel match (similarity ${diff.similarity.toStringAsFixed(4)})'
            : 'pixels differ (similarity ${diff.similarity.toStringAsFixed(4)})',
      );
    }
    final s = ssimSimilarity(b, g);
    final ok = s >= threshold;
    return LensResult(
      surface: surface,
      passed: ok,
      similarity: s,
      note: ok
          ? 'ssim match (similarity ${s.toStringAsFixed(4)})'
          : 'ssim below threshold (similarity ${s.toStringAsFixed(4)} < $threshold)',
    );
  } on LensPixelException catch (e) {
    return LensResult(surface: surface, passed: false, note: 'decode failed: $e');
  }
}

// ── self-test (`appbox gate lens --self-test`) ─────────────────────────────

/// Build a temp fixture repo, prove a positive (match) and a negative
/// (tampered surface MUST fail) — the gates-must-be-able-to-fail contract.
Future<GateResult> _lensSelfTest() async {
  final tmp = await Directory.systemTemp.createTemp('gate-lens-selftest-');
  final details = <String>[];
  HttpServer? a;
  HttpServer? b;
  try {
    // positive: capture + compare the same color passes.
    final (sa, baseA) = await _bootColorServer('#0000ff');
    a = sa;
    _writeSelfTestConfig(tmp.path, baseA);
    final ctxPos = GateContext(repoRoot: tmp.path);
    await lensGate(ctxPos, recaptureGoldens: true);
    final r1 = await lensGate(ctxPos);
    if (!r1.passed) {
      details.addAll(r1.details);
      details.add('  FAIL  positive: expected the surface to match its golden');
      return GateResult.fail('lens self-test: FAIL (positive case)', details);
    }
    details.add('  PASS  positive: surface matches golden');

    // negative: swap the color — the gate must now fail.
    await a.close();
    a = null;
    final (sb, baseB) = await _bootColorServer('#ffffff');
    b = sb;
    _writeSelfTestConfig(tmp.path, baseB);
    final ctxNeg = GateContext(repoRoot: tmp.path);
    final r2 = await lensGate(ctxNeg);
    if (r2.passed) {
      details.add('  FAIL  negative: tampered surface should have failed');
      return GateResult.fail(
          'lens self-test: FAIL (negative case did not fail)', details);
    }
    final scoreLine = r2.details.firstWhere(
      (d) => d.toUpperCase().contains('SSIM'),
      orElse: () => r2.details.join('; '),
    );
    details.add('  # NEGATIVE: tampered surface correctly failed ($scoreLine)');
    details.add('lens self-test: PASS (positive match + negative mismatch)');
    return GateResult.ok('lens self-test: PASS', details);
  } finally {
    await a?.close();
    await b?.close();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  }
}

Future<(HttpServer, String)> _bootColorServer(String color) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final base = 'http://${server.address.address}:${server.port}';
  server.listen((req) {
    req.response.headers.contentType = ContentType.html;
    req.response.write('<!DOCTYPE html><html><head><style>'
        'body{margin:0;background:$color;width:390px;height:844px;}'
        '</style></head><body></body></html>');
    req.response.close();
  });
  return (server, base);
}

void _writeSelfTestConfig(String repoRoot, String baseUrl) {
  final cfg = {
    'targets': ['web'],
    'viewports': {
      'mobile': {'width': 390, 'height': 844},
    },
    'lens': {
      'goldens': 'designs/appbox-studio/goldens',
      'surfaces': {'home': '/'},
      'serve': {'kind': 'url', 'base': baseUrl},
      'capture': {'kind': 'same', 'settleMs': 300},
      'modes': {'compare': 'ssim', 'threshold': 0.98},
    },
  };
  Directory('$repoRoot/config').createSync(recursive: true);
  File('$repoRoot/config/appbox.config.json')
      .writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(cfg)}\n');
}

// ── helpers ────────────────────────────────────────────────────────────────

class _Vp {
  final String name;
  final int width;
  final int height;
  _Vp(this.name, this.width, this.height);
}

LensMode? _parseMode(dynamic v) {
  switch (v is String ? v.toLowerCase() : v) {
    case 'byte':
      return LensMode.byte;
    case 'pixel':
      return LensMode.pixel;
    case 'ssim':
      return LensMode.ssim;
    default:
      return null;
  }
}

List<_Vp> _resolveViewports(Map<String, dynamic> config) {
  final vps = config['viewports'];
  if (vps is! Map) return const [];
  final out = <_Vp>[];
  for (final entry in vps.entries) {
    final v = entry.value;
    if (v is Map) {
      final w = (v['width'] as num?)?.toInt();
      final h = (v['height'] as num?)?.toInt();
      if (w != null && h != null) out.add(_Vp(entry.key as String, w, h));
    }
  }
  return out;
}

String _resolveUnder(String root, String rel) =>
    rel.startsWith('/') ? rel : '$root/$rel';

String _joinUrl(String base, String path) {
  if (path.isEmpty || path == '/') return '$base/';
  final p = path.startsWith('/') ? path : '/$path';
  return '$base$p';
}

/// Loopback static server over a directory (the dart:io analog of python's
/// SimpleHTTPRequestHandler). Mirrors gate_freeze's _bindStaticServer.
Future<HttpServer> _bindStaticServer(String root) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final raw = Uri.decodeComponent(request.uri.path);
    if (raw.contains('..')) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }
    var fsPath = raw.endsWith('/') ? '$root$raw/index.html' : '$root$raw';
    final f = File(fsPath);
    if (await f.exists()) {
      final bytes = await f.readAsBytes();
      request.response
        ..headers.contentType = _mime(raw)
        ..contentLength = bytes.length
        ..add(bytes);
      await request.response.close();
    } else {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    }
  });
  return server;
}

ContentType _mime(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.html')) return ContentType.html;
  if (lower.endsWith('.css')) return ContentType('text', 'css');
  if (lower.endsWith('.js')) return ContentType('application', 'javascript');
  if (lower.endsWith('.json')) return ContentType('application', 'json');
  if (lower.endsWith('.png')) return ContentType('image', 'png');
  if (lower.endsWith('.svg')) return ContentType('image', 'svg+xml');
  return ContentType('application', 'octet-stream');
}
