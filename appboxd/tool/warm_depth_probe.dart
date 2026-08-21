// warm_depth_probe.dart — how DEEP can one warm Chrome go before it drifts,
// and does its memory grow?
//
// `warm_vs_cold_probe.dart` established that a warm Chrome renders identically
// to a cold one — but only across 15 captures over ~26 seconds. Its own verdict
// named that as the weak condition, because a daemon holds one browser for
// hours across hundreds of pages. This probe answers the two questions that
// condition leaves open:
//
//   Q1 does the warm browser EVER diverge from the cold baseline, and at which
//      capture index / elapsed time does it first happen?
//   Q2 does Chrome's memory grow with depth, and what recycle policy follows?
//
// Run:  cd appboxd && dart run tool/warm_depth_probe.dart
// ~25 minutes. Prints progress every 25 captures and rewrites its report
// section every 10, so a run that dies at minute 18 still leaves its depth.
//
// ── Why a sibling file rather than a bigger warm_vs_cold_probe ─────────────
// Different runtime class (25 min vs 5 min) and a different question shape
// (onset + memory curve, not cross-arm equality). But it IMPORTS the pages,
// the hashing, and above all `capture()` from warm_vs_cold_probe.dart, so both
// probes drive byte-identical pages through a byte-identical capture path.
// That shared import is what makes run 1 and run 2 comparable at all; copying
// the pages would have quietly broken the comparison the moment either drifted.
//
// ── Which arm, and why only one ───────────────────────────────────────────
// WARM-SAME-TAB is the deep arm. Font-shaping, GPU raster and shader caches
// live in the browser/GPU process and warm regardless of tab shape, while
// renderer-local state dies with the tab — so the same tab accumulates strictly
// more state and is the shape most likely to drift. Depth is the variable under
// test; shape is not. One arm at depth 700 is stronger evidence than two arms
// at 350. A short WARM-NEW-TAB tail follows only to answer the separate
// memory question: does per-capture tab churn leak?
//
// ── Anti-false-pass design ────────────────────────────────────────────────
//  1. Cold baseline captured TWICE and required to match before the long run
//     starts. If today's machine cannot reproduce its own cold capture, no
//     drift claim is available and the probe aborts rather than measuring.
//  2. The negative control is re-asserted DURING the run, every 50 captures —
//     not just at the start. A 25-minute run reporting "no drift" is worthless
//     if the capture path broke at minute 3 and every later hash is of an error
//     page. The control must keep proving the instrument can still see.
//  3. The control alone is not enough: it is its own page, so it would keep
//     passing even if the REAL pages started rendering blank. Every capture is
//     therefore also byte-length-checked against its baseline; a blank render
//     collapses PNG size (a real page here is 5 KB-783 KB, a blank one ~2 KB)
//     and is flagged rather than counted as a match.
//  4. A crashed or reconnected browser INVALIDATES the depth claim — the window
//     is only as deep as the browser actually lived. There is no CDP event for
//     full browser death (only `Target.targetCrashed`, for renderers), so a
//     `Browser.getVersion` round-trip at every progress checkpoint is the
//     liveness signal; a throw ends the arm and the report states the depth
//     actually reached.
//  5. A short run can never read as success. Depth reached is printed on every
//     result line, and the verdict states it explicitly and claims nothing
//     beyond it.
//  6. Divergence is classified, not just counted: transient (returns to
//     baseline), persistent (never returns), or wandering (multiple distinct
//     hashes after onset). Those imply different daemon fixes.
//  7. Memory is reported as TWO columns. Summing `ps` RSS across Chrome's
//     processes double-counts shared pages, and the double-count grows with
//     process count — the very signal being read. Browser-process RSS is the
//     defensible curve; the sum is labelled an upper bound. (Chrome's own
//     `SystemInfo.getProcessInfo` was checked on this build: it returns type,
//     id and cpuTime only, with no memory field, so it supplies process COUNT
//     and nothing more.)
//
// Reads appboxd/lib/cdp.dart; never writes it.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:appboxd/cdp.dart';

import 'warm_vs_cold_probe.dart'
    show
        Shot,
        capture,
        kDepthMarker,
        kSettleMarker,
        kH,
        kPages,
        kSettleMs,
        kW,
        pad,
        provenance,
        reportFile,
        sameBytes,
        serve,
        shortHash;

// ── knobs ─────────────────────────────────────────────────────────────────
/// Captures in the deep WARM-SAME-TAB arm. ~1.75s each, so ~20 minutes.
const int kDepth = 700;

/// Captures in the WARM-NEW-TAB tail, which exists only to answer whether
/// per-capture tab churn leaks. Short on purpose — depth belongs to the arm
/// above.
const int kTailDepth = 100;

/// Hard stop. Whichever comes first, this or [kDepth].
const Duration kMaxRun = Duration(minutes: 30);

const int kProgressEvery = 25; // print a heartbeat
const int kControlEvery = 50; // re-assert the negative control
const int kMemEvery = 10; // sample memory + rewrite the report section

/// A capture whose PNG is more than this far from its baseline's size is
/// treated as a suspect render (blank/error page), not as a mere difference.
const double kBlankSuspectRatio = 0.5;

/// Mutation switch for verifying the detectors are real rather than decorative.
/// When true, two baselines are captured WRONG on purpose — `text` at a 1px
/// wider viewport (so every warm text capture must register as DIVERGENCE) and
/// `static` from the css page (so every warm static capture must register as a
/// size SUSPECT). Run with it on and both columns must light up; if they stay
/// at zero the detectors do not work and every "no divergence" they print is
/// meaningless. MUST be false for a real measurement.
const bool kMutateBaseline =
    bool.fromEnvironment('MUTATE_BASELINE', defaultValue: false);

// ── output ────────────────────────────────────────────────────────────────
final _log = StringBuffer();
void say(String line) {
  stdout.writeln(line);
  _log.writeln(line);
}

// ── memory sampling ───────────────────────────────────────────────────────
class MemSample {
  final int index; // capture index when taken
  final int elapsedSec;
  final int browserRssMb; // the defensible curve
  final int summedRssMb; // upper bound: shared pages counted per process
  final int psProcCount;
  final int cdpProcCount; // Chrome's own process table
  MemSample(this.index, this.elapsedSec, this.browserRssMb, this.summedRssMb,
      this.psProcCount, this.cdpProcCount);
}

