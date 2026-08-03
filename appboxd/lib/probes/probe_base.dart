// The design-probe harness, on the one browser engine (`cdp.dart`).
//
// This is the Dart port of `tools/_probe_base.mjs`. Its target rules are not
// style — they are the residue of two incidents, quoted below from the file
// they came from so the next reader does not have to go find it:
//
//   "every probe used to resolve its target as
//      const BASE = process.env.APPBOX_BASE || 'http://localhost:4319';
//    and NONE of them read process.argv. So `node tools/probe-x.mjs --port 4335`
//    silently ran against 4319 — the shared dev server — while the operator
//    believed it was hitting an isolated instance they had just booted. That
//    cost a real incident: probes ran flow-mutating requests against a live
//    project, and a whole root-cause investigation was built on runs that had
//    never targeted the server they claimed to."
//
//   "probe-shell-chrome.mjs's flow-move (section F) and probe-inspect.mjs both
//    drive real POSTs into whatever project the target server has bound as its
//    projectRoot. […] that has corrupted real `portalo` data three times,
//    because the only defense was an operator remembering to copy the project
//    and pass --base every time."
//
// The three target rules, in the original's order of importance:
//   1. An argument that cannot be honoured is a HARD ERROR, never a no-op.
//      A flag that looks supported and does nothing is worse than no flag.
//   2. The resolved base is PRINTED before any check runs, so a misdirected
//      run is visible in the first line of output instead of invisible.
//   3. --base / --port beat APPBOX_BASE, which beats the 4319 default.
//
// Note on rule 3: the default is kept, and kept LOUD (see the NOTE line in
// [resolveTarget]). "No silent default-port fallback" is the law; a fallback
// that announces itself is what the original shipped, and parity depends on
// it staying that way.
//
// Structure follows the same split lens_cli.dart uses: the rules are pure
// functions returning a verdict ([resolveTarget], [disposableVerdict]) and the
// CLI maps the verdict to output and an exit code. Nothing here calls exit(),
// so both rules are testable without a subprocess — see
// `test/probe_base_test.dart`.

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/cdp.dart';

/// The shared dev server. Rule 3's last resort — loud, never silent.
const String kDefaultBase = 'http://localhost:4319';

/// Disposable means the bound project's name ends in `-probe` or `-test`.
final RegExp _disposableRe = RegExp(r'-(?:probe|test)$');

const Set<String> _knownTargetFlags = {'--base', '--port', '-b', '-p'};

// ── rule 1 + rule 3: resolving the target ────────────────────────────────

/// The outcome of target resolution: either a [base] to run against, or an
/// [error] explaining why the run is refused. Never both.
class ProbeTarget {
  /// Resolved base URL, null when [error] is set.
  final String? base;

  /// How it was resolved: `--base`, `--port`, `APPBOX_BASE` or `default`.
  final String via;

  /// Lines to print before any check runs (rule 2).
  final List<String> notes;

  /// Usage failure. Non-null means refuse to run, exit 2.
  final String? error;

  const ProbeTarget._(this.base, this.via, this.notes, this.error);

  bool get ok => error == null;
}

