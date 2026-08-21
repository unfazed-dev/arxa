// Settle-determinism probe — does the stability loop fix the measured defect?
//
// Reproduces the 4-row table from docs/plans/rust-port-closure-and-surgical-lens.md
// (W1 amendment) with BOTH settle paths in the same run:
//
//   OLD = navigate + Future.delayed(1500ms)      — CdpTab.navigateAndSettle
//   NEW = navigate + settleUntilStable()         — capture-until-two-match
//
// WHY BOTH ARMS, ALWAYS. This project has shipped six checks whose "pass"
// outcome was also their "did not run" outcome. A settle probe that only runs
// the new path and reports "1 distinct image" cannot distinguish "the loop
// worked" from "this page was never nondeterministic in the first place". The
// OLD column is the control: on the variable-load page it MUST show >= 2
// distinct images. If it shows 1, this probe did not reproduce the defect and
// every NEW-column result in the run is meaningless — the probe says so out
// loud rather than printing a green table.
//
// Run: cd appboxd && dart run tool/settle_determinism_probe.dart

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/cdp.dart';

const _n = 5;
const _viewportW = 390;
const _viewportH = 844;

/// Flat colour blocks. No animation, no variable load. Control page: every arm
/// must return exactly 1 distinct image, or the capture path itself is broken.
const _staticPage = '''
<!doctype html><meta charset=utf-8><title>static</title>
<style>body{margin:0;font:16px/1.4 -apple-system,sans-serif}
.b{height:120px}.a{background:#204a87}.c{background:#c17d11}.d{background:#4e9a06}</style>
<div class="b a"></div><div class="b c"></div><div class="b d"></div>
<p style="padding:12px">static content, no motion</p>
''';

/// Infinite CSS animation. Under OLD this is phase-locked (constant load time
/// + constant timer = same phase every run), so it reads as deterministic
/// while being live. Under NEW it can never converge — that is the point of
/// running it: it measures the cost of the loop's known failure mode.
const _animatedPage = '''
<!doctype html><meta charset=utf-8><title>animated</title>
<style>body{margin:0;background:#111}
@keyframes spin{from{transform:rotate(0deg)}to{transform:rotate(360deg)}}
#s{width:160px;height:160px;margin:80px auto;background:linear-gradient(#e33,#3e3);
   animation:spin 2s linear infinite}</style>
<div id=s></div>
''';

/// THE DEFECT REPRODUCER — and the first version of it was WRONG, which is
/// worth recording. It busy-waited BEFORE first paint and produced 1 distinct
/// image, i.e. no defect. The reason: `navigate()` waits for `Page.loadEvent`
/// and the settle timer starts THERE, so anything slow before load just shifts
/// the whole timeline and the timer stays phase-locked to it.
///
/// Variance only bites when it lands AFTER load — async data, lazy images,
/// framework hydration. So that is what this models: on `load`, wait a random
/// 100-1200ms, then reveal content with a 900ms transition. Total time to a
/// settled page is 1000-2100ms, straddling the fixed 1500ms timer, so the old
/// path catches it sometimes mid-reveal and sometimes not at all. The final
/// pixels are identical every run — only the arrival time varies.
const _variableLoadPage = '''
<!doctype html><meta charset=utf-8><title>variable-load</title>
<style>body{margin:0;background:#fff}
#c{padding:40px;font:20px/1.5 -apple-system,sans-serif;color:#204a87;
   opacity:0;transform:translateY(40px);transition:opacity 900ms ease-out,transform 900ms ease-out}
body.ready #c{opacity:1;transform:none}
.sq{width:100px;height:100px;background:#c17d11;margin-top:20px}</style>
<div id=c>variable load, fixed outcome<div class=sq></div></div>
<script>
  // Post-load async work of variable duration — the shape that actually breaks
  // a fixed timer. Pre-load delay does not (see the doc comment above).
  window.addEventListener('load', function () {
    setTimeout(function () {
      document.body.classList.add('ready');
    }, 100 + Math.floor(Math.random() * 1100));
  });
</script>
''';

Future<HttpServer> _serve(Map<String, String> pages) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    final body = pages[req.uri.path];
    if (body == null) {
      req.response.statusCode = 404;
      await req.response.close();
      return;
    }
    req.response.headers.contentType = ContentType.html;
    // No-store: a cached response would remove the very variance under test.
    req.response.headers.set('cache-control', 'no-store');
    req.response.write(body);
    await req.response.close();
  });
  return server;
}

/// One capture through the OLD path: navigate, then a flat timer.
Future<String> _captureOld(String url, int settleMs) async {
  final client = await CdpClient.launch();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(_viewportW, _viewportH);
    await tab.navigateAndSettle(url, settleMs: settleMs);
    return base64Encode(await tab.screenshot());
  } finally {
    await client.close();
  }
}