/// RSS of the browser process, and the summed RSS of every process holding
/// this profile. Mirrors `cdp.dart`'s `_pidsOwningProfile` convention — same
/// `ps` shape, same whole-dir guard, same `--type=` meaning — because "who owns
/// this profile" should have one convention in this codebase, not two.
(int browserKb, int summedKb, int count) sampleRss(String userDataDir, int? browserPid) {
  final ProcessResult ps;
  try {
    ps = Process.runSync('ps', ['-eo', 'pid=,rss=,command=']);
  } catch (_) {
    return (0, 0, 0);
  }
  if (ps.exitCode != 0) return (0, 0, 0);
  final needle = '--user-data-dir=$userDataDir';
  var browser = 0, summed = 0, count = 0;
  for (final line in (ps.stdout as String).split('\n')) {
    final at = line.indexOf(needle);
    if (at < 0) continue;
    // Whole dir, not a prefix — `appbox-cdp-AB` must not claim `…-ABC`'s rows.
    final rest = line.substring(at + needle.length);
    if (rest.isNotEmpty && !rest.startsWith(' ')) continue;
    final fields = line.trimLeft().split(RegExp(r'\s+'));
    if (fields.length < 2) continue;
    final pid = int.tryParse(fields[0]);
    final rss = int.tryParse(fields[1]);
    if (pid == null || rss == null) continue;
    count++;
    summed += rss;
    if (pid == browserPid) browser = rss;
  }
  return (browser, summed, count);
}

Future<int> cdpProcCount(CdpClient client) async {
  try {
    final r = await client.send('SystemInfo.getProcessInfo');
    return (r['result']['processInfo'] as List).length;
  } catch (_) {
    return -1;
  }
}

// ── per-page drift bookkeeping ────────────────────────────────────────────
class PageTrack {
  final String page;
  Uint8List? baseline;
  int baselineLen = 0;
  int captures = 0;
  int matches = 0;
  int diverged = 0;
  int blankSuspect = 0;
  int errors = 0;
  int? firstDivergeIndex;
  int? firstDivergeSec;
  /// Distinct outputs seen AFTER the first divergence — 1 means it settled on
  /// one new rendering, >1 means it is wandering.
  final postDivergeHashes = <String>{};
  bool returnedToBaseline = false;
  PageTrack(this.page);

  String get classification {
    // A page whose every capture was a suspect render has NO valid samples —
    // saying "no divergence" there would be the did-not-run outcome wearing
    // the pass outcome's clothes. Caught by the baseline-mutation run, which
    // made every static capture a suspect and still read as clean.
    if (captures > 0 && matches == 0 && firstDivergeIndex == null) {
      return 'NO VALID SAMPLES ($blankSuspect suspect, $errors error)';
    }
    if (firstDivergeIndex == null) return 'no divergence';
    if (postDivergeHashes.length > 1) return 'WANDERING (${postDivergeHashes.length} distinct)';
    if (returnedToBaseline) return 'TRANSIENT (returned to baseline)';
    return 'PERSISTENT (never returned)';
  }
}

// ── report section ────────────────────────────────────────────────────────
/// Rewrite the depth section of the shared report, preserving everything the
/// warm-vs-cold probe owns above the marker. Called every [kMemEvery] captures
/// so a run that dies mid-flight still leaves a readable "depth reached: N".
Future<void> writeSection(String body) async {
  final doc = reportFile();
  await doc.parent.create(recursive: true);
  var head = '';
  var tail = '';
  if (doc.existsSync()) {
    final existing = await doc.readAsString();
    final at = existing.indexOf(kDepthMarker);
    head = at >= 0 ? existing.substring(0, at) : '$existing\n';
    // warm_settle_probe.dart owns everything below its own marker, which sits
    // BELOW this section. Carry it, or rewriting the depth section would
    // silently delete a measurement this probe does not own.
    final settleAt = existing.indexOf(kSettleMarker);
    if (settleAt >= 0) tail = '\n${existing.substring(settleAt)}';
  }
  await doc.writeAsString('$head$kDepthMarker\n\n$body$tail');
}

String fmtDur(int sec) =>
    '${(sec ~/ 60).toString().padLeft(2, '0')}m${(sec % 60).toString().padLeft(2, '0')}s';

// ── main ──────────────────────────────────────────────────────────────────
Future<void> main() async {
  exit(await run());
}