/// Resolve the probe target from [args] and [env], per rules 1 and 3.
///
/// Pure: returns the messages rather than printing them, so a test can assert
/// on the refusal as easily as on the happy path.
ProbeTarget resolveTarget(List<String> args, {Map<String, String>? env}) {
  final environment = env ?? Platform.environment;
  String? base;
  String? port;

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (!a.startsWith('-')) continue;
    final eq = a.indexOf('=');
    final key = eq == -1 ? a : a.substring(0, eq);
    final inline = eq == -1 ? null : a.substring(eq + 1);
    if (!_knownTargetFlags.contains(key)) {
      // Rule 1. Silently ignoring this is the exact bug this file exists for.
      return ProbeTarget._(null, 'none', const [],
          'probe: unsupported argument ${jsonEncode(a)}.\n'
          '       Supported: --base <url> | --port <n>. Or set APPBOX_BASE.\n'
          '       Refusing to run rather than silently target $kDefaultBase.');
    }
    final value = inline ?? (i + 1 < args.length ? args[++i] : null);
    if (value == null || value.startsWith('-')) {
      return ProbeTarget._(
          null, 'none', const [], 'probe: $key needs a value.');
    }
    if (key == '--base' || key == '-b') {
      base = value;
    } else {
      port = value;
    }
  }

  if (base != null && port != null) {
    return ProbeTarget._(
        null, 'none', const [], 'probe: pass --base OR --port, not both.');
  }

  final envBase = environment['APPBOX_BASE'];
  final resolved = base ??
      (port != null ? 'http://localhost:$port' : null) ??
      envBase ??
      kDefaultBase;
  final via = base != null
      ? '--base'
      : port != null
          ? '--port'
          : envBase != null
              ? 'APPBOX_BASE'
              : 'default';

  // Rule 2. First line of every probe run, always.
  final notes = <String>['probe target: $resolved  (via $via)'];
  if (via == 'default') {
    notes.add(
        'probe target: NOTE — this is the shared dev server. Pass --port to isolate.');
  }
  return ProbeTarget._(resolved, via, notes, null);
}

// ── refusing to mutate a project that isn't disposable ───────────────────

/// The verdict on whether a target is safe for a probe that writes.
class DisposableVerdict {
  /// True when the probe may proceed.
  final bool ok;

  /// One line to print when [ok]; the refusal to print when not.
  final String message;

  const DisposableVerdict(this.ok, this.message);
}

/// Decide, from a `GET /__projects` body, whether [base] is safe to mutate.
///
/// Reads `boundProject` and NEVER `current`. `current` is a live read of the
/// global `~/.appbox/current` marker, which lies in both directions:
/// a server booted with `--project <name>` never touches the marker, and any
/// other process can flip the marker without restarting the server. Both were
/// proven live — a server booted `--project portalo-endpointtest` reported
/// `current: "portalo"`, the SAFE-looking value, while bound to the
/// non-disposable copy. `boundProject` is the project this server process
/// resolved once at boot, read straight from projectRoot: a per-process fact
/// no other process can flip. (Confirmed again on this port's own parity run:
/// `/__projects` returned `current: "portalo"` with
/// `boundProject: "portalo-probe"`.)
///
/// [projects] null means the fetch failed or returned non-JSON. Cannot-confirm
/// fails closed, the same as an unsupported flag above: a silent pass here is
/// the same bug moved one level up.
DisposableVerdict disposableVerdict(
  Map<String, dynamic>? projects,
  String base, {
  String? fetchError,
}) {
  if (projects == null) {
    return DisposableVerdict(
        false,
        'probe: could not confirm $base is serving a disposable project\n'
        '       (GET /__projects failed: ${fetchError ?? 'unreadable'}).\n'
        '       Refusing to run a mutation probe against an unverified target.');
  }
  if (!projects.containsKey('boundProject')) {
    // Older server binary. This is unknown, not null — do not read it as
    // "no project bound."
    return DisposableVerdict(
        false,
        'probe: could not confirm $base is serving a disposable project\n'
        '       (GET /__projects has no "boundProject" field — this server\n'
        '       binary predates that field). Refusing to run a mutation\n'
        '       probe against a target this guard can\'t read.');
  }

  final boundProject = projects['boundProject'];
  if (boundProject == null) {
    // A stated fact, not missing information: nothing is overlaid, so
    // /__project_write — the one channel every project write goes through —
    // has nothing to write into either (it denies 409 'no project overlaid').
    return DisposableVerdict(
        true, 'probe target: $base has no project bound (artifact-only) — proceeding.');
  }
  if (boundProject is! String || !_disposableRe.hasMatch(boundProject)) {
    return DisposableVerdict(
        false,
        'probe: $base is bound to project "$boundProject", which is not\n'
        '       disposable (its name must end in -probe or -test). This\n'
        '       probe mutates whatever project it\'s pointed at — running it\n'
        '       here risks the exact corruption this guard exists to stop.\n'
        '       Make a disposable copy and serve THAT on a spare port:\n'
        '         cp -R ~/.appbox/projects/$boundProject ~/.appbox/projects/$boundProject-probe\n'
        '         dart run appboxd/bin/appbox.dart design serve designs/appbox-studio --project $boundProject-probe --port 4330\n'
        '       then run this probe with --base http://localhost:4330\n'
        '       (boundProject is fixed at boot and belongs to this process\n'
        '       alone, so --project is fine here — nothing to get out of\n'
        '       sync with, unlike the old current-marker recipe.)');
  }
  return DisposableVerdict(true,
      'probe target: confirmed disposable project "$boundProject" (boundProject)');
}

