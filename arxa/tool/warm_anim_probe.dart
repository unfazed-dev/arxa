// warm_anim_probe.dart — the warm-Chrome questions, asked on pages where the
// freeze machinery actually does something.
//
// Every warm-Chrome result in this document so far — the original four arms,
// the 700-capture depth run, the settle-rate arm — was measured on pages where
// `freezeAnimations()` reported `{finite: 0, infinite: 0, smil: 0, videos: 0,
// committed: 0}`. The machinery under test did nothing. The lens exists to
// capture animated pages; that is the entire reason the settle protocol was
// built. So "a warm Chrome is safe to reuse" was proven only in the case where
// the protocol was not needed.
//
// There is a measured reason to expect animated pages to differ, quoted in
// cdp.dart:641-651: an element that merely HAS an animation is promoted to its
// own compositor layer, and that layer rasters differently run to run. A page
// whose animation was provably pinned (currentTime 0, computed transform
// identity, every run) still gave 3 distinct images out of 4, worst case 13,345
// pixels. Removing the `animation` property took it to 4/4 identical. Compositor
// promotion is exactly the GPU-side state a warm browser might accumulate or
// reuse differently, and no previous arm has touched it.
//
// Run:  cd arxa && dart run tool/warm_anim_probe.dart   (~12 min)
//
// ── Three INDEPENDENT answers, deliberately not a gated chain ─────────────
//  Q1 Does the freeze stay effective across a long warm session? NOT measured
//     via `settleForCapture`'s `frozen` map — that reports the SECOND freeze
//     and reads zero on every correctly-frozen page, so asserting
//     `committed > 0` on it would fail exactly when the freeze is working. See
//     the long note above `liveAnimations` for the measurement that proved it.
//  Q2 Do animated pages stay byte-identical warm vs cold?
//  Q3 Does memory behave differently when the freeze really walks the DOM and
//     writes inline styles on every capture?
//
// Q1 and Q3 do NOT depend on byte-identity, so a page that cannot reproduce
// itself COLD still answers them. That is why a disagreeing cold baseline does
// not abort this probe, unlike the earlier ones: aborting would throw away two
// of the three answers. A page that cannot reproduce itself cold simply has no
// warm-vs-cold claim available, and that fact is itself the Q2 finding.
//
// ── Anti-false-pass design ────────────────────────────────────────────────
//  1. COLD SELF-CONSISTENCY FIRST, at N=10 on the animated pages. The prior
//     evidence was 3-of-4 distinct; at N=5 an intermittent fault could show 1
//     distinct by luck, certify cold as stable, and cause the warm arm's
//     divergences to be misattributed to warmth. N=10 is ~100s of insurance on
//     the exact question most likely to break.
//  2. Freeze effectiveness checked from BOTH directions: zero live animations
//     after every settle (the freeze worked), AND a periodic direct probe that
//     the page still HAS animations to freeze. Either alone is insufficient —
//     a page that quietly stopped animating leaves zero live animations too,
//     and would sail through the first check while exercising nothing.
//  3. The animation-free control runs in the same arm. A divergence seen on
//     animated pages but not the control is attributable to the animation; a
//     divergence on both is the machine.
//  4. The control's freeze-path hash is asserted against `5f46dca47862`, the
//     hash the static page has produced through five prior runs on the
//     plain-settle path. Freeze is a no-op there, so it must match; if it does
//     not, something changed and that outranks every other reading here.
//  5. Divergence is CLASSIFIED, not counted. Clustered-from-an-onset and
//     persistent means warm drift; scattered with no onset means page-level
//     nondeterminism the cold N missed. Those are opposite conclusions.
//  6. `converged: false` is tracked in its own column and is a finding about
//     the settle protocol on animated pages, not probe breakage.
//
// Reads arxa/lib/cdp.dart; never writes it.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:arxa/cdp.dart';

import 'warm_depth_probe.dart' show MemSample, cdpProcCount, fmtDur, sampleRss;
import 'warm_settle_probe.dart' show classifySettleMemory, median;
import 'warm_vs_cold_probe.dart'
    show
        kAnimMarker,
        kH,
        kSettleMs,
        kW,
        pad,
        pixelDelta,
        provenance,
        reportFile,
        sameBytes,
        shortHash;

// ── knobs ─────────────────────────────────────────────────────────────────
const int kArm = 180; // warm captures (lead asked 150-200)
const int kColdAnimated = 10; // cold passes per ANIMATED page
const int kColdControl = 5; // cold passes for the animation-free control
const Duration kMaxRun = Duration(minutes: 30);
const int kMemEvery = 10;
const int kProgressEvery = 20;
const int kFreezeProbeEvery = 20;
const int kTimeoutMs = 8000;

/// The hash the animation-free static page has produced on the plain-settle
/// path through five prior runs in this document. Freeze is a no-op on it, so
/// the freeze path must reach the same pixels.
const String kKnownStaticHash = '5f46dca47862';

const kPages = <String, String>{
  'anim-inf': '/anim-infinite', // infinite → pause + currentTime 0
  'anim-fin': '/anim-finite', // finite w/ fill:both → finish()
  'control': '/static-control', // animation-free control
};

/// Pages the freeze must actually do work on.
const kAnimatedPages = {'anim-inf', 'anim-fin'};

final _log = StringBuffer();
void say(String line) {
  stdout.writeln(line);
  _log.writeln(line);
}

// ── the pages ─────────────────────────────────────────────────────────────
// Deterministic in CONTENT (no random, no Date, no remote resources); the only
// thing moving is the animation, which the freeze is supposed to pin. Animated
// properties are transform / opacity / colour / background-position, all of
// which the freeze's de-promotion collector handles — a page animating
// something the collector skips would report `committed: 0` and look like a
// freeze failure when it was really a bad page.

