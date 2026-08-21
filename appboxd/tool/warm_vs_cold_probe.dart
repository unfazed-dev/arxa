// warm_vs_cold_probe.dart — does a REUSED Chrome render byte-identically to a
// FRESHLY-LAUNCHED one?
//
// This gates the `appbox lens` daemon plan: holding ONE warm Chrome and reusing
// it across captures kills ~1.4s of launch per invocation, but the tool exists
// to compare pixels. A speed win that changes pixels is worthless. No official
// source (Chromium/CDP/Puppeteer/Playwright) documents whether font-shaping,
// GPU raster, or shader caches perturb output once warm — so it is measured.
//
// Run:  cd appboxd && dart run tool/warm_vs_cold_probe.dart
// Slow by construction (the cold arms relaunch Chrome per capture). ~5 min.
//
// ── Anti-false-pass design ────────────────────────────────────────────────
// This repo has been burned six times by a check whose "pass" outcome was also
// its "did not run" outcome. The guards here exist against exactly that:
//
//  1. TWO negative controls, printed FIRST, through the SAME capture path as
//     every real measurement:
//       coarse — same page at 1280 vs 1281 px wide → hashes MUST differ
//       fine   — one 14px word recoloured by ONE RGB step → hashes MUST differ
//     The fine control is the load-bearing one: cache-driven drift looks like a
//     few antialiased glyph edges, so if the instrument cannot see a one-step
//     recolour it cannot see the thing being hunted, and every "identical" it
//     reports is meaningless. Either control failing aborts the run.
//  2. A SECOND cold pass (COLD-B). If COLD-A != COLD-B the machine itself is
//     nondeterministic and no warm-vs-cold verdict means anything — a distinct
//     failure mode from "warm drifts", indistinguishable without this arm.
//  3. Warm arms INTERLEAVE pages (text→css→static, five rounds) instead of
//     reloading one page. Re-navigating the same URL can be a no-op that never
//     repaints — "all 5 identical" would then be the did-not-run outcome in
//     disguise. Interleaving forces a real layout+paint AND actually warms the
//     caches, which is the condition the daemon would run under.
//  4. Every capture is fenced: a throw, a timeout, or zero bytes records an
//     ERROR sample. An arm reports n/N beside every count, so a short arm that
//     "trivially all matches" is visible rather than silently passing.
//  5. Both BYTE hashes (PNG stream) and PIXEL hashes (decoded RGBA) are
//     reported. PNG encoding can in principle vary while pixels do not; without
//     the pixel column a spurious "warm drifts" is unfalsifiable.
//  6. Any difference found is quantified — differing-pixel count and max
//     channel delta — because 3 antialiased pixels and a wholesale re-raster
//     are different verdicts for the daemon plan.
//  7. GPU status is read from the browser (SystemInfo.getInfo) and printed. If
//     headless fell back to CPU raster, the shader cache the `css` page is
//     meant to exercise was never in play, and "css identical" would prove
//     nothing about it. The reader must be able to see which happened.
//  8. Render-richness floors. A page that rendered BLANK would be identical in
//     every arm — the purest form of the pass-outcome-equals-did-not-run bug.
//     Each page must clear a distinct-colour and non-white-coverage floor
//     before its results are allowed to count.
//
// Reads appboxd/lib/cdp.dart; never writes it.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:appboxd/cdp.dart';
import 'package:image/image.dart' as img;

// ── knobs ─────────────────────────────────────────────────────────────────
const int kN = 5; // samples per page per arm
const int kW = 1280;
const int kH = 800;
const int kSettleMs = 1500; // identical in EVERY arm — an asymmetric settle
// would manufacture the exact drift under test.

/// Everything from here down in the report belongs to `warm_depth_probe.dart`.
/// Both probes write one document, so each must preserve the other's half.
const String kDepthMarker = '<!-- depth-probe-section -->';

const kPages = <String, String>{
  'text': '/text', // font-shaping cache
  'css': '/css', // GPU raster + shader cache
  'static': '/static', // control: flat colour, must never move
};

/// Minimum distinct colours and non-white coverage each page must produce.
/// A blank page is identical in every arm, so these floors are what stop the
/// probe from "passing" on nothing at all. Set well below what the pages
/// actually render, so they catch a blank/failed render, not normal variation.
const kRichnessFloor = <String, (int, double)>{
  'text': (40, 3.0), // antialiased glyphs on white
  'css': (5000, 90.0), // gradients everywhere
  'static': (8, 50.0), // flat blocks, few colours by design
};

// ── one capture ───────────────────────────────────────────────────────────
class Shot {
  final String page;
  final String arm;
  final Uint8List? bytes;
  final String? error;
  final int ms;
  Shot.ok(this.page, this.arm, this.bytes, this.ms) : error = null;
  Shot.err(this.page, this.arm, this.error, this.ms) : bytes = null;
  bool get isOk => error == null;
}

/// The capture sequence. IDENTICAL in every arm — same calls, same order, same
/// settle — so the only variable is which browser/tab it runs on.
Future<Shot> capture(
  CdpSession tab,
  String page,
  String arm,
  String url, {
  int width = kW,
  int height = kH,
}) async {
  final sw = Stopwatch()..start();
  try {
    await tab.navigateAndSettle('about:blank', settleMs: 100);
    await tab.setViewport(width, height);
    await tab.navigateAndSettle(url, settleMs: kSettleMs);
    final bytes = Uint8List.fromList(await tab.screenshot());
    sw.stop();
    if (bytes.isEmpty) {
      return Shot.err(page, arm, 'screenshot returned 0 bytes', sw.elapsedMilliseconds);
    }
    return Shot.ok(page, arm, bytes, sw.elapsedMilliseconds);
  } on TimeoutException catch (e) {
    sw.stop();
    return Shot.err(page, arm, 'timeout: $e', sw.elapsedMilliseconds);
  } catch (e) {
    sw.stop();
    return Shot.err(page, arm, '$e', sw.elapsedMilliseconds);
  }
}