/// `GET $base/__projects`, or null with [error] set when it cannot be read.
class ProjectsResponse {
  /// Decoded body, null when unreadable.
  final Map<String, dynamic>? body;

  /// Why it was unreadable, null on success.
  final String? error;

  const ProjectsResponse(this.body, this.error);

  /// The project this server process bound at boot. Null both when the server
  /// says nothing is overlaid and when the body could not be read — callers
  /// that must tell those apart read [body] directly.
  String? get boundProject {
    final v = body?['boundProject'];
    return v is String ? v : null;
  }
}

/// Fetch `GET $base/__projects`.
Future<ProjectsResponse> fetchProjects(String base) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse('$base/__projects'));
    final res = await req.close();
    if (res.statusCode != 200) {
      return ProjectsResponse(null, 'HTTP ${res.statusCode}');
    }
    final body = await res.transform(utf8.decoder).join();
    return ProjectsResponse(jsonDecode(body) as Map<String, dynamic>, null);
  } catch (e) {
    return ProjectsResponse(null, '$e');
  } finally {
    client.close(force: true);
  }
}

/// Fetch `GET $base/__projects` and hand the body to [disposableVerdict].
Future<DisposableVerdict> checkDisposableProject(String base) async {
  final res = await fetchProjects(base);
  return disposableVerdict(res.body, base, fetchError: res.error);
}

// ── check + section reporting ────────────────────────────────────────────

/// Accumulates check results and prints them in the probes' output shape.
///
/// The shape is load-bearing, not cosmetic: the .mjs suite and this one are
/// diffed textually during the parity window, so section headers, the two-space
/// `[PASS]`/`[FAIL]` indent, the ` — detail` suffix and the trailer all match
/// `_probe_base.mjs`'s consumers byte for byte.
class ProbeReport {
  /// Where output goes. Injectable so a test can read what was printed.
  final StringSink out;

  int _fails = 0;

  ProbeReport({StringSink? out}) : out = out ?? stdout;

  /// Failed checks so far.
  int get fails => _fails;

  /// A section header, e.g. `=== /design ===`, preceded by a blank line.
  void section(String name) => out.writeln('\n=== $name ===');

  /// Record a check. [detail] is appended after an em dash when non-empty.
  void check(String name, bool ok, [String detail = '']) {
    if (!ok) _fails++;
    out.writeln(
        '  [${ok ? 'PASS' : 'FAIL'}] $name${detail.isNotEmpty ? ' — $detail' : ''}');
  }

  /// A check that does not apply here — not a pass and not a failure.
  void skip(String why) => out.writeln('  [skip] $why');

  /// A condition that did not settle. The check behind it still reports the
  /// real state, so this is information, not a result.
  void warn(String why) => out.writeln('  [warn] $why');

  /// A thrown error: counted as a failure, in the .mjs `ERR <message>` shape.
  void error(Object e) {
    _fails++;
    out.writeln('ERR ${e is Exception || e is Error ? '$e' : e}');
  }

  /// Print the trailer and return the process exit code (0 clean, 1 failures).
  int finish() {
    out.writeln('\n==== ${_fails != 0 ? '$_fails FAILED' : 'ALL PASSED'} ====');
    return _fails != 0 ? 1 : 0;
  }
}

// ── studio-specific waits ────────────────────────────────────────────────
//
// These stay here rather than in cdp.dart because they encode facts about
// THIS app: `base.html` sets htmx-config `globalViewTransitions: true`, and
// the studio's swaps are htmx swaps. cdp.dart is the engine for every target
// the lens drives; a wait that assumes htmx does not belong in it.

