// `appbox design` — CLI entry for the ported designer runtimes (Task 19).
//
// Dispatches the six ported verbs and returns the process exit code (the
// caller — `bin/appbox.dart` — wraps the return in `exit(...)`). Exit codes
// are the legacy .mjs contracts:
//   lint           0 clean · 1 findings · 2 usage
//   check-ladder   0 ok · 1 drift · 2 usage
//   check-wiring   0 ok · 1 problems · 2 usage
//   pseudolocalize 0 wrote · 64 usage · 66 nothing-to-do
//   vendor-fetch   0 vendored · 1 failed · 2 usage
//   doctor         0 all-present · 1 missing
//   serve          0 ok · 64 usage · 66 no-artifact · 69 EADDRINUSE ·
//                  77 EACCES · 70 other (Task 20; design_server.dart)
//   eject          0 ejected · 1 vendor|htmx-required fail · 2 usage (Task 20.5)
//   ds-check       0 entry · 2 no-entry · 1 not-a-dir · 64 usage (Task 22.1)
//   record-asset   0 recorded · 64 usage · 1 io|json (Task 22.1)
//   ds-import      0 imported · 64 usage · 1 not-a-dir|no-manifest|io (Task 22.1)
//
// Usage:
//   appbox design lint <artifact-dir>
//   appbox design check-ladder [--config <p>] [--doc <p>]
//   appbox design check-wiring <artifact-dir> <fragments|mutations-posted|urls-resolve|targets-exist>
//   appbox design pseudolocalize <artifact-dir>
//   appbox design vendor-fetch [--vendor <dir>]
//   appbox design doctor
//   appbox design serve <dir|name> [--port N] [--host H] [--json] [--no-watch]
//   appbox design eject <artifact-dir> <out-dir> [--target=node|cloudflare|vercel] [--kits=a,b]
//   appbox design ds-check <projectDir> [--verbose]
//   appbox design record-asset <projectDir> <htmlPath> [flags]
//   appbox design record-asset <projectDir> --remove [<htmlPath>] [flags]
//   appbox design ds-import <dsDir> <projectDir> [--primary]
//   appbox design --self-test

import 'dart:io';

import 'package:appboxd/design_server.dart';
import 'package:appboxd/design_selftest.dart';
import 'package:appboxd/design_tools.dart';
import 'package:appboxd/probes/probe_cli.dart';

const String _usage = '''
Usage: appbox design <subcommand> [options]

Subcommands:
  lint <artifact-dir>                No-ad-hoc-client-JS lint (ADR-0002)
                                     + widget/panel gate (W1–W6)
  check-ladder [--config <p>] [--doc <p>]
                                     Ladder config ↔ doctrine drift check
  check-wiring <dir> <property>      Wiring joins (fragments|mutations-posted|
                                     urls-resolve|targets-exist)
  pseudolocalize <artifact-dir>      Generate the qps-ploc pseudo-locale
  vendor-fetch [--vendor <dir>]      Fetch + SRI-pin the vendored client libs
  doctor                             Preflight the Dart toolchain the gates use
  eject <artifact-dir> <out-dir>     Eject a self-contained Hono app (JS runtime
       [--target=node|cloudflare|vercel]   scaffold + narrowed vendor + README).
       [--kits=a,b]                   node boots locally (default port 4399);
                                     cloudflare/vercel emit deployable trees.
  selftest [<artifact-dir>] [--negative]
                                     Structural-contract selftest + falsifiability
  ds-check <projectDir> [--verbose]  Read-only design-system structural check
  record-asset <projectDir> <htmlPath> [flags]
                                     Index a UI deliverable in _d_meta.json
  ds-import <dsDir> <projectDir> [--primary]
                                     Sync a compiled DS into _ds/<slug>/
  probe <name…|all> [--port <n> | --base <url>] [--project <name>]
                                     Behavioural probes against a served design
                                     (appbox design probe --help)
  --self-test                        Run the embedded invariant self-test

Note: `appbox design serve` runs the Dart design server (Task 20);
`shoot`/`console-check` are `appbox lens shoot`/`appbox lens check`.''';

/// Entry point for `appbox design`. Returns the process exit code.
Future<int> designMain(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(_usage);
    return 2;
  }
  if (args.first == '--self-test') {
    return _selfTest();
  }
  final cmd = args.first;
  final rest = args.sublist(1);
  switch (cmd) {
    case 'lint':
      return _emit(designLint(rest));
    case 'check-ladder':
      return _emit(designCheckLadder(rest));
    case 'check-wiring':
      return _emit(designCheckWiring(rest));
    case 'pseudolocalize':
      return _emit(designPseudolocalize(rest));
    case 'vendor-fetch':
      return _emit(await designVendorFetch(rest));
    case 'doctor':
      return _emit(designDoctor(rest));
    case 'serve':
      return designServe(rest);
    case 'eject':
      return _emit(await designEject(rest));
    case 'ds-check':
      return _emit(designDsCheck(rest));
    case 'record-asset':
      return _emit(designRecordAsset(rest));
    case 'ds-import':
      return _emit(designDsImport(rest));
    case 'selftest':
      return designSelftestMain(rest);
    case 'probe':
      return runProbeCli(rest);
    default:
      stderr.writeln("appbox design: unknown subcommand '$cmd'");
      stderr.writeln(_usage);
      return 2;
  }
}

/// Flush a [CmdResult] to the real sinks and return its exit code.
int _emit(CmdResult r) {
  for (final l in r.stdoutLines) {
    stdout.writeln(l);
  }
  for (final l in r.stderrLines) {
    stderr.writeln(l);
  }
  return r.exitCode;
}

/// Embedded invariant self-test (R5: a check that has never failed is not a
/// check). Returns 0 on PASS, 2 on FAIL.
Future<int> _selfTest() async {
  try {
    // 1. comment stripping — a documented ban is not itself a violation.
    if (stripComments('{# hx-on:click #}<script src=/x.js></script>')
        .contains('hx-on')) {
      throw 'comment not stripped';
    }
    // 2. lint inverse: vendor + JSON-data scripts pass.
    final d = Directory.systemTemp.createTempSync('design_selftest_');
    try {
      File('${d.path}/v.html').writeAsStringSync(
          '<script src="/assets/vendor/htmx.min.js"></script>'
          '<script type="application/json">{"a":1}</script>');
      if (lintArtifact(d.path).isNotEmpty) throw 'vendor/json script flagged';
    } finally {
      d.deleteSync(recursive: true);
    }
    // 3. plural brace-walker round-trip.
    final pl = parsePlural('{n, plural, =0{none} one{one} other{#}}');
    if (pl == null || pl.varName != 'n' || !pl.options.containsKey('one')) {
      throw 'parsePlural broke';
    }
    if (parsePlural('not a plural') != null) throw 'non-plural parsed';
    // 4. placeholder byte-preservation through plocText.
    if (!plocText('Hi {x}').contains('{x}')) throw 'placeholder clobbered';
    // 5. SRI matches openssl on a fixed input.
    const expected =
        'sha384-ywB1P0WjXou1oD1pmsZQBycsMqsO3tFjGotgWkP/W+2AhgcroefMI1i67KE0yCWn';
    if (await sri('abc'.codeUnits) != expected) throw 'sri diverged from openssl';
    // 6. manifest entry shape is closed.
    if (manifestEntry(file: 'f', pkg: 'p', version: 'v', integrity: 'i').length != 4) {
      throw 'manifest shape changed';
    }
  } catch (e) {
    stderr.writeln('self-test: FAIL: $e');
    return 2;
  }
  stdout.writeln('self-test: PASS');
  return 0;
}
