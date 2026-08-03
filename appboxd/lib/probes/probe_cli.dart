// `appbox design probe <names…|all>` — the design-probe dispatcher.
//
// House style follows lens_cli.dart: a thin argv→lib adapter that parses,
// calls, and maps the outcome to an exit code. The rules live in
// probe_base.dart as pure functions; this file is where their verdicts become
// stdout and a status.
//
// Exit codes: 0 all checks passed · 1 a check failed · 2 env/usage (bad args,
// unknown probe, unverifiable target, Chrome missing) — the same split
// lens_cli.dart uses, and the same one the .mjs probes exit with.

import 'dart:io';

import 'package:appboxd/cdp.dart';
import 'package:appboxd/probes/probe_base.dart';
import 'package:appboxd/probes/registry.dart';

String _usage() {
  final rows = kProbes
      .map((p) => '  ${p.name.padRight(18)} ${p.summary}${p.mutates ? ' [mutates]' : ''}')
      .join('\n');
  return '''
Usage: appbox design probe <name…|all> [--port <n> | --base <url>] [--project <name>]

Probes (run order for `all`):
$rows

Target (exactly one of --port/--base; APPBOX_BASE is the fallback):
  --port <n>        Target http://localhost:<n>
  --base <url>      Target <url>
  --project <name>  Assert the server is bound to <name> before running. The
                    guard already refuses a non-disposable project; this is for
                    when you know WHICH disposable copy you meant.

Probes marked [mutates] write into the served project and refuse to run unless
the server's boundProject ends in -probe or -test.

Exit codes: 0 ok · 1 check failed · 2 env/usage.''';
}

/// Entry point for `appbox design probe`. Returns the process exit code.
Future<int> runProbeCli(List<String> args) async {
  if (args.isEmpty || args.first == '-h' || args.first == '--help') {
    stderr.writeln(_usage());
    return args.isEmpty ? 2 : 0;
  }

  // Split argv into probe names and target flags. Any flag that takes a
  // separate value must carry that value across the split, or the value lands
  // in the wrong bucket — `--port 4371` would read 4371 as a probe name, and
  // resolveTarget would then fall back to the default port with nothing said.
  // That is rule 1's failure mode reintroduced one layer up, so the set of
  // value-taking flags is stated here explicitly rather than inferred.
  const valueFlags = {'--base', '--port', '-b', '-p', '--project'};
  final passthrough = <String>[];
  final names = <String>[];
  String? expectProject;
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (!a.startsWith('-')) {
      names.add(a);
      continue;
    }
    final eq = a.indexOf('=');
    final key = eq == -1 ? a : a.substring(0, eq);
    String? value = eq == -1 ? null : a.substring(eq + 1);
    if (eq == -1 && valueFlags.contains(key)) {
      value = i + 1 < args.length ? args[++i] : null;
      if (value == null || value.startsWith('-')) {
        stderr.writeln('probe: $key needs a value.');
        return 2;
      }
    }
    if (key == '--project') {
      if (value == null || value.isEmpty) {
        stderr.writeln('probe: --project needs a value.');
        return 2;
      }
      expectProject = value;
    } else {
      // Unknown flags go through untouched: resolveTarget owns rule 1 and
      // produces the refusal that names the supported set.
      passthrough.add(key);
      if (value != null) passthrough.add(value);
    }
  }

  // Target resolution runs BEFORE the probe names are checked, so that an
  // argument this CLI could not honour is diagnosed as such. An unrecognised
  // flag leaves its value stranded in the name list, and reporting that value
  // as "unknown probe" would send the operator hunting for a typo in the
  // wrong argument — while the actual unhonoured flag went unmentioned. Rule 1
  // is the one with an incident behind it, so it reports first.
  final target = resolveTarget(passthrough);
  if (!target.ok) {
    stderr.writeln(target.error);
    return 2;
  }

  if (names.isEmpty) {
    stderr.writeln('probe: name a probe to run, or `all`.');
    stderr.writeln(_usage());
    return 2;
  }

  final selected = <Probe>[];
  if (names.length == 1 && names.first == 'all') {
    selected.addAll(kProbes);
  } else {
    for (final n in names) {
      final p = probeByName(n);
      if (p == null) {
        // Rule 1's spirit: a name that cannot be honoured is a hard error, and
        // the error says what WOULD have worked.
        stderr.writeln("probe: unknown probe '$n'.");
        stderr.writeln('       Available: ${kProbes.map((p) => p.name).join(', ')}, all');
        return 2;
      }
      selected.add(p);
    }
  }

  final base = target.base!;
  for (final line in target.notes) {
    stdout.writeln(line);
  }

  // The guard runs before Chrome is launched: a refusal should cost nothing
  // and, more to the point, must happen before anything can click.
  if (selected.any((p) => p.mutates)) {
    final verdict = await checkDisposableProject(base);
    if (!verdict.ok) {
      stderr.writeln(verdict.message);
      return 2;
    }
    stdout.writeln(verdict.message);
  }
  if (expectProject != null) {
    final projects = await fetchProjects(base);
    if (projects.boundProject != expectProject) {
      stderr.writeln('probe: $base is bound to project'
          ' "${projects.boundProject ?? '(unreadable: ${projects.error ?? 'no project bound'})'}",'
          ' not "$expectProject" as --project asserts.');
      return 2;
    }
  }

  // Chrome is launched only if something in this run needs a page. A suite of
  // purely HTTP probes boots no browser at all, and `probe context-sync` on a
  // machine with no Chrome installed is a legitimate run rather than an
  // environment failure.
  CdpClient? browser;
  var worst = 0;
  var passed = 0;
  if (selected.any((p) => p.needsBrowser)) {
    try {
      browser = await CdpClient.launch();
    } catch (e) {
      // Chrome missing or unlaunchable is an environment failure, not a failed
      // check — naming it is the difference between "fix your machine" and
      // "the studio regressed".
      stderr.writeln('probe: could not launch Chrome — $e');
      return 2;
    }
  }

  try {
    for (final probe in selected) {
      if (selected.length > 1) stdout.writeln('\n--- probe: ${probe.name} ---');
      final report = ProbeReport(bareVerdicts: probe.bareVerdicts);
      // One browser context per probe — its own cookie jar, so its own studio
      // session. Without it every probe's tabs share `kdh_sid` and a probe's
      // result depends on which probe ran before it; see ProbeContext.newPage
      // for the measured case. One per probe rather than per page because that
      // is the isolation the .mjs suite had: one node process per probe.
      final browserContextId =
          probe.needsBrowser ? await browser!.createBrowserContext() : null;
      final ctx = ProbeContext(
        base: base,
        browser: probe.needsBrowser ? browser : null,
        report: report,
        browserContextId: browserContextId,
      );
      try {
        await probe.body(ctx);
      } catch (e) {
        // Matches the .mjs `catch (e) { console.log('ERR', e.message); fails++ }`:
        // a thrown probe still prints a trailer and still reports the checks it
        // managed to run.
        report.error(e);
      } finally {
        // In a finally so a thrown probe cannot leak its context into the next
        // one — a leaked context is the very state bleed this exists to stop.
        if (browserContextId != null) {
          await browser!.disposeBrowserContext(browserContextId);
        }
      }
      final code = report.finish();
      if (code == 0) passed++;
      if (code > worst) worst = code;
    }
  } finally {
    await browser?.close();
  }

  if (selected.length > 1) {
    stdout.writeln('\n==== SUITE: $passed/${selected.length} probes passed ====');
  }
  return worst;
}