/// Install the swap/transition counters this file's waits read. MUST be called
/// on a fresh target BEFORE its first navigate — it is an init script, so it
/// survives navigation, but only if it is in place before the page runs.
///
/// Two counters:
/// - `__hxSettled` — htmx's own "this swap is done" event, counted. A probe
///   that needs to know a swap landed should ask htmx rather than guess from
///   the DOM: "is .panel-viewer present" is true before the click as well as
///   after, so a wait built on it returns instantly and asserts nothing.
/// - `__vtBusy` — in-flight view transitions. Every studio swap runs inside
///   `document.startViewTransition`, which is what made a naive
///   poll-for-the-post-condition rewrite worse than the fixed sleeps it
///   replaced: the condition becomes true INSIDE the transition callback,
///   while the transition is still playing. Acting at that instant starts a
///   second transition, the browser reports `Transition was skipped`, and the
///   swap is lost — the probe then reports a regression it caused itself.
Future<void> trackTransitions(CdpSession session) async {
  await session.addInitScript(r'''
window.__hxSettled = 0;
addEventListener('htmx:afterSettle', () => { window.__hxSettled++; }, true);

window.__vtBusy = 0;
(() => {
  const d = document;
  const orig = d.startViewTransition && d.startViewTransition.bind(d);
  if (!orig) return; // no support → __vtBusy stays 0, waits are unaffected
  d.startViewTransition = (cb) => {
    window.__vtBusy++;
    const t = orig(cb);
    const done = () => { window.__vtBusy = Math.max(0, window.__vtBusy - 1); };
    // `finished` rejects on a skipped transition — settle either way, or one
    // skip would wedge the counter above zero and hang every later wait.
    t.finished.then(done, done);
    return t;
  };
})();
''');
}

/// The line [probeWaitFor] reports when a condition never held.
///
/// Split out because it is the one string in this file ported by hand from
/// `_probe_base.mjs` rather than derived from a rule, and the parity diff reads
/// it. A function can be asserted on; an interpolation buried in an async path
/// that only runs on timeout cannot.
String waitTimeoutMessage(Duration timeout, String label) =>
    'timed out after ${timeout.inMilliseconds}ms waiting for'
    ' ${label.isEmpty ? 'a condition' : label} — the check below reports the real state';

/// Wait for [expression] to hold, then let any in-flight view transition drain.
///
/// The drain is why this wraps [CdpSession.waitForFunction] rather than
/// calling it directly: the condition may have become true mid-transition (see
/// [trackTransitions]), and the caller is about to act on the page. Cheap when
/// [trackTransitions] was never installed — the expression is then `0 === 0`.
///
/// On timeout it reports and returns false rather than throwing, so the check
/// behind it still runs and reports the real state.
Future<bool> probeWaitFor(
  CdpSession session,
  String expression, {
  Duration timeout = const Duration(seconds: 8),
  String label = '',
  ProbeReport? report,
}) async {
  final held = await session.waitForFunction(expression, timeout: timeout);
  if (!held) {
    report?.warn(waitTimeoutMessage(timeout, label));
    return false;
  }
  await session.waitForFunction('(window.__vtBusy || 0) === 0',
      timeout: const Duration(seconds: 5),
      polling: const Duration(milliseconds: 50));
  return true;
}

/// Wait for the DOM to stop changing — the honest replacement for a blanket
/// settle sleep at call sites where there is no single condition to name (a
/// full-stage re-render touching several panels at once).
///
/// Preferred over naming a condition ONLY when the alternative would be a
/// guess: an assertion that waits for the wrong condition is worse than one
/// that waits too long, because it passes vacuously. Where the post-condition
/// is known, use [probeWaitFor].
///
/// Two consecutive identical samples [quietMs] apart, or [timeoutMs],
/// whichever comes first. The sample is element count AND innerHTML length
/// together: length alone collides across a swap that happens to produce
/// same-size markup, and a collision reads as "quiet" while the page moves.
Future<bool> waitQuiet(
  CdpSession session, {
  int quietMs = 120,
  int timeoutMs = 8000,
  ProbeReport? report,
}) async {
  final started = DateTime.now();
  String? prev;
  while (DateTime.now().difference(started).inMilliseconds < timeoutMs) {
    String? now;
    try {
      now = await session.evaluate(
              "document.querySelectorAll('*').length + ':' + document.body.innerHTML.length")
          as String?;
    } on CdpException {
      now = null;
    }
    if (now != null && now == prev) return true;
    prev = now;
    await Future.delayed(Duration(milliseconds: quietMs));
  }
  report?.warn('the DOM never went quiet within ${timeoutMs}ms —'
      ' the checks below report whatever state it reached');
  return false;
}

