// lens_cli — `appbox lens <verb>` dispatcher.
//
// Thin argv→lib adapters: each verb maps to one lib/lens/*.dart function. The
// modules own the capture/compare logic; this file only parses argv, calls the
// function, and maps the outcome to an exit code. JSON evidence goes to stdout
// or `--out <path>` per the lens convention (writeLensJson).
//
// Exit codes: 0 success · 1 fail (assertion/compare/console error) ·
// 2 env/usage (missing tool, bad args, unknown verb). Plan Task 7.
//
// argv style follows the plan's verb table: positional args, then `--flag=value`
// for value flags and bare `--flag` for booleans (--full, --crawl, --html).

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/cdp.dart';
import 'package:appboxd/lens.dart';
import 'package:appboxd/lens/native/adb.dart';
import 'package:appboxd/lens/native/flutter_vm.dart';
import 'package:appboxd/lens/native/sck.dart';
import 'package:appboxd/lens/native/simctl.dart';

const String _usage = '''
Usage: appbox lens <verb> [args]

Web verbs (CDP — each captures at a viewport; console/page errors auto-fail):
  shot <url> <out.png> [w] [h] [settleMs] [--full]
                                      Golden capture (--full = whole page)
  check <url> <out.png> [w] [h] [settle] [--selector=<css>] [--press=<Key>]... [--expect=<js>]
                                      Navigate + assert selector/press/expect + screenshot
  compare <url> <golden.png> [w] [h] [--mode=byte|pixel|ssim] [--threshold=0.95]
                                      Compare live vs golden; exit 1 on fail
  shoot <url> [--rungs=compact,medium,expanded] [--out=dir] [--artifact=dir]
                                      Viewport-ladder golden pass; exit 1 if a
                                      rung has console errors or horizontal overflow
  tokens <url> [w] [h] [--settle=Ms] [--out=path]
                                      Design-token scales (palette/type/spacing/radii)
  dom <url> [--out=path] [--html]     DOMSnapshot (or outerHTML with --html)
  a11y <url> [--out=path]             Accessibility tree
  net <url> [--traceMs=3000] [--out=path]
                                      Network trace (per-request records)
  color <url> <hex> [w] [h] [--region=x,y,w,h] [--threshold=5] [--out=path]
                                      Region color assert (ΔE2000 <= threshold)
  record <url> <out.mp4> [seconds] [fps] [w] [h]
                                      Screencast → mp4 (needs ffmpeg)
  burst <url> <out-dir> [count] [intervalMs] [w] [h]
                                      Rapid screenshot burst → PNG frames
  anim <url> [w] [h] [--out=path]     Scroll-scrubbed easing certification
  flipbook <url> --trigger=<css> [w] [h] [--out=path]
                                      WAAPI animation oracle after a click
  states <url> --trigger=<css>:<click|hover|focus> [--trigger=...] [--out=path]
                                      Before/after interaction states + diff
  skeleton <url> [w] [h] [--out=path] Structural skeleton (lens-skeleton/1)
  skeleton-diff <a.json> <b.json>     Diff two skeletons; exit 1 on deltas
  crawl <baseUrl> [--routes=/a,/b] [--crawl] [--crawl-max=20] [--out=dir]
                                      Multi-route crawl + design-system merge
  ocr <png>                           macOS Vision OCR → text/observations JSON
  text-diff <a.png> <b.png>           OCR + line diff of two PNGs

Native verbs (appbox lens native <family> <verb> …):
  native adb <shot|record|devices|open-url|ui-tree> [--serial=S] …
  native ios <shot|record|devices|open-url|status-bar|appearance> [--udid=U] …
  native macos shot <out.png> [--window-id=N]
  native flutter <screenshot|render|widget|semantics|eval|flag|parse-uri> --uri=<ws> …

Options:
  -h, --help        Print this usage
  --self-test       Run the dispatcher invariant self-check
  --visible         Open a visible Chrome window with a per-verb colored glow
                    during capture (default: headless). Web verbs only; native
                    verbs accept it as a no-op.

Value flags use --name=value; bare flags (--full, --crawl, --html) are boolean.
Exit codes: 0 ok · 1 fail · 2 env/usage.''';

