// Motion capture for the appbox lens: burst stills, screencast→mp4 record,
// scroll-scrubbed easing certification, and the WAAPI-oracle flipbook.
//
// Ports the probe-runner motion verbs (web_record, multishot, web_anim,
// web_flipbook) onto the CdpScreencast (Task 2) + the CDP client. ffmpeg
// encode runs through ProcessRunner (lib/process.dart) so the whole record
// path is unit-testable with NO real encode — inject a fake runner.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:appboxd/cdp.dart';
import 'package:appboxd/process.dart';

/// Normalized RMS below this certifies a curve fit (probe-runner `_anim_core`).
const double kEasingRmsCeiling = 0.05;

/// Result of fitting a value series against the standard easing curves.
class EasingFit {
  final bool certified;
  final String? easing; // best-matching curve name (null until at least one fit)
  final double rms; // normalized residual of the best curve
  final String? reason; // why certification failed (null when certified)
  const EasingFit({
    required this.certified,
    required this.easing,
    required this.rms,
    required this.reason,
  });
}

/// Fit [values] (sampled at equal parametric steps across the sweep) against
/// linear, ease-in (t²), ease-out (1-(1-t)²), ease-in-out (smoothstep).
/// Certify the best curve only when its normalized RMS < [kEasingRmsCeiling]
/// AND the series is monotonic. Pure Dart — directly unit-tested. Ported
/// `_anim_core`: same semantics, no OpenCV.
EasingFit fitEasing(List<double> values) {
  final n = values.length;
  if (n < 2) {
    return const EasingFit(
        certified: false, easing: null, rms: double.infinity, reason: 'series too short');
  }
  final from = values.first;
  final to = values.last;
  final span = to - from; // signed; non-zero (flat handled below)
  if (span == 0) {
    return const EasingFit(
        certified: false, easing: null, rms: double.infinity, reason: 'flat series');
  }
  // Monotonic in the overall direction. Flat interior segments are allowed.
  for (var i = 1; i < n; i++) {
    if ((values[i] - values[i - 1]) * span < 0) {
      return const EasingFit(
          certified: false, easing: null, rms: double.infinity, reason: 'non-monotonic');
    }
  }
  // Normalize each sample to 0→1 over the from→to span, then least-squares
  // each standard curve (also 0→1). RMS is in normalized units so the 0.05
  // ceiling is comparable across px / opacity / arbitrary value ranges.
  final curves = <String, double Function(double)>{
    'linear': (t) => t,
    'ease-in': (t) => t * t,
    'ease-out': (t) => 1 - (1 - t) * (1 - t),
    'ease-in-out': (t) => t * t * (3 - 2 * t),
  };
  String? bestName;
  var bestRms = double.infinity;
  curves.forEach((name, fn) {
    var sse = 0.0;
    for (var i = 0; i < n; i++) {
      final t = i / (n - 1);
      final actual = (values[i] - from) / span;
      final err = actual - fn(t);
      sse += err * err;
    }
    final rms = math.sqrt(sse / n);
    if (rms < bestRms) {
      bestRms = rms;
      bestName = name;
    }
  });
  if (bestRms < kEasingRmsCeiling) {
    return EasingFit(certified: true, easing: bestName, rms: bestRms, reason: null);
  }
  return EasingFit(
      certified: false, easing: bestName, rms: bestRms, reason: 'rms exceeds $kEasingRmsCeiling');
}

/// Rapid screenshot burst — [count] PNGs of [url] at [intervalMs] apart.
/// Consecutive frames of an animating page differ. Console/page errors are
/// collected on the session; a separate capture may inspect them. (Ported
/// `multishot`, web-side.)
Future<List<List<int>>> burstFrames(
  String url, {
  int width = 390,
  int height = 844,
  int count = 5,
  int intervalMs = 100,
  int settleMs = 1500,
}) async {
  final client = await CdpClient.launch();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(width, height);
    await tab.navigateAndSettle(url, settleMs: settleMs);
    final frames = <List<int>>[];
    for (var i = 0; i < count; i++) {
      frames.add(await tab.screenshot());
      if (i < count - 1) await Future.delayed(Duration(milliseconds: intervalMs));
    }
    return frames;
  } finally {
    await client.close();
  }
}