Future<int> run() async {
  final server = await serve();
  final base = 'http://127.0.0.1:${server.port}';
  final prov = provenance();
  final pageNames = kPages.keys.toList();

  say('# warm-Chrome DEPTH probe');
  say('');
  say('Source:   $prov');
  say('Settle:   plain fixed navigateAndSettle(${kSettleMs}ms) — the newer '
      'cdp.dart helpers are deliberately unused (see report)');
  say('Viewport: ${kW}x$kH @ dsf 1, headless=new');
  say('Target:   $kDepth captures WARM-SAME-TAB, then $kTailDepth WARM-NEW-TAB, '
      'hard stop ${kMaxRun.inMinutes}m');
  say('');

  String chromeVersion = 'unknown';

  // ── Phase 1: cold baseline, captured twice ─────────────────────────────
  // If the machine cannot reproduce its own cold capture today, nothing about
  // warm drift is measurable and this must abort rather than measure.
  say('== PHASE 1: COLD BASELINE (captured twice, must agree) ==');
  final tracks = {for (final p in pageNames) p: PageTrack(p)};
  var baselineOk = true;
  for (final page in pageNames) {
    final shots = <Shot>[];
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
        shots.add(await capture(tab, page, 'COLD', '$base${kMutateBaseline ? (page == "static" ? "/css" : kPages[page]) : kPages[page]}', width: kMutateBaseline && page == 'text' ? kW + 1 : kW));
      } catch (e) {
        shots.add(Shot.err(page, 'COLD', 'launch failed: $e', 0));
      } finally {
        try {
          await c?.close();
        } catch (_) {}
      }
    }
    if (!shots[0].isOk || !shots[1].isOk) {
      say('${pad(page, 8)}ERROR — ${shots[0].error ?? shots[1].error}');
      baselineOk = false;
      continue;
    }
    final agree = sameBytes(shots[0].bytes!, shots[1].bytes!);
    say('${pad(page, 8)}${shortHash(shots[0].bytes!)} vs ${shortHash(shots[1].bytes!)}  '
        '${shots[0].bytes!.length} bytes  => ${agree ? "AGREE" : "DISAGREE — machine not reproducible today"}');
    if (!agree) {
      baselineOk = false;
      continue;
    }
    tracks[page]!
      ..baseline = shots[0].bytes
      ..baselineLen = shots[0].bytes!.length;
  }

  // The negative control's own cold baseline: the two variants must differ,
  // and each must be stable, so the in-run re-assertions have something to
  // compare against.
  String? ctlA, ctlB;
  {
    CdpClient? c;
    try {
      c = await CdpClient.launch();
      final tab = await c.newTab();
      await tab.enable();
      final a = await capture(tab, 'fine', 'COLD', '$base/fine?c=%23202020');
      final b = await capture(tab, 'fine', 'COLD', '$base/fine?c=%23202021');
      if (a.isOk && b.isOk && !sameBytes(a.bytes!, b.bytes!)) {
        ctlA = shortHash(a.bytes!);
        ctlB = shortHash(b.bytes!);
        say('${pad("control", 8)}$ctlA vs $ctlB  => DIFFER (instrument can see)');
      } else {
        say('${pad("control", 8)}FAIL — control variants did not differ');
        baselineOk = false;
      }
    } catch (e) {
      say('${pad("control", 8)}ERROR — $e');
      baselineOk = false;
    } finally {
      try {
        await c?.close();
      } catch (_) {}
    }
  }
  say('');
  if (!baselineOk) {
    say('ABORT — no usable cold baseline. Nothing about depth was measured.');
    await server.close(force: true);
    await writeSection('## Depth\n\nINVALID — the cold baseline could not be '
        'established (see log), so no depth was measured.\n\n```\n'
        '${_log.toString().trimRight()}\n```\n');
    return 3;
  }

  // ── Phase 2: the deep warm arm ─────────────────────────────────────────
  say('== PHASE 2: WARM-SAME-TAB, depth $kDepth ==');
  final mem = <MemSample>[];
  final controlChecks = <String>[];
  var depthReached = 0;
  var browserDied = false;
  String? deathNote;
  final clock = Stopwatch()..start();

  final client = await CdpClient.launch();
  final udd = client.userDataDir!.path;
  final bpid = client.chromePid;
  say('browser pid $bpid, profile $udd');
  say('');

  Future<void> snapshotReport() async {
    await writeSection(buildSection(
      prov: prov,
      chromeVersion: chromeVersion,
      tracks: tracks,
      mem: mem,
      controlChecks: controlChecks,
      depthReached: depthReached,
      elapsedSec: clock.elapsed.inSeconds,
      browserDied: browserDied,
      deathNote: deathNote,
      tail: _tail,
      complete: false,
    ));
  }

  try {
    final tab = await client.newTab();
    await tab.enable();

    for (var i = 0; i < kDepth; i++) {
      if (clock.elapsed >= kMaxRun) {
        say('[stop] hard time limit ${kMaxRun.inMinutes}m reached at capture $i');
        break;
      }
      final page = pageNames[i % pageNames.length];
      final t = tracks[page]!;
      final shot = await capture(tab, page, 'WARM-DEPTH', '$base${kPages[page]}');
      depthReached = i + 1;
      t.captures++;

      if (!shot.isOk) {
        t.errors++;
        say('[ERROR] capture $i ($page): ${shot.error}');
        // An error here may mean the browser is gone; the liveness probe below
        // decides. Never treat an error as a match.
        browserDied = true;
        deathNote = 'capture $i ($page) threw: ${shot.error}';
        break;
      }

      final len = shot.bytes!.length;
      final ratio = (len - t.baselineLen).abs() / t.baselineLen;
      if (ratio > kBlankSuspectRatio) {
        t.blankSuspect++;
        say('[SUSPECT] capture $i ($page): $len bytes vs baseline '
            '${t.baselineLen} — likely blank/error render, NOT counted as match');
        continue;
      }

      if (sameBytes(t.baseline!, shot.bytes!)) {
        t.matches++;
        if (t.firstDivergeIndex != null) t.returnedToBaseline = true;
      } else {
        t.diverged++;
        t.postDivergeHashes.add(shortHash(shot.bytes!));
        if (t.firstDivergeIndex == null) {
          t.firstDivergeIndex = i;
          t.firstDivergeSec = clock.elapsed.inSeconds;
          say('[DRIFT] first divergence on "$page" at capture $i '
              '(${fmtDur(clock.elapsed.inSeconds)}), hash ${shortHash(shot.bytes!)}');
        }
      }

      // Negative control, re-asserted mid-run: the instrument must still see.
      if (i > 0 && i % kControlEvery == 0) {
        try {
          final a = await capture(tab, 'fine', 'CTL', '$base/fine?c=%23202020');
          final b = await capture(tab, 'fine', 'CTL', '$base/fine?c=%23202021');
          if (!a.isOk || !b.isOk) {
            controlChecks.add('i=$i ERROR');
            say('[control] i=$i ERROR — ${a.error ?? b.error}');
          } else {
            final ha = shortHash(a.bytes!), hb = shortHash(b.bytes!);
            final differ = !sameBytes(a.bytes!, b.bytes!);
            final stable = ha == ctlA && hb == ctlB;
            controlChecks.add('i=$i ${differ ? "differ" : "SAME(BROKEN)"}'
                '${stable ? "" : " hash-moved"}');
            if (!differ) {
              say('[control] i=$i SAME — INSTRUMENT BROKEN from here; results '
                  'past this index are not trustworthy');
            } else if (!stable) {
              say('[control] i=$i differ ok, but control hashes moved '
                  '($ha/$hb vs cold $ctlA/$ctlB) — that IS drift on the control page');
            }
          }
        } catch (e) {
          controlChecks.add('i=$i THREW');
          say('[control] i=$i threw: $e');
        }
      }

      // Memory sample + durable partial report.
      if (i % kMemEvery == 0) {
        final (b, s, n) = sampleRss(udd, bpid);
        mem.add(MemSample(i, clock.elapsed.inSeconds, b ~/ 1024, s ~/ 1024, n,
            await cdpProcCount(client)));
        await snapshotReport();
      }

      // Heartbeat + liveness. No CDP event announces full browser death, so a
      // round-trip is the signal; a throw ends the arm honestly.
      if (i > 0 && i % kProgressEvery == 0) {
        try {
          await client.send('Browser.getVersion');
        } catch (e) {
          browserDied = true;
          deathNote = 'Browser.getVersion failed at capture $i: $e';
          say('[DEAD] $deathNote');
          break;
        }
        final m = mem.isEmpty ? null : mem.last;
        say('[$i/$kDepth] ${fmtDur(clock.elapsed.inSeconds)}  '
            'browserRSS ${m?.browserRssMb ?? "-"}MB  procs ${m?.psProcCount ?? "-"}  '
            'matches ${tracks.values.fold(0, (a, t) => a + t.matches)}  '
            'diverged ${tracks.values.fold(0, (a, t) => a + t.diverged)}');
      }
    }
    // Final memory point for the arm.
    final (b, s, n) = sampleRss(udd, bpid);
    mem.add(MemSample(depthReached, clock.elapsed.inSeconds, b ~/ 1024,
        s ~/ 1024, n, await cdpProcCount(client)));
  } catch (e) {
    browserDied = true;
    deathNote = 'arm aborted: $e';
    say('[DEAD] $deathNote');
  } finally {
    try {
      await client.close();
    } catch (_) {}
  }
  final armSec = clock.elapsed.inSeconds;
  say('');
  say('depth reached: $depthReached of $kDepth in ${fmtDur(armSec)}');
  say('');

  // ── Phase 3: new-tab churn tail (memory question only) ─────────────────
  say('== PHASE 3: WARM-NEW-TAB tail, $kTailDepth captures (does tab churn leak?) ==');
  await runTail(base, pageNames, tracks);
  say('');

  // ── results ────────────────────────────────────────────────────────────
  say('== Q1: DRIFT ONSET ==');
  say('${pad("page", 8)}${pad("n", 6)}${pad("match", 7)}${pad("diverge", 9)}'
      '${pad("suspect", 9)}${pad("err", 5)}${pad("first-diverge", 16)}classification');
  for (final page in pageNames) {
    final t = tracks[page]!;
    final onset = t.firstDivergeIndex == null
        ? '—'
        : 'i=${t.firstDivergeIndex} @${fmtDur(t.firstDivergeSec!)}';
    say('${pad(page, 8)}${pad("${t.captures}", 6)}${pad("${t.matches}", 7)}'
        '${pad("${t.diverged}", 9)}${pad("${t.blankSuspect}", 9)}'
        '${pad("${t.errors}", 5)}${pad(onset, 16)}${t.classification}');
  }
  say('');
  say('in-run negative controls: ${controlChecks.isEmpty ? "none run" : controlChecks.join("  ")}');
  say('');

  say('== Q2: MEMORY CURVE (WARM-SAME-TAB) ==');
  say('${pad("i", 7)}${pad("elapsed", 9)}${pad("browserRSS", 12)}'
      '${pad("summedRSS*", 12)}${pad("ps-procs", 10)}cdp-procs');
  for (final m in mem) {
    say('${pad("${m.index}", 7)}${pad(fmtDur(m.elapsedSec), 9)}'
        '${pad("${m.browserRssMb}MB", 12)}${pad("${m.summedRssMb}MB", 12)}'
        '${pad("${m.psProcCount}", 10)}${m.cdpProcCount}');
  }
  say('* summedRSS double-counts shared pages across Chrome processes — it is '
      'an UPPER BOUND, not a measurement. browserRSS is the defensible curve.');
  say('');
  final memVerdict = classifyMemory(mem);
  say(memVerdict);
  say('');

  await server.close(force: true);

  final section = buildSection(
    prov: prov,
    chromeVersion: chromeVersion,
    tracks: tracks,
    mem: mem,
    controlChecks: controlChecks,
    depthReached: depthReached,
    elapsedSec: armSec,
    browserDied: browserDied,
    deathNote: deathNote,
    tail: _tail,
    complete: true,
  );
  await writeSection(section);
  say('Report: ${reportFile().path}');

  final drifted = tracks.values.any((t) => t.firstDivergeIndex != null);
  final unhealthy = tracks.values.any((t) => t.errors > 0 || t.blankSuspect > 0);
  return (browserDied || drifted || unhealthy) ? 1 : 0;
}