/// Entry point for `appbox lens`. Returns the process exit code.
Future<int> runLensCli(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(_usage);
    return 2;
  }
  // --visible/--glow/--show: open a real (non-headless) Chrome window with a
  // per-verb colored glow during capture. Recognized everywhere; only the CDP
  // (web) verbs actually show a glow — native verbs capture real devices and
  // accept the flag as a no-op.
  if (args.any(_isVisibleFlag)) {
    LensSession.visible = true;
  }
  switch (args.first) {
    case '-h':
    case '--help':
      stdout.writeln(_usage);
      return 0;
    case '--self-test':
      return _selfTest();
    case 'native':
      return _runNative(args.sublist(1));
  }

  final verb = args.first;
  LensSession.verb = verb;
  // Strip the visible flag so it never reaches the per-verb _Args parsers.
  final rest = args.sublist(1).where((t) => !_isVisibleFlag(t)).toList(growable: false);
  final (detail, viewportW, viewportH) = _parseViewport(rest);
  LensSession.detail = detail;
  // Same W/H used for setViewport → size the Chrome window so the emulated
  // content fills the window (in visible mode) and the glow reads as the
  // window glowing. null when the verb has no viewport args.
  LensSession.windowW = viewportW;
  LensSession.windowH = viewportH;
  final a = _Args(rest);
  switch (verb) {
    case 'shot':
      return _shot(a);
    case 'check':
      return _check(a);
    case 'compare':
      return _compare(a);
    case 'shoot':
      return _shoot(a);
    case 'tokens':
      return _tokens(a);
    case 'dom':
      return _dom(a);
    case 'a11y':
      return _a11y(a);
    case 'net':
      return _net(a);
    case 'color':
      return _color(a);
    case 'record':
      return _record(a);
    case 'burst':
      return _burst(a);
    case 'anim':
      return _anim(a);
    case 'flipbook':
      return _flipbook(a);
    case 'states':
      return _states(a);
    case 'skeleton':
      return _skeleton(a);
    case 'skeleton-diff':
      return _skeletonDiff(a);
    case 'crawl':
      return _crawl(a);
    case 'ocr':
      return _ocr(a);
    case 'text-diff':
      return _textDiff(a);
    default:
      stderr.writeln('appbox lens: unknown verb "$verb"');
      stderr.writeln(_usage);
      return 2;
  }
}

// ── argv model ─────────────────────────────────────────────────────

/// True for any of the --visible/--glow/--show aliases (bare boolean flags).
bool _isVisibleFlag(String t) =>
    t == '--visible' || t == '--glow' || t == '--show';

/// Best-effort viewport parse: the first pair of consecutive positionals that
/// look like viewport dimensions. Returns (detail label, w, h) — all null when
/// no plausible WxH pair is present (dom/a11y/net/states/crawl), so the glow
/// pill just shows the verb and the window keeps its default size.
///
/// The same w/h drives LensSession.windowW/windowH (visible-mode window sizing)
/// and the per-verb setViewport call, so the emulated content fills the window.
(String?, int?, int?) _parseViewport(List<String> positional) {
  for (var i = 0; i + 1 < positional.length; i++) {
    final w = int.tryParse(positional[i]);
    final h = int.tryParse(positional[i + 1]);
    if (w != null && h != null && w >= 200 && w <= 5000 && h >= 200 && h <= 5000) {
      return ('${w}x$h', w, h);
    }
  }
  return (null, null, null);
}

/// Manual argv parser: positionals + `--name=value` (or bare `--flag`).
/// Repeated value flags accumulate in [all]; [value] returns the first.
class _Args {
  _Args(List<String> tokens)
      : positional = [],
        _values = {},
        _multi = {} {
    for (final t in tokens) {
      if (t.startsWith('--')) {
        final eq = t.indexOf('=');
        final name = eq > 0 ? t.substring(2, eq) : t.substring(2);
        final value = eq > 0 ? t.substring(eq + 1) : '';
        _values.putIfAbsent(name, () => value);
        _multi.putIfAbsent(name, () => []).add(value);
      } else {
        positional.add(t);
      }
    }
  }

  final List<String> positional;
  final Map<String, String> _values;
  final Map<String, List<String>> _multi;

  bool has(String n) => _values.containsKey(n);
  String? value(String n) => _values[n];
  List<String> all(String n) => _multi[n] ?? const [];
  int? intVal(String n) => _values[n] == null ? null : int.tryParse(_values[n]!);
  double? doubleVal(String n) =>
      _values[n] == null ? null : double.tryParse(_values[n]!);

  /// Positional [i] as int, or [fallback] when absent / unparseable.
  int intAt(int i, int fallback) =>
      i < positional.length ? (int.tryParse(positional[i]) ?? fallback) : fallback;
}

int _usageErr(String syntax) {
  stderr.writeln('appbox lens: usage: $syntax');
  return 2;
}

/// Format a JSON-result map, write it to `--out` (lens convention) or stdout,
/// then return 0 when `certified` is true, else 1 (console/page errors).
int _emitJson(Map<String, dynamic> result, String? out, String verb) {
  final json = const JsonEncoder.withIndent('  ').convert(result);
  if (out == null) {
    stdout.writeln(json);
  } else {
    writeLensJson(out, json);
  }
  final certified = result['certified'] == true;
  stdout.writeln('lens $verb: ${certified ? 'PASS' : 'FAIL'}');
  return certified ? 0 : 1;
}

LensMode _parseMode(String? s) {
  switch (s) {
    case 'pixel':
      return LensMode.pixel;
    case 'ssim':
      return LensMode.ssim;
    case 'byte':
    case null:
      return LensMode.byte;
    default:
      stderr.writeln('lens compare: unknown mode "$s", falling back to byte');
      return LensMode.byte;
  }
}