/// Record [seconds] of [url] to [outMp4] via CDP screencast → ffmpeg.
///
/// Throws [StateError] if ffmpeg is missing, the page never paints (no
/// frames), or ffmpeg exits non-zero. [runner] is the test seam — inject a
/// fake to avoid a real encode. (Ported `web_record`.)
Future<void> recordVideo(
  String url,
  String outMp4, {
  int width = 390,
  int height = 844,
  int seconds = 5,
  int fps = 15,
  int settleMs = 1500,
  ProcessRunner runner = const RealProcessRunner(),
  String ffmpeg = 'ffmpeg',
}) async {
  // Preflight ffmpeg presence with a clear remediation message.
  final preflight = await runner.run('which', [ffmpeg]);
  if (preflight.exitCode != 0 || preflight.stdout.trim().isEmpty) {
    throw StateError(
      'ffmpeg not found on PATH (probed `$ffmpeg`). Install it to record: '
      'brew install ffmpeg (macOS) / apt install ffmpeg (Debian).',
    );
  }

  final client = await CdpClient.launch();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(width, height);
    await tab.navigateAndSettle(url, settleMs: settleMs);

    final cast = await tab.screencast(format: 'jpeg', quality: 85);
    final frames = <List<int>>[];
    final sub = cast.frames.listen((f) => frames.add(f.bytes));
    await Future.delayed(Duration(seconds: seconds));
    await cast.stop();
    await sub.cancel();

    if (frames.isEmpty) {
      // Protocol behavior (Task 2 note): an idle page produces no frames.
      throw StateError('screencast produced no frames — page never painted');
    }
    await framesToMp4(frames, outMp4, fps, runner: runner, ffmpeg: ffmpeg);
  } finally {
    await client.close();
  }
}

/// Assemble jpeg [frames] into [outMp4] at [fps] via ffmpeg's image2 demuxer.
///
/// Frames are written to a temp dir as zero-padded sequential JPEGs and the
/// whole invocation goes through [runner], so tests fake the encode with no
/// real ffmpeg. The image2 file demuxer (rather than the image2pipe+stdin
/// sketch in the plan) is what the ProcessRunner.run seam supports — that
/// interface has no stdin handle. Same ffmpeg codec pipeline either way.
/// Public so the encode path is unit-testable in isolation (real screencast
/// delivery is non-deterministic; see plan Task 4 + the cdp screencast test).
Future<void> framesToMp4(
  List<List<int>> frames,
  String outMp4,
  int fps, {
  ProcessRunner runner = const RealProcessRunner(),
  String ffmpeg = 'ffmpeg',
}) async {
  final tmp = await Directory.systemTemp.createTemp('appbox-motion-');
  try {
    final pad = frames.length.toString().length; // zero-pad width
    for (var i = 0; i < frames.length; i++) {
      final name = 'frame_${i.toString().padLeft(pad, '0')}.jpg';
      File('${tmp.path}/$name').writeAsBytesSync(frames[i]);
    }
    final res = await runner.run(ffmpeg, [
      '-y',
      '-f', 'image2',
      '-framerate', '$fps',
      '-i', '${tmp.path}/frame_%0${pad}d.jpg',
      '-c:v', 'libx264',
      '-pix_fmt', 'yuv420p',
      '-movflags', '+faststart',
      outMp4,
    ]);
    if (res.exitCode != 0) {
      throw StateError(
        'ffmpeg exited ${res.exitCode} assembling $outMp4 '
        '(${frames.length} frames): ${res.stderr}',
      );
    }
  } finally {
    await tmp.delete(recursive: true);
  }
}

// Samples every element with a non-`none` transform, returning its matrix
// translate (tx, ty) plus a stable [data-lens-mover] selector. Avoids regex
// (and its Dart-string backslash escaping) by slicing between the parens.
const String _transformSamplerJs = '''(function () {
  var els = document.querySelectorAll('*');
  var out = [];
  var idx = 0;
  for (var i = 0; i < els.length; i++) {
    var el = els[i];
    var t = getComputedStyle(el).transform;
    if (!t || t === 'none') continue;
    var tx = 0, ty = 0;
    var open = t.indexOf('(');
    var close = t.lastIndexOf(')');
    if (open > 0 && close > open) {
      var v = t.substring(open + 1, close).split(',').map(parseFloat);
      if (t.indexOf('matrix3d') === 0) {
        tx = v.length > 12 ? v[12] : 0;
        ty = v.length > 13 ? v[13] : 0;
      } else {
        tx = v.length > 4 ? v[4] : 0;
        ty = v.length > 5 ? v[5] : 0;
      }
    }
    if (!el.dataset.lensMover) el.dataset.lensMover = 'm' + idx;
    out.push({ selector: '[data-lens-mover="' + el.dataset.lensMover + '"]',
               tx: tx, ty: ty });
    idx++;
  }
  return out;
})''';