// ── hashing ───────────────────────────────────────────────────────────────
// FNV-1a 64. package:crypto is not a dependency of appboxd; this is the
// "simple deterministic hash you write" fallback. Hashes are LABELS only —
// every distinct-count below is computed by exact byte equality, so the
// reported counts carry no collision risk whatsoever.
int fnv1a64(List<int> data) {
  var h = 0xcbf29ce484222325;
  for (final b in data) {
    h ^= b;
    h *= 0x100000001b3;
  }
  return h;
}

String hex64(int h) =>
    ((h >> 32) & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0') +
    (h & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');

String shortHash(List<int> data) => hex64(fnv1a64(data)).substring(0, 12);

/// Decoded RGBA of a PNG, or null if it will not decode.
Uint8List? rgba(Uint8List png) {
  final im = img.decodePng(png);
  if (im == null) return null;
  return im.getBytes(order: img.ChannelOrder.rgba);
}

bool sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Exact-equality bucketing. Returns the number of distinct byte sequences.
int distinctCount(List<Uint8List> samples) {
  final reps = <Uint8List>[];
  for (final s in samples) {
    if (!reps.any((r) => sameBytes(r, s))) reps.add(s);
  }
  return reps.length;
}

/// (distinct colours, percent non-white) for one capture — the evidence that a
/// page rendered something rather than nothing.
(int, double) richness(Uint8List png) {
  final b = rgba(png);
  if (b == null) return (0, 0);
  final colours = <int>{};
  var nonWhite = 0;
  for (var i = 0; i < b.length; i += 4) {
    colours.add((b[i] << 16) | (b[i + 1] << 8) | b[i + 2]);
    if (!(b[i] > 250 && b[i + 1] > 250 && b[i + 2] > 250)) nonWhite++;
  }
  return (colours.length, nonWhite * 100.0 / (b.length ~/ 4));
}

/// How far apart two PNGs actually are, in pixels — the detail that decides
/// whether a drift is salvageable with a tolerance or kills the plan.
String pixelDelta(Uint8List a, Uint8List b) {
  final ra = rgba(a), rb = rgba(b);
  if (ra == null || rb == null) return 'UNDECODABLE';
  if (ra.length != rb.length) return 'DIMENSIONS DIFFER (${ra.length} vs ${rb.length} bytes)';
  var diffPx = 0, maxDelta = 0;
  for (var i = 0; i < ra.length; i += 4) {
    var d = 0;
    for (var c = 0; c < 4; c++) {
      final delta = (ra[i + c] - rb[i + c]).abs();
      if (delta > d) d = delta;
    }
    if (d > 0) {
      diffPx++;
      if (d > maxDelta) maxDelta = d;
    }
  }
  final total = ra.length ~/ 4;
  final pct = (diffPx * 100.0 / total).toStringAsFixed(4);
  return '$diffPx/$total px differ ($pct%), max channel delta $maxDelta';
}

// ── the deterministic test pages ──────────────────────────────────────────
// Rules: no animation, no Math.random, no Date, no remote resource, no
// @font-face. System/web-safe families only. The page must render the same
// thing every single time — warm vs cold is the ONLY variable under test.

const _reset = '''
*{margin:0;padding:0;box-sizing:border-box;
  animation:none!important;transition:none!important}
html,body{width:100%;height:100%;overflow:hidden;background:#ffffff}
''';

// Fixed lorem — no generator, no randomness.
const _lorem =
    'Quantum ledger frameworks reconcile divergent state across nine shards '
    'while the arbiter holds quorum. Typography hinting varies by weight, by '
    'size, and by the family the shaper resolves. Kerning pairs AV, To, Wa, '
    'LT, and Yo exercise the pair table. Ligatures fi fl ffi ffl st ct.';

String _textPage() {
  final families = [
    'Helvetica, Arial, sans-serif',
    'Georgia, "Times New Roman", serif',
    '"Courier New", Courier, monospace',
    'Verdana, Geneva, sans-serif',
    '"Trebuchet MS", Tahoma, sans-serif',
    'Palatino, "Palatino Linotype", serif',
  ];
  final sizes = [9, 11, 13, 16, 19, 23, 28, 34, 41, 52];
  final weights = [100, 300, 400, 500, 700, 900];
  final buf = StringBuffer();
  for (var i = 0; i < families.length; i++) {
    for (var j = 0; j < sizes.length; j++) {
      final fam = families[i];
      final size = sizes[j];
      final weight = weights[(i + j) % weights.length];
      final ls = ((i + j) % 5) - 2; // -2..2 px letter-spacing
      buf.writeln('<p style="font-family:$fam;font-size:${size}px;'
          'font-weight:$weight;letter-spacing:${ls}px;color:#1a1a1a;'
          'line-height:1.15">${_lorem.substring(0, 60 + (i * 10 + j) % 180)}</p>');
    }
  }
  return '''<!doctype html><html><head><meta charset="utf-8">
<title>text</title><style>$_reset
body{padding:8px;overflow:hidden}</style></head>
<body>$buf</body></html>''';
}

String _cssPage() {
  final buf = StringBuffer();
  for (var i = 0; i < 24; i++) {
    final hue = (i * 37) % 360;
    final rot = (i * 7) % 45;
    final blur = 2 + (i % 6) * 3;
    final radius = 4 + (i % 9) * 6;
    buf.writeln('''
<div style="position:relative;width:180px;height:150px;
  border-radius:${radius}px;
  background:linear-gradient(${(i * 15) % 360}deg,
    hsl($hue,80%,62%), hsl(${(hue + 90) % 360},70%,42%));
  box-shadow:0 ${4 + i % 8}px ${12 + i % 20}px rgba(0,0,0,.42),
             inset 0 1px 0 rgba(255,255,255,.5);
  transform:rotate(${rot - 22}deg) scale(${0.86 + (i % 7) * 0.03});
  filter:saturate(${100 + (i % 5) * 22}%);">
  <div style="position:absolute;inset:18px;border-radius:${radius}px;
    background:radial-gradient(circle at 32% 28%,
      rgba(255,255,255,.92), rgba(255,255,255,0) 68%);
    backdrop-filter:blur(${blur}px);mix-blend-mode:screen"></div>
  <div style="position:absolute;left:12px;bottom:10px;width:64px;height:22px;
    background:conic-gradient(from ${(i * 23) % 360}deg,
      #ff5f6d,#ffc371,#2ec4b6,#ff5f6d);
    border-radius:11px;filter:blur(${(i % 3)}px);opacity:.86"></div>
</div>''');
  }
  return '''<!doctype html><html><head><meta charset="utf-8">
<title>css</title><style>$_reset
body{padding:10px;display:flex;flex-wrap:wrap;gap:14px;
  background:linear-gradient(160deg,#101828,#334155)}</style></head>
<body>$buf</body></html>''';
}

String _staticPage() {
  final buf = StringBuffer();
  const flats = [
    '#e11d48', '#f59e0b', '#10b981', '#3b82f6', '#8b5cf6', '#0f172a',
    '#64748b', '#facc15', '#14b8a6', '#ef4444', '#22c55e', '#6366f1',
  ];
  for (var i = 0; i < 48; i++) {
    buf.writeln('<div style="width:150px;height:120px;'
        'background:${flats[i % flats.length]}"></div>');
  }
  return '''<!doctype html><html><head><meta charset="utf-8">
<title>static</title><style>$_reset
body{display:flex;flex-wrap:wrap;background:#ffffff}</style></head>
<body>$buf</body></html>''';
}

/// The FINE negative control: identical in every respect except one 14px word
/// whose colour differs by ONE step in the blue channel.
String _finePage(String colour) {
  return '''<!doctype html><html><head><meta charset="utf-8">
<title>fine</title><style>$_reset
body{padding:40px;font-family:Helvetica,Arial,sans-serif;background:#ffffff}
</style></head>
<body>
<p style="font-size:14px;color:#202020">baseline paragraph of ordinary text
that is identical in both variants of this control page.</p>
<p style="font-size:14px"><span style="color:$colour">delta</span></p>
<p style="font-size:14px;color:#202020">trailing paragraph, also identical.</p>
</body></html>''';
}

// ── in-process static server (no network) ─────────────────────────────────
Future<HttpServer> serve() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    String body;
    switch (req.uri.path) {
      case '/text':
        body = _textPage();
      case '/css':
        body = _cssPage();
      case '/static':
        body = _staticPage();
      case '/fine':
        body = _finePage(req.uri.queryParameters['c'] ?? '#202020');
      default:
        req.response.statusCode = 404;
        await req.response.close();
        return;
    }
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.html
      // No caching anywhere: the browser must re-fetch and re-render, so a
      // warm arm can never "match" merely by replaying a cached response.
      ..headers.set('cache-control', 'no-store, no-cache, must-revalidate')
      ..write(body);
    await req.response.close();
  });
  return server;
}