// ── new-tab churn tail ────────────────────────────────────────────────────
String _tail = 'not run';

/// Divergences and errors seen in the tail. Module-level so the VERDICT can
/// see them: counting them only inside the tail's own text would let a
/// new-tab drift sit in the document underneath a verdict saying "no drift".
int _tailDiverged = 0;
int _tailErrors = 0;

Future<void> runTail(
    String base, List<String> pageNames, Map<String, PageTrack> tracks) async {
  final samples = <MemSample>[];
  var done = 0;
  var diverged = 0, errors = 0;
  final clock = Stopwatch()..start();
  CdpClient? client;
  try {
    client = await CdpClient.launch();
    final udd = client.userDataDir!.path;
    final bpid = client.chromePid;
    for (var i = 0; i < kTailDepth; i++) {
      final page = pageNames[i % pageNames.length];
      try {
        final tab = await client.newTab();
        await tab.enable();
        final shot = await capture(tab, page, 'TAIL', '$base${kPages[page]}');
        await client.send('Target.closeTarget', {'targetId': tab.targetId});
        if (!shot.isOk) {
          errors++;
        } else if (!sameBytes(tracks[page]!.baseline!, shot.bytes!)) {
          diverged++;
        }
        done = i + 1;
      } catch (e) {
        errors++;
        stdout.writeln('[tail] capture $i failed: $e');
        break;
      }
      if (i % kMemEvery == 0) {
        final (b, s, n) = sampleRss(udd, bpid);
        samples.add(MemSample(i, clock.elapsed.inSeconds, b ~/ 1024, s ~/ 1024,
            n, await cdpProcCount(client)));
      }
    }
    final (b, s, n) = sampleRss(udd, bpid);
    samples.add(MemSample(done, clock.elapsed.inSeconds, b ~/ 1024, s ~/ 1024,
        n, await cdpProcCount(client)));
  } catch (e) {
    stdout.writeln('[tail] aborted: $e');
  } finally {
    try {
      await client?.close();
    } catch (_) {}
  }

  _tailDiverged = diverged;
  _tailErrors = errors;
  final buf = StringBuffer();
  buf.writeln('depth reached: $done of $kTailDepth, diverged $diverged, errors $errors');
  buf.writeln('${pad("i", 7)}${pad("elapsed", 9)}${pad("browserRSS", 12)}'
      '${pad("summedRSS*", 12)}${pad("ps-procs", 10)}cdp-procs');
  for (final m in samples) {
    buf.writeln('${pad("${m.index}", 7)}${pad(fmtDur(m.elapsedSec), 9)}'
        '${pad("${m.browserRssMb}MB", 12)}${pad("${m.summedRssMb}MB", 12)}'
        '${pad("${m.psProcCount}", 10)}${m.cdpProcCount}');
  }
  if (samples.length >= 2) {
    final d = samples.last.browserRssMb - samples.first.browserRssMb;
    buf.writeln('browserRSS change over $done new-tab captures: '
        '${d >= 0 ? "+" : ""}${d}MB  (raw first-to-last, INCLUDES startup '
        'warmup — the browser and GPU processes coming up account for most of '
        'any early rise, so this is an upper bound on churn-driven growth, not '
        'a leak measurement)');
  }
  _tail = buf.toString();
  stdout.write(_tail);
  _log.write(_tail);
}