/// Capture and certify a scroll-scrubbed animation. Sweeps the page from top
/// to bottom, sampling every element whose transform varies; fits each
/// channel against the standard easing curves; re-visits step 0 to prove the
/// mapping is reproducible (else `certified: false, reason: non-deterministic`).
///
/// Output: `{url, maxScroll, movers: [{selector, channels: {translateY:
/// {from, to, range, easing, rms, certified}}}], consoleErrors, certified}`.
/// (Ported `web_anim`; the probe-runner's cv2 heuristic is replaced by this
/// exhaustive sample-then-fit core.)
Future<Map<String, dynamic>> captureScrollAnim(
  String url, {
  int width = 390,
  int height = 844,
  int steps = 40,
  int settleMs = 1500,
}) async {
  final client = await CdpClient.launch();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(width, height);
    await tab.navigateAndSettle(url, settleMs: settleMs);

    final maxScroll = ((await tab.evaluate(
      'document.body.scrollHeight - window.innerHeight',
    )) as num).toDouble();

    // Forward sweep: set scrollY, wait one rAF, sample transforms.
    final sweep = <List<Map<String, dynamic>>>[];
    for (var i = 0; i < steps; i++) {
      final sy = (i * maxScroll / (steps - 1)).round();
      await tab.evaluate('window.scrollTo(0, $sy)');
      await tab.evaluate('new Promise(requestAnimationFrame)');
      final raw = await tab.evaluate('$_transformSamplerJs()') as List;
      sweep.add([for (final m in raw) Map<String, dynamic>.from(m as Map)]);
    }

    // Reproducibility revisit of step 0 (must match within 1px).
    await tab.evaluate('window.scrollTo(0, 0)');
    await tab.evaluate('new Promise(requestAnimationFrame)');
    final revisitRaw = await tab.evaluate('$_transformSamplerJs()') as List;
    final revisit = [for (final m in revisitRaw) Map<String, dynamic>.from(m as Map)];

    // Group rows by selector → per-channel value series (one per sweep step).
    final order = <String>[];
    final bySel = <String, List<Map<String, dynamic>>>{};
    for (final step in sweep) {
      for (final m in step) {
        final sel = m['selector'] as String;
        (bySel.putIfAbsent(sel, () {
          order.add(sel);
          return <Map<String, dynamic>>[];
        })).add(m);
      }
    }

    final firstBySel = <String, Map<String, dynamic>>{
      for (final m in sweep.first) m['selector'] as String: m,
    };
    var reproducible = true;
    for (final m in revisit) {
      final orig = firstBySel[m['selector'] as String];
      if (orig == null) continue;
      if (((m['tx'] as num) - (orig['tx'] as num)).abs() > 1 ||
          ((m['ty'] as num) - (orig['ty'] as num)).abs() > 1) {
        reproducible = false;
      }
    }

    final movers = <Map<String, dynamic>>[];
    for (final sel in order) {
      final series = bySel[sel]!;
      final channels = <String, dynamic>{};
      void channel(String name, List<double> v) {
        final lo = v.reduce(math.min);
        final hi = v.reduce(math.max);
        if ((hi - lo) <= 1e-3) return; // static channel — no motion to certify
        final fit = fitEasing(v);
        channels[name] = {
          'from': v.first,
          'to': v.last,
          'range': (v.last - v.first).abs(),
          'easing': fit.certified ? fit.easing : null,
          'rms': fit.rms,
          'certified': fit.certified,
          if (!fit.certified && fit.reason != null) 'reason': fit.reason,
        };
      }
      channel('translateX', [for (final m in series) (m['tx'] as num).toDouble()]);
      channel('translateY', [for (final m in series) (m['ty'] as num).toDouble()]);
      if (channels.isNotEmpty) movers.add({'selector': sel, 'channels': channels});
    }

    final allCertified = movers.every((m) =>
        (m['channels'] as Map).values.every((c) => (c as Map)['certified'] as bool));
    final consoleErrors = [...tab.consoleErrors, ...tab.pageErrors];

    return {
      'url': url,
      'maxScroll': maxScroll,
      'movers': movers,
      'consoleErrors': consoleErrors,
      'certified': reproducible && allCertified && consoleErrors.isEmpty,
      if (!reproducible) 'reason': 'non-deterministic',
    };
  } finally {
    await client.close();
  }
}