// ── arms ──────────────────────────────────────────────────────────────────
final _out = StringBuffer();
void say(String line) {
  stdout.writeln(line);
  _out.writeln(line);
}

/// COLD: a fresh CdpClient.launch() per capture, fully disposed between.
Future<List<Shot>> coldArm(String base, String arm) async {
  final shots = <Shot>[];
  for (var round = 0; round < kN; round++) {
    for (final entry in kPages.entries) {
      stderr.writeln('  [$arm] round ${round + 1}/$kN ${entry.key}');
      CdpClient? client;
      try {
        client = await CdpClient.launch();
        final tab = await client.newTab();
        await tab.enable();
        shots.add(await capture(tab, entry.key, arm, '$base${entry.value}'));
      } catch (e) {
        shots.add(Shot.err(entry.key, arm, 'launch/attach failed: $e', 0));
      } finally {
        try {
          await client?.close();
        } catch (_) {}
      }
    }
  }
  return shots;
}

/// WARM-SAME-TAB: one launch, one tab, pages INTERLEAVED across rounds.
Future<List<Shot>> warmSameTabArm(String base) async {
  const arm = 'WARM-SAME-TAB';
  final shots = <Shot>[];
  final client = await CdpClient.launch();
  try {
    final tab = await client.newTab();
    await tab.enable();
    for (var round = 0; round < kN; round++) {
      for (final entry in kPages.entries) {
        stderr.writeln('  [$arm] round ${round + 1}/$kN ${entry.key}');
        shots.add(await capture(tab, entry.key, arm, '$base${entry.value}'));
      }
    }
  } finally {
    await client.close();
  }
  return shots;
}