List<int> _hexToRgb(String hex) {
  final h = hex.replaceFirst('#', '');
  if (h.length < 6) throw FormatException('hex must be #rrggbb: $hex');
  return [
    int.parse(h.substring(0, 2), radix: 16),
    int.parse(h.substring(2, 4), radix: 16),
    int.parse(h.substring(4, 6), radix: 16),
  ];
}

// ── web verbs ──────────────────────────────────────────────────────

Future<int> _shot(_Args a) async {
  if (a.positional.length < 2) {
    return _usageErr('shot <url> <out.png> [w] [h] [settleMs] [--full]');
  }
  final url = a.positional[0];
  final out = a.positional[1];
  final w = a.intAt(2, 1280);
  final h = a.intAt(3, 800);
  final settle = a.intAt(4, 1500);
  await captureGolden(url, w, h,
      goldenPath: out, settleMs: settle, fullPage: a.has('full'));
  stdout.writeln(
      'lens shot: $url -> $out (${w}x$h${a.has('full') ? ', full page' : ''})');
  return 0;
}

Future<int> _check(_Args a) async {
  if (a.positional.length < 2) {
    return _usageErr('check <url> <out.png> [w] [h] [settle] '
        '[--selector=<css>] [--press=<Key>]... [--expect=<js>]');
  }
  return _lensCheck(
    a.positional[0],
    a.positional[1],
    a.intAt(2, 1280),
    a.intAt(3, 800),
    a.intAt(4, 1500),
    selector: a.value('selector'),
    presses: a.all('press'),
    expect: a.value('expect'),
  );
}

/// Ports tool/lens_check.dart verbatim: navigate, assert selector/press/expect,
/// screenshot. Console/page errors are always a failure (lens doctrine).
Future<int> _lensCheck(
  String url,
  String out,
  int w,
  int h,
  int settleMs, {
  String? selector,
  List<String> presses = const [],
  String? expect,
}) async {
  final failures = <String>[];
  final client = await CdpClient.launch();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(w, h);
    await tab.navigateAndSettle(url, settleMs: settleMs);

    if (selector != null) {
      final found = await tab.evaluate('!!document.querySelector(${_js(selector)})');
      if (found != true) failures.add('selector not found: $selector');
    }
    for (final k in presses) {
      await tab.key(k);
      await Future.delayed(const Duration(milliseconds: 250));
    }
    if (presses.isNotEmpty) {
      await Future.delayed(const Duration(milliseconds: 500));
    }
    if (expect != null) {
      final ok = await tab.evaluate(expect);
      if (ok != true) failures.add('expect not truthy: $expect (got $ok)');
    }
    final errors = [...tab.consoleErrors, ...tab.pageErrors];
    if (errors.isNotEmpty) {
      failures.add('${errors.length} console/page error(s): ${errors.first}');
    }
    final png = await tab.screenshot();
    final f = File(out);
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(png);
  } finally {
    await client.close();
  }
  if (failures.isNotEmpty) {
    stderr.writeln('lens check FAILED: $url\n  ${failures.join('\n  ')}');
    return 1;
  }
  stdout.writeln('lens check ok: $url -> $out (${w}x$h)');
  return 0;
}

String _js(String s) => "'${s.replaceAll('\\', '\\\\').replaceAll("'", "\\'")}'";

Future<int> _compare(_Args a) async {
  if (a.positional.length < 2) {
    return _usageErr(
        'compare <url> <golden.png> [w] [h] [--mode=byte|pixel|ssim] [--threshold=0.95]');
  }
  final r = await compareGolden(
    a.positional[0],
    a.positional[1],
    a.intAt(2, 1280),
    a.intAt(3, 800),
    mode: _parseMode(a.value('mode')),
    threshold: a.doubleVal('threshold') ?? 0.95,
  );
  stdout.writeln('lens compare: ${r.passed ? 'PASS' : 'FAIL'} — ${r.note}');
  return r.passed ? 0 : 1;
}

Future<int> _tokens(_Args a) async {
  if (a.positional.isEmpty) {
    return _usageErr('tokens <url> [w] [h] [--settle=Ms] [--out=path]');
  }
  final result = await extractTokens(
    a.positional[0],
    a.intAt(1, 1280),
    a.intAt(2, 800),
    settleMs: a.intVal('settle') ?? 1500,
  );
  return _emitJson(result, a.value('out'), 'tokens');
}

Future<int> _dom(_Args a) async {
  if (a.positional.isEmpty) {
    return _usageErr('dom <url> [--out=path] [--html]');
  }
  final url = a.positional[0];
  final out = a.value('out');
  if (a.has('html')) {
    final html = await extractOuterHtml(url);
    if (out == null) {
      stdout.writeln(html);
    } else {
      writeLensJson(out, html);
    }
    stdout.writeln('lens dom: PASS (outerHTML)');
    return 0;
  }
  final result = await extractDom(url);
  return _emitJson(result, out, 'dom');
}

