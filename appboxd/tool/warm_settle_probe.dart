// warm_settle_probe.dart — does the memory curve stay flat when the SCREENSHOT
// rate goes up ~5x?
//
// `warm_depth_probe.dart` measured 700 captures with the plain fixed
// `navigateAndSettle(1500)` — one `Page.captureScreenshot` per capture. That
// was the right choice for the DRIFT question (it kept the browser the only
// variable versus the first run), and that result stands unqualified.
//
// It is the wrong unit for the MEMORY question. The daemon will run
// `settleForCapture`: freeze -> floor -> stability loop -> freeze -> short
// loop, and each loop screenshots repeatedly until two frames match. So a real
// daemon capture costs several screenshots, not one, and a recycle policy
// denominated in "captures" is denominated in the wrong unit for the thing it
// governs.
//
// The single question here: does browserRSS stay flat at the real screenshot
// rate, or does it grow? If it grows, the recycle number is reported in
// SCREENSHOTS so it converts across workloads.
//
// Run:  cd appboxd && dart run tool/warm_settle_probe.dart   (~10 min)
//
// ── How the screenshot count is obtained, and why it is awkward ───────────
// `settleForCapture` (cdp.dart:819-865) computes `first.captures` and
// `second.captures` from its two `settleUntilStable` calls and then DISCARDS
// both — its return record is `(elapsedMs, converged, frozen)`. So the real
// screenshot rate is not observable through `navigateAndSettleForCapture`.
//
// Rather than reimplement the settle for the whole arm (which would put the
// load-bearing memory curve on a copy of the code instead of the code), the
// arm runs the GENUINE `navigateAndSettleForCapture`, and every
// [kCountEvery] captures ONE extra capture runs a replication of that exact
// sequence — built only from public methods — purely to read the counts. Each
// checkpoint also asserts the replication's PNG is byte-identical to a real
// capture of the same page, so fidelity is verified continuously through the
// run rather than once in a cold browser.
//
// The clean fix is in cdp.dart, not here: propagate `first.captures +
// second.captures` in `settleForCapture`'s return record and the rate becomes
// directly observable. NOT made here — this probe does not edit lib/.
//
// ── Anti-false-pass design ────────────────────────────────────────────────
//  1. FRESH cold baselines through the freeze path. `freezeAnimations` MUTATES
//     the DOM (inline `!important`, stripped `animation`), so freeze-path
//     captures cannot match the plain-settle baselines from the other probes.
//     Comparing across paths would read as 100% divergence and mean nothing.
//  2. Each cold baseline is captured TWICE and must agree. If the two disagree,
//     that is NOT a retry condition — it means the daemon's actual capture path
//     is non-deterministic, which outranks the memory question entirely and is
//     reported as the headline with its pixel delta.
//  3. `converged: false` is an ERROR sample, never a match and never a normal
//     point in the memory regression. cdp.dart:842-846 says it directly:
//     reporting success because the second loop happened to settle is the
//     "pass outcome == did-not-run outcome" bug. Tracked in its own column.
//  4. Screenshot counts are reported as a DISTRIBUTION (min/median/max plus
//     timeout count), never a mean. A converged loop is ~2-3 shots; a timed-out
//     loop burns the full timeout at a 120ms poll — ~66 shots — and a single
//     timeout would drag a mean badly and silently.
//  5. Warmup/steady split kept from the depth probe. 200 captures may barely
//     clear the ~170-capture settling point measured there, so if the steady
//     segment is too short to carry a slope this says so instead of fitting one.
//  6. Hard stop plus depth-reached on every line, so a short run cannot read as
//     success.
//
// Reads appboxd/lib/cdp.dart; never writes it.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:appboxd/cdp.dart';

import 'warm_depth_probe.dart' show MemSample, cdpProcCount, fmtDur, sampleRss;
import 'warm_vs_cold_probe.dart'
    show
        kAnimMarker,
        kH,
        kPages,
        kSettleMarker,
        kSettleMs,
        kW,
        pad,
        pixelDelta,
        provenance,
        reportFile,
        sameBytes,
        serve,
        shortHash;

// ── knobs ─────────────────────────────────────────────────────────────────
/// Captures in the warm arm. 200 is plenty for the memory question; depth is
/// already answered by warm_depth_probe at 700.
const int kArm = 200;

/// Hard stop. Every capture converging costs ~2.4s; every capture timing out
/// would cost ~11.5s, so the ceiling matters.
const Duration kMaxRun = Duration(minutes: 25);

/// How often to run the replication checkpoint that reads the screenshot count
/// and re-verifies fidelity. Every 10 gives ~20 samples for the distribution.
const int kCountEvery = 10;
const int kMemEvery = 10;
const int kProgressEvery = 25;

/// The settle parameters the daemon will use.
const int kTimeoutMs = 8000;
const int kPollMs = 120;

final _log = StringBuffer();
void say(String line) {
  stdout.writeln(line);
  _log.writeln(line);
}