// ── the probe contract ───────────────────────────────────────────────────

/// Everything a probe body is handed: the resolved target, a live browser, and
/// the report to write checks into.
class ProbeContext {
  /// Resolved base URL, e.g. `http://localhost:4371`.
  final String base;

  /// The browser, or null for a probe that declared `needsBrowser: false` —
  /// no Chrome was launched for it.
  ///
  /// Nullable on purpose: a probe reaching for a browser it declared it did
  /// not need should not compile, rather than fail at the moment it clicks.
  /// Most probes never touch this — [newPage] and [closePage] are the path,
  /// and they raise an explanatory error rather than a null-dereference.
  final CdpClient? browser;

  /// Where checks are recorded.
  final ProbeReport report;

  ProbeContext({
    required this.base,
    required this.browser,
    required this.report,
  });

  /// True when this probe has a browser available.
  bool get hasBrowser => browser != null;

  CdpClient get _browser =>
      browser ??
      (throw StateError('this probe declared needsBrowser: false, so no Chrome'
          ' was launched — set needsBrowser: true in its Probe, or drop the'
          ' browser call'));

  /// Open a fresh target, size it, and install the swap counters.
  ///
  /// One target per section, not one per run: state leaks between sections
  /// otherwise (a preserved draft, a pinned panel), and a section that depends
  /// on the section before it cannot be run or read on its own.
  Future<CdpSession> newPage({int width = 1600, int height = 1000}) async {
    final session = await _browser.newTab();
    await session.setViewport(width, height);
    await trackTransitions(session);
    return session;
  }

  /// Navigate and wait for the DOM to go quiet.
  ///
  /// Ceiling: Playwright's `waitUntil: 'networkidle'` has no CDP equivalent.
  /// The load event plus [waitQuiet] is the closest honest equivalent, and is
  /// arguably the better wait — it tracks the DOM the assertions read rather
  /// than the request count.
  Future<void> goto(CdpSession session, String path) async {
    await session.navigate('$base$path');
    await waitQuiet(session, report: report);
  }

  /// Close one target. The browser outlives it; the suite closes the browser.
  Future<void> closePage(CdpSession session) async {
    await _browser.send('Target.closeTarget', {'targetId': session.targetId});
  }
}

/// A probe body: drive the browser, record checks on `ctx.report`.
typedef ProbeBody = Future<void> Function(ProbeContext ctx);

/// One registered probe.
class Probe {
  /// CLI name, e.g. `composer-draft`.
  final String name;

  /// One line for the CLI listing.
  final String summary;

  /// True when the probe writes to the served project — POSTs a message, moves
  /// a flow, edits a fixture. Mutating probes are gated on
  /// [checkDisposableProject] before Chrome is launched at all.
  ///
  /// Declared per probe, enforced by the harness, uniformly. Some `.mjs`
  /// originals mutate without calling the guard (`probe-no-reload`,
  /// `probe-composer-draft`); the guard's whole rationale is that case, so the
  /// ports declare it and the capability map records the strengthening.
  final bool mutates;

  /// False for a probe that talks to the server over HTTP and never needs a
  /// page — `context-sync` is the case. The harness then launches no Chrome at
  /// all for it, rather than booting a browser to leave it idle. Same target
  /// rules, same guard, same reporting: one suite, one runner, and the browser
  /// is an ingredient rather than the frame.
  final bool needsBrowser;

  /// The checks.
  final ProbeBody body;

  const Probe({
    required this.name,
    required this.summary,
    required this.mutates,
    required this.body,
    this.needsBrowser = true,
  });
}