Future<int> _a11y(_Args a) async {
  if (a.positional.isEmpty) {
    return _usageErr('a11y <url> [--out=path]');
  }
  final result = await extractA11y(a.positional[0]);
  return _emitJson(result, a.value('out'), 'a11y');
}

Future<int> _net(_Args a) async {
  if (a.positional.isEmpty) {
    return _usageErr('net <url> [--traceMs=3000] [--out=path]');
  }
  final result = await traceNet(a.positional[0], traceMs: a.intVal('traceMs') ?? 3000);
  return _emitJson(result, a.value('out'), 'net');
}

Future<int> _color(_Args a) async {
  if (a.positional.length < 2) {
    return _usageErr(
        'color <url> <hex> [w] [h] [--region=x,y,w,h] [--threshold=5] [--out=path]');
  }
  final expected = _hexToRgb(a.positional[1]);
  final png = await captureGolden(a.positional[0], a.intAt(2, 1280), a.intAt(3, 800));
  final im = decodePng(png);
  List<double> mean;
  final region = a.value('region');
  if (region != null) {
    final parts = region.split(',').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((p) => p == null)) {
      return _usageErr('--region=x,y,w,h');
    }
    mean = regionMeanLab(im, parts[0]!, parts[1]!, parts[2]!, parts[3]!);
  } else {
    mean = regionMeanLab(im, 0, 0, im.width, im.height);
  }
  final expLab = rgbToLab(expected[0], expected[1], expected[2]);
  final delta =
      deltaE2000Lab(mean[0], mean[1], mean[2], expLab[0], expLab[1], expLab[2]);
  final threshold = a.doubleVal('threshold') ?? 5.0;
  final passed = delta <= threshold;
  final result = {
    'url': a.positional[0],
    'expected': a.positional[1],
    'regionMeanLab': mean,
    'deltaE2000': delta,
    'threshold': threshold,
    'passed': passed,
  };
  final json = const JsonEncoder.withIndent('  ').convert(result);
  if (a.value('out') == null) {
    stdout.writeln(json);
  } else {
    writeLensJson(a.value('out')!, json);
  }
  stdout.writeln(
      'lens color: ${passed ? 'PASS' : 'FAIL'} — ΔE2000 ${delta.toStringAsFixed(2)} (threshold $threshold)');
  return passed ? 0 : 1;
}

Future<int> _skeleton(_Args a) async {
  if (a.positional.isEmpty) {
    return _usageErr('skeleton <url> [w] [h] [--out=path]');
  }
  final result = await captureSkeleton(a.positional[0],
      width: a.intAt(1, 390), height: a.intAt(2, 844));
  return _emitJson(result, a.value('out'), 'skeleton');
}

Future<int> _skeletonDiff(_Args a) async {
  if (a.positional.length < 2) {
    return _usageErr('skeleton-diff <a.json> <b.json>');
  }
  final aMap =
      jsonDecode(File(a.positional[0]).readAsStringSync()) as Map<String, dynamic>;
  final bMap =
      jsonDecode(File(a.positional[1]).readAsStringSync()) as Map<String, dynamic>;
  final result = diffSkeleton(aMap, bMap);
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
  final certified = result['certified'] == true;
  final n = (result['deltas'] as List).length;
  stdout.writeln('lens skeleton-diff: ${certified ? 'PASS' : 'FAIL'} — $n delta(s)');
  return certified ? 0 : 1;
}

Future<int> _states(_Args a) async {
  if (a.positional.isEmpty) {
    return _usageErr(
        'states <url> --trigger=<css>:<click|hover|focus> [--trigger=...] [--out=path]');
  }
  final raw = a.all('trigger');
  if (raw.isEmpty) {
    return _usageErr('at least one --trigger=<css>:<action> is required');
  }
  final triggers = <StateTrigger>[];
  for (final t in raw) {
    final colon = t.lastIndexOf(':');
    if (colon <= 0) {
      return _usageErr('trigger must be <css>:<click|hover|focus> (got "$t")');
    }
    triggers.add(StateTrigger(t.substring(0, colon), t.substring(colon + 1)));
  }
  final result = await captureStates(a.positional[0], triggers: triggers);
  return _emitJson(result, a.value('out'), 'states');
}

Future<int> _anim(_Args a) async {
  if (a.positional.isEmpty) {
    return _usageErr('anim <url> [w] [h] [--out=path]');
  }
  final result =
      await captureScrollAnim(a.positional[0], width: a.intAt(1, 390), height: a.intAt(2, 844));
  return _emitJson(result, a.value('out'), 'anim');
}