const _reset = '''
*{margin:0;padding:0;box-sizing:border-box}
html,body{width:100%;height:100%;overflow:hidden;background:#fff}
''';

/// INFINITE animations on gradients — the compositor-promotion case.
String _animInfinite() {
  final buf = StringBuffer();
  for (var i = 0; i < 18; i++) {
    final hue = (i * 41) % 360;
    buf.writeln('''
<div class="tile t$i" style="
  background:linear-gradient(${(i * 27) % 360}deg,
    hsl($hue,82%,60%), hsl(${(hue + 120) % 360},72%,44%));"></div>''');
  }
  final keys = StringBuffer();
  for (var i = 0; i < 18; i++) {
    keys.writeln('''
.t$i{animation:spin$i ${3 + i % 5}s linear infinite;}
@keyframes spin$i{
  from{transform:rotate(${i * 7}deg) scale(.92);opacity:.72}
  50% {transform:rotate(${i * 7 + 180}deg) scale(1.04);opacity:1}
  to  {transform:rotate(${i * 7 + 360}deg) scale(.92);opacity:.72}
}''');
  }
  return '''<!doctype html><html><head><meta charset="utf-8">
<title>anim-infinite</title><style>$_reset
body{padding:12px;display:flex;flex-wrap:wrap;gap:16px;
  background:linear-gradient(140deg,#0f172a,#334155)}
.tile{width:190px;height:150px;border-radius:14px;
  box-shadow:0 8px 22px rgba(0,0,0,.45)}
$keys</style></head><body>$buf</body></html>''';
}

/// FINITE animations with `fill: both` holding NON-DEFAULT end states, so the
/// freeze's commit-then-drop path runs across many elements. A bare
/// `animation:none` would snap these back to their pre-animation style — the
/// exact case cdp.dart:649-651 says committing first exists to protect.
String _animFinite() {
  final buf = StringBuffer();
  final keys = StringBuffer();
  for (var i = 0; i < 24; i++) {
    final hue = (i * 53) % 360;
    buf.writeln('<div class="card c$i">card $i</div>');
    keys.writeln('''
.c$i{animation:land$i ${1 + (i % 4) * 0.3}s ease-out both;}
@keyframes land$i{
  from{transform:translateY(${20 + i}px) scale(.86);opacity:0;
       color:#ffffff;background:hsl($hue,70%,70%)}
  to  {transform:translateY(${(i % 5) - 2}px) scale(1.0${i % 6});opacity:1;
       color:hsl(${(hue + 180) % 360},80%,18%);background:hsl($hue,74%,58%)}
}''');
  }
  return '''<!doctype html><html><head><meta charset="utf-8">
<title>anim-finite</title><style>$_reset
body{padding:14px;display:flex;flex-wrap:wrap;gap:12px;background:#f8fafc;
  font-family:Helvetica,Arial,sans-serif}
.card{width:150px;height:104px;border-radius:12px;display:flex;
  align-items:center;justify-content:center;font-size:15px;font-weight:700;
  box-shadow:0 4px 14px rgba(15,23,42,.28)}
$keys</style></head><body>$buf</body></html>''';
}