// Reads every active animation via the WAAPI oracle: per animation, its
// keyframes, timing (duration/easing) and playState.
const String _readAnimationsJs = '''(function () {
  return document.getAnimations().map(function (a) {
    var eff = a.effect;
    var kf = (eff && eff.getKeyframes) ? eff.getKeyframes() : [];
    var timing = (eff && eff.getTiming) ? eff.getTiming() : {};
    return {
      target: 'element',
      keyframes: kf.map(function (k) {
        return {
          opacity: k.opacity == null ? null
            : (typeof k.opacity === 'number' ? k.opacity : parseFloat(k.opacity)),
          offset: k.offset,
        };
      }),
      duration: typeof timing.duration === 'number' ? timing.duration : 0,
      easing: timing.easing || '',
      playState: a.playState,
    };
  });
})''';

/// Capture an event-triggered animation via the WAAPI oracle. Navigates,
/// clicks [triggerSelector], then polls `document.getAnimations()` for
/// [watchMs]; recovers keyframes/duration/easing/playState directly from the
/// animation's effect.
///
/// Output: `{url, animations: [{target, keyframes, duration, easing,
/// playState}], reliable, consoleErrors, certified}`. `reliable: false`
/// when the oracle observes no animations. (Ported `web_flipbook`, oracle
/// path.)
Future<Map<String, dynamic>> captureFlipbook(
  String url, {
  required String triggerSelector,
  int width = 390,
  int height = 844,
  int watchMs = 2000,
  int settleMs = 1500,
}) async {
  final client = await CdpClient.launch();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(width, height);
    await tab.navigateAndSettle(url, settleMs: settleMs);

    await _clickSelector(tab, triggerSelector);

    var anims = <dynamic>[];
    final deadline = DateTime.now().add(Duration(milliseconds: watchMs));
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 100));
      anims = await tab.evaluate('$_readAnimationsJs()') as List;
      if (anims.isNotEmpty) break;
    }

    final reliable = anims.isNotEmpty;
    // kimitail: WAAPI covers appbox's own designs; when a design animates
    // outside WAAPI the caller may fall back to burstFrames + pixelDiff
    // region tracking. That frame-recovery path is NOT built here — add it
    // when a real design reports reliable:false on a known-animating page.
    final consoleErrors = [...tab.consoleErrors, ...tab.pageErrors];
    return {
      'url': url,
      'animations': anims,
      'reliable': reliable,
      'consoleErrors': consoleErrors,
      'certified': reliable && consoleErrors.isEmpty,
    };
  } finally {
    await client.close();
  }
}

/// Click the center of [selector]'s border box (DOM.getBoxModel → center →
/// Input mouse press/release), mirroring elementScreenshot in cdp.dart.
Future<void> _clickSelector(CdpSession tab, String selector) async {
  final doc = await tab.send('DOM.getDocument');
  final node = await tab.send('DOM.querySelector', {
    'nodeId': doc['result']['root']['nodeId'],
    'selector': selector,
  });
  if (node['result']['nodeId'] == 0) {
    throw CdpException('captureFlipbook: trigger not found: $selector');
  }
  final box = await tab.send('DOM.getBoxModel', {'nodeId': node['result']['nodeId']});
  final border = box['result']['model']['border'] as List;
  final xs = [border[0], border[2], border[4], border[6]]
      .map((v) => (v as num).toDouble())
      .toList();
  final ys = [border[1], border[3], border[5], border[7]]
      .map((v) => (v as num).toDouble())
      .toList();
  final cx = ((xs.reduce(math.min) + xs.reduce(math.max)) / 2).round();
  final cy = ((ys.reduce(math.min) + ys.reduce(math.max)) / 2).round();
  await tab.click(cx, cy);
}