Future<int> _flipbook(_Args a) async {
  final trigger = a.value('trigger');
  if (a.positional.isEmpty || trigger == null) {
    return _usageErr('flipbook <url> --trigger=<css> [w] [h] [--out=path]');
  }
  final result = await captureFlipbook(a.positional[0],
      triggerSelector: trigger, width: a.intAt(1, 390), height: a.intAt(2, 844));
  return _emitJson(result, a.value('out'), 'flipbook');
}

Future<int> _record(_Args a) async {
  if (a.positional.length < 2) {
    return _usageErr('record <url> <out.mp4> [seconds] [fps] [w] [h]');
  }
  try {
    await recordVideo(
      a.positional[0],
      a.positional[1],
      width: a.intAt(4, 390),
      height: a.intAt(5, 844),
      seconds: a.intAt(2, 5),
      fps: a.intAt(3, 15),
    );
    stdout.writeln('lens record: ${a.positional[0]} -> ${a.positional[1]}');
    return 0;
  } on StateError catch (e) {
    stderr.writeln('lens record: ${e.message}');
    // ffmpeg missing / page never painted → env(2); a failed encode → fail(1).
    return e.message.startsWith('ffmpeg not found') ||
            e.message.contains('no frames')
        ? 2
        : 1;
  }
}

Future<int> _burst(_Args a) async {
  if (a.positional.length < 2) {
    return _usageErr('burst <url> <out-dir> [count] [intervalMs] [w] [h]');
  }
  final outDir = a.positional[1];
  final frames = await burstFrames(
    a.positional[0],
    width: a.intAt(4, 390),
    height: a.intAt(5, 844),
    count: a.intAt(2, 5),
    intervalMs: a.intAt(3, 100),
  );
  Directory(outDir).createSync(recursive: true);
  final pad = frames.length.toString().length;
  for (var i = 0; i < frames.length; i++) {
    File('$outDir/frame_${i.toString().padLeft(pad, '0')}.png')
        .writeAsBytesSync(frames[i]);
  }
  stdout.writeln('lens burst: ${frames.length} frame(s) -> $outDir');
  return 0;
}

Future<int> _crawl(_Args a) async {
  if (a.positional.isEmpty) {
    return _usageErr('crawl <baseUrl> [--routes=/a,/b] [--crawl] [--crawl-max=20] [--out=dir]');
  }
  final routes = a
      .value('routes')
      ?.split(',')
      .where((s) => s.isNotEmpty)
      .toList() ??
      const ['/'];
  final result = await crawlSite(
    a.positional[0],
    routes: routes,
    crawl: a.has('crawl'),
    crawlMax: a.intVal('crawl-max') ?? 20,
    outDir: a.value('out'),
  );
  final merged = await mergeDesignSystem(result.outDir);
  stdout.writeln('lens crawl: ${result.routes.length} route(s) -> ${result.outDir} '
      '(${(merged['palette'] as List).length} palette clusters, ${result.skipped.length} skipped)');
  // Every route skipped = nothing certified.
  return result.routes.isNotEmpty ? 0 : 1;
}

Future<int> _ocr(_Args a) async {
  if (a.positional.isEmpty) {
    return _usageErr('ocr <png>');
  }
  try {
    final result = await ocrText(a.positional[0]);
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
    return 0;
  } on LensNativeException catch (e) {
    stderr.writeln('lens ocr: $e');
    return 2; // missing swiftc / Vision helper / permission
  }
}

Future<int> _textDiff(_Args a) async {
  if (a.positional.length < 2) {
    return _usageErr('text-diff <a.png> <b.png>');
  }
  try {
    final lines = await textDiffPngs(a.positional[0], a.positional[1]);
    for (final l in lines) {
      stdout.writeln(l);
    }
    return 0;
  } on LensNativeException catch (e) {
    stderr.writeln('lens text-diff: $e');
    return 2;
  }
}

// ── shoot: viewport-ladder pass ────────────────────────────────────

/// One rung of the ladder: width + height. Names resolve via ladder.json.
class _Rung {
  const _Rung(this.name, this.width, this.height);
  final String name;
  final int width;
  final int height;
}

/// The built-in ladder (mirrors skills/appbox-designer/runtime/ladder.json).
/// Used when the file is not found, so `shoot` works without the skills tree.
const List<_Rung> _defaultLadder = [
  _Rung('compact', 390, 844),
  _Rung('medium', 744, 1133),
  _Rung('expanded', 1280, 832),
];