// ── memory classification ─────────────────────────────────────────────────
// Chrome's browser process climbs steeply for the first handful of captures as
// renderers and the GPU process come up, then levels. That STARTUP WARMUP is
// not a leak, and fitting one line through warmup + steady state reports a
// slope that is pure artefact — the smoke run at depth 12 fitted +665 MB per
// 100 captures from warmup alone. A recycle policy derived from that number
// would be badly wrong, so warmup is separated from steady state and every
// growth claim below is made on the STEADY segment only.

/// Samples whose browserRSS actually read. `sampleRss` matches the browser
/// process by the pid resolved once at launch; if that match ever fails it
/// returns 0, and a 0 entering the curve is a FAILED READING masquerading as a
/// measurement — it would drag the least-squares slope negative and could flip
/// the recycle policy. Dropped here, and the drop count is reported so the
/// omission is visible rather than silent.
List<MemSample> _valid(List<MemSample> m) =>
    m.where((s) => s.browserRssMb > 0).toList();

/// How many MB of movement counts as noise rather than growth: 2% of the
/// typical reading, floored at 5MB. RSS wobbles by a few MB from ordinary
/// allocator behaviour, and browserRSS is integer MB, so anything inside this
/// band should not be read as a trend.
int _noiseBandMb(List<int> vals) {
  final mid = vals[vals.length ~/ 2];
  final pct = (mid * 0.02).round();
  return pct < 5 ? 5 : pct;
}

/// Index in [m] where steady state is taken to begin: past the first quarter
/// of the arm. Everything before it is warmup.
int _steadyFrom(List<MemSample> m) => m.length < 8 ? 1 : (m.length * 0.25).floor();

/// MB per 100 captures, least squares over [m] from [from] onward.
double _slopePer100(List<MemSample> m, int from) {
  final seg = m.sublist(from);
  if (seg.length < 3) return 0;
  final n = seg.length;
  final mx = seg.map((s) => s.index.toDouble()).toList();
  final my = seg.map((s) => s.browserRssMb.toDouble()).toList();
  final meanX = mx.reduce((a, b) => a + b) / n;
  final meanY = my.reduce((a, b) => a + b) / n;
  var num = 0.0, den = 0.0;
  for (var i = 0; i < n; i++) {
    num += (mx[i] - meanX) * (my[i] - meanY);
    den += (mx[i] - meanX) * (mx[i] - meanX);
  }
  return den == 0 ? 0 : (num / den) * 100;
}