/// WARM-NEW-TAB: one launch + one --user-data-dir, a fresh tab per capture
/// (closed after). Pages interleaved, same as above.
Future<List<Shot>> warmNewTabArm(String base) async {
  const arm = 'WARM-NEW-TAB';
  final shots = <Shot>[];
  final client = await CdpClient.launch();
  try {
    for (var round = 0; round < kN; round++) {
      for (final entry in kPages.entries) {
        stderr.writeln('  [$arm] round ${round + 1}/$kN ${entry.key}');
        try {
          final tab = await client.newTab();
          await tab.enable();
          shots.add(await capture(tab, entry.key, arm, '$base${entry.value}'));
          await client.send('Target.closeTarget', {'targetId': tab.targetId});
          // Prove the browser survived the tab close, so a dead browser
          // reports ERROR instead of quietly shortening the arm.
          await client.send('Browser.getVersion');
        } catch (e) {
          shots.add(Shot.err(entry.key, arm, 'tab cycle failed: $e', 0));
        }
      }
    }
  } finally {
    await client.close();
  }
  return shots;
}

// ── reporting ─────────────────────────────────────────────────────────────
class ArmResult {
  final String arm;
  final String page;
  final int ok;
  final int total;
  final int distinctBytes;
  final int distinctPixels;
  final String byteHash;
  final String pixelHash;
  final int avgMs;
  final List<String> errors;
  final Uint8List? rep; // first good sample — the cross-arm comparison subject
  ArmResult(this.arm, this.page, this.ok, this.total, this.distinctBytes,
      this.distinctPixels, this.byteHash, this.pixelHash, this.avgMs,
      this.errors, this.rep);
  bool get healthy => errors.isEmpty && ok == total;
}

ArmResult summarise(String arm, String page, List<Shot> all) {
  final mine = all.where((s) => s.page == page && s.arm == arm).toList();
  final good = mine.where((s) => s.isOk).toList();
  final errs = mine.where((s) => !s.isOk).map((s) => s.error!).toList();
  if (good.isEmpty) {
    return ArmResult(arm, page, 0, mine.length, 0, 0, '-', '-', 0,
        errs.isEmpty ? ['no samples captured'] : errs, null);
  }
  final pngs = good.map((s) => s.bytes!).toList();
  final rgbas = <Uint8List>[];
  for (final p in pngs) {
    final r = rgba(p);
    if (r == null) {
      errs.add('PNG failed to decode');
    } else {
      rgbas.add(r);
    }
  }
  final avg = good.map((s) => s.ms).reduce((a, b) => a + b) ~/ good.length;
  return ArmResult(
    arm,
    page,
    good.length,
    mine.length,
    distinctCount(pngs),
    rgbas.isEmpty ? 0 : distinctCount(rgbas),
    shortHash(pngs.first),
    rgbas.isEmpty ? '-' : shortHash(rgbas.first),
    avg,
    errs,
    pngs.first,
  );
}

String pad(String s, int n) => s.length >= n ? s : s + ' ' * (n - s.length);

/// Which commit, and which exact bytes of cdp.dart, this measurement ran
/// against. `appboxd/lib/cdp.dart` is under active edit by other work, and the
/// capture path (`navigateAndSettle` / `setViewport` / `screenshot`) lives in
/// it — so "measured against some version" has to become "measured against
/// these bytes" or the result cannot be re-checked later. Read at probe start.
String provenance() {
  String sh(String exe, List<String> args) {
    try {
      final r = Process.runSync(exe, args);
      return r.exitCode == 0 ? (r.stdout as String).trim() : 'unavailable';
    } catch (_) {
      return 'unavailable';
    }
  }

  final head = sh('git', ['rev-parse', '--short', 'HEAD']);
  final dirty = sh('git', ['status', '--porcelain', '--', 'lib/cdp.dart']);
  final digest = sh('shasum', ['-a', '256', 'lib/cdp.dart']).split(' ').first;
  final cdpState = dirty.isEmpty ? 'clean at HEAD' : 'MODIFIED vs HEAD';
  return 'HEAD $head | lib/cdp.dart $cdpState, sha256 '
      '${digest.length >= 16 ? digest.substring(0, 16) : digest}';
}