/// Resolve the active rungs: --rungs > $APPBOX_LADDER > --artifact
/// _d_meta.json .ladder > ladder.json (all rungs). Each item is a name from
/// the ladder or a raw width (paired with a default 4:3-ish height).
List<_Rung> _resolveRungs(_Args a, String repoRoot) {
  final ladder = _loadLadder(repoRoot);
  List<String>? requested;
  final flag = a.value('rungs');
  if (flag != null) {
    requested = flag.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  } else if (Platform.environment['APPBOX_LADDER'] != null &&
      Platform.environment['APPBOX_LADDER']!.isNotEmpty) {
    requested = Platform.environment['APPBOX_LADDER']!
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  } else {
    final artifactDir = a.value('artifact');
    if (artifactDir != null) {
      final meta = File('$artifactDir/_d_meta.json');
      if (meta.existsSync()) {
        try {
          final doc = jsonDecode(meta.readAsStringSync()) as Map<String, dynamic>;
          final raw = doc['ladder'];
          if (raw is String && raw.isNotEmpty) {
            requested = raw.split(',').map((s) => s.trim()).toList();
          }
        } on FormatException {
          // malformed meta — fall through to full ladder
        }
      }
    }
  }
  requested ??= [for (final r in ladder) r.name];
  return [for (final spec in requested) _matchRung(spec, ladder)];
}

/// Match a rung by name; a bare integer is a raw width paired with a default
/// height (the medium rung's height, a sane mobile/tablet viewport).
_Rung _matchRung(String spec, List<_Rung> ladder) {
  final byName = ladder.firstWhere(
    (r) => r.name == spec,
    orElse: () => throw StateError('no such rung: $spec'),
  );
  return byName;
}

/// Load the ladder from skills/appbox-designer/runtime/ladder.json, falling
/// back to [_defaultLadder] when the file is absent or malformed.
List<_Rung> _loadLadder(String repoRoot) {
  final f = File('$repoRoot/skills/appbox-designer/runtime/ladder.json');
  if (!f.existsSync()) return List<_Rung>.unmodifiable(_defaultLadder);
  try {
    final doc = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final rungs = doc['rungs'] as Map<String, dynamic>?;
    if (rungs == null) return List<_Rung>.unmodifiable(_defaultLadder);
    final out = <_Rung>[];
    for (final entry in rungs.entries) {
      final r = entry.value as Map<String, dynamic>;
      out.add(_Rung(entry.key, (r['width'] as num).toInt(), (r['height'] as num).toInt()));
    }
    return out;
  } on Exception {
    return List<_Rung>.unmodifiable(_defaultLadder);
  }
}

String _findRepoRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}/config/appbox.config.json').existsSync()) return dir.path;
    final parent = dir.parent;
    if (parent.path == dir.path) return Directory.current.path;
    dir = parent;
  }
}

Future<int> _shoot(_Args a) async {
  if (a.positional.isEmpty) {
    return _usageErr('shoot <url> [--rungs=compact,medium,expanded] [--out=dir] [--artifact=dir]');
  }
  final url = a.positional[0];
  final List<_Rung> rungs;
  try {
    rungs = _resolveRungs(a, _findRepoRoot());
  } on StateError catch (e) {
    stderr.writeln('lens shoot: $e');
    return 2;
  }
  if (rungs.isEmpty) {
    stderr.writeln('lens shoot: no rungs resolved');
    return 2;
  }
  final outDir = a.value('out') ??
      Directory.systemTemp.createTempSync('lens-shoot').path;
  Directory(outDir).createSync(recursive: true);

  var problems = 0;
  final perRung = <Map<String, dynamic>>[];
  for (final rung in rungs) {
    final client = await CdpClient.launch();
    try {
      final tab = await client.newTab();
      await tab.enable();
      await tab.setViewport(rung.width, rung.height);
      await tab.navigateAndSettle(url);
      final errors = [...tab.consoleErrors, ...tab.pageErrors];
      final overflow =
          (await tab.evaluate('document.documentElement.scrollWidth > '
              'document.documentElement.clientWidth')) as bool? ??
              false;
      final png = await tab.screenshot();
      final pngPath = '$outDir/${rung.name}_${rung.width}.png';
      File(pngPath).writeAsBytesSync(png);
      final clean = errors.isEmpty && !overflow;
      if (!clean) problems++;
      perRung.add({
        'name': rung.name,
        'width': rung.width,
        'height': rung.height,
        'consoleErrors': errors.length,
        'overflow': overflow,
        'clean': clean,
        'png': pngPath,
      });
      stdout.writeln(
          'lens shoot ${rung.name} (${rung.width}px): ${clean ? 'ok' : 'PROBLEMS'} -> $pngPath');
    } finally {
      await client.close();
    }
  }
  writeLensJson('$outDir/shoot.json',
      const JsonEncoder.withIndent('  ').convert({'url': url, 'rungs': perRung}));
  stdout.writeln(
      'lens shoot: ${perRung.length} rung(s), $problems problem(s) -> $outDir/shoot.json');
  return problems == 0 ? 0 : 1;
}

// ── native ────────────────────────────────────────────────────────