String classifyMemory(List<MemSample> raw) {
  final dropped = raw.length - _valid(raw).length;
  final m = _valid(raw);
  final note = dropped == 0
      ? ''
      : '\n  NOTE: $dropped of ${raw.length} samples read browserRSS=0 (the '
          'browser pid match failed) and were DROPPED — they are failed '
          'readings, not measurements.';
  if (m.length < 4) {
    return 'MEMORY: too few usable samples (${m.length}) to classify.$note';
  }
  final from = _steadyFrom(m);
  final steady = m.sublist(from);
  final warmFirst = m.first.browserRssMb;
  final steadyFirst = steady.first.browserRssMb;
  final steadyLast = steady.last.browserRssMb;
  final max = m.map((s) => s.browserRssMb).reduce((a, b) => a > b ? a : b);
  final wholePer100 = _slopePer100(m, 0);
  final steadyPer100 = _slopePer100(m, from);
  final steadyGrowthPct =
      steadyFirst == 0 ? 0.0 : (steadyLast - steadyFirst) * 100 / steadyFirst;

  // Range beats slope for deciding flatness. browserRSS is integer MB, so a
  // plateau that jitters a few MB still fits a small nonzero slope — and that
  // artefact alone could push the recycle policy into the growth branch and
  // produce a bogus "reaches 2GB after N captures" extrapolation. If the whole
  // steady segment sits inside a few MB it is flat, whatever the fit says.
  final steadyVals = steady.map((s) => s.browserRssMb).toList();
  final sMin = steadyVals.reduce((a, b) => a < b ? a : b);
  final sMax = steadyVals.reduce((a, b) => a > b ? a : b);
  final flatByRange = (sMax - sMin) <= _noiseBandMb(steadyVals);

  // TREND and VOLATILITY are different questions, and only the first decides
  // whether a daemon must recycle. Chrome's RSS oscillates — this run saw it
  // fall 320MB -> 254MB between captures 50 and 100 — so a wide band is normal
  // and is NOT growth. Judging on the band alone would label an oscillating but
  // trendless curve "SHRINKING" or "LINEAR GROWTH" depending on where the fit
  // happened to land, and the growth label would then drive a bogus
  // "reaches 2GB after N captures" extrapolation. So: slope decides the label,
  // band only describes how much it wobbles on the way.
  final label = steadyPer100 >= 5
      ? 'LINEAR GROWTH in steady state'
      : (steadyPer100 <= -5
          ? 'NET DECLINE in steady state (Chrome releasing memory; not growth)'
          : (flatByRange
              ? 'FLAT AND STABLE after warmup'
              : 'NO SUSTAINED GROWTH after warmup '
                  '(oscillates within ${sMax - sMin}MB, no trend)'));

  return (StringBuffer()
        ..writeln('MEMORY: $label')
        ..writeln('  steady range ${sMin}MB-${sMax}MB (band '
            '${sMax - sMin}MB, noise threshold ${_noiseBandMb(steadyVals)}MB) '
            '${flatByRange ? "<- inside noise, so FLAT regardless of the fitted slope" : ""}')
        ..write(note.isEmpty ? '' : '${note.trimRight()}\n')
        ..writeln('  settling captures ${m.first.index}-${steady.first.index}: '
            '${warmFirst}MB -> ${steadyFirst}MB, peaking at '
            '${m.sublist(0, from).map((s) => s.browserRssMb).reduce((a, b) => a > b ? a : b)}MB '
            '(processes coming up AND Chrome then releasing what it '
            'over-allocated — this segment both rises and falls, so read the '
            'table rather than these two endpoints; NOT a leak, and excluded '
            'from every growth number below)')
        ..writeln('  steady   captures ${steady.first.index}-${steady.last.index}: '
            '${steadyFirst}MB -> ${steadyLast}MB '
            '(${steadyGrowthPct >= 0 ? "+" : ""}${steadyGrowthPct.toStringAsFixed(1)}%), '
            '${steady.length} samples')
        ..writeln('  steady slope ${steadyPer100 >= 0 ? "+" : ""}'
            '${steadyPer100.toStringAsFixed(2)} MB per 100 captures  <- the number '
            'that matters')
        ..writeln('  (whole-arm slope ${wholePer100 >= 0 ? "+" : ""}'
            '${wholePer100.toStringAsFixed(2)} MB/100 is shown only to make the '
            'warmup artefact visible; do not use it)')
        ..writeln('  peak browserRSS ${max}MB')
        ..writeln('  labels are decided by TREND (the steady slope), not by the '
            'band: LINEAR GROWTH = >=+5MB/100 captures; NET DECLINE = '
            '<=-5MB/100; otherwise no sustained growth, reported as FLAT AND '
            'STABLE when the band is also inside the noise threshold and as '
            'oscillating-without-trend when it is not. A wide band alone is '
            'volatility, not growth, and only growth can force a recycle.'))
      .toString()
      .trimRight();
}

/// Turn the memory curve into the thing a daemon author actually needs.
/// Uses the steady segment only, for the reason given above.
String recyclePolicy(List<MemSample> raw, int depthReached, int elapsedSec) {
  final m = _valid(raw);
  if (m.length < 4) return 'Not enough usable memory samples to recommend a policy.';
  final from = _steadyFrom(m);
  final steady = m.sublist(from);
  final per100 = _slopePer100(m, from);
  final max = m.map((s) => s.browserRssMb).reduce((a, b) => a > b ? a : b);
  final span = steady.last.index - steady.first.index;
  final growth = steady.last.browserRssMb - steady.first.browserRssMb;
  final steadyVals = steady.map((s) => s.browserRssMb).toList();
  final band = steadyVals.reduce((a, b) => a > b ? a : b) -
      steadyVals.reduce((a, b) => a < b ? a : b);
  // Only a sustained upward TREND can force a recycle. Oscillation — which
  // Chrome does, releasing memory as well as taking it — is volatility, not
  // growth, and must not manufacture a "reaches 2GB after N captures"
  // extrapolation out of a curve that has no trend at all.
  if (per100 < 1) {
    return 'RECYCLE POLICY: memory does not require one within the measured '
        'window. After warmup, browserRSS moved '
        '${growth >= 0 ? "+" : ""}${growth}MB across $span captures '
        '(steady slope ${per100 >= 0 ? "+" : ""}${per100.toStringAsFixed(2)}MB '
        'per 100 captures — no sustained upward trend), oscillating within a '
        '${band}MB band and peaking at ${max}MB. Chrome both takes and releases '
        'memory across a run, so that band is volatility rather than growth, '
        'and volatility alone never forces a recycle — '
        'no memory threshold is reachable from this data. Recommend '
        'recycling every $depthReached captures or ${(elapsedSec / 60).round()} '
        'minutes, whichever comes first — the deepest point actually verified. '
        'A larger number would be a claim that going further is safe, which '
        'this run cannot support: recycling AT the verified depth is the only '
        'recommendation the evidence carries. The honest statement is "no '
        'growth was observed through $depthReached captures / '
        '${fmtDur(elapsedSec)}", and nothing here licenses a claim past that.';
  }
  final headroom = (2048 - max) / (per100 / 100);
  return 'RECYCLE POLICY: after warmup, browserRSS grew ${growth}MB across '
      '$span captures — a steady slope of +${per100.toStringAsFixed(2)}MB per '
      '100 captures, peaking at ${max}MB. At that rate it reaches 2GB after '
      'roughly ${headroom.round()} further captures. Recommend recycling every '
      '${(depthReached / 2).round()} captures or '
      '${(elapsedSec / 120).round()} minutes, whichever comes first — half the '
      'measured depth, keeping the daemon inside the window actually observed '
      'rather than extrapolating past it.';
}