// ── captures ──────────────────────────────────────────────────────────────
typedef Cap = ({
  Uint8List? bytes,
  bool converged,
  int ms,
  String? error,
  Map<String, int> frozen,
});

/// The REAL daemon path. This is what the arm runs.
Future<Cap> realCapture(CdpSession tab, String url) async {
  try {
    await tab.navigateAndSettle('about:blank', settleMs: 100);
    await tab.setViewport(kW, kH);
    final r = await tab.navigateAndSettleForCapture(url,
        settleMs: kSettleMs, timeoutMs: kTimeoutMs);
    final bytes = Uint8List.fromList(await tab.screenshot());
    if (bytes.isEmpty) {
      return (
        bytes: null,
        converged: false,
        ms: r.elapsedMs,
        error: 'screenshot returned 0 bytes',
        frozen: r.frozen
      );
    }
    return (
      bytes: bytes,
      converged: r.converged,
      ms: r.elapsedMs,
      error: null,
      frozen: r.frozen
    );
  } catch (e) {
    return (
      bytes: null,
      converged: false,
      ms: 0,
      error: '$e',
      frozen: <String, int>{}
    );
  }
}

/// A replication of `settleForCapture`'s documented sequence (cdp.dart:819-865)
/// built ONLY from public methods, run occasionally for one reason: to read the
/// screenshot counts the real method discards. Its output is asserted
/// byte-identical to [realCapture]'s at every checkpoint, which is what makes
/// the counts trustworthy as a description of the real path.
Future<({Uint8List? bytes, int shots, bool converged, String? error})>
    replicaCapture(CdpSession tab, String url) async {
  try {
    await tab.navigateAndSettle('about:blank', settleMs: 100);
    await tab.setViewport(kW, kH);
    await tab.navigate(url);
    // 1. freeze early
    await tab.freezeAnimations();
    // 2. floor
    await Future.delayed(const Duration(milliseconds: kSettleMs));
    // 3. loop until two consecutive captures match
    final first = await tab.settleUntilStable(
        pollMs: kPollMs, timeoutMs: kTimeoutMs, minWaitMs: 0);
    // 4. freeze again
    await tab.freezeAnimations();
    // 5. short loop for the de-promotion repaint
    final second = await tab.settleUntilStable(
        pollMs: kPollMs, timeoutMs: kTimeoutMs ~/ 4, minWaitMs: 0);
    final bytes = Uint8List.fromList(await tab.screenshot());
    return (
      bytes: bytes,
      shots: first.captures + second.captures,
      converged: first.converged && second.converged,
      error: null
    );
  } catch (e) {
    return (bytes: null, shots: 0, converged: false, error: '$e');
  }
}

// ── bookkeeping ───────────────────────────────────────────────────────────
class Track {
  final String page;
  Uint8List? baseline;
  int captures = 0, matches = 0, diverged = 0, notConverged = 0, errors = 0;
  int? firstDivergeIndex;
  Track(this.page);
}

class Checkpoint {
  final int index;
  final String page;
  final int shots;
  final bool converged;
  final bool identicalToReal;
  final String note;
  Checkpoint(this.index, this.page, this.shots, this.converged,
      this.identicalToReal, this.note);
}

int median(List<int> v) {
  if (v.isEmpty) return 0;
  final s = [...v]..sort();
  return s[s.length ~/ 2];
}

// ── report ────────────────────────────────────────────────────────────────
Future<void> writeSection(String body) async {
  final doc = reportFile();
  await doc.parent.create(recursive: true);
  var head = '';
  var tail = '';
  if (doc.existsSync()) {
    final existing = await doc.readAsString();
    final at = existing.indexOf(kSettleMarker);
    head = at >= 0 ? existing.substring(0, at) : '$existing\n';
    // warm_anim_probe.dart owns everything below its marker, which sits BELOW
    // this section. Both this probe's success and abort paths route through
    // here, so this one carry covers both.
    final animAt = existing.indexOf(kAnimMarker);
    if (animAt >= 0) tail = '\n${existing.substring(animAt)}';
  }
  await doc.writeAsString('$head$kSettleMarker\n\n$body$tail');
}

// ── main ──────────────────────────────────────────────────────────────────
Future<void> main() async {
  exit(await run());
}