/// docs/research/warm-vs-cold-chrome-determinism.md, wherever the probe is run
/// from — the repo root is the nearest ancestor holding both `docs/` and
/// `appboxd/`, so a wrong cwd cannot silently scatter the report.
File reportFile() {
  var dir = Directory.current.absolute;
  for (var i = 0; i < 6; i++) {
    if (Directory('${dir.path}/docs').existsSync() &&
        Directory('${dir.path}/appboxd').existsSync()) {
      return File('${dir.path}/docs/research/warm-vs-cold-chrome-determinism.md');
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  throw StateError('repo root (a dir holding both docs/ and appboxd/) not found '
      'above ${Directory.current.path}');
}

// ── main ──────────────────────────────────────────────────────────────────
Future<void> main() async {
  exit(await run());
}

Future<int> run() async {
  final server = await serve();
  final base = 'http://127.0.0.1:${server.port}';
  final prov = provenance();
  say('# warm vs cold Chrome determinism probe');
  say('');
  say('Source:   $prov');

  // Chrome version + GPU status, straight from the browser that will measure.
  String chromeVersion = 'unknown';
  String gpuLine = 'unknown';
  try {
    final probe = await CdpClient.launch();
    final v = await probe.send('Browser.getVersion');
    chromeVersion = '${v['result']['product']} '
        '(protocol ${v['result']['protocolVersion']}, ${v['result']['jsVersion']})';
    // Whether the css arm's shader/raster caches were actually in play at all.
    try {
      final info = await probe.send('SystemInfo.getInfo');
      final gpu = info['result']['gpu'] as Map<String, dynamic>;
      final dev = (gpu['devices'] as List)
          .map((d) => (d as Map)['deviceString'] ?? '?')
          .join(', ');
      final fs = (gpu['featureStatus'] as Map?) ?? const {};
      final flags = ['gpu_compositing', 'rasterization', 'webgl', 'opengl']
          .where(fs.containsKey)
          .map((k) => '$k=${fs[k]}')
          .join(' ');
      gpuLine = '$dev | $flags';
    } catch (e) {
      gpuLine = 'SystemInfo.getInfo unavailable: $e';
    }
    await probe.close();
  } catch (e) {
    stderr.writeln('Chrome unavailable: $e');
    say('ABORT — Chrome could not be launched: $e');
    await server.close(force: true);
    return 4;
  }
  say('Chrome:   $chromeVersion');
  say('GPU:      $gpuLine');
  say('Viewport: ${kW}x$kH @ dsf 1, headless=new, settle ${kSettleMs}ms');
  say('N:        $kN samples per page per arm');
  say('Pages:    text (font-shaping) / css (GPU raster+shader) / static (flat control)');
  say('');

  // ── NEGATIVE CONTROLS FIRST ────────────────────────────────────────────
  // If these do not show a difference, the capture+hash path cannot see one,
  // and every "identical" printed below would be worthless. Abort on failure.
  say('== NEGATIVE CONTROLS (instrument sensitivity) ==');
  var controlsOk = true;
  {
    final client = await CdpClient.launch();
    try {
      final tab = await client.newTab();
      await tab.enable();

      // coarse: same page, 1280 vs 1281 px wide.
      final c1 = await capture(tab, 'static', 'NC-coarse', '$base/static', width: kW);
      final c2 = await capture(tab, 'static', 'NC-coarse', '$base/static', width: kW + 1);
      if (!c1.isOk || !c2.isOk) {
        say('NC-coarse  ERROR — ${c1.error ?? c2.error}');
        controlsOk = false;
      } else {
        final differ = !sameBytes(c1.bytes!, c2.bytes!);
        say('NC-coarse  static @${kW}px vs @${kW + 1}px  '
            '${shortHash(c1.bytes!)} vs ${shortHash(c2.bytes!)}  '
            '=> ${differ ? "DIFFER (expected) PASS" : "SAME — INSTRUMENT BROKEN"}');
        if (!differ) controlsOk = false;
      }

      // fine: one 14px word, ONE RGB step apart, identical viewport.
      final f1 = await capture(tab, 'fine', 'NC-fine', '$base/fine?c=%23202020');
      final f2 = await capture(tab, 'fine', 'NC-fine', '$base/fine?c=%23202021');
      if (!f1.isOk || !f2.isOk) {
        say('NC-fine    ERROR — ${f1.error ?? f2.error}');
        controlsOk = false;
      } else {
        final differ = !sameBytes(f1.bytes!, f2.bytes!);
        say('NC-fine    one 14px word #202020 vs #202021  '
            '${shortHash(f1.bytes!)} vs ${shortHash(f2.bytes!)}  '
            '=> ${differ ? "DIFFER (expected) PASS" : "SAME — INSTRUMENT BROKEN"}');
        say('           magnitude: ${pixelDelta(f1.bytes!, f2.bytes!)}');
        if (!differ) controlsOk = false;
      }

      // Render richness. A blank page matches itself in every arm — the
      // purest pass-outcome-equals-did-not-run failure. Each page must clear
      // a floor before its "identical" is allowed to mean anything.
      say('');
      say('== RENDER RICHNESS (did the pages draw anything?) ==');
      for (final entry in kPages.entries) {
        final floor = kRichnessFloor[entry.key]!;
        final s = await capture(tab, entry.key, 'RICHNESS', '$base${entry.value}');
        if (!s.isOk) {
          say('${pad(entry.key, 8)}ERROR — ${s.error}');
          controlsOk = false;
          continue;
        }
        final (colours, nonWhite) = richness(s.bytes!);
        final pass = colours >= floor.$1 && nonWhite >= floor.$2;
        say('${pad(entry.key, 8)}$colours distinct colours, '
            '${nonWhite.toStringAsFixed(1)}% non-white, '
            '${s.bytes!.length} PNG bytes  (floor: ${floor.$1} colours, '
            '${floor.$2}% non-white)  => ${pass ? "PASS" : "FAIL — BLANK/TRIVIAL RENDER"}');
        if (!pass) controlsOk = false;
      }
    } finally {
      await client.close();
    }
  }
  say('');
  say('CONTROL VERDICT: ${controlsOk ? "PASS — the instrument can see a "
      "difference, and the pages draw something to see it in" : "FAIL"}');
  say('');
  if (!controlsOk) {
    say('ABORTING. With a blind instrument every "identical" below would be');
    say('the did-not-run outcome wearing the pass outcome\'s clothes.');
    await server.close(force: true);
    final aborted = reportFile();
    await aborted.parent.create(recursive: true);
    // Carry the depth section here too. Without it, an abort on this path would
    // overwrite the whole document with a stub and destroy warm_depth_probe's
    // measurement — which costs 25 minutes to produce and, since this file is
    // untracked, has no git copy to recover from. A failure in THIS probe must
    // never delete a different probe's result.
    var keep = '';
    if (aborted.existsSync()) {
      final existing = await aborted.readAsString();
      final at = existing.indexOf(kDepthMarker);
      if (at >= 0) keep = '\n${existing.substring(at)}';
    }
    await aborted.writeAsString('# Warm vs cold Chrome determinism\n\n'
        '## VERDICT\n\nINVALID — the negative controls failed, so the '
        'instrument could not see a difference it was designed to see. '
        'Nothing about warm vs cold was measured. (Any "Depth" section below '
        'is a SEPARATE measurement by warm_depth_probe.dart and is '
        'unaffected by this failure.)\n\n```\n'
        '${_out.toString().trimRight()}\n```\n$keep');
    return 3;
  }

  // ── the arms ───────────────────────────────────────────────────────────
  final shots = <Shot>[];
  stderr.writeln('COLD-A ...');
  shots.addAll(await coldArm(base, 'COLD-A'));
  stderr.writeln('WARM-SAME-TAB ...');
  shots.addAll(await warmSameTabArm(base));
  stderr.writeln('WARM-NEW-TAB ...');
  shots.addAll(await warmNewTabArm(base));
  stderr.writeln('COLD-B ...');
  shots.addAll(await coldArm(base, 'COLD-B'));
  await server.close(force: true);

  const arms = ['COLD-A', 'WARM-SAME-TAB', 'WARM-NEW-TAB', 'COLD-B'];
  final res = <String, ArmResult>{};
  for (final arm in arms) {
    for (final page in kPages.keys) {
      res['$page|$arm'] = summarise(arm, page, shots);
    }
  }

  say('== PER-ARM STABILITY (distinct outputs within one arm) ==');
  say('${pad("page", 8)}${pad("arm", 15)}${pad("n/N", 7)}'
      '${pad("distinct-bytes", 16)}${pad("distinct-px", 13)}'
      '${pad("hash", 14)}${pad("ms/shot", 9)}status');
  for (final page in kPages.keys) {
    for (final arm in arms) {
      final r = res['$page|$arm']!;
      final status = r.errors.isNotEmpty
          ? 'ERROR: ${r.errors.first}'
          : (r.ok < r.total ? 'ERROR short arm' : 'ok');
      say('${pad(page, 8)}${pad(arm, 15)}${pad("${r.ok}/${r.total}", 7)}'
          '${pad("${r.distinctBytes}", 16)}${pad("${r.distinctPixels}", 13)}'
          '${pad(r.byteHash, 14)}${pad("${r.avgMs}", 9)}$status');
    }
  }
  say('');

  // ── machine determinism: COLD-A vs COLD-B ──────────────────────────────
  // Without this, "warm drifts" and "everything drifts" are indistinguishable.
  say('== MACHINE DETERMINISM CHECK (COLD-A vs COLD-B) ==');
  var machineStable = true;
  for (final page in kPages.keys) {
    final a = res['$page|COLD-A']!, b = res['$page|COLD-B']!;
    if (!a.healthy || !b.healthy || a.rep == null || b.rep == null) {
      say('${pad(page, 8)}ERROR — an arm did not produce clean samples');
      machineStable = false;
      continue;
    }
    final same = sameBytes(a.rep!, b.rep!);
    say('${pad(page, 8)}${same ? "IDENTICAL" : "DIFFERS — ${pixelDelta(a.rep!, b.rep!)}"}');
    if (!same) machineStable = false;
  }
  say('MACHINE BASELINE: ${machineStable ? "STABLE — cold is reproducible across "
      "two independent passes, so a warm difference would be attributable to warmth" : "UNSTABLE — two cold passes disagree; NO warm-vs-cold verdict is meaningful"}');
  say('');

  // ── the actual question ────────────────────────────────────────────────
  say('== WARM == COLD ? (the question) ==');
  var warmEqualsCold = true;
  final drifts = <String>[];
  for (final page in kPages.keys) {
    final cold = res['$page|COLD-A']!;
    for (final arm in ['WARM-SAME-TAB', 'WARM-NEW-TAB']) {
      final warm = res['$page|$arm']!;
      if (!cold.healthy || !warm.healthy || cold.rep == null || warm.rep == null) {
        say('${pad(page, 8)}${pad(arm, 15)}ERROR — '
            'cold ${cold.ok}/${cold.total}, warm ${warm.ok}/${warm.total}');
        warmEqualsCold = false;
        drifts.add('$page/$arm: ERROR, not measured');
        continue;
      }
      final same = sameBytes(cold.rep!, warm.rep!);
      if (same) {
        say('${pad(page, 8)}${pad(arm, 15)}IDENTICAL to COLD-A');
      } else {
        final delta = pixelDelta(cold.rep!, warm.rep!);
        say('${pad(page, 8)}${pad(arm, 15)}DIFFERS — $delta');
        say('${pad("", 23)}distinct-in-warm-arm=${warm.distinctBytes}/${warm.ok}');
        warmEqualsCold = false;
        drifts.add('$page/$arm: $delta '
            '(warm arm itself held ${warm.distinctBytes} distinct outputs)');
      }
    }
  }
  say('');

  // ── verdict ────────────────────────────────────────────────────────────
  final allHealthy = res.values.every((r) => r.healthy);
  String verdict;
  if (!allHealthy) {
    verdict = 'INVALID — at least one arm errored or came up short; '
        'no determinism claim is supported by this run.';
  } else if (!machineStable) {
    verdict = 'INVALID — two independent COLD passes disagree, so this machine '
        'is not reproducible even without reuse. Warm-vs-cold cannot be '
        'isolated here.';
  } else if (warmEqualsCold) {
    final warmSecs = res.values
            .where((r) => r.arm.startsWith('WARM'))
            .map((r) => r.avgMs * r.ok)
            .fold(0, (a, b) => a + b) ~/
        (2 * 1000); // two warm arms
    verdict = 'YES, CONDITIONALLY — a warm Chrome is safe to reuse for pixel '
        'comparison, on the conditions actually held fixed by this run: the '
        'same Chrome build ($chromeVersion), the same viewport (${kW}x$kH @ '
        'dsf 1, headless=new), the same fixed ${kSettleMs}ms settle in every '
        'capture, and a warm window only as deep as THIS probe drove it — '
        '${kN * kPages.length} captures over ~${warmSecs}s per warm arm. Those '
        'four were controlled, not proven invariant. Pin the build, viewport '
        'and settle, and re-run this probe on a Chrome upgrade.\n\n'
        'The depth condition is NOT limited to the ${kN * kPages.length} '
        'captures above: it was measured separately and much deeper by '
        '`warm_depth_probe.dart`. See the "Depth" section further down this '
        'document for the depth actually verified, the drift-onset result, the '
        'memory curve and the recycle policy — that section, not this '
        'paragraph, is the authority on how long one warm Chrome may be reused.';
  } else {
    verdict = 'NO — warm output drifts from cold. Drift detail:\n  - '
        '${drifts.join("\n  - ")}';
  }
  say('== VERDICT ==');
  say(verdict);
  say('');
  say('Reproduce: cd appboxd && dart run tool/warm_vs_cold_probe.dart');

  // ── durable report ─────────────────────────────────────────────────────
  final doc = reportFile();
  await doc.parent.create(recursive: true);
  // warm_depth_probe.dart owns everything below kDepthMarker in this same
  // document (one file holds the whole warm-Chrome answer). Preserve it, or a
  // re-run here would silently delete a 25-minute measurement.
  var carried = '';
  if (doc.existsSync()) {
    final existing = await doc.readAsString();
    final at = existing.indexOf(kDepthMarker);
    if (at >= 0) carried = '\n${existing.substring(at)}';
  }
  await doc.writeAsString('''
# Warm vs cold Chrome determinism

Does a REUSED (warm) Chrome render a page byte-identically to a
FRESHLY-LAUNCHED (cold) one? This gates the `appbox lens` daemon plan, which
would hold one warm Chrome to save the ~1.4s per-invocation launch. `lens`
exists to compare pixels, so a speed win that changes pixels is worthless.
No official Chromium / CDP / Puppeteer / Playwright source documents this
either way, so it is measured here rather than looked up.

## VERDICT

$verdict

## How to reproduce

```
cd appboxd && dart run tool/warm_vs_cold_probe.dart
```

Probe source: `appboxd/tool/warm_vs_cold_probe.dart` (self-contained; serves
its own pages from an in-process `HttpServer` on 127.0.0.1 — no network).

## Setup

- Source under measurement: `$prov`
  (`lib/cdp.dart` holds the capture path — `navigateAndSettle`, `setViewport`,
  `screenshot` — and is under concurrent edit by other work, so its content
  hash is recorded rather than assumed.)
- Chrome: `$chromeVersion`
- GPU: `$gpuLine`
- Viewport: ${kW}x$kH, deviceScaleFactor 1, `--headless=new`
- Settle: ${kSettleMs}ms, identical in every arm
- N: $kN samples per page per arm
- Machine state: no other Chrome work was running. For the deep run in the
  "Depth" section the team lead deliberately held off launching any captures,
  so both measurements were taken on an otherwise-quiet machine. This matters:
  CPU and GPU contention from a second browser is exactly the kind of thing that
  could manufacture a spurious "drift", and a determinism claim measured under
  unknown contention would be much weaker than one measured under known-quiet
  conditions.
- Page kinds:
  - `text` — 60 blocks across 6 web-safe families x 10 sizes x 6 weights,
    varying letter-spacing (exercises the font-shaping cache)
  - `css` — 24 tiles of linear/radial/conic gradients, box-shadow, blur,
    backdrop-filter, mix-blend-mode, rotate/scale transforms (GPU raster +
    shader cache)
  - `static` — 48 flat colour blocks, no text, no effects (control: must be
    identical in every arm)
- Arms: COLD-A (fresh launch + full dispose per capture), WARM-SAME-TAB (one
  launch, one tab), WARM-NEW-TAB (one launch, fresh tab per capture, same
  `--user-data-dir`), COLD-B (a second independent cold pass).
- Warm arms interleave the three pages across rounds rather than reloading one
  page, so every capture is a real cross-page navigation that forces a fresh
  layout + paint — and so the caches under test are genuinely exercised.

## Negative control

Two controls run through the exact capture path used by every measurement:

- **coarse** — the same page at ${kW}px vs ${kW + 1}px wide; hashes must differ.
- **fine** — one 14px word recoloured by ONE step in the blue channel
  (`#202020` -> `#202021`) at an identical viewport; hashes must differ.

The fine control is the load-bearing one. Cache-driven drift, if it exists,
looks like a handful of antialiased glyph edges; an instrument that cannot see
a one-step recolour cannot see that either, and would report "identical" for
every arm regardless of the truth. A control failure aborts the run rather than
printing results.

Both controls are printed before any real result, in the raw output below.

## Render-richness gate

A page that rendered BLANK would be identical in every arm — the purest form of
a check whose pass outcome is also its did-not-run outcome. So each page must
clear a distinct-colour and non-white-coverage floor before its results are
allowed to count, and the measured richness is printed. The `GPU` line above
serves the same purpose for the `css` page: if headless had fallen back to CPU
raster, the shader cache that page exists to exercise would never have been in
play, and "css identical" would prove nothing about it.

## Results

```
${_out.toString().trimRight()}
```

## Operational hazards for a warm-Chrome daemon

Found the hard way while running these probes, not derived from theory. All
three bite a daemon specifically, because a daemon holds ONE browser for hours.

**1. The `appbox-cdp-` profile prefix is shared by every launch.**
`CdpClient.launch()` creates its profile with
`Directory.systemTemp.createTemp('appbox-cdp-')`, so every Chrome any code in
this repo starts carries that prefix. A `pkill -f "appbox-cdp-"` therefore kills
*every* such Chrome on the machine at once — a daemon's long-lived browser
included, and any colleague's capture along with it. This was done for real
during this work while reaping a killed probe's orphans, and it could have taken
out another worker's session.

**2. The correct reap is an ownership check, not a prefix match.**
`cdp.dart`'s `_pidsOwningProfile(dir, browserOnly: true)` matches on the exact
`--user-data-dir=<dir>` and guards the boundary explicitly — its comment reads
"Whole dir, not a prefix: `appbox-cdp-AB` must not claim `…-ABC`'s pid", so
someone has already been bitten by this class of bug. A daemon reaping orphans
at startup must ask *who owns this specific dir* and kill only those pids; a
profile dir with no owning pid is a genuine orphan and its directory can be
deleted on its own. `CdpClient` exposes `userDataDir` and `chromePid` for
exactly this purpose.

**3. A SIGKILLed run can never clean up after itself, so something else must.**
`close()` is what awaits profile release and deletes the dir; a hard kill skips
it entirely, leaving both a live browser and its profile behind. Orphan reaping
on daemon startup is therefore not optional — and it must be the scoped kind
from point 2, or the daemon's own cleanup becomes the thing that kills its
neighbours.

**4. Nothing tells a daemon its browser died.**
CDP has no event for full browser death — `Target.targetCrashed` covers
renderers only. The sole liveness signal is the transport: a closed WebSocket,
or a `Browser.getVersion` round-trip that throws. A daemon must treat socket
closure as browser death and relaunch, rather than assuming a browser it has not
heard from is still there. This probe uses exactly that round-trip as its
liveness check for the same reason.

## Notes and limits

- Distinct counts are computed by exact byte equality over the samples, not by
  hash bucketing, so they carry no collision risk. The printed hashes
  (FNV-1a 64, first 12 hex chars) are labels only; `package:crypto` is not an
  `appboxd` dependency.
- Both PNG-byte and decoded-RGBA distinct counts are reported. PNG encoding
  could in principle vary while pixels do not; the pixel column is what makes a
  "differs" result falsifiable.
- Sample counts are printed as `n/N` on every row, so a short arm cannot pass
  by trivially matching itself. Any throw, timeout, or zero-byte screenshot
  records an ERROR sample and marks the arm unhealthy.
- COLD-B exists to separate "warm drifts" from "this machine drifts". If the
  two cold passes ever disagree, no warm-vs-cold conclusion is available at all.
- The guards are checkable rather than decorative. To confirm the richness gate
  still bites, raise a floor in `kRichnessFloor` past what the page can render
  (e.g. `'static': (999999, 50.0)`) and re-run: the probe must print
  `FAIL — BLANK/TRIVIAL RENDER`, abort before any arm, and exit 3. This was run
  during development and behaved exactly so. The negative controls are checkable
  the same way — make the fine control's two colours equal and the run must
  abort.
- Every capture navigates to `about:blank` first, so the previous document is
  discarded. That is deliberate — it keeps the call sequence identical in all
  four arms — but it scopes the finding: this probe measures PROCESS- and
  GPU-level cache reuse (font shaping, raster, shader), not same-document state
  carryover. A daemon that reuses a live document rather than re-navigating is
  not covered by this result.
- Warm-window depth is a condition, not a proven invariant *for this probe*:
  each warm arm here ran only ${kN * kPages.length} captures over roughly half a
  minute. Depth is answered by `warm_depth_probe.dart` in the "Depth" section
  below, which drives one warm browser far deeper and reports drift onset and
  the memory curve. Read that section for the depth actually verified; do not
  read a depth limit out of this one.
- What this probe does NOT cover: other viewports (only ${kW}x$kH), other device
  scale factors (only 1), `--visible` mode, `fullPage` captures, pages that load
  fonts or images over the network, and any Chrome build other than the one
  named above. A daemon reusing a warm browser should pin the viewport and
  settle it was measured at, and this file should be regenerated after a Chrome
  upgrade.
- The newer `cdp.dart` settle helpers (`freezeAnimations`, `settleUntilStable`,
  `settleForCapture`, `navigateAndSettleForCapture`) are deliberately NOT used
  here. This probe uses the plain fixed `navigateAndSettle(settleMs: $kSettleMs)`
  so its runs stay comparable to each other; the variable under test is the
  browser, not the settle. Their absence is a choice, not an oversight.
$carried''');
  say('Report: ${doc.path}');
  return allHealthy && machineStable && warmEqualsCold ? 0 : 1;
}