// ── report body ───────────────────────────────────────────────────────────
String buildSection({
  required String prov,
  required String chromeVersion,
  required Map<String, PageTrack> tracks,
  required List<MemSample> mem,
  required List<String> controlChecks,
  required int depthReached,
  required int elapsedSec,
  required bool browserDied,
  required String? deathNote,
  required String tail,
  required bool complete,
}) {
  final drifted = tracks.values.any((t) => t.firstDivergeIndex != null);
  final unhealthy = tracks.values.any((t) => t.errors > 0 || t.blankSuspect > 0) ||
      _tailErrors > 0;
  // The control page is not in `tracks`, so without these two its failures
  // would print loudly to stdout and STILL leave the verdict reading "NO
  // DRIFT" — a signal that fires but never reaches the conclusion, which is
  // the same false-pass bug class inverted.
  final ctlBlind = controlChecks.any((c) =>
      c.contains('SAME(BROKEN)') || c.contains('ERROR') || c.contains('THREW'));
  final ctlMoved = controlChecks.any((c) => c.contains('hash-moved'));
  final ctlFirstBad = controlChecks.firstWhere(
      (c) => c.contains('SAME(BROKEN)') || c.contains('ERROR') || c.contains('THREW'),
      orElse: () => '');

  String verdict;
  if (!complete) {
    verdict = 'IN PROGRESS — depth reached so far: $depthReached of $kDepth '
        '(${fmtDur(elapsedSec)}). This section is rewritten every $kMemEvery '
        'captures; if it still says IN PROGRESS the run did not finish, and '
        'nothing is claimed beyond the depth shown.';
  } else if (browserDied) {
    verdict = 'PARTIAL — the browser did not survive the run. $deathNote. '
        'Depth actually reached: $depthReached of $kDepth in '
        '${fmtDur(elapsedSec)}. The warm window is only as deep as the browser '
        'lived, so NOTHING is claimed beyond capture $depthReached, and the '
        'captures around the failure are not averaged over.';
  } else if (ctlBlind) {
    verdict = 'INVALID — the in-run negative control failed at "$ctlFirstBad". '
        'From that point the capture path could no longer be shown to detect a '
        'difference it was designed to detect, so every "identical" recorded '
        'after it is unfalsifiable. Depth reached before the control failed is '
        'all that can be read from this run, and the no-drift result is NOT '
        'available.';
  } else if (ctlMoved) {
    verdict = 'DRIFT ON THE CONTROL PAGE. The control variants still differed '
        'from each other (so the instrument can see), but their hashes moved '
        'away from the cold values partway through: '
        '${controlChecks.where((c) => c.contains("hash-moved")).join("; ")}. '
        'That is a genuine drift finding on a fourth page kind, and it stands '
        'regardless of what the three main pages did. Depth reached: '
        '$depthReached.';
  } else if (_tailDiverged > 0) {
    verdict = 'DRIFT IN THE NEW-TAB TAIL. The deep same-tab arm held for all '
        '$depthReached captures, but $_tailDiverged of the new-tab tail '
        'captures diverged from the cold baseline. A daemon using a fresh tab '
        'per capture is therefore NOT covered by the same-tab result — see the '
        'tail section.';
  } else if (unhealthy) {
    verdict = 'PARTIAL — $depthReached captures completed, but at least one '
        'page recorded an error or a suspect (blank-sized) render. Those are '
        'listed below and are NOT counted as matches. Treat the drift result '
        'as unproven until they are explained.';
  } else if (drifted) {
    final lines = tracks.values
        .where((t) => t.firstDivergeIndex != null)
        .map((t) => '${t.page}: first divergence at capture '
            '${t.firstDivergeIndex} (${fmtDur(t.firstDivergeSec!)}), '
            '${t.diverged}/${t.captures} captures diverged, ${t.classification}')
        .join('\n  - ');
    verdict = 'WARM CHROME DRIFTS WITH DEPTH. Onset:\n  - $lines\n\n'
        'A daemon must recycle before the earliest onset above, or accept a '
        'pixel tolerance sized to the divergence.';
  } else {
    verdict = 'NO DRIFT WITHIN THE MEASURED DEPTH. One warm Chrome produced '
        'byte-identical output to the cold baseline across all $depthReached '
        'captures over ${fmtDur(elapsedSec)}, on every page kind, with the '
        'negative control re-asserted throughout. This does NOT extend past '
        '$depthReached captures / ${fmtDur(elapsedSec)} — that is the window '
        'measured, and the claim stops there.';
  }

  final b = StringBuffer()
    ..writeln('## Depth: how long can one warm Chrome be reused?')
    ..writeln()
    ..writeln('`warm_vs_cold_probe.dart` showed warm == cold, but only across 15')
    ..writeln('captures over ~26s. That was the weak condition in its verdict, since a')
    ..writeln('daemon holds one browser for hours. This section measures the two things')
    ..writeln('that condition leaves open: whether the warm browser ever diverges from')
    ..writeln('the cold baseline (and at which capture), and whether its memory grows.')
    ..writeln()
    ..writeln('### VERDICT (depth)')
    ..writeln()
    ..writeln(verdict)
    ..writeln()
    ..writeln('### Setup')
    ..writeln()
    ..writeln('- Probe: `appboxd/tool/warm_depth_probe.dart`')
    ..writeln('- Reproduce: `cd appboxd && dart run tool/warm_depth_probe.dart`')
    ..writeln('- Source under measurement: `$prov`')
    ..writeln('- Chrome: `$chromeVersion`')
    ..writeln('- Settle: the plain fixed `navigateAndSettle(settleMs: $kSettleMs)`.')
    ..writeln('  The newer `cdp.dart` helpers (`freezeAnimations`,')
    ..writeln('  `settleUntilStable`, `settleForCapture`,')
    ..writeln('  `navigateAndSettleForCapture`) exist and were deliberately NOT used,')
    ..writeln('  so this run stays comparable to the warm-vs-cold run above — the')
    ..writeln('  variable under test is the browser, not the settle. Their absence is')
    ..writeln('  a choice, not an oversight.')
    ..writeln('- Pages, hashing and the capture function are IMPORTED from')
    ..writeln('  `warm_vs_cold_probe.dart` rather than copied, so both probes drive')
    ..writeln('  byte-identical pages through a byte-identical capture path. Copying')
    ..writeln('  them would have broken the comparison the moment either changed.')
    ..writeln('- Arm: WARM-SAME-TAB, one browser, one tab, pages rotated. Same-tab was')
    ..writeln('  chosen over new-tab because font-shaping, GPU raster and shader caches')
    ..writeln('  live in the browser/GPU process and warm regardless of tab shape,')
    ..writeln('  while renderer-local state dies with the tab — so the same tab')
    ..writeln('  accumulates strictly more state and is the shape most likely to drift.')
    ..writeln('  Depth is the variable under test, so the budget went to one deep arm')
    ..writeln('  rather than two shallow ones.')
    ..writeln('- Target depth $kDepth captures, hard stop ${kMaxRun.inMinutes}m.')
    ..writeln('  **Depth actually reached: $depthReached in ${fmtDur(elapsedSec)}.**')
    ..writeln()
    ..writeln('### Q1 — drift onset')
    ..writeln()
    ..writeln('```')
    ..writeln('${pad("page", 8)}${pad("n", 6)}${pad("match", 7)}${pad("diverge", 9)}'
        '${pad("suspect", 9)}${pad("err", 5)}${pad("first-diverge", 16)}classification');
  for (final t in tracks.values) {
    final onset = t.firstDivergeIndex == null
        ? '—'
        : 'i=${t.firstDivergeIndex} @${fmtDur(t.firstDivergeSec!)}';
    b.writeln('${pad(t.page, 8)}${pad("${t.captures}", 6)}${pad("${t.matches}", 7)}'
        '${pad("${t.diverged}", 9)}${pad("${t.blankSuspect}", 9)}'
        '${pad("${t.errors}", 5)}${pad(onset, 16)}${t.classification}');
  }
  b
    ..writeln('```')
    ..writeln()
    ..writeln('Divergence, if any, is classified rather than merely counted, because')
    ..writeln('the three shapes imply different fixes: TRANSIENT (diverges then returns')
    ..writeln('to baseline) suggests a settle race a retry would absorb; PERSISTENT')
    ..writeln('(never returns) is a real cache state change that caps reuse at the')
    ..writeln('onset index; WANDERING (several distinct outputs after onset) would kill')
    ..writeln('reuse outright.')
    ..writeln()
    ..writeln('### In-run negative control')
    ..writeln()
    ..writeln('The control is re-asserted every $kControlEvery captures, not just at the')
    ..writeln('start: a 25-minute run reporting "no drift" would be worthless if the')
    ..writeln('capture path had broken at minute 3 and every later hash were of an')
    ..writeln('error page. Each check re-renders the two one-RGB-step-apart variants and')
    ..writeln('requires them to differ; it also checks their hashes still match the cold')
    ..writeln('values, so drift on the control page itself is visible.')
    ..writeln()
    ..writeln('```')
    ..writeln(controlChecks.isEmpty ? 'none run' : controlChecks.join('\n'))
    ..writeln('```')
    ..writeln()
    ..writeln('The control cannot catch everything: it is its own page, so it would keep')
    ..writeln('passing even if the real pages began rendering blank. Every capture is')
    ..writeln('therefore also size-checked against its baseline PNG (a blank render')
    ..writeln('collapses to ~2KB against real pages of 5KB-783KB); anything more than')
    ..writeln('${(kBlankSuspectRatio * 100).round()}% off is counted in the `suspect` column above and never as a match.')
    ..writeln()
    ..writeln('### Q2 — memory curve (WARM-SAME-TAB)')
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
    ..writeln('`* summedRSS` sums `ps` RSS across every process holding the profile.')
    ..writeln('Chrome processes share large mappings, so that sum double-counts shared')
    ..writeln('pages — and the double-count grows with process count, which is the very')
    ..writeln('signal being read. It is an UPPER BOUND, not a measurement.')
    ..writeln('`browserRSS` (the browser process alone) is the defensible curve.')
    ..writeln('Chrome\'s own `SystemInfo.getProcessInfo` was checked on this build and')
    ..writeln('returns `type`, `id` and `cpuTime` only — no memory field — so it')
    ..writeln('contributes the process COUNT column and nothing more. That column is')
    ..writeln('still worth reading: `cdp-procs` (Chrome\'s own table) matching')
    ..writeln('`ps-procs` (this probe\'s reconstruction by `--user-data-dir` match) is')
    ..writeln('what licenses using `ps` for the memory numbers at all. Where the two')
    ..writeln('columns disagree, the `ps` rows are not the process set Chrome thinks')
    ..writeln('it has, and the RSS figures on that row should not be trusted.')
    ..writeln()
    ..writeln(classifyMemory(mem))
    ..writeln()
    ..writeln('### Recycle policy')
    ..writeln()
    ..writeln(recyclePolicy(mem, depthReached, elapsedSec))
    ..writeln()
    ..writeln('### New-tab churn tail')
    ..writeln()
    ..writeln('A short WARM-NEW-TAB run (fresh tab per capture, closed after) follows')
    ..writeln('the deep arm to answer the separate question of whether per-capture tab')
    ..writeln('churn leaks. It is short on purpose: depth belongs to the arm above.')
    ..writeln()
    ..writeln('**It is too short to answer the leak question, and the number below')
    ..writeln('should not be read as if it did.** The same-tab arm did not reach steady')
    ..writeln('state until around capture 170; this tail stops at $kTailDepth, so it')
    ..writeln('never leaves its own settling phase and its end-to-end delta cannot')
    ..writeln('separate churn-driven growth from ordinary warmup. What the tail DOES')
    ..writeln('establish is the drift result — every tail capture is compared against')
    ..writeln('the same cold baseline, and that comparison is valid at any depth.')
    ..writeln('For a daemon that opens a fresh tab per capture, memory behaviour is')
    ..writeln('therefore NOT established here; raise `kTailDepth` past the settling')
    ..writeln('point and re-run before relying on it.')
    ..writeln()
    ..writeln('```')
    ..writeln(tail.trimRight())
    ..writeln('```')
    ..writeln()
    ..writeln('### What this does NOT establish')
    ..writeln()
    ..writeln('- Nothing beyond $depthReached captures / ${fmtDur(elapsedSec)}. A daemon')
    ..writeln('  running longer than that is outside the measured window.')
    ..writeln('- Only this Chrome build, this viewport (${kW}x$kH @ dsf 1), this fixed')
    ..writeln('  ${kSettleMs}ms settle, and these three page kinds.')
    ..writeln('- Every capture re-navigates via `about:blank`, so this measures')
    ..writeln('  process- and GPU-level cache reuse, not same-document state carryover.')
    ..writeln('- Memory was read from `ps` RSS; Chrome\'s own per-process memory')
    ..writeln('  accounting is not exposed by the CDP commands available on this build.')
    ..writeln();
  return b.toString();
}