/// One capture through the NEW path: navigate, optionally freeze animations,
/// then capture-until-two-match.
Future<({String shot, bool converged, int elapsedMs})> _captureNew(
    String url,
    {required bool freeze}) async {
  final client = await CdpClient.launch();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(_viewportW, _viewportH);
    final s = freeze
        // The shipping candidate: freeze -> floor -> loop -> freeze -> loop.
        ? await tab.navigateAndSettleForCapture(url, settleMs: 1500)
        // Step 7 in isolation, to show what the loop does and does not fix.
        : await () async {
            await tab.navigate(url);
            final r = await tab.settleUntilStable();
            return (
              elapsedMs: r.elapsedMs,
              converged: r.converged,
              frozen: <String, int>{},
              screenshots: r.captures,
              frozenLate: <String, int>{},
            );
          }();
    return (
      shot: base64Encode(await tab.screenshot()),
      converged: s.converged,
      elapsedMs: s.elapsedMs,

    );
  } finally {
    await client.close();
  }
}

class _Arm {
  final shots = <String>[];
  final errors = <String>[];
  var timeouts = 0;
  final elapsed = <int>[];

  int get distinct => shots.toSet().length;
  // -1, not 0: an arm that captured nothing must never read as "1 distinct,
  // perfectly stable". A poison value forces the report to show ERROR.
  int get verdict => shots.length < _n ? -1 : distinct;
}

Future<void> main() async {
  final server = await _serve({
    '/static': _staticPage,
    '/animated': _animatedPage,
    '/variable': _variableLoadPage,
  });
  final base = 'http://127.0.0.1:${server.port}';
  final pages = {
    'static': '$base/static',
    'animated': '$base/animated',
    'variable-load': '$base/variable',
  };

  final old = <String, _Arm>{};
  final neu = <String, _Arm>{};
  final frz = <String, _Arm>{};

  try {
    for (final entry in pages.entries) {
      stdout.writeln('capturing ${entry.key} ...');
      final o = _Arm(), n = _Arm(), f = _Arm();
      for (var i = 0; i < _n; i++) {
        try {
          o.shots.add(await _captureOld(entry.value, 1500));
        } catch (e) {
          o.errors.add('$e');
        }
        for (final (arm, freeze) in [(n, false), (f, true)]) {
          try {
            final r = await _captureNew(entry.value, freeze: freeze);
            arm.shots.add(r.shot);
            arm.elapsed.add(r.elapsedMs);
            if (!r.converged) arm.timeouts++;
          } catch (e) {
            arm.errors.add('$e');
          }
        }
      }
      old[entry.key] = o;
      neu[entry.key] = n;
      frz[entry.key] = f;
    }
  } finally {
    await server.close(force: true);
  }

  // ── control first: did the probe reproduce the defect at all? ──────────
  final controlOld = old['variable-load']!;
  final controlOk = controlOld.verdict >= 2;
  stdout.writeln('');
  stdout.writeln('CONTROL — old path on variable-load must be NONDETERMINISTIC');
  stdout.writeln('  distinct images: ${controlOld.verdict} '
      '(samples ${controlOld.shots.length}/$_n)  '
      '=> ${controlOk ? "REPRODUCED" : "NOT REPRODUCED"}');
  if (!controlOk) {
    stdout.writeln('  !! The defect did not reproduce on this machine/run.');
    stdout.writeln('  !! Every NEW-column result below is therefore MEANINGLESS:');
    stdout.writeln('  !! "1 distinct" cannot be distinguished from "nothing to fix".');
  }

  String cell(_Arm a, {bool withTime = false}) {
    if (a.verdict < 0) return 'ERROR ${a.shots.length}/$_n';
    final t = withTime && a.elapsed.isNotEmpty
        ? ' ~${(a.elapsed.reduce((x, y) => x + y) / a.elapsed.length).round()}ms'
        : '';
    final to = a.timeouts > 0 ? ' TO×${a.timeouts}' : '';
    return '${a.verdict} distinct$t$to';
  }

  stdout.writeln('');
  stdout.writeln('page            | OLD flat 1500ms | NEW loop only        '
      '| NEW freeze+loop');
  stdout.writeln('----------------|-----------------|----------------------'
      '|----------------------');
  for (final k in pages.keys) {
    stdout.writeln('${k.padRight(15)} | ${cell(old[k]!).padRight(15)} '
        '| ${cell(neu[k]!, withTime: true).padRight(20)} '
        '| ${cell(frz[k]!, withTime: true)}');
  }

  stdout.writeln('');
  for (final k in pages.keys) {
    for (final e in [...old[k]!.errors, ...neu[k]!.errors, ...frz[k]!.errors]) {
      stdout.writeln('error on $k: $e');
    }
  }

  // The shipping candidate is freeze+loop, so that is the arm the verdict
  // judges. It has to fix BOTH defects the old path shows.
  final fixesVariable = controlOk && frz['variable-load']!.verdict == 1;
  final fixesAnimated = old['animated']!.verdict > 1 &&
      frz['animated']!.verdict == 1 &&
      frz['animated']!.timeouts == 0;
  stdout.writeln('freeze+loop fixes variable-load: '
      '${fixesVariable ? "YES" : "NO"}  (control reproduced: $controlOk)');
  stdout.writeln('freeze+loop fixes animated:      '
      '${fixesAnimated ? "YES" : "NO"}  (old was '
      '${old['animated']!.verdict} distinct)');
  exitCode = (fixesVariable && fixesAnimated) ? 0 : 1;
}