Future<int> _runNative(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('appbox lens native: missing <family> (adb|ios|macos|flutter)');
    stderr.writeln(_usage);
    return 2;
  }
  switch (args.first) {
    case 'adb':
      return _nativeAdb(_Args(args.sublist(1)));
    case 'ios':
      return _nativeIos(_Args(args.sublist(1)));
    case 'macos':
      return _nativeMacos(_Args(args.sublist(1)));
    case 'flutter':
      return _nativeFlutter(_Args(args.sublist(1)));
    default:
      stderr.writeln('appbox lens native: unknown family "${args.first}"');
      return 2;
  }
}

Future<int> _nativeAdb(_Args a) async {
  if (a.positional.isEmpty) {
    stderr.writeln('appbox lens native adb: missing verb '
        '(shot|record|devices|open-url|ui-tree)');
    return 2;
  }
  final verb = a.positional.first;
  final port = LensAdb(serial: a.value('serial'), env: Platform.environment);
  try {
    switch (verb) {
      case 'devices':
        stdout.writeln(
            const JsonEncoder.withIndent('  ').convert(await port.devices()));
        return 0;
      case 'shot':
        if (a.positional.length < 2) {
          return _usageErr('native adb shot <out.png> [--serial=S]');
        }
        await port.shot(a.positional[1]);
        stdout.writeln('lens native adb shot -> ${a.positional[1]}');
        return 0;
      case 'record':
        if (a.positional.length < 2) {
          return _usageErr('native adb record <out.mp4> [seconds]');
        }
        await port.record(a.positional[1], seconds: a.intAt(2, 10));
        stdout.writeln('lens native adb record -> ${a.positional[1]}');
        return 0;
      case 'open-url':
        if (a.positional.length < 2) {
          return _usageErr('native adb open-url <url>');
        }
        await port.openUrl(a.positional[1]);
        stdout.writeln('lens native adb open-url: ${a.positional[1]}');
        return 0;
      case 'ui-tree':
        stdout.writeln(
            const JsonEncoder.withIndent('  ').convert(await port.uiTree()));
        return 0;
      default:
        stderr.writeln('appbox lens native adb: unknown verb "$verb"');
        return 2;
    }
  } on LensNativeException catch (e) {
    stderr.writeln('lens native adb: $e');
    return 2;
  }
}

Future<int> _nativeIos(_Args a) async {
  if (a.positional.isEmpty) {
    stderr.writeln(
        'appbox lens native ios: missing verb (shot|record|devices|open-url|status-bar|appearance)');
    return 2;
  }
  final verb = a.positional.first;
  final sim = LensSimctl(udid: a.value('udid') ?? 'booted');
  try {
    switch (verb) {
      case 'devices':
        stdout.writeln(
            const JsonEncoder.withIndent('  ').convert(await sim.devices()));
        return 0;
      case 'shot':
        if (a.positional.length < 2) {
          return _usageErr('native ios shot <out.png> [--udid=U]');
        }
        await sim.shot(a.positional[1]);
        stdout.writeln('lens native ios shot -> ${a.positional[1]}');
        return 0;
      case 'record':
        if (a.positional.length < 2) {
          return _usageErr('native ios record <out.mp4> [seconds]');
        }
        await sim.record(a.positional[1], seconds: a.intAt(2, 10));
        stdout.writeln('lens native ios record -> ${a.positional[1]}');
        return 0;
      case 'open-url':
        if (a.positional.length < 2) {
          return _usageErr('native ios open-url <url>');
        }
        await sim.openUrl(a.positional[1]);
        stdout.writeln('lens native ios open-url: ${a.positional[1]}');
        return 0;
      case 'status-bar':
        // positional[1] = override|clear (default override — the golden chrome).
        if (a.positional.length > 1 && a.positional[1] == 'clear') {
          await sim.statusBarClear();
        } else {
          await sim.statusBarOverride();
        }
        stdout.writeln('lens native ios status-bar: ok');
        return 0;
      case 'appearance':
        if (a.positional.length < 2) {
          return _usageErr('native ios appearance <dark|light>');
        }
        await sim.appearance(a.positional[1]);
        stdout.writeln('lens native ios appearance: ${a.positional[1]}');
        return 0;
      default:
        stderr.writeln('appbox lens native ios: unknown verb "$verb"');
        return 2;
    }
  } on LensNativeException catch (e) {
    stderr.writeln('lens native ios: $e');
    return 2;
  }
}

Future<int> _nativeMacos(_Args a) async {
  if (a.positional.isEmpty) {
    stderr.writeln('appbox lens native macos: missing verb (only "shot")');
    return 2;
  }
  final verb = a.positional.first;
  if (verb != 'shot') {
    stderr.writeln('appbox lens native macos: only "shot" is supported (got "$verb")');
    return 2;
  }
  if (a.positional.length < 2) {
    return _usageErr('native macos shot <out.png> [--window-id=N]');
  }
  try {
    await LensSck().shot(a.positional[1], windowId: a.intVal('window-id'));
    stdout.writeln('lens native macos shot -> ${a.positional[1]}');
    return 0;
  } on LensNativeException catch (e) {
    stderr.writeln('lens native macos: $e');
    return 2;
  }
}