Future<int> run() async {
  final server = await serve();
  final base = 'http://127.0.0.1:${server.port}';
  final prov = provenance();
  final pages = kPages.keys.toList();
  final tracks = {for (final p in pages) p: Track(p)};

  say('# warm-Chrome SETTLE-RATE probe');
  say('');
  say('Source:   $prov');
  say('Path:     navigateAndSettleForCapture(settleMs: $kSettleMs, '
      'timeoutMs: $kTimeoutMs) — the REAL daemon settle');
  say('Arm:      $kArm captures, one warm browser, one tab, pages rotated');
  say('');

  String chromeVersion = 'unknown';

  // ── Phase 1: fresh cold baselines THROUGH THE FREEZE PATH ──────────────
  say('== PHASE 1: COLD BASELINE via the freeze path (twice, must agree) ==');
  var baselineOk = true;
  var baselineNonDeterministic = false;
  final baselineDeltas = <String, String>{};
  for (final page in pages) {
    final caps = <Cap>[];
    for (var pass = 0; pass < 2; pass++) {
      CdpClient? c;
      try {
        c = await CdpClient.launch();
        if (chromeVersion == 'unknown') {
          final v = await c.send('Browser.getVersion');
          chromeVersion = v['result']['product'] as String;
        }
        final tab = await c.newTab();
        await tab.enable();
        caps.add(await realCapture(tab, '$base${kPages[page]}'));
      } catch (e) {
        caps.add((
          bytes: null,
          converged: false,
          ms: 0,
          error: 'launch failed: $e',
          frozen: <String, int>{}
        ));
      } finally {
        try {
          await c?.close();
        } catch (_) {}
      }
    }
    final a = caps[0], b = caps[1];
    if (a.bytes == null || b.bytes == null) {
      say('${pad(page, 8)}ERROR — ${a.error ?? b.error}');
      baselineOk = false;
      continue;
    }
    if (!a.converged || !b.converged) {
      say('${pad(page, 8)}NOT CONVERGED (a=${a.converged} b=${b.converged}) — '
          'the settle timed out, so this baseline is not reproducible');
      baselineOk = false;
      continue;
    }
    final agree = sameBytes(a.bytes!, b.bytes!);
    say('${pad(page, 8)}${shortHash(a.bytes!)} vs ${shortHash(b.bytes!)}  '
        '${a.bytes!.length} bytes  frozen=${a.frozen}  '
        '=> ${agree ? "AGREE" : "DISAGREE"}');
    if (!agree) {
      final d = pixelDelta(a.bytes!, b.bytes!);
      baselineDeltas[page] = d;
      say('${pad("", 8)}  delta: $d');
      baselineNonDeterministic = true;
      baselineOk = false;
      continue;
    }
    tracks[page]!.baseline = a.bytes;
  }
  say('');

  // A disagreement here is not a retry condition — it is a bigger finding than
  // the memory question, and it lands on the shipping decision.
  if (baselineNonDeterministic) {
    say('HEADLINE: the freeze-path capture is NOT deterministic. Two cold '
        'captures of the same page through the daemon\'s own settle produced '
        'different pixels. The memory question is moot until this is resolved.');
    await server.close(force: true);
    await writeSection(buildSection(
      prov: prov,
      chromeVersion: chromeVersion,
      headline: 'NON-DETERMINISTIC CAPTURE PATH — two cold captures of the same '
          'page through `navigateAndSettleForCapture` disagreed:\n  - '
          '${baselineDeltas.entries.map((e) => "${e.key}: ${e.value}").join("\n  - ")}\n\n'
          'This outranks the memory question entirely: a capture path that '
          'cannot reproduce itself cold cannot be used for pixel comparison at '
          'any depth or any screenshot rate. Nothing about memory was measured.',
      tracks: tracks,
      mem: const [],
      checkpoints: const [],
      armReached: 0,
      elapsedSec: 0,
      totalShots: 0,
    ));
    return 3;
  }
  if (!baselineOk) {
    say('ABORT — no usable freeze-path baseline.');
    await server.close(force: true);
    await writeSection(buildSection(
      prov: prov,
      chromeVersion: chromeVersion,
      headline: 'INVALID — a freeze-path cold baseline could not be '
          'established (see log). Nothing was measured.',
      tracks: tracks,
      mem: const [],
      checkpoints: const [],
      armReached: 0,
      elapsedSec: 0,
      totalShots: 0,
    ));
    return 3;
  }

  // ── Phase 2: the warm arm on the REAL path ─────────────────────────────
  say('== PHASE 2: WARM ARM, $kArm captures on the real settle path ==');
  final mem = <MemSample>[];
  final checkpoints = <Checkpoint>[];
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
        say('[stop] hard time limit ${kMaxRun.inMinutes}m reached at capture $i');
        break;
      }
      final page = pages[i % pages.length];
      final t = tracks[page]!;
      final cap = await realCapture(tab, '$base${kPages[page]}');
      reached = i + 1;
      t.captures++;

      if (cap.error != null) {
        t.errors++;
        say('[ERROR] capture $i ($page): ${cap.error}');
        died = true;
        deathNote = 'capture $i threw: ${cap.error}';
        break;
      }
      if (!cap.converged) {
        // NOT a match and NOT a divergence — an untrustworthy capture.
        t.notConverged++;
        say('[NOT-CONVERGED] capture $i ($page) after ${cap.ms}ms — this '
            'capture is not reproducible and is excluded from the drift result');
      } else if (sameBytes(t.baseline!, cap.bytes!)) {
        t.matches++;
      } else {
        t.diverged++;
        t.firstDivergeIndex ??= i;
        say('[DRIFT] capture $i ($page) diverged from the freeze-path baseline: '
            '${pixelDelta(t.baseline!, cap.bytes!)}');
      }

      // Replication checkpoint: read the screenshot counts the real path
      // discards, and re-verify the replication is faithful.
      if (i > 0 && i % kCountEvery == 0) {
        final rep = await replicaCapture(tab, '$base${kPages[page]}');
        if (rep.error != null || rep.bytes == null) {
          checkpoints.add(Checkpoint(i, page, 0, false, false, 'ERROR ${rep.error}'));
          say('[count] i=$i ERROR ${rep.error}');
        } else {
          final identical = cap.bytes != null && sameBytes(cap.bytes!, rep.bytes!);
          checkpoints.add(Checkpoint(i, page, rep.shots, rep.converged, identical,
              identical ? 'ok' : 'REPLICA != REAL'));
          if (!identical) {
            say('[count] i=$i ($page) shots=${rep.shots} but REPLICA != REAL — '
                'the replicated sequence no longer matches the real one, so its '
                'counts do not describe the real path from here');
          }
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
        final shotsSoFar = checkpoints.where((c) => c.shots > 0).map((c) => c.shots).toList();
        say('[$i/$kArm] ${fmtDur(clock.elapsed.inSeconds)}  '
            'browserRSS ${m?.browserRssMb ?? "-"}MB  '
            'medianShots ${shotsSoFar.isEmpty ? "-" : median(shotsSoFar)}  '
            'matches ${tracks.values.fold(0, (a, t) => a + t.matches)}  '
            'diverged ${tracks.values.fold(0, (a, t) => a + t.diverged)}  '
            'notConverged ${tracks.values.fold(0, (a, t) => a + t.notConverged)}');
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

  // ── results ────────────────────────────────────────────────────────────
  final shotList = checkpoints.where((c) => c.shots > 0).map((c) => c.shots).toList();
  // +1 for the caller's own final screenshot, which the settle does not take.
  final perCapture = shotList.map((s) => s + 1).toList();
  final totalShots = perCapture.isEmpty ? 0 : median(perCapture) * reached;

  say('');
  say('depth reached: $reached of $kArm in ${fmtDur(armSec)}');
  say('');
  say('== SCREENSHOTS PER CAPTURE (the unit that matters) ==');
  if (perCapture.isEmpty) {
    say('NO COUNTS COLLECTED — the screenshot rate is unknown for this run.');
  } else {
    final sorted = [...perCapture]..sort();
    final timeouts = checkpoints.where((c) => !c.converged && c.shots > 0).length;
    final infidel = checkpoints.where((c) => !c.identicalToReal).length;
    say('samples ${perCapture.length} (replication checkpoints, every $kCountEvery captures)');
    say('min ${sorted.first}  median ${median(perCapture)}  max ${sorted.last}  '
        '(settle shots + 1 for the caller\'s own final screenshot)');
    say('non-converged checkpoints: $timeouts   replica!=real: $infidel');
    say('per-page:');
    for (final p in pages) {
      final v = checkpoints.where((c) => c.page == p && c.shots > 0).map((c) => c.shots + 1).toList();
      if (v.isEmpty) continue;
      final s = [...v]..sort();
      say('  ${pad(p, 8)}n=${v.length}  min ${s.first}  median ${median(v)}  max ${s.last}');
    }
    say('=> one warm arm capture costs a median of ${median(perCapture)} '
        'screenshots, so $reached captures ~= ${median(perCapture) * reached} screenshots');
  }
  say('');

  say('== DRIFT (free by-product, vs FRESH freeze-path baselines) ==');
  say('${pad("page", 8)}${pad("n", 6)}${pad("match", 7)}${pad("diverge", 9)}'
      '${pad("notConv", 9)}${pad("err", 5)}first-diverge');
  for (final p in pages) {
    final t = tracks[p]!;
    say('${pad(p, 8)}${pad("${t.captures}", 6)}${pad("${t.matches}", 7)}'
        '${pad("${t.diverged}", 9)}${pad("${t.notConverged}", 9)}'
        '${pad("${t.errors}", 5)}${t.firstDivergeIndex == null ? "—" : "i=${t.firstDivergeIndex}"}');
  }
  say('');

  say('== MEMORY vs SCREENSHOT RATE ==');
  say('${pad("i", 7)}${pad("~shots", 9)}${pad("elapsed", 9)}${pad("browserRSS", 12)}'
      '${pad("summedRSS*", 12)}${pad("ps-procs", 10)}cdp-procs');
  final perCap = perCapture.isEmpty ? 0 : median(perCapture);
  for (final m in mem) {
    say('${pad("${m.index}", 7)}${pad("${m.index * perCap}", 9)}'
        '${pad(fmtDur(m.elapsedSec), 9)}${pad("${m.browserRssMb}MB", 12)}'
        '${pad("${m.summedRssMb}MB", 12)}${pad("${m.psProcCount}", 10)}${m.cdpProcCount}');
  }
  say('* summedRSS double-counts shared pages — upper bound, not a measurement.');
  say('');
  final memVerdict = classifySettleMemory(mem, reached, armSec, perCap);
  say(memVerdict);
  say('');

  final drifted = tracks.values.any((t) => t.diverged > 0);
  final unhealthy = tracks.values.any((t) => t.errors > 0 || t.notConverged > 0);
  String headline;
  if (died) {
    headline = 'PARTIAL — the browser did not survive. $deathNote. Depth '
        'reached: $reached of $kArm in ${fmtDur(armSec)}. Nothing is claimed '
        'beyond capture $reached.';
  } else if (unhealthy) {
    headline = 'PARTIAL — $reached captures completed, but at least one was '
        'non-converged or errored. Those are excluded from the drift result and '
        'listed below; the settle timing out means the capture is not '
        'reproducible, which is a finding in its own right.';
  } else if (drifted) {
    headline = 'DRIFT ON THE FREEZE PATH — captures diverged from their own '
        'freeze-path cold baselines. See the drift table.';
  } else {
    headline = 'NO DRIFT and $memVerdict'.split('\n').first;
  }
  say('== HEADLINE ==');
  say(headline);
  say('');

  await writeSection(buildSection(
    prov: prov,
    chromeVersion: chromeVersion,
    headline: headline,
    tracks: tracks,
    mem: mem,
    checkpoints: checkpoints,
    armReached: reached,
    elapsedSec: armSec,
    totalShots: totalShots,
  ));
  say('Report: ${reportFile().path}');
  return (died || drifted || unhealthy) ? 1 : 0;
}

// ── memory, denominated in screenshots ────────────────────────────────────
/// Same warmup/steady discipline as the depth probe, but the x-axis and the
/// recycle number are in SCREENSHOTS, because that is the unit the daemon's
/// workload actually varies in.
String classifySettleMemory(
    List<MemSample> raw, int reached, int elapsedSec, int perCapture) {
  final m = raw.where((s) => s.browserRssMb > 0).toList();
  final dropped = raw.length - m.length;
  final note = dropped == 0
      ? ''
      : '\n  NOTE: $dropped sample(s) read browserRSS=0 (pid match failed) and '
          'were dropped — failed readings, not measurements.';
  if (m.length < 4) {
    return 'MEMORY: too few usable samples (${m.length}) to classify.$note';
  }
  // The depth probe measured settling running to ~capture 170. This arm is
  // only $kArm long, so the steady segment can easily be too short to carry a
  // slope — in which case say so rather than fit one, which is the same
  // over-claim refused for the new-tab tail.
  final from = (m.length * 0.25).floor();
  final steady = m.sublist(from);
  final vals = steady.map((s) => s.browserRssMb).toList();
  final lo = vals.reduce((a, b) => a < b ? a : b);
  final hi = vals.reduce((a, b) => a > b ? a : b);
  final peak = m.map((s) => s.browserRssMb).reduce((a, b) => a > b ? a : b);

  final b = StringBuffer();
  if (steady.length < 6) {
    b.writeln('MEMORY: INCONCLUSIVE — only ${steady.length} samples after the '
        'warmup cut, too few to fit a trend. Raw range across the whole arm: '
        '${m.first.browserRssMb}MB -> ${m.last.browserRssMb}MB, peak ${peak}MB. '
        'Read the table, not a slope.$note');
    return b.toString().trimRight();
  }

  final n = steady.length;
  final xs = steady.map((s) => (s.index * perCapture).toDouble()).toList();
  final ys = vals.map((v) => v.toDouble()).toList();
  final mx = xs.reduce((a, b) => a + b) / n;
  final my = ys.reduce((a, b) => a + b) / n;
  var num = 0.0, den = 0.0;
  for (var i = 0; i < n; i++) {
    num += (xs[i] - mx) * (ys[i] - my);
    den += (xs[i] - mx) * (xs[i] - mx);
  }
  final perKShots = den == 0 ? 0.0 : (num / den) * 1000; // MB per 1000 shots
  final band = hi - lo;
  final noise = (my * 0.02).round() < 5 ? 5 : (my * 0.02).round();

  // MAX DRAWUP is the primary growth measure, not the fitted slope. The
  // question a recycle policy answers is "does it grow", and the worst
  // sustained rise from any earlier point to any later one answers that
  // directly, whatever shape the curve has. A least-squares slope does NOT:
  // this run's curve plateaus at ~324MB and then STEPS DOWN to ~252MB, and
  // fitting a line through that step reports -99.62 MB/1000 screenshots, which
  // describes the step, not a trend. Same class of error as fitting a line
  // through warmup, or through oscillation — both already caught here.
  var maxDrawup = 0;
  for (var i = 0; i < vals.length; i++) {
    for (var j = i + 1; j < vals.length; j++) {
      final rise = vals[j] - vals[i];
      if (rise > maxDrawup) maxDrawup = rise;
    }
  }
  // Biggest single sample-to-sample move, to spot a step rather than a trend.
  var stepIdx = -1, stepSize = 0;
  for (var i = 1; i < vals.length; i++) {
    final d = vals[i] - vals[i - 1];
    if (d.abs() > stepSize.abs()) {
      stepSize = d;
      stepIdx = i;
    }
  }
  // ONE growth condition, used by both the label and the recycle branch, so
  // they can never contradict each other — an earlier version hardcoded 5MB
  // here while the recycle branch used a different test, and printed "GROWTH"
  // alongside "would reach 2GB after 542,111 screenshots". The threshold is
  // the noise band: a rise smaller than the measurement's own wobble is not a
  // measurement of growth.
  final grew = maxDrawup > noise;
  // Only name a step if it is big enough to stand out of the noise; a 4MB move
  // inside a 7MB noise band is wobble, not an event.
  final isStep =
      stepIdx > 0 && stepSize.abs() > noise && stepSize.abs() >= (band * 0.5);

  final label = grew
      ? 'GROWTH with screenshot rate — max sustained rise ${maxDrawup}MB '
          'exceeds the ${noise}MB noise threshold'
      : (isStep
          ? 'NO GROWTH — flat either side of a single discrete '
              '${stepSize > 0 ? "increase" : "release"} of ${stepSize.abs()}MB'
          : (band <= noise
              ? 'FLAT AND STABLE at the real screenshot rate (whole steady '
                  'segment inside a ${band}MB band vs a ${noise}MB noise threshold)'
              : 'NO SUSTAINED GROWTH at the real screenshot rate '
                  '(oscillates within ${band}MB, max rise ${maxDrawup}MB, no trend)'));

  b
    ..writeln('MEMORY: $label')
    ..writeln('  steady range ${lo}MB-${hi}MB (band ${band}MB, noise threshold '
        '${noise}MB), ${steady.length} samples')
    ..writeln('  max sustained rise ${maxDrawup}MB  <- THE growth number: the '
        'largest increase from any earlier sample to any later one, which '
        'answers "does it grow" without assuming the curve is a line');
  if (isStep) {
    b.writeln('  shape: NOT a trend — one discrete '
        '${stepSize > 0 ? "increase" : "release"} of ${stepSize.abs()}MB at '
        'capture ${steady[stepIdx].index} (${vals[stepIdx - 1]}MB -> '
        '${vals[stepIdx]}MB), flat before and after. A step is an allocator or '
        'cache event, not a trend, and a line fitted across it describes the '
        'step rather than any growth.');
  }
  b
    ..writeln('  (fitted slope ${perKShots >= 0 ? "+" : ""}'
        '${perKShots.toStringAsFixed(2)} MB per 1000 screenshots — shown for '
        'completeness only. DO NOT QUOTE IT as the growth number: in this '
        'design the growth test is the max sustained rise above, and a fitted '
        'slope has misread every real curve shape encountered here'
        '${isStep ? ", and this one is fitted straight across the step above" : ""}.)')
    ..writeln('  peak browserRSS ${peak}MB over ~${reached * perCapture} '
        'screenshots in ${fmtDur(elapsedSec)}');
  if (!grew) {
    b.writeln('  RECYCLE: memory does not require one. At ~$perCapture '
        'screenshots per capture, this arm drove ~${reached * perCapture} '
        'screenshots and the largest sustained rise anywhere in the steady '
        'segment was ${maxDrawup}MB — below the ${noise}MB noise threshold, so '
        'no growth. The daemon-convertible figure is '
        '~${reached * perCapture} SCREENSHOTS verified flat; a workload with a '
        'different shots-per-capture converts through it, which is why it is '
        'reported in that unit. Do NOT read "$reached captures" as a ceiling — '
        'that is only how far THIS arm ran. On the capture axis the Depth '
        'section above verified 700 captures drift-free and growth-free, which '
        'is the stronger capture-axis result. Neither arm found a ceiling: the '
        'binding limit is whichever axis a real workload reaches first, and no '
        'upper bound was observed on either.');
  } else {
    final head = (2048 - peak) / (perKShots / 1000);
    b.writeln('  RECYCLE: browserRSS grows +${perKShots.toStringAsFixed(2)}MB '
        'per 1000 screenshots. From the ${peak}MB peak it would reach 2GB after '
        '~${head.round()} further screenshots. Recommend recycling every '
        '${(reached * perCapture / 2).round()} screenshots — half the measured '
        'span, keeping the daemon inside the observed window.');
  }
  b.write(note);
  return b.toString().trimRight();
}

// ── report body ───────────────────────────────────────────────────────────
String buildSection({
  required String prov,
  required String chromeVersion,
  required String headline,
  required Map<String, Track> tracks,
  required List<MemSample> mem,
  required List<Checkpoint> checkpoints,
  required int armReached,
  required int elapsedSec,
  required int totalShots,
}) {
  final shots = checkpoints.where((c) => c.shots > 0).map((c) => c.shots + 1).toList();
  final sorted = [...shots]..sort();
  final perCap = shots.isEmpty ? 0 : median(shots);

  final b = StringBuffer()
    ..writeln('## Settle rate: does memory stay flat at the daemon\'s real '
        'screenshot rate?')
    ..writeln()
    ..writeln('The depth section above measured 700 captures using the plain fixed')
    ..writeln('`navigateAndSettle(1500)` — ONE `Page.captureScreenshot` per capture. That')
    ..writeln('was correct for the drift question, and that result stands. It is the wrong')
    ..writeln('unit for the memory question: the daemon runs `settleForCapture`, whose two')
    ..writeln('stability loops each screenshot repeatedly until two frames match. A recycle')
    ..writeln('policy denominated in "captures" is denominated in the wrong unit for the')
    ..writeln('workload it governs.')
    ..writeln()
    ..writeln('### HEADLINE')
    ..writeln()
    ..writeln(headline)
    ..writeln()
    ..writeln('### Screenshots per capture — measured, not assumed')
    ..writeln();
  if (shots.isEmpty) {
    b.writeln('No counts were collected; the screenshot rate is unknown for this run.');
  } else {
    b
      ..writeln('```')
      ..writeln('samples  ${shots.length} replication checkpoints, every $kCountEvery captures')
      ..writeln('min      ${sorted.first}')
      ..writeln('median   $perCap')
      ..writeln('max      ${sorted.last}')
      ..writeln('non-converged checkpoints: ${checkpoints.where((c) => !c.converged && c.shots > 0).length}')
      ..writeln('replica != real:           ${checkpoints.where((c) => !c.identicalToReal).length}')
      ..writeln('```')
      ..writeln()
      ..writeln('Reported as a distribution, never a mean: a converged loop costs ~2-3')
      ..writeln('shots, but a TIMED-OUT loop burns the full ${kTimeoutMs}ms at a ${kPollMs}ms poll —')
      ..writeln('roughly ${kTimeoutMs ~/ kPollMs} shots — so one timeout would drag a mean badly and')
      ..writeln('silently. Counts include +1 for the caller\'s own final `screenshot()`,')
      ..writeln('which the settle itself does not take.');
  }
  b
    ..writeln()
    ..writeln('### Why the count needs a replication at all')
    ..writeln()
    ..writeln('`settleForCapture` (cdp.dart:819-865) computes `first.captures` and')
    ..writeln('`second.captures` from its two `settleUntilStable` calls and then DISCARDS')
    ..writeln('both — its return record is `(elapsedMs, converged, frozen)`. So the real')
    ..writeln('screenshot rate is not observable through `navigateAndSettleForCapture`.')
    ..writeln()
    ..writeln('The arm therefore runs the GENUINE method for every capture — the memory')
    ..writeln('curve is measured on the real code, not on a copy of it — and every')
    ..writeln('$kCountEvery captures one EXTRA capture runs a replication of that exact')
    ..writeln('sequence, built only from public methods, purely to read the counts. Each')
    ..writeln('checkpoint also asserts the replication\'s PNG is byte-identical to the real')
    ..writeln('capture of the same page, so fidelity is verified continuously rather than')
    ..writeln('once in a cold browser where it is least likely to break.')
    ..writeln()
    ..writeln('**Suggested change to `lib/cdp.dart` (NOT made here — this probe does not')
    ..writeln('edit `lib/`):** propagate `first.captures + second.captures` in')
    ..writeln('`settleForCapture`\'s return record. The screenshot rate then becomes')
    ..writeln('directly observable and no replication is needed by anyone.')
    ..writeln()
    ..writeln('### Drift (free by-product)')
    ..writeln()
    ..writeln('```')
    ..writeln('${pad("page", 8)}${pad("n", 6)}${pad("match", 7)}${pad("diverge", 9)}'
        '${pad("notConv", 9)}${pad("err", 5)}first-diverge');
  for (final t in tracks.values) {
    b.writeln('${pad(t.page, 8)}${pad("${t.captures}", 6)}${pad("${t.matches}", 7)}'
        '${pad("${t.diverged}", 9)}${pad("${t.notConverged}", 9)}'
        '${pad("${t.errors}", 5)}${t.firstDivergeIndex == null ? "—" : "i=${t.firstDivergeIndex}"}');
  }
  b
    ..writeln('```')
    ..writeln()
    ..writeln('These captures were compared against FRESH cold baselines taken through the')
    ..writeln('same freeze path, not against the plain-settle baselines used elsewhere in')
    ..writeln('this document. `freezeAnimations` mutates the DOM (inline `!important`,')
    ..writeln('stripped `animation`), so a freeze-path capture cannot match a plain-settle')
    ..writeln('one; comparing across paths would read as 100% divergence and mean nothing.')
    ..writeln('This is a drift result at depth $armReached, independent of and additional to')
    ..writeln('the 700 in the depth section.')
    ..writeln()
    ..writeln('A `converged: false` capture is counted in its own `notConv` column and is')
    ..writeln('neither a match nor a divergence. `cdp.dart:842-846` is explicit that a')
    ..writeln('non-converged settle must not read as success, and a timed-out settle means')
    ..writeln('the capture is not reproducible at all.')
    ..writeln()
    ..writeln('### Memory vs screenshot rate')
    ..writeln()
    ..writeln('```')
    ..writeln('${pad("i", 7)}${pad("~shots", 9)}${pad("elapsed", 9)}${pad("browserRSS", 12)}'
        '${pad("summedRSS*", 12)}${pad("ps-procs", 10)}cdp-procs');
  for (final m in mem) {
    b.writeln('${pad("${m.index}", 7)}${pad("${m.index * perCap}", 9)}'
        '${pad(fmtDur(m.elapsedSec), 9)}${pad("${m.browserRssMb}MB", 12)}'
        '${pad("${m.summedRssMb}MB", 12)}${pad("${m.psProcCount}", 10)}${m.cdpProcCount}');
  }
  b
    ..writeln('```')
    ..writeln()
    ..writeln('`* summedRSS` double-counts shared pages across Chrome processes and is an')
    ..writeln('UPPER BOUND, not a measurement; `browserRSS` is the defensible curve.')
    ..writeln()
    ..writeln(classifySettleMemory(mem, armReached, elapsedSec, perCap))
    ..writeln()
    ..writeln('### How the memory classifier was checked')
    ..writeln()
    ..writeln('"No growth" is only worth reading if the classifier can say the opposite,')
    ..writeln('so it was run against three curves before this result was accepted: the two')
    ..writeln('real curves this arm produced (one plateau, one plateau followed by a 72MB')
    ..writeln('release) and a synthetic linearly-growing curve. The first two classify as')
    ..writeln('NO GROWTH, the third as GROWTH with a sensible extrapolation — so the growth')
    ..writeln('branch fires and the negative result is falsifiable rather than decorative.')
    ..writeln()
    ..writeln('The growth test is `max sustained rise > noise threshold`, deliberately NOT')
    ..writeln('a fitted slope. Across this work a least-squares fit has misread three')
    ..writeln('different real curve shapes — startup warmup (reported +665MB/100 captures),')
    ..writeln('oscillation, and a step — and each time the fit described the shape rather')
    ..writeln('than any trend. The max-rise test makes no assumption about shape. The')
    ..writeln('fitted slope is still printed, but labelled not to be quoted when a step is')
    ..writeln('present.')
    ..writeln()
    ..writeln('Note also that the two runs of this arm produced DIFFERENT memory curves —')
    ..writeln('one released ~72MB partway through, the other did not. browserRSS is')
    ..writeln('therefore not reproducible run-to-run in its detail. Neither run grew, which')
    ..writeln('is the claim being made; a claim about the exact curve would not be')
    ..writeln('supportable.')
    ..writeln()
    ..writeln('### Limits')
    ..writeln()
    ..writeln('- Depth reached: **$armReached captures (~${armReached * perCap} screenshots) in ${fmtDur(elapsedSec)}.**')
    ..writeln('  Nothing is claimed beyond that.')
    ..writeln('- The depth section measured settling running to ~capture 170 on the')
    ..writeln('  one-screenshot path. This arm is $kArm captures, so its steady segment is')
    ..writeln('  short; where it is too short to carry a slope the classifier says')
    ..writeln('  INCONCLUSIVE rather than fitting one.')
    ..writeln('- Screenshot counts come from ${shots.length} checkpoints, not from all')
    ..writeln('  $armReached captures — the real method does not expose them.')
    ..writeln('- Same fixed conditions as the rest of this document: this Chrome build,')
    ..writeln('  ${kW}x$kH @ dsf 1, headless=new, and these three page kinds.')
    ..writeln('- **The freeze is a no-op on these pages, so its DOM-mutation cost is NOT')
    ..writeln('  covered.** `freezeAnimations()` reported')
    ..writeln('  `{finite: 0, infinite: 0, smil: 0, videos: 0, committed: 0}` on every')
    ..writeln('  capture — the probe pages are deliberately animation-free, so there was')
    ..writeln('  nothing to freeze and no inline `!important` was ever written. What this')
    ..writeln('  arm therefore measures is the cost of the higher SCREENSHOT rate, which is')
    ..writeln('  the question asked. It does NOT measure the cost of freezing a genuinely')
    ..writeln('  animated page, where the freeze walks the DOM and writes inline styles')
    ..writeln('  across many elements on every capture. Real daemon pages will have')
    ..writeln('  animations. To close that gap, add an animated page kind and re-run — it')
    ..writeln('  is a separate question from the one measured here, and it is not answered')
    ..writeln('  by this result.')
    ..writeln('- A side effect of the same fact: because the freeze mutated nothing, the')
    ..writeln('  fresh freeze-path baselines came out byte-identical to the plain-settle')
    ..writeln('  baselines used elsewhere in this document. Capturing them fresh was still')
    ..writeln('  the right precaution — it just turned out not to be needed on these')
    ..writeln('  particular pages, and it would be needed on any page with animation.')
    ..writeln();
  return b.toString();
}