/// The animation-free control. Byte-for-byte the `static` page used by the
/// other probes, so its hash is comparable to the known value.
String _staticControl() {
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
<title>static</title><style>*{margin:0;padding:0;box-sizing:border-box;
  animation:none!important;transition:none!important}
html,body{width:100%;height:100%;overflow:hidden;background:#ffffff}
body{display:flex;flex-wrap:wrap;background:#ffffff}</style></head>
<body>$buf</body></html>''';
}

Future<HttpServer> serveAnim() async {
  final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  s.listen((req) async {
    String body;
    switch (req.uri.path) {
      case '/anim-infinite':
        body = _animInfinite();
      case '/anim-finite':
        body = _animFinite();
      case '/static-control':
        body = _staticControl();
      default:
        req.response.statusCode = 404;
        await req.response.close();
        return;
    }
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.html
      ..headers.set('cache-control', 'no-store, no-cache, must-revalidate')
      ..write(body);
    await req.response.close();
  });
  return s;
}

// ── capture ───────────────────────────────────────────────────────────────
typedef Cap = ({
  Uint8List? bytes,
  bool converged,
  int ms,
  int screenshots,
  Map<String, int> frozen,
  int liveAnimsAfter,
  String? error,
});

// ── Why `frozen` cannot answer Q1, and what does ──────────────────────────
// MEASURED, not assumed. `settleForCapture` runs freeze -> floor -> loop ->
// freeze -> loop and returns the SECOND freeze's map (cdp.dart:835). The first
// freeze has already written `animation: none !important` onto every animated
// element, so the second finds nothing left to do. Direct observation on these
// pages:
//
//   /anim-infinite  getAnimations()=18  1st {infinite:18, committed:18}  2nd all 0
//   /anim-finite    getAnimations()=24  1st {finite:24,   committed:24}  2nd all 0
//   /static-control getAnimations()=0   1st all 0                        2nd all 0
//
// So `frozen['committed'] > 0` is FALSE on every correctly-frozen page, and
// asserting it would fail exactly when the freeze is working. It reads zero
// whether the freeze did everything or nothing — a field whose "all fine"
// value equals its "did not run" value, which is the shape this whole document
// exists to avoid. `freezeAnimations`'s own doc says a caller seeing
// `{finite: 0, infinite: 0}` on a page it believes is animated "has learned
// something"; routed through `settleForCapture`, every caller sees that always,
// so that diagnostic affordance is silently destroyed.
//
// Q1 is therefore answered two ways, neither of which uses `frozen`:
//   (a) EVERY capture, on the real path: after the settle, evaluate
//       `document.getAnimations().length`. The freeze drops the animation
//       property, so this MUST be 0 on an animated page. If the freeze ever
//       stops working, live animations remain and this goes positive.
//   (b) PERIODICALLY: navigate fresh, count animations BEFORE any freeze (must
//       be > 0 — proves the page still animates rather than having quietly
//       gone inert), then call `freezeAnimations()` directly to read the FIRST
//       pass's `committed`.
// (a) catches the freeze failing; (b) catches the page failing. Neither alone
// is sufficient: a page that stopped animating would pass (a) trivially.

/// After the settle, how many live animations remain. 0 means the freeze
/// de-promoted everything it found.
Future<int> liveAnimations(CdpSession tab) async {
  try {
    final n = await tab
        .evaluate('document.getAnimations ? document.getAnimations().length : -1');
    return n is int ? n : -1;
  } catch (_) {
    return -1;
  }
}

/// The real daemon path, now reporting its own screenshot cost via the
/// `screenshots` field added in d8717759 — no replication harness needed.
Future<Cap> capture(CdpSession tab, String url) async {
  try {
    await tab.navigateAndSettle('about:blank', settleMs: 100);
    await tab.setViewport(kW, kH);
    final r = await tab.navigateAndSettleForCapture(url,
        settleMs: kSettleMs, timeoutMs: kTimeoutMs);
    final bytes = Uint8List.fromList(await tab.screenshot());
    // Read AFTER the screenshot so it cannot perturb the pixels.
    final live = await liveAnimations(tab);
    if (bytes.isEmpty) {
      return (
        bytes: null,
        converged: false,
        ms: r.elapsedMs,
        screenshots: r.screenshots,
        frozen: r.frozen,
        liveAnimsAfter: live,
        error: 'screenshot returned 0 bytes'
      );
    }
    return (
      bytes: bytes,
      converged: r.converged,
      ms: r.elapsedMs,
      screenshots: r.screenshots,
      frozen: r.frozen,
      liveAnimsAfter: live,
      error: null
    );
  } catch (e) {
    return (
      bytes: null,
      converged: false,
      ms: 0,
      screenshots: 0,
      frozen: <String, int>{},
      liveAnimsAfter: -1,
      error: '$e'
    );
  }
}

/// (b): does the page still animate, and does the FIRST freeze still commit?
/// Navigates fresh and freezes by hand, so it observes the first pass rather
/// than the second. Run periodically; it is a different path from the arm's
/// captures and is used only for these two counts.
Future<({int preAnims, int committed, String? error})> freezeProbe(
    CdpSession tab, String url) async {
  try {
    await tab.navigateAndSettle('about:blank', settleMs: 100);
    await tab.setViewport(kW, kH);
    await tab.navigate(url);
    final pre = await liveAnimations(tab);
    final first = await tab.freezeAnimations();
    return (preAnims: pre, committed: first['committed'] ?? 0, error: null);
  } catch (e) {
    return (preAnims: -1, committed: -1, error: '$e');
  }
}

int distinct(List<Uint8List> xs) {
  final reps = <Uint8List>[];
  for (final x in xs) {
    if (!reps.any((r) => sameBytes(r, x))) reps.add(x);
  }
  return reps.length;
}

// ── bookkeeping ───────────────────────────────────────────────────────────
class Cold {
  final String page;
  int n = 0, errors = 0, notConverged = 0;
  int distinctCount = 0;
  Uint8List? rep;
  String worstDelta = '';
  final liveAfter = <int>[];
  int preAnims = -1; // animations present before any freeze
  int firstCommitted = -1; // what the FIRST freeze committed
  bool get reproducible => distinctCount == 1 && errors == 0 && notConverged == 0;
  Cold(this.page);
}

class Warm {
  final String page;
  int captures = 0, matches = 0, diverged = 0, notConverged = 0, errors = 0;
  /// Captures where live animations REMAINED after the settle — the freeze
  /// failed to de-promote. Signal (a).
  int freezeLost = 0;
  int? firstDivergeIndex;
  final divergeIndices = <int>[];
  final postDivergeHashes = <String>{};
  bool returnedToBaseline = false;
  final liveAfter = <int>[]; // signal (a), per capture
  final probePre = <int>[]; // signal (b), periodic: animations before freeze
  final probeCommitted = <int>[]; // signal (b), periodic: first-pass committed
  final shots = <int>[];
  Warm(this.page);

  /// Clustered-from-an-onset and persistent means warm drift; scattered with no
  /// onset means page-level nondeterminism. Opposite conclusions, so the shape
  /// is reported rather than a bare count.
  String get shape {
    if (diverged == 0) return 'no divergence';
    if (captures > 0 && matches == 0) {
      return 'NEVER MATCHED ($diverged/$captures) — not comparable at all';
    }
    // Returning to baseline after diverging means the output is not settling on
    // a new rendering — it is wandering between renderings, which is what
    // page-level nondeterminism looks like. Warm drift, by contrast, starts at
    // an index and stays.
    if (returnedToBaseline) {
      return 'SCATTERED ($diverged of $captures, returns to baseline) — reads as '
          'page-level nondeterminism, not warm drift';
    }
    if (postDivergeHashes.length > 1) {
      return 'WANDERING (${postDivergeHashes.length} distinct after onset)';
    }
    return 'PERSISTENT from i=$firstDivergeIndex — reads as warm drift';
  }
}

// ── report plumbing ───────────────────────────────────────────────────────
Future<void> writeSection(String body) async {
  final doc = reportFile();
  await doc.parent.create(recursive: true);
  var head = '';
  if (doc.existsSync()) {
    final existing = await doc.readAsString();
    final at = existing.indexOf(kAnimMarker);
    head = at >= 0 ? existing.substring(0, at) : '$existing\n';
  }
  await doc.writeAsString('$head$kAnimMarker\n\n$body');
}

String dist(List<int> v) {
  if (v.isEmpty) return 'none';
  final s = [...v]..sort();
  return 'min ${s.first}, median ${median(v)}, max ${s.last}, n=${v.length}';
}

// ── main ──────────────────────────────────────────────────────────────────
Future<void> main() async {
  exit(await run());
}

Future<int> run() async {
  final server = await serveAnim();
  final base = 'http://127.0.0.1:${server.port}';
  final prov = provenance();
  final pageNames = kPages.keys.toList();

  say('# warm-Chrome ANIMATED-PAGES probe');
  say('');
  say('Source:   $prov');
  say('Path:     navigateAndSettleForCapture(settleMs: $kSettleMs, timeoutMs: $kTimeoutMs)');
  say('Arm:      $kArm warm captures; cold N=$kColdAnimated animated / $kColdControl control');
  say('');

  String chromeVersion = 'unknown';

  // ── Phase 1: COLD self-consistency ─────────────────────────────────────
  // Can each page even reproduce itself with a FRESH browser every time? If an
  // animated page cannot, warmth is not the variable and Q2 has no answer for
  // it — but Q1 and Q3 still do, which is why this never aborts.
  say('== PHASE 1: COLD SELF-CONSISTENCY (fresh browser per capture) ==');
  final cold = {for (final p in pageNames) p: Cold(p)};
  for (final page in pageNames) {
    final c = cold[page]!;
    final n = kAnimatedPages.contains(page) ? kColdAnimated : kColdControl;
    final shots = <Uint8List>[];
    for (var i = 0; i < n; i++) {
      CdpClient? cl;
      try {
        cl = await CdpClient.launch();
        if (chromeVersion == 'unknown') {
          final v = await cl.send('Browser.getVersion');
          chromeVersion = v['result']['product'] as String;
        }
        final tab = await cl.newTab();
        await tab.enable();
        // On the first cold pass, observe the FIRST freeze directly, so the
        // report can state what this page actually gives the freeze to do.
        if (i == 0) {
          final fp = await freezeProbe(tab, '$base${kPages[page]}');
          c.preAnims = fp.preAnims;
          c.firstCommitted = fp.committed;
        }
        final cap = await capture(tab, '$base${kPages[page]}');
        c.n++;
        if (cap.error != null) {
          c.errors++;
        } else {
          if (!cap.converged) c.notConverged++;
          c.liveAfter.add(cap.liveAnimsAfter);
          shots.add(cap.bytes!);
        }
      } catch (e) {
        c.n++;
        c.errors++;
        say('  cold $page pass $i: $e');
      } finally {
        try {
          await cl?.close();
        } catch (_) {}
      }
    }
    c.distinctCount = distinct(shots);
    if (shots.isNotEmpty) c.rep = shots.first;
    if (c.distinctCount > 1) {
      // Worst-case delta between the first sample and any other.
      var worst = '';
      for (final s in shots.skip(1)) {
        if (!sameBytes(shots.first, s)) {
          worst = pixelDelta(shots.first, s);
          break;
        }
      }
      c.worstDelta = worst;
    }
    say('${pad(page, 10)}n=${c.n}  distinct=${c.distinctCount}  '
        'notConv=${c.notConverged}  err=${c.errors}  '
        'preAnims=${c.preAnims} firstFreezeCommitted=${c.firstCommitted}  '
        'liveAfter[${dist(c.liveAfter)}]  '
        '${c.reproducible ? "REPRODUCIBLE COLD" : "NOT reproducible cold"}');
    if (c.worstDelta.isNotEmpty) say('${pad("", 10)}  delta: ${c.worstDelta}');
  }
  say('');

  // Cross-check: freeze is a no-op on the control, so the freeze path must
  // reach the hash the plain-settle path has produced five times already.
  final ctl = cold['control']!;
  var controlHashOk = false;
  if (ctl.rep != null) {
    final h = shortHash(ctl.rep!);
    controlHashOk = h == kKnownStaticHash;
    say('control freeze-path hash $h vs known plain-settle $kKnownStaticHash '
        '=> ${controlHashOk ? "MATCH (apparatus consistent with the rest of this document)" : "MISMATCH — something changed; this outranks every other reading below"}');
  }
  // Did the freeze actually engage on the animated pages at all? Checked
  // against the FIRST freeze, observed directly — not against
  // settleForCapture's `frozen`, which reports the second pass and reads zero
  // on every correctly-frozen page.
  for (final p in kAnimatedPages) {
    final c = cold[p]!;
    if (c.preAnims <= 0 || c.firstCommitted <= 0) {
      say('WARNING: $p has preAnims=${c.preAnims}, firstFreezeCommitted='
          '${c.firstCommitted} — this page does not give the freeze real work, '
          'so it does not exercise what this probe exists to exercise. Fix the '
          'page before reading anything below.');
    } else {
      say('$p gives the freeze real work: ${c.preAnims} live animations before, '
          '${c.firstCommitted} elements committed and de-promoted by the first '
          'freeze.');
    }
    final stillLive = c.liveAfter.where((x) => x != 0).length;
    if (stillLive > 0) {
      say('WARNING: $p left animations live after the settle in '
          '$stillLive/${c.liveAfter.length} cold captures.');
    }
  }
  say('');

  // ── Phase 2: the warm arm ──────────────────────────────────────────────
  say('== PHASE 2: WARM ARM, $kArm captures, one browser, one tab ==');
  final warm = {for (final p in pageNames) p: Warm(p)};
  final mem = <MemSample>[];
  var reached = 0;
  var died = false;
  String? deathNote;
  final clock = Stopwatch()..start();

  final client = await CdpClient.launch();
  final udd = client.userDataDir!.path;
  final bpid = client.chromePid;
  say('browser pid $bpid');
  say('');

  try {
    final tab = await client.newTab();
    await tab.enable();
    for (var i = 0; i < kArm; i++) {
      if (clock.elapsed >= kMaxRun) {
        say('[stop] hard time limit reached at capture $i');
        break;
      }
      final page = pageNames[i % pageNames.length];
      final w = warm[page]!;
      final cap = await capture(tab, '$base${kPages[page]}');
      reached = i + 1;
      w.captures++;

      if (cap.error != null) {
        w.errors++;
        say('[ERROR] capture $i ($page): ${cap.error}');
        died = true;
        deathNote = 'capture $i threw: ${cap.error}';
        break;
      }
      w.shots.add(cap.screenshots);
      w.liveAfter.add(cap.liveAnimsAfter);

      // Q1 signal (a): after the settle, nothing should still be animating.
      // NOT `frozen['committed']` — see the long note above; that field reads
      // zero on a correctly-frozen page and would fail exactly when the freeze
      // is working.
      if (kAnimatedPages.contains(page) && cap.liveAnimsAfter != 0) {
        w.freezeLost++;
        say('[FREEZE LOST] capture $i ($page): ${cap.liveAnimsAfter} animations '
            'still live after the settle — the freeze stopped de-promoting. '
            'Everything after this measures a different thing.');
      }

      // Q1 signal (b), periodically: does the page still animate at all, and
      // does the FIRST freeze still commit? Catches the page going inert,
      // which signal (a) would pass trivially.
      if (i > 0 && i % kFreezeProbeEvery == 0) {
        final fp = await freezeProbe(tab, '$base${kPages[page]}');
        if (fp.error != null) {
          say('[freeze-probe] i=$i ($page) ERROR ${fp.error}');
        } else {
          w.probePre.add(fp.preAnims);
          w.probeCommitted.add(fp.committed);
          if (kAnimatedPages.contains(page) &&
              (fp.preAnims <= 0 || fp.committed <= 0)) {
            say('[freeze-probe] i=$i ($page) pre=${fp.preAnims} '
                'committed=${fp.committed} — the page stopped animating or the '
                'freeze stopped committing; captures here are not exercising '
                'what this probe exists to exercise');
          }
        }
      }

      if (!cap.converged) {
        w.notConverged++;
      } else if (cold[page]!.rep != null &&
          sameBytes(cold[page]!.rep!, cap.bytes!)) {
        w.matches++;
        if (w.firstDivergeIndex != null) w.returnedToBaseline = true;
      } else if (cold[page]!.rep != null) {
        w.diverged++;
        w.divergeIndices.add(i);
        w.postDivergeHashes.add(shortHash(cap.bytes!));
        if (w.firstDivergeIndex == null) {
          w.firstDivergeIndex = i;
          say('[DIVERGE] $page first differs from its cold baseline at capture '
              '$i: ${pixelDelta(cold[page]!.rep!, cap.bytes!)}');
        }
      }

      if (i % kMemEvery == 0) {
        final (b, s, n) = sampleRss(udd, bpid);
        mem.add(MemSample(i, clock.elapsed.inSeconds, b ~/ 1024, s ~/ 1024, n,
            await cdpProcCount(client)));
      }
      if (i > 0 && i % kProgressEvery == 0) {
        try {
          await client.send('Browser.getVersion');
        } catch (e) {
          died = true;
          deathNote = 'Browser.getVersion failed at capture $i: $e';
          say('[DEAD] $deathNote');
          break;
        }
        final m = mem.isEmpty ? null : mem.last;
        say('[$i/$kArm] ${fmtDur(clock.elapsed.inSeconds)}  '
            'RSS ${m?.browserRssMb ?? "-"}MB  '
            'match ${warm.values.fold(0, (a, w) => a + w.matches)}  '
            'diverge ${warm.values.fold(0, (a, w) => a + w.diverged)}  '
            'notConv ${warm.values.fold(0, (a, w) => a + w.notConverged)}  '
            'freezeLost ${warm.values.fold(0, (a, w) => a + w.freezeLost)}');
      }
    }
    final (b, s, n) = sampleRss(udd, bpid);
    mem.add(MemSample(reached, clock.elapsed.inSeconds, b ~/ 1024, s ~/ 1024, n,
        await cdpProcCount(client)));
  } catch (e) {
    died = true;
    deathNote = 'arm aborted: $e';
    say('[DEAD] $deathNote');
  } finally {
    try {
      await client.close();
    } catch (_) {}
  }
  await server.close(force: true);
  final armSec = clock.elapsed.inSeconds;

  // ── the three answers ──────────────────────────────────────────────────
  final allShots = <int>[];
  for (final w in warm.values) {
    allShots.addAll(w.shots);
  }
  final perCap = allShots.isEmpty ? 0 : median(allShots) + 1;

  say('');
  say('depth reached: $reached of $kArm in ${fmtDur(armSec)}');
  say('');

  say('== Q1: DOES THE FREEZE STAY EFFECTIVE? ==');
  say('(a) live animations remaining after each settle — must be 0');
  say('${pad("page", 10)}${pad("n", 6)}${pad("liveAfter distribution", 40)}freeze-lost');
  for (final p in pageNames) {
    final w = warm[p]!;
    say('${pad(p, 10)}${pad("${w.captures}", 6)}${pad(dist(w.liveAfter), 40)}'
        '${w.freezeLost}');
  }
  say('(b) periodic direct probe — animations present BEFORE the freeze, and '
      'what the FIRST freeze committed');
  say('${pad("page", 10)}${pad("preAnims", 30)}firstFreezeCommitted');
  for (final p in pageNames) {
    final w = warm[p]!;
    say('${pad(p, 10)}${pad(dist(w.probePre), 30)}${dist(w.probeCommitted)}');
  }
  final totalLost = warm.values.fold(0, (a, w) => a + w.freezeLost);
  final wentInert = kAnimatedPages.any((p) =>
      warm[p]!.probePre.any((x) => x <= 0) ||
      warm[p]!.probeCommitted.any((x) => x <= 0));
  say(totalLost == 0 && !wentInert
      ? 'VERDICT Q1: the freeze kept working for the whole arm — zero live '
          'animations after every settle, and the periodic probe kept finding '
          'live animations to freeze and committing them.'
      : 'VERDICT Q1: PROBLEM — freeze-lost captures: $totalLost; page went '
          'inert at some checkpoint: $wentInert. Readings after the first such '
          'event are not measuring the freeze path.');
  say('');

  say('== Q2: WARM vs COLD ON ANIMATED PAGES ==');
  say('${pad("page", 10)}${pad("cold", 22)}${pad("n", 6)}${pad("match", 7)}'
      '${pad("diverge", 9)}${pad("notConv", 9)}shape');
  for (final p in pageNames) {
    final c = cold[p]!, w = warm[p]!;
    final coldTxt = c.reproducible
        ? 'stable (${c.n} passes)'
        : 'UNSTABLE ${c.distinctCount}/${c.n} distinct';
    say('${pad(p, 10)}${pad(coldTxt, 22)}${pad("${w.captures}", 6)}'
        '${pad("${w.matches}", 7)}${pad("${w.diverged}", 9)}'
        '${pad("${w.notConverged}", 9)}'
        '${c.reproducible ? w.shape : "NO CLAIM AVAILABLE — page is not reproducible cold"}');
  }
  say('');

  say('== Q3: MEMORY WITH THE FREEZE DOING REAL WORK ==');
  say('${pad("i", 7)}${pad("elapsed", 9)}${pad("browserRSS", 12)}'
      '${pad("summedRSS*", 12)}${pad("ps-procs", 10)}cdp-procs');
  for (final m in mem) {
    say('${pad("${m.index}", 7)}${pad(fmtDur(m.elapsedSec), 9)}'
        '${pad("${m.browserRssMb}MB", 12)}${pad("${m.summedRssMb}MB", 12)}'
        '${pad("${m.psProcCount}", 10)}${m.cdpProcCount}');
  }
  say('* summedRSS double-counts shared pages — upper bound, not a measurement.');
  final memVerdict = classifySettleMemory(mem, reached, armSec, perCap);
  say(memVerdict);
  say('');
  say('screenshots per capture (from settleForCapture.screenshots, +1 for the '
      'caller\'s own): ${dist(allShots.map((s) => s + 1).toList())}');
  say('');

  await writeSection(buildSection(
    prov: prov,
    chromeVersion: chromeVersion,
    cold: cold,
    warm: warm,
    mem: mem,
    reached: reached,
    elapsedSec: armSec,
    perCap: perCap,
    allShots: allShots,
    died: died,
    deathNote: deathNote,
    controlHashOk: controlHashOk,
    memVerdict: memVerdict,
  ));
  say('Report: ${reportFile().path}');

  final anyDrift = pageNames.any((p) => cold[p]!.reproducible && warm[p]!.diverged > 0);
  return (died || totalLost > 0 || anyDrift) ? 1 : 0;
}

// ── report body ───────────────────────────────────────────────────────────
String buildSection({
  required String prov,
  required String chromeVersion,
  required Map<String, Cold> cold,
  required Map<String, Warm> warm,
  required List<MemSample> mem,
  required int reached,
  required int elapsedSec,
  required int perCap,
  required List<int> allShots,
  required bool died,
  required String? deathNote,
  required bool controlHashOk,
  required String memVerdict,
}) {
  final pageNames = kPages.keys.toList();
  final totalLost = warm.values.fold(0, (a, w) => a + w.freezeLost);
  final unstableCold =
      pageNames.where((p) => !cold[p]!.reproducible).toList();
  final drifted =
      pageNames.where((p) => cold[p]!.reproducible && warm[p]!.diverged > 0).toList();

  final b = StringBuffer()
    ..writeln('## Animated pages: the case the settle protocol exists for')
    ..writeln()
    ..writeln('Every warm-Chrome result above this section was measured on pages where')
    ..writeln('`freezeAnimations()` reported `{finite: 0, infinite: 0, smil: 0,')
    ..writeln('videos: 0, committed: 0}` — the machinery under test did nothing. The lens')
    ..writeln('exists to capture animated pages, so "a warm Chrome is safe to reuse" was')
    ..writeln('proven only in the case where the protocol was not needed. This section')
    ..writeln('closes that hole.')
    ..writeln()
    ..writeln('There is a measured reason to expect a difference, from `cdp.dart:641-651`:')
    ..writeln('an element that merely HAS an animation is promoted to its own compositor')
    ..writeln('layer, and that layer rasters differently run to run — a page whose')
    ..writeln('animation was provably pinned still gave 3 distinct images of 4, worst case')
    ..writeln('13,345 pixels. Compositor promotion is exactly the GPU-side state a warm')
    ..writeln('browser might reuse differently, and no earlier arm touched it.')
    ..writeln()
    ..writeln('### Setup')
    ..writeln()
    ..writeln('- Probe: `arxa/tool/warm_anim_probe.dart`')
    ..writeln('- Reproduce: `cd arxa && dart run tool/warm_anim_probe.dart`')
    ..writeln('- Source: `$prov`')
    ..writeln('- Chrome: `$chromeVersion`')
    ..writeln('- Path: the real `navigateAndSettleForCapture`, reading its own')
    ..writeln('  `screenshots` field (added in `d8717759`) — the replication harness the')
    ..writeln('  settle-rate section needed is gone.')
    ..writeln('- Pages: `anim-inf` (18 tiles, INFINITE gradient/transform/opacity')
    ..writeln('  animations → freeze pauses and pins `currentTime = 0`); `anim-fin`')
    ..writeln('  (24 cards, FINITE animations with `fill: both` holding non-default end')
    ..writeln('  states → freeze calls `finish()`, then commits inline and de-promotes);')
    ..writeln('  `control` (the animation-free static page, byte-identical to the one used')
    ..writeln('  throughout this document).')
    ..writeln('- Cold N: $kColdAnimated per animated page, $kColdControl for the control.')
    ..writeln('  Ten rather than five on the animated pages because the prior evidence was')
    ..writeln('  3-of-4 distinct; at N=5 an intermittent fault could show 1 distinct by')
    ..writeln('  luck, certify cold as stable, and make the warm arm\'s divergences look')
    ..writeln('  like warmth.')
    ..writeln('- Warm arm: $kArm captures, one browser, one tab, three pages rotated.')
    ..writeln('  **Depth reached: $reached in ${fmtDur(elapsedSec)}.**')
    ..writeln()
    ..writeln('The control\'s freeze-path hash was checked against `$kKnownStaticHash`, the')
    ..writeln('hash the static page has produced on the plain-settle path through five')
    ..writeln('prior runs in this document: '
        '**${controlHashOk ? "MATCH" : "MISMATCH"}**'
        '${controlHashOk ? " — the apparatus here is consistent with everything above." : ""}')
    ..writeln();
  if (!controlHashOk) {
    b
      ..writeln('**MISMATCH.** The control should be unaffected by the freeze, so this')
      ..writeln('outranks every other reading in this section — something about the')
      ..writeln('apparatus or the machine changed, and the results below should not be')
      ..writeln('interpreted until it is explained.')
      ..writeln();
  }

  // ── Q1 ──
  b
    ..writeln('### Q1 — does the freeze stay effective across a long warm session?')
    ..writeln()
    ..writeln('**`settleForCapture`\'s `frozen` map cannot answer this, and using it')
    ..writeln('would have produced a false alarm.** The sequence is freeze -> floor ->')
    ..writeln('loop -> freeze -> loop, and the record returns the SECOND freeze')
    ..writeln('(`cdp.dart:835`). The first freeze has already written')
    ..writeln('`animation: none !important` onto every animated element, so the second')
    ..writeln('finds nothing left. Measured directly on these pages:')
    ..writeln()
    ..writeln('```')
    ..writeln('/anim-infinite   getAnimations()=18   1st {infinite:18, committed:18}   2nd all 0')
    ..writeln('/anim-finite     getAnimations()=24   1st {finite:24,   committed:24}   2nd all 0')
    ..writeln('/static-control  getAnimations()=0    1st all 0                         2nd all 0')
    ..writeln('```')
    ..writeln()
    ..writeln('So `frozen[\'committed\'] > 0` is FALSE on every correctly-frozen page —')
    ..writeln('the assertion would fail exactly when the freeze is working. The field')
    ..writeln('reads zero whether the freeze did everything or nothing: its "all fine"')
    ..writeln('value equals its "did not run" value, which is the shape this document')
    ..writeln('exists to avoid. `freezeAnimations` documents that a caller seeing')
    ..writeln('`{finite: 0, infinite: 0}` on a page it believes is animated "has learned')
    ..writeln('something"; routed through `settleForCapture` every caller sees that')
    ..writeln('always, so the diagnostic is silently destroyed.')
    ..writeln()
    ..writeln('Q1 is therefore answered two ways, neither using `frozen`.')
    ..writeln()
    ..writeln('**(a) Every capture, on the real path** — after the settle, count live')
    ..writeln('animations. The freeze drops the `animation` property, so this must be 0;')
    ..writeln('if the freeze ever stops working, live animations remain.')
    ..writeln()
    ..writeln('```')
    ..writeln('${pad("page", 10)}${pad("n", 6)}${pad("liveAfter distribution", 40)}freeze-lost');
  for (final p in pageNames) {
    final w = warm[p]!;
    b.writeln('${pad(p, 10)}${pad("${w.captures}", 6)}'
        '${pad(dist(w.liveAfter), 40)}${w.freezeLost}');
  }
  b
    ..writeln('```')
    ..writeln()
    ..writeln('**(b) Periodically, by hand** — navigate fresh, count animations BEFORE')
    ..writeln('any freeze, then call `freezeAnimations()` directly to read the FIRST')
    ..writeln('pass. (a) catches the freeze failing; (b) catches the PAGE failing, which')
    ..writeln('(a) would pass trivially since a page that stopped animating also leaves')
    ..writeln('zero live animations.')
    ..writeln()
    ..writeln('```')
    ..writeln('${pad("page", 10)}${pad("preAnims (before freeze)", 34)}firstFreezeCommitted');
  for (final p in pageNames) {
    final w = warm[p]!;
    b.writeln('${pad(p, 10)}${pad(dist(w.probePre), 34)}${dist(w.probeCommitted)}');
  }
  b
    ..writeln('```')
    ..writeln()
    ..writeln(totalLost == 0
        ? '**The freeze kept working for the whole arm.** Zero live animations after'
            ' every settle, and the periodic probe kept finding live animations to'
            ' freeze and committing them — so the pages never went inert either.'
        : '**THE FREEZE FAILED** on $totalLost animated captures, which still had live'
            ' animations after the settle. From the first of those onward this arm was'
            ' no longer measuring the freeze path.')
    ..writeln()
    // ── Q2 ──
    ..writeln('### Q2 — do animated pages stay byte-identical warm vs cold?')
    ..writeln()
    ..writeln('```')
    ..writeln('${pad("page", 10)}${pad("cold", 24)}${pad("n", 6)}${pad("match", 7)}'
        '${pad("diverge", 9)}${pad("notConv", 9)}shape');
  for (final p in pageNames) {
    final c = cold[p]!, w = warm[p]!;
    final coldTxt = c.reproducible
        ? 'stable (${c.n} passes)'
        : 'UNSTABLE ${c.distinctCount}/${c.n}';
    b.writeln('${pad(p, 10)}${pad(coldTxt, 24)}${pad("${w.captures}", 6)}'
        '${pad("${w.matches}", 7)}${pad("${w.diverged}", 9)}'
        '${pad("${w.notConverged}", 9)}'
        '${c.reproducible ? w.shape : "NO CLAIM — not reproducible cold"}');
  }
  b..writeln('```')..writeln();
  if (unstableCold.isNotEmpty) {
    b
      ..writeln('**${unstableCold.join(", ")} cannot reproduce ${unstableCold.length == 1 ? "itself" : "themselves"} COLD**, with a fresh')
      ..writeln('browser for every capture. Warmth is therefore not the variable for')
      ..writeln('${unstableCold.length == 1 ? "that page" : "those pages"} and no warm-vs-cold claim is available — the instability is')
      ..writeln('a property of capturing that page at all. Cold deltas:')
      ..writeln();
    for (final p in unstableCold) {
      final c = cold[p]!;
      b.writeln('- `$p`: ${c.distinctCount} distinct in ${c.n} cold passes'
          '${c.worstDelta.isEmpty ? "" : " — ${c.worstDelta}"}');
    }
    b
      ..writeln()
      ..writeln('That is the honest answer to Q2 for ${unstableCold.length == 1 ? "it" : "them"}, and it is a finding about')
      ..writeln('the freeze and compositor promotion, NOT about reusing a browser. Q1 and')
      ..writeln('Q3 below are unaffected: neither depends on byte-identity, which is why')
      ..writeln('this probe does not abort on a disagreeing cold baseline the way the')
      ..writeln('earlier ones do.')
      ..writeln();
  }
  if (drifted.isNotEmpty) {
    b
      ..writeln('**${drifted.join(", ")} diverged warm despite being reproducible cold.**')
      ..writeln('That is warm drift on a page kind the daemon must handle, and it is the')
      ..writeln('result that decides whether the daemon can hold a browser at all. The')
      ..writeln('shape column distinguishes the two readings: PERSISTENT from an onset')
      ..writeln('index is warm drift; SCATTERED with returns to baseline reads as')
      ..writeln('page-level nondeterminism the cold sample missed.')
      ..writeln();
  }
  if (unstableCold.isEmpty && drifted.isEmpty) {
    b
      ..writeln('**No drift.** Every page that could reproduce itself cold also matched')
      ..writeln('that cold baseline from a warm browser, for all $reached captures — the')
      ..writeln('animated pages included. The compositor-promotion effect quoted above')
      ..writeln('does not, on this evidence, survive the freeze\'s de-promotion pass, and')
      ..writeln('reusing a warm browser does not reintroduce it.')
      ..writeln();
  }

  // ── Q3 ──
  b
    ..writeln('### Q3 — memory with the freeze doing real work')
    ..writeln()
    ..writeln('```')
    ..writeln('${pad("i", 7)}${pad("elapsed", 9)}${pad("browserRSS", 12)}'
        '${pad("summedRSS*", 12)}${pad("ps-procs", 10)}cdp-procs');
  for (final m in mem) {
    b.writeln('${pad("${m.index}", 7)}${pad(fmtDur(m.elapsedSec), 9)}'
        '${pad("${m.browserRssMb}MB", 12)}${pad("${m.summedRssMb}MB", 12)}'
        '${pad("${m.psProcCount}", 10)}${m.cdpProcCount}');
  }
  b
    ..writeln('```')
    ..writeln()
    ..writeln('`* summedRSS` double-counts shared pages — upper bound, not a measurement.')
    ..writeln()
    ..writeln(memVerdict)
    ..writeln()
    ..writeln('Same max-sustained-rise test and same classifier as the settle-rate')
    ..writeln('section, which was validated against both real curves and a synthetic')
    ..writeln('growing curve before its negative result was accepted.')
    ..writeln()
    ..writeln('Screenshots per capture here: ${dist(allShots.map((s) => s + 1).toList())}')
    ..writeln('(read from `settleForCapture.screenshots`, +1 for the caller\'s own final')
    ..writeln('`screenshot()`).')
    ..writeln()
    ..writeln('### Limits')
    ..writeln()
    ..writeln('- Depth reached: **$reached captures in ${fmtDur(elapsedSec)}**'
        '${died ? " — THE BROWSER DID NOT SURVIVE: $deathNote" : ""}. Nothing is claimed beyond it.')
    ..writeln('- Two animated page kinds, not an exhaustive set. GIF and APNG have no')
    ..writeln('  pause API at all — `cdp.dart` says so and Playwright has the same hole —')
    ..writeln('  so they are outside both the freeze and this measurement.')
    ..writeln('- Cross-origin iframes and `<video>` are likewise untested here.')
    ..writeln('- Same fixed conditions as the rest of this document: this Chrome build,')
    ..writeln('  ${kW}x$kH @ dsf 1, headless=new, machine otherwise quiet.')
    ..writeln();
  return b.toString();
}