Future<int> _nativeFlutter(_Args a) async {
  if (a.positional.isEmpty) {
    stderr.writeln('appbox lens native flutter: missing verb '
        '(screenshot|render|widget|semantics|eval|flag|parse-uri)');
    return 2;
  }
  final verb = a.positional.first;

  // parse-uri is the one pure verb — no VM connection.
  if (verb == 'parse-uri') {
    if (a.positional.length < 2) {
      return _usageErr('native flutter parse-uri <text-or-file>');
    }
    final arg = a.positional[1];
    final text = File(arg).existsSync() ? File(arg).readAsStringSync() : arg;
    final uri = parseVmServiceUri(text);
    if (uri == null) {
      stderr.writeln('no VM service URI found');
      return 1;
    }
    stdout.writeln(uri);
    return 0;
  }

  final uri = a.value('uri');
  if (uri == null) {
    return _usageErr('native flutter $verb needs --uri=<wsUri> (or use parse-uri)');
  }
  try {
    final vm = await FlutterVm.connect(uri);
    try {
      switch (verb) {
        case 'screenshot':
          if (a.positional.length < 2) {
            return _usageErr('native flutter screenshot --uri=<ws> <out.png>');
          }
          final png = await vm.screenshot();
          final f = File(a.positional[1])
            ..parent.createSync(recursive: true)
            ..writeAsBytesSync(png);
          stdout.writeln('lens native flutter screenshot -> ${f.path}');
          return 0;
        case 'render':
          stdout.writeln(await vm.dumpRenderTree());
          return 0;
        case 'widget':
          stdout.writeln(await vm.dumpWidgetTree());
          return 0;
        case 'semantics':
          stdout.writeln(await vm.dumpSemanticsTree());
          return 0;
        case 'eval':
          if (a.positional.length < 2) {
            return _usageErr('native flutter eval --uri=<ws> <expr>');
          }
          stdout.writeln(await vm.evalDart(a.positional[1]));
          return 0;
        case 'flag':
          if (a.positional.length < 3) {
            return _usageErr('native flutter flag --uri=<ws> <ext> <on|off>');
          }
          await vm.setFlag(a.positional[1], a.positional[2] == 'on');
          stdout.writeln('lens native flutter flag: ${a.positional[1]}=${a.positional[2]}');
          return 0;
        default:
          stderr.writeln('appbox lens native flutter: unknown verb "$verb"');
          return 2;
      }
    } finally {
      await vm.dispose();
    }
  } on LensVmException catch (e) {
    stderr.writeln('lens native flutter: $e');
    return 2;
  }
}

// ── self-test ─────────────────────────────────────────────────────

/// Dispatcher invariants — pure, no Chrome/toolchain. Mirrors the negative
/// self-test doctrine (R5): a check that has never failed is not a check.
int _selfTest() {
  try {
    // 1. _Args parses positionals, --name=value, and bare booleans.
    final a = _Args(['url', 'out.png', '390', '--full', '--mode=ssim', '--trigger=a:click', '--trigger=b:hover']);
    if (a.positional.length != 3) throw '_Args: positional count';
    if (!a.has('full')) throw '_Args: boolean flag';
    if (a.value('mode') != 'ssim') throw '_Args: value flag';
    if (a.all('trigger').length != 2) throw '_Args: repeated flag';
    if (a.intAt(2, 0) != 390) throw '_Args: intAt';
    // 2. mode parse round-trip + fallback.
    if (_parseMode('pixel') != LensMode.pixel) throw 'mode pixel';
    if (_parseMode('garbage') != LensMode.byte) throw 'mode fallback';
    // 3. skeleton-diff self-diff is clean; a real delta is flagged (pure).
    final sk = {
      'nodes': [
        {'id': 'a', 'bbox': [0, 0, 10, 10], 'z': 0}
      ]
    };
    if (diffSkeleton(sk, sk)['certified'] != true) throw 'self-diff not clean';
    final sk2 = {
      'nodes': [
        {'id': 'b', 'bbox': [0, 0, 10, 10], 'z': 0}
      ]
    };
    if (diffSkeleton(sk, sk2)['certified'] == true) throw 'delta not flagged';
    // 4. hex parse.
    final rgb = _hexToRgb('#ff8800');
    if (rgb[0] != 255 || rgb[1] != 136 || rgb[2] != 0) throw 'hex parse: $rgb';
    // 5. parseVmServiceUri extracts wsUri from an app.debugPort event.
    final uri = parseVmServiceUri(
        '{"event":"app.debugPort","params":{"wsUri":"ws://127.0.0.1:9/xyz/"}}');
    if (uri != 'ws://127.0.0.1:9/xyz/') throw 'vm uri parse: $uri';
  } catch (e) {
    stderr.writeln('lens self-test: FAIL: $e');
    return 2;
  }
  stdout.writeln('lens self-test: PASS');
  return 0;
}
