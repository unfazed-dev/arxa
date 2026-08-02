// Tests for the Dart designer-skill runtime ports — Task 19.
//
// One group per ported verb (lint, check-ladder, check-wiring, pseudolocalize,
// vendor-fetch, doctor). Each case asserts BOTH the exit code AND the
// stdout/stderr text of the legacy .mjs contract. The pseudolocalize goldens
// were captured byte-for-byte from runtime/pseudolocalize.mjs on the fixture
// below (see test/fixtures/ploc_golden.arb, ploc_seed_golden.json).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:appboxd/design_server.dart';
import 'package:appboxd/design_tools.dart';
import 'package:appboxd/design_cli.dart';
import 'package:test/test.dart';

// ── helpers ─────────────────────────────────────────────────────────────

Directory _tmpDir() => Directory.systemTemp.createTempSync('design_tools_test_');

void _write(Directory d, String rel, String content) {
  final f = File('${d.path}/$rel');
  f.parent.createSync(recursive: true);
  f.writeAsStringSync(content);
}

/// The exact arb + seed content the committed goldens were generated from.
const _enArb = '''{
  "@@locale": "en",
  "@_readme": "English source catalog.",
  "greet": "Hello {name}",
  "count": "{count, plural, =0{None} one{One item} other{{count} items}}",
  "save": "Save"
}
''';

const _enSeed = '''{
  "_note": "seed is SSOT",
  "id": "stable-id",
  "status": "active",
  "title": "Hello",
  "items": [
    {"id": "a1", "label": "First"},
    {"id": "a2", "label": "Second"}
  ]
}
''';

// ── eject serve-smoke helper (Task 20.5) ──────────────────────────────────

class _EjectResp {
  final int status;
  final String body;
  _EjectResp(this.status, this.body);
}

Future<_EjectResp> _ejectGet(String url) async {
  final client = HttpClient();
  try {
    final res = await (await client.getUrl(Uri.parse(url))).close();
    final body = await utf8.decoder.bind(res).join();
    return _EjectResp(res.statusCode, body);
  } finally {
    client.close(force: true);
  }
}

void main() {
  // ── lint ─────────────────────────────────────────────────────────────

  group('design lint', () {
    test('clean dir → exit 0 + clean line', () {
      final d = _tmpDir();
      _write(d, 'clean.html', '<p>no scripts here</p>');
      addTearDown(() => d.deleteSync(recursive: true));

      final r = designLint([d.path]);
      expect(r.exitCode, 0);
      expect(r.stderrLines, isEmpty);
      expect(r.stdoutLines.single,
          'lint clean: no custom client-side JS in ${d.path}');
    });

    test('each of the 4 rules fires → exit 1, findings on stderr', () {
      final d = _tmpDir();
      _write(d, 'a.html', '<script src="/js/app.js"></script>');
      _write(d, 'b.html', '<button hx-on:click="x">b</button>');
      _write(d, 'c.html', '<div hx-vals="js:{a:1}"></div>');
      _write(d, 'e.html', '<div hx-trigger="click[ctrlKey]"></div>');
      addTearDown(() => d.deleteSync(recursive: true));

      final r = designLint([d.path]);
      expect(r.exitCode, 1);
      expect(r.stderrLines.first, 'client-JS lint failed:');
      expect(r.stderrLines.skip(1).toList(),
          containsAll(const ['non-vendor <script> tag', 'hx-on handler',
            'js:-prefixed attribute', '[expr] trigger filter'].map(
                (m) => endsWith(': $m'))));
    });

    test('named vendor + JSON-data scripts pass', () {
      final d = _tmpDir();
      _write(d, 'v.html',
          '<script src="/assets/vendor/htmx.min.js"></script>'
          '<script type="application/json">{"a":1}</script>');
      addTearDown(() => d.deleteSync(recursive: true));
      expect(designLint([d.path]).exitCode, 0);
    });

    test('comments are stripped — commented ban is not a violation', () {
      final d = _tmpDir();
      _write(d, 'c.html', '{# hx-on:click explains the ban #}'
          '<!-- <script src=/x.js></script> -->');
      addTearDown(() => d.deleteSync(recursive: true));
      final r = designLint([d.path]);
      expect(r.exitCode, 0, reason: r.stderrLines.join('\n'));
    });

    test('missing arg → usage, exit 2', () {
      final r = designLint([]);
      expect(r.exitCode, 2);
      expect(r.stderrLines.single, 'usage: appbox design lint <artifact-dir>');
    });
  });

  // ── inspect coverage / states / retry (D7, D9, D10, D13) ─────────────

  group('design lint — inspection coverage', () {
    // A fully-annotated control: carries data-el AND the whole required set,
    // so it satisfies the per-tag rule and never counts as unannotated.
    const annotatedButton = '<button data-el="button:Go" '
        'data-inspect-role="button" data-inspect-style="filled" '
        'data-inspect-fn="Starts checkout">Go</button>';

    test('D7 — 11 interactive elements, 1 annotation: fails C, passes B', () {
      final d = _tmpDir();
      addTearDown(() => d.deleteSync(recursive: true));
      // Ten unannotated controls, every one of them invisible to the OLD
      // `<a href>|<button>` regex and to bar B, so this single fixture proves
      // the widened detector and the C→B toggle at once.
      _write(d, 'surfaces/home.html', '$annotatedButton'
          '<label>Name</label><label>Email</label>'
          '<div role="tab">One</div><div role="tab">Two</div>'
          '<div role="switch">Dark</div>'
          '<div tabindex="0">Focusable</div><div tabindex="2">Also</div>'
          '<div hx-get="/x">Load</div><div hx-post="/y">Send</div>'
          '<div hx-trigger="click">Trig</div>'
          // tabindex="-1" is programmatic focus, NOT an affordance — it must
          // not inflate the count.
          '<div tabindex="-1">Not a control</div>');

      final c = designLint([d.path]);
      expect(c.exitCode, 1, reason: c.stdoutLines.join('\n'));
      expect(c.stderrLines.skip(1).single,
          endsWith('10 interactive element(s) carry no data-el — inspect has '
              'nothing to bind to (coverage bar C)'));

      final b = designLint([d.path, '--coverage-b']);
      expect(b.exitCode, 0, reason: b.stderrLines.join('\n'));
    });

    test('D7 — input / hx-post / role=button are SEEN by the detector', () {
      final d = _tmpDir();
      addTearDown(() => d.deleteSync(recursive: true));
      _write(d, 'surfaces/form.html',
          '<input type="email" placeholder="you@example.com">'
          '<div hx-post="/subscribe">Subscribe</div>'
          '<div role="button">Dismiss</div>');

      final r = designLint([d.path]);
      expect(r.exitCode, 1, reason: 'the old regex saw none of these');
      expect(r.stderrLines.skip(1).single,
          endsWith('3 interactive element(s) carry no data-el — inspect has '
              'nothing to bind to (coverage bar C)'));
    });

    test('D9 — an inferred fn passes, and is reported apart from an authored '
        'one', () {
      final authored = _tmpDir();
      final inferred = _tmpDir();
      addTearDown(() => authored.deleteSync(recursive: true));
      addTearDown(() => inferred.deleteSync(recursive: true));
      _write(authored, 'surfaces/a.html', annotatedButton);
      _write(inferred, 'surfaces/a.html',
          annotatedButton.replaceFirst('<button ',
              '<button data-inspect-fn-provenance="inferred" '));

      final a = designLint([authored.path]);
      final i = designLint([inferred.path]);
      // Both PASS — inferred is legitimate, not missing.
      expect(a.exitCode, 0, reason: a.stderrLines.join('\n'));
      expect(i.exitCode, 0, reason: i.stderrLines.join('\n'));
      // …but only one of them is reported, so coverage and confidence stay
      // separable numbers.
      expect(a.stdoutLines.where((l) => l.startsWith('note:')), isEmpty);
      expect(i.stdoutLines.where((l) => l.startsWith('note:')).single,
          endsWith('1 data-inspect-fn value(s) marked inferred — derived, not '
              'authored; confirm before shipping'));
    });

    test('D10 — a declared state with no branch fails; an undeclared branch '
        'fails too', () {
      final d = _tmpDir();
      addTearDown(() => d.deleteSync(recursive: true));
      _write(d, 'intake/registry.json', jsonEncode([
        {'id': 'portalo.home', 'states': ['loading', 'empty']},
        {'id': 'portalo.cart', 'states': ['loading']},
      ]));
      _write(d, 'design/surfaces/home.html',
          "{% if state == 'loading' %}<p>…</p>{% endif %}");
      _write(d, 'design/surfaces/cart.html',
          "{% if state == 'loading' %}<p>…</p>{% endif %}"
          "{% if state == 'error' %}<p>oops</p>{% endif %}");

      final r = designLint([d.path]);
      expect(r.exitCode, 1);
      expect(r.stderrLines.skip(1), containsAll([
        endsWith("registry declares state 'empty' but the surface has no "
            "{% if state == 'empty' %} branch"),
        endsWith("surface branches on state 'error' that the registry does "
            'not declare'),
      ]));
    });

    test('D10 — no registry reachable leaves the rule off', () {
      final d = _tmpDir();
      addTearDown(() => d.deleteSync(recursive: true));
      _write(d, 'surfaces/loose.html',
          "{% if state == 'error' %}<p>oops</p>{% endif %}");
      expect(designLint([d.path]).exitCode, 0);
    });

    test('D13 — an unscrollable error region fails; a scrollable one with a '
        'single affordance fails too', () {
      // A retry control that is itself fully annotated, so the only findings
      // left are D13's.
      const retry = '<button data-el="button:Retry" data-inspect-role="button" '
          'data-inspect-style="ghost" data-inspect-fn="Refetches the page" '
          'data-retry>Retry</button>';
      final d = _tmpDir();
      addTearDown(() => d.deleteSync(recursive: true));
      // Both affordances, but a box that cannot scroll: RefreshIndicator never
      // sees the pull it advertises.
      _write(d, 'surfaces/unscrollable.html',
          '<div data-state="error" data-refresh="pull">$retry</div>');
      // Scrolls, but offers the button alone.
      _write(d, 'surfaces/one_affordance.html',
          '<div data-state="empty" data-scroll="y">$retry</div>');
      // Scrolls and offers both — the shape the designer must emit.
      _write(d, 'surfaces/ok.html',
          '<div data-state="error" data-scroll="y" data-refresh="pull">'
          '$retry</div>');

      final r = designLint([d.path]);
      expect(r.exitCode, 1);
      final msgs = r.stderrLines.skip(1).toList();
      expect(msgs, containsAll([
        allOf(contains('unscrollable.html'),
            endsWith("'error' region is not scrollable (data-scroll missing) — "
                'RefreshIndicator cannot detect a pull inside an unscrollable '
                'box')),
        allOf(contains('one_affordance.html'),
            endsWith("'empty' region offers retry control — BOTH "
                'data-refresh="pull" and a data-retry control are required; '
                'the pull gesture is not discoverable on an error screen')),
      ]));
      expect(msgs.where((m) => m.contains('ok.html')), isEmpty);
    });
  });

  // ── check-ladder ────────────────────────────────────────────────────

  group('design check-ladder', () {
    final cfg = jsonEncode({
      'boundaries': [600, 840],
      'rungs': {
        'compact': {'width': 390},
        'medium': {'width': 744},
        'expanded': {'width': 1280},
      },
    });
    final docSync = '''
# ladder

| rung | width |
|---|---|
| `compact` | **390** |
| `medium` | **744** |
| `expanded` | **1280** |
''';

    test('in-sync → exit 0 + summary line', () {
      final problems = checkLadderFromInputs(cfg: cfg, docText: docSync);
      expect(problems, isEmpty);
    });

    test('config rung missing from doc → problem', () {
      final drifted = docSync.replaceAll('| `medium` | **744** |\n', '');
      final problems = checkLadderFromInputs(cfg: cfg, docText: drifted);
      expect(problems, anyElement(contains('no table row for rung "medium"')));
    });

    test('doc rung missing from config → problem', () {
      final extra = docSync.replaceAll('| `expanded`', '| `extra`')
          .replaceAll('**1280**', '**999**');
      final problems = checkLadderFromInputs(cfg: cfg, docText: extra);
      expect(problems,
          anyElement(contains('doc names rung "extra" (999px)')));
    });

    test('rung width equals a boundary → problem', () {
      final cfgBoundary = jsonEncode({
        'boundaries': [600, 840],
        'rungs': {
          'compact': {'width': 600},
          'medium': {'width': 744},
          'expanded': {'width': 1280},
        },
      });
      final problems =
          checkLadderFromInputs(cfg: cfgBoundary, docText: docSync);
      expect(problems,
          anyElement(contains('rung "compact" sits ON boundary 600')));
    });

    test('designCheckLadder CLI: ok path → exit 0 + summary', () {
      final d = _tmpDir();
      _write(d, 'ladder.json', cfg);
      _write(d, 'doc.md', docSync);
      addTearDown(() => d.deleteSync(recursive: true));
      final r = designCheckLadder(
          ['--config', '${d.path}/ladder.json', '--doc', '${d.path}/doc.md']);
      expect(r.exitCode, 0);
      expect(r.stdoutLines.single,
          'ladder ok: compact=390 medium=744 expanded=1280');
    });
  });

  // ── check-wiring ────────────────────────────────────────────────────

  group('design check-wiring', () {
    late Directory d;

    setUp(() {
      d = _tmpDir();
      _write(d, 'app.routes.js', '''
export default [
  ['GET', '/'],
  ['POST', '/save'],
];
''');
      // markup: ids, urls, targets, a posted mutation — all resolvable.
      _write(d, 'index.html', '''
<div id="main"></div>
<a href="/">home</a>
<form hx-post="/save" hx-target="#main"><button>save</button></form>
''');
      // fragments: a viewmodel that renders `${VIEW}#row` + a co-located view macro.
      _write(d, 'thing_viewmodel.js', '''
const VIEW = 'thing_view.html';
const frag = `\${VIEW}#row`;
''');
      _write(d, 'thing_view.html', '''
{% macro row(item) %}<li>{{ item }}</li>{% endmacro %}
''');
    });

    tearDown(() => d.deleteSync(recursive: true));

    test('all four properties green on the fixture', () {
      for (final p in [
        'fragments',
        'mutations-posted',
        'urls-resolve',
        'targets-exist'
      ]) {
        final r = designCheckWiring([d.path, p]);
        expect(r.exitCode, 0, reason: '$p: ${r.stderrLines.join("\n")}');
        expect(r.stdoutLines.single, '$p: ok');
      }
    });

    test('fragments: missing macro → exit 1', () {
      _write(d, 'thing_view.html', '{% macro other() %}{% endmacro %}');
      final r = designCheckWiring([d.path, 'fragments']);
      expect(r.exitCode, 1);
      expect(r.stderrLines, anyElement(contains('defines no such macro')));
    });

    test('mutations-posted: unsent route → exit 1', () {
      _write(d, 'app.routes.js', '''
export default [
  ['GET', '/'],
  ['POST', '/save'],
  ['POST', '/delete'],
];
''');
      final r = designCheckWiring([d.path, 'mutations-posted']);
      expect(r.exitCode, 1);
      expect(r.stderrLines,
          anyElement(contains('POST /delete is a route no markup sends to')));
    });

    test('urls-resolve: unknown url → exit 1', () {
      _write(d, 'index.html',
          '<a href="/nope">x</a>\n<div id="main"></div>');
      final r = designCheckWiring([d.path, 'urls-resolve']);
      expect(r.exitCode, 1);
      expect(r.stderrLines,
          anyElement(contains('"/nope" matches no route')));
    });

    test('targets-exist: dangling target → exit 1', () {
      _write(d, 'index.html',
          '<div hx-target="#ghost"></div>');
      final r = designCheckWiring([d.path, 'targets-exist']);
      expect(r.exitCode, 1);
      expect(r.stderrLines,
          anyElement(contains('hx-target="#ghost"')));
    });

    test('bad property → usage, exit 2', () {
      final r = designCheckWiring([d.path, 'bogus']);
      expect(r.exitCode, 2);
      expect(r.stderrLines.first, contains('usage:'));
    });

    test('missing args → usage, exit 2', () {
      expect(designCheckWiring([]).exitCode, 2);
    });
  });

  // ── pseudolocalize ──────────────────────────────────────────────────

  group('design pseudolocalize', () {
    test('placeholder preservation + lookalike mapping', () {
      // {var} byte-preserved; ASCII letters mapped; padding wraps.
      expect(plocText('Hi {name}'), '[!! Hï {name} ~̷~~̷~ !!]');
    });

    test('plural option bodies transformed, keywords/braces intact', () {
      final v = plocValue('{count, plural, =0{None} one{One} other{{count}}}');
      expect(v, contains('plural'));
      expect(v, contains('=0{'));
      expect(v, contains('one{'));
      expect(v, contains('other{'));
      expect(v, contains('{count}'));
    });

    test('arb output byte-equal to the .mjs golden', () {
      final d = _tmpDir();
      _write(d, 'l10n/app_en.arb', _enArb);
      addTearDown(() => d.deleteSync(recursive: true));

      final r = designPseudolocalize([d.path]);
      expect(r.exitCode, 0);
      final out = File('${d.path}/l10n/app_qps-ploc.arb').readAsStringSync();
      final golden = File('test/fixtures/ploc_golden.arb').readAsStringSync();
      expect(out, golden);
      // @@locale forced to qps-ploc; @-keys skipped.
      expect(out, contains('"@@locale": "qps-ploc"'));
      expect(out, contains('"@_readme": "English source catalog."'));
    });

    test('seed json transformed except ENUM_KEYS and _-prefixed keys', () {
      final d = _tmpDir();
      _write(d, 'l10n/app_en.arb', _enArb);
      _write(d, 'models/greeting_model/greeting_seed.en.json', _enSeed);
      addTearDown(() => d.deleteSync(recursive: true));

      designPseudolocalize([d.path]);
      final out = File('${d.path}/models/greeting_model/greeting_seed.qps-ploc.json')
          .readAsStringSync();
      final golden =
          File('test/fixtures/ploc_seed_golden.json').readAsStringSync();
      expect(out, golden);
      // id/status preserved; title transformed; _note preserved.
      expect(out, contains('"id": "stable-id"'));
      expect(out, contains('"status": "active"'));
      expect(out, contains('"_note": "seed is SSOT"'));
    });

    test('JSON nulls in seeds pass through (regression: null → Object crash)', () {
      final d = _tmpDir();
      _write(d, 'models/greeting_model/greeting_seed.en.json',
          '{"artifact": null, "items": [{"text": "Hi", "extra": null}]}');
      addTearDown(() => d.deleteSync(recursive: true));

      final r = designPseudolocalize([d.path]);
      expect(r.exitCode, 0);
      final out = File('${d.path}/models/greeting_model/greeting_seed.qps-ploc.json')
          .readAsStringSync();
      expect(out, contains('"artifact": null'));
      expect(out, contains('"extra": null'));
    });

    test('nothing to do → exit 66', () {
      final d = _tmpDir();
      addTearDown(() => d.deleteSync(recursive: true));
      final r = designPseudolocalize([d.path]);
      expect(r.exitCode, 66);
      expect(r.stderrLines.first, contains('nothing pseudolocalized'));
    });

    test('missing arg → usage, exit 64', () {
      final r = designPseudolocalize([]);
      expect(r.exitCode, 64);
      expect(r.stderrLines.first, contains('usage:'));
    });
  });

  // ── vendor-fetch ────────────────────────────────────────────────────

  group('design vendor-fetch', () {
    test('sri() computes sha384-base64 matching openssl', () async {
      // printf 'abc' | openssl dgst -sha384 -binary | base64
      const expected = 'sha384-ywB1P0WjXou1oD1pmsZQBycsMqsO3tFjGotgWkP/W+2AhgcroefMI1i67KE0yCWn';
      expect(await sri(utf8.encode('abc')), expected);
    });

    test('SRI mismatch hard-fails (local HttpServer, injectable base url)',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((req) async {
        // Serve tampered bytes for every candidate path.
        final body = utf8.encode('TAMPERED-NOT-HTMX');
        req.response
          ..contentLength = body.length
          ..add(body)
          ..close();
      });
      final base = 'http://${server.address.host}:${server.port}';

      final out = Directory.systemTemp.createTempSync('vf_mismatch_');
      addTearDown(() => out.deleteSync(recursive: true));
      final r = await vendorFetch(out.path,
          baseUrl: '$base/cdn', registryBase: '$base/npm');
      expect(r.exitCode, 1);
      expect(r.stderrLines.join('\n'), contains('integrity mismatch'));
    });

    test('manifest entry shape {file, package, version, integrity}', () {
      final entry = manifestEntry(
          file: 'htmx.min.js', pkg: 'htmx.org', version: '2.0.10',
          integrity: 'sha384-xxx');
      expect(entry.keys,
          unorderedEquals(['file', 'package', 'version', 'integrity']));
      expect(entry['file'], 'htmx.min.js');
      expect(entry['package'], 'htmx.org');
      expect(entry['version'], '2.0.10');
      expect(entry['integrity'], 'sha384-xxx');
    });
  });

  // ── doctor ──────────────────────────────────────────────────────────

  group('design doctor', () {
    test('all-ok probes → exit 0 + ok rows', () {
      final report = doctorCheck(probes: () sync* {
        yield const DoctorRow(true, 'dart ≥ 3.12', 'found 3.12.0', 'install dart');
        yield const DoctorRow(true, 'runtime/vendor/htmx.min.js', 'present', 'restore');
      }());
      expect(report.exitCode, 0);
      expect(report.rows, everyElement(predicate<DoctorRow>((r) => r.ok)));
      expect(report.stdoutLines, anyElement(contains('all present')));
    });

    test('any miss → exit 1 + MISS row + fix', () {
      final report = doctorCheck(probes: () sync* {
        yield const DoctorRow(true, 'dart ≥ 3.12', 'found 3.12.0', 'install dart');
        yield const DoctorRow(false, 'ffmpeg', 'absent', 'brew install ffmpeg');
      }());
      expect(report.exitCode, 1);
      expect(report.stdoutLines, anyElement(contains('  MISS')));
      expect(report.stdoutLines, anyElement(contains('1 missing')));
      expect(report.stdoutLines, anyElement(contains('brew install ffmpeg')));
    });
  });

  // ── design_cli dispatch ─────────────────────────────────────────────

  group('designMain', () {
    test('unknown verb → usage, exit 2', () {
      expect(designMain(['bogus']), completion(2));
    });

    test('serve with no target → usage, exit 64', () {
      // serve is wired (Task 20): no target is a usage error (exit 64), not a
      // stub. Full serve coverage lives in design_server_test.dart.
      expect(designMain(['serve']), completion(64));
    });

    test('--self-test → exit 0', () {
      expect(designMain(['--self-test']), completion(0));
    });

    test('ds-check dispatches (missing arg → exit 64)', () {
      expect(designMain(['ds-check']), completion(64));
    });

    test('record-asset dispatches (missing args → exit 64)', () {
      expect(designMain(['record-asset']), completion(64));
    });

    test('ds-import dispatches (missing args → exit 64)', () {
      expect(designMain(['ds-import']), completion(64));
    });

    test('eject dispatches (missing args → exit 2)', () {
      expect(designMain(['eject']), completion(2));
    });
  });

  // ── ds-check (Task 22.1) ───────────────────────────────────────────────
  // Ported from check-design-system.mjs. The component/token/card inventory
  // needs ds-core.mjs's buildModel (750 lines, dropped per plan §22.1), so
  // the Dart port validates the structural gate the .mjs's exit code hinges
  // on: the resolvable global-CSS entry + namespace.

  group('design ds-check', () {
    test('missing projectDir → usage, exit 64', () {
      final r = designDsCheck([]);
      expect(r.exitCode, 64);
      expect(r.stderrLines.first, contains('Usage:'));
    });

    test('not a directory → exit 1', () {
      final r = designDsCheck(['/no/such/dir/here_xyz']);
      expect(r.exitCode, 1);
      expect(r.stderrLines.first, contains('Not a directory'));
    });

    test('DS with a styles.css entry → namespace line, exit 0', () {
      final d = _tmpDir();
      _write(d, 'styles.css', ':root { --color-brand: #0a0; }');
      addTearDown(() => d.deleteSync(recursive: true));
      final r = designDsCheck([d.path]);
      expect(r.exitCode, 0, reason: r.stderrLines.join('\n'));
      expect(r.stdoutLines, anyElement(startsWith('Namespace:')));
      expect(r.stdoutLines, anyElement(contains('styles.css')));
    });

    test('namespace read from a compiled manifest', () {
      final d = _tmpDir();
      _write(d, 'styles.css', ':root { --c: #000; }');
      _write(d, '_ds_manifest.json',
          jsonEncode({'namespace': 'AcmeCo_a1b2c3', 'globalCssPaths': []}));
      addTearDown(() => d.deleteSync(recursive: true));
      final r = designDsCheck([d.path]);
      expect(r.exitCode, 0);
      expect(r.stdoutLines, anyElement(contains('AcmeCo_a1b2c3')));
    });

    test('no global CSS entry → exit 2', () {
      final d = _tmpDir();
      _write(d, 'readme.txt', 'no css here');
      addTearDown(() => d.deleteSync(recursive: true));
      final r = designDsCheck([d.path]);
      expect(r.exitCode, 2);
      expect(r.stdoutLines, anyElement(contains('No global CSS entry')));
    });
  });

  // ── record-asset (Task 22.1) ───────────────────────────────────────────
  // Ported 1:1 from record-asset.mjs + lib/asset-store.mjs: the _d_meta.json
  // asset model, exact JSON shape, exact exit codes.

  group('design record-asset', () {
    test('records a deliverable into a fresh project → bootstraps _d_meta.json',
        () {
      final d = _tmpDir();
      addTearDown(() => d.deleteSync(recursive: true));
      final r = designRecordAsset([d.path, 'Welcome.html']);
      expect(r.exitCode, 0, reason: r.stderrLines.join('\n'));
      expect(r.stdoutLines.first, contains('Recorded asset "Welcome"'));
      final meta =
          jsonDecode(File('${d.path}/_d_meta.json').readAsStringSync());
      // Project-level fields bootstrapped in reference order.
      expect(meta['type'], 'design');
      expect(meta['designSystems'], []);
      expect(meta['primaryDesignSystem'], null);
      expect(meta.containsKey('createdAt'), true);
      expect(meta.containsKey('updatedAt'), true);
      // Asset version shape: {path, createdAt, status}.
      final versions =
          (meta['assets']['Welcome']['versions'] as List).cast<Map>();
      expect(versions.single['path'], 'Welcome.html');
      expect(versions.single['status'], 'needs-review');
      expect(versions.single.containsKey('createdAt'), true);
    });

    test('re-recording the same path updates in place (no second version)', () {
      final d = _tmpDir();
      addTearDown(() => d.deleteSync(recursive: true));
      designRecordAsset([d.path, 'Page.html']);
      final r = designRecordAsset(
          [d.path, 'Page.html', '--status', 'approved']);
      expect(r.exitCode, 0);
      expect(r.stdoutLines.first, contains('Updated asset "Page"'));
      final meta =
          jsonDecode(File('${d.path}/_d_meta.json').readAsStringSync());
      final versions =
          (meta['assets']['Page']['versions'] as List).cast<Map>();
      expect(versions.length, 1);
      expect(versions.single['status'], 'approved');
    });

    test('--name groups versions under one asset; --inherit-from resolves it',
        () {
      final d = _tmpDir();
      addTearDown(() => d.deleteSync(recursive: true));
      designRecordAsset([d.path, 'My Design.html']);
      designRecordAsset(
          [d.path, 'My Design v2.html', '--inherit-from', 'My Design.html']);
      final meta =
          jsonDecode(File('${d.path}/_d_meta.json').readAsStringSync());
      // Both paths grouped under the derived "My Design" name.
      final versions =
          (meta['assets']['My Design']['versions'] as List).cast<Map>();
      expect(versions.map((v) => v['path']).toList(),
          ['My Design.html', 'My Design v2.html']);
    });

    test('viewport via --width/--height; status validated', () {
      final d = _tmpDir();
      addTearDown(() => d.deleteSync(recursive: true));
      final r = designRecordAsset(
          [d.path, 'Screen.html', '--width', '390', '--height', '744']);
      expect(r.exitCode, 0);
      final meta =
          jsonDecode(File('${d.path}/_d_meta.json').readAsStringSync());
      final vp = (meta['assets']['Screen']['versions'] as List)
          .cast<Map>()
          .single['viewport'];
      expect(vp, {'width': 390, 'height': 744});

      // invalid status → usage 64
      expect(
          designRecordAsset([d.path, 'Screen.html', '--status', 'bogus'])
              .exitCode,
          64);
    });

    test('--height without --width → usage 64', () {
      final d = _tmpDir();
      addTearDown(() => d.deleteSync(recursive: true));
      expect(
          designRecordAsset([d.path, 'X.html', '--height', '744']).exitCode, 64);
    });

    test('absolute path normalized to project-relative POSIX', () {
      final d = _tmpDir();
      addTearDown(() => d.deleteSync(recursive: true));
      final r =
          designRecordAsset([d.path, '${d.path}/sub/Card.dc.html']);
      expect(r.exitCode, 0);
      final meta =
          jsonDecode(File('${d.path}/_d_meta.json').readAsStringSync());
      // .dc.html stripped from the name; path is project-relative.
      expect((meta['assets'] as Map).keys.single, 'Card');
      final versions =
          (meta['assets']['Card']['versions'] as List).cast<Map>();
      expect(versions.single['path'], 'sub/Card.dc.html');
    });

    test('--remove drops a version, then the asset', () {
      final d = _tmpDir();
      addTearDown(() => d.deleteSync(recursive: true));
      designRecordAsset([d.path, 'A.html']);
      designRecordAsset([d.path, 'B.html']);
      // remove one path across all assets
      final r = designRecordAsset([d.path, '--remove', 'A.html']);
      expect(r.exitCode, 0);
      final meta =
          jsonDecode(File('${d.path}/_d_meta.json').readAsStringSync());
      expect((meta['assets'] as Map).keys, ['B']);
    });

    test('--remove on a project with no _d_meta.json → exit 0, nothing to do',
        () {
      final d = _tmpDir();
      addTearDown(() => d.deleteSync(recursive: true));
      final r = designRecordAsset([d.path, '--remove', '--name', 'X']);
      expect(r.exitCode, 0);
      expect(r.stdoutLines.first, contains('nothing to remove'));
    });

    test('missing projectDir → usage 64', () {
      expect(designRecordAsset([]).exitCode, 64);
    });
  });

  // ── ds-import (Task 22.1) ──────────────────────────────────────────────
  // Ported from import-design-system.mjs. The per-load _ds_prompt.md needs
  // ds-prompt.mjs's renderDsPrompt (290 lines, dropped per plan §22.1) and is
  // NOT generated; the file-sync + _d_meta.json binding is ported faithfully.

  group('design ds-import', () {
    Directory makeCompiledDs() {
      final ds = _tmpDir();
      _write(ds, '_ds_manifest.json', jsonEncode({
        'namespace': 'Acme_a1b2c3',
        'globalCssPaths': ['styles.css'],
      }));
      _write(ds, 'styles.css',
          '@import "tokens.css";\n:root{--c:#000}\n@font-face{font-family:"Body";'
          'src:url("assets/body.woff2") format("woff2");}');
      _write(ds, 'tokens.css', ':root{--c:#000}');
      _write(ds, 'assets/body.woff2', 'woff2-bytes');
      _write(ds, '_ds_bundle.js', '// @ds-bundle: {"namespace":"Acme_a1b2c3"}\n');
      _write(ds, 'README.md', '# Acme System\nA system.\n');
      _write(ds, 'SKILL.md', 'name: acme-system\n');
      return ds;
    }

    test('missing args → usage 64', () {
      expect(designDsImport(['only-one']).exitCode, 64);
    });

    test('dsDir not a directory → exit 1', () {
      final proj = _tmpDir();
      addTearDown(() => proj.deleteSync(recursive: true));
      final r = designDsImport(['/no/such/xyz_ds', proj.path]);
      expect(r.exitCode, 1);
      expect(r.stderrLines.first, contains('not a directory'));
    });

    test('dsDir without _ds_manifest.json → exit 1', () {
      final proj = _tmpDir();
      final ds = _tmpDir();
      addTearDown(() {
        proj.deleteSync(recursive: true);
        ds.deleteSync(recursive: true);
      });
      final r = designDsImport([ds.path, proj.path]);
      expect(r.exitCode, 1);
      expect(r.stderrLines.first, contains('not a compiled design system'));
    });

    test('imports the runtime copy + records the binding in _d_meta.json', () {
      final proj = _tmpDir();
      final ds = makeCompiledDs();
      final slug = p.basename(ds.path);
      addTearDown(() {
        proj.deleteSync(recursive: true);
        ds.deleteSync(recursive: true);
      });
      final r = designDsImport([ds.path, proj.path]);
      expect(r.exitCode, 0, reason: r.stderrLines.join('\n'));
      expect(r.stdoutLines.first, contains('Imported'));

      // runtime copy: CSS @import closure (post-order: tokens.css before
      // styles.css) + url() font asset + bundle + manifest + readme + skill.
      final dest = '${proj.path}/_ds/$slug';
      expect(File('$dest/tokens.css').existsSync(), true);
      expect(File('$dest/styles.css').existsSync(), true);
      expect(File('$dest/assets/body.woff2').existsSync(), true);
      expect(File('$dest/_ds_bundle.js').existsSync(), true);
      expect(File('$dest/_ds_manifest.json').existsSync(), true);
      expect(File('$dest/README.md').existsSync(), true);

      // binding recorded in _d_meta.json.
      final meta =
          jsonDecode(File('${proj.path}/_d_meta.json').readAsStringSync());
      expect(meta['primaryDesignSystem'], slug);
      final dsEntries = (meta['designSystems'] as List).cast<Map>();
      expect(dsEntries.single['slug'], slug);
      expect(dsEntries.single['namespace'], 'Acme_a1b2c3');
      expect(dsEntries.single['dsFolder'], '_ds/$slug');
      expect(dsEntries.single['name'], 'Acme System'); // README's first h1
    });

    test('re-import updates the existing entry; --primary claims primary', () {
      final proj = _tmpDir();
      final ds = makeCompiledDs();
      final slug = p.basename(ds.path);
      addTearDown(() {
        proj.deleteSync(recursive: true);
        ds.deleteSync(recursive: true);
      });
      designDsImport([ds.path, proj.path]);
      // second import re-syncs in place (no duplicate designSystems entry)
      final r = designDsImport([ds.path, proj.path, '--primary']);
      expect(r.exitCode, 0);
      final meta =
          jsonDecode(File('${proj.path}/_d_meta.json').readAsStringSync());
      expect((meta['designSystems'] as List).length, 1);
      expect(meta['primaryDesignSystem'], slug);
    });
  });

  // ── eject (Task 20.5) ──────────────────────────────────────────────────
  // Ported from skills/appbox-designer/runtime/eject.mjs: copies the artifact,
  // narrows vendor/ to the libs its HTML actually loads (with the
  // htmx-required HARD FAIL), writes the narrowed manifest, and emits a
  // README carrying the `appbox design serve . --no-watch` line — no node.
  // The .mjs's package.json + node-runtime copy + smoke.test.mjs are dropped.

  final String ejectFixture =
      p.absolute('../skills/appbox-designer/examples/hello-hda');

  group('design eject', () {
    test('missing args → usage, exit 2', () {
      expect(designEject([]).exitCode, 2);
      expect(designEject(['only-one']).exitCode, 2);
      expect(designEject([]).stderrLines.first, contains('usage'));
    });

    test('ejects hello-hda: copied artifact + narrowed vendor + README', () {
      final out = _tmpDir();
      addTearDown(() => out.deleteSync(recursive: true));
      final r = designEject([ejectFixture, out.path]);
      expect(r.exitCode, 0, reason: r.stderrLines.join('\n'));

      // 1. the artifact itself is copied (routes + a nested view).
      expect(File(p.join(out.path, 'app.routes.js')).existsSync(), isTrue);
      expect(
          File(p.join(out.path, 'ui', 'views', 'main_shell', 'home',
                  'home_view.html'))
              .existsSync(),
          isTrue);

      // 2. narrowed vendor: hello-hda loads exactly htmx + preload + head-support.
      //    mustache.min.js is vendored but NOT referenced → must be absent.
      final vendor = Directory(p.join(out.path, 'runtime', 'vendor'));
      expect(vendor.existsSync(), isTrue);
      final jsFiles = vendor
          .listSync()
          .whereType<File>()
          .map((f) => p.basename(f.path))
          .where((n) => n.endsWith('.js'))
          .toSet();
      expect(jsFiles, {'htmx.min.js', 'preload.min.js', 'head-support.js'});
      expect(
          File(p.join(vendor.path, 'mustache.min.js')).existsSync(), isFalse);

      // narrowed manifest: only the 3 referenced rows.
      final manifest = jsonDecode(
          File(p.join(vendor.path, 'manifest.json')).readAsStringSync()) as List;
      final files = manifest.map((e) => (e as Map)['file']).toSet();
      expect(files, {'htmx.min.js', 'preload.min.js', 'head-support.js'});

      // 3. README carries the serve invocation line; no node/npm anywhere.
      final readme = File(p.join(out.path, 'README.md')).readAsStringSync();
      expect(readme, contains('appbox design serve . --no-watch'));
      expect(readme.toLowerCase(), isNot(contains('npm')));
      expect(readme.toLowerCase(), isNot(contains('node ')));

      // stdout next: line points at the serve command.
      expect(r.stdoutLines.last, contains('appbox design serve'));
    });

    test('referencing a non-vendored lib → exit 1', () {
      final d = _tmpDir();
      _write(d, 'app.routes.js', "export default [['GET','/']];\n");
      _write(d, 'index.html',
          '<script src="/assets/vendor/htmx.min.js"></script>'
          '<script src="/assets/vendor/totally-fake.js"></script>');
      final out = _tmpDir();
      addTearDown(() {
        d.deleteSync(recursive: true);
        out.deleteSync(recursive: true);
      });
      final r = designEject([d.path, out.path]);
      expect(r.exitCode, 1);
      expect(r.stderrLines.first, contains('not vendored'));
      expect(r.stderrLines.first, contains('totally-fake.js'));
      // eject.mjs copies the artifact before the vendor guard — a failed eject
      // leaves the partial copy (non-transactional, matching the source).
      expect(File(p.join(out.path, 'app.routes.js')).existsSync(), isTrue);
      expect(
          Directory(p.join(out.path, 'runtime', 'vendor')).existsSync(), isFalse,
          reason: 'no vendor copied when the guard fires');
    });

    test('no htmx referenced → exit 1 (htmx-required hard fail)', () {
      final d = _tmpDir();
      _write(d, 'app.routes.js', "export default [['GET','/']];\n");
      _write(d, 'index.html',
          '<script src="/assets/vendor/preload.min.js"></script>');
      final out = _tmpDir();
      addTearDown(() {
        d.deleteSync(recursive: true);
        out.deleteSync(recursive: true);
      });
      final r = designEject([d.path, out.path]);
      expect(r.exitCode, 1);
      expect(r.stderrLines.first, contains('htmx.min.js'));
      expect(r.stderrLines.first, contains('refusing to eject'));
    });

    test('map-island artifact ejects the leaflet subdir incl. images/', () {
      final d = _tmpDir();
      _write(d, 'app.routes.js', "export default [['GET','/']];\n");
      _write(d, 'index.html',
          '<script src="/assets/vendor/htmx.min.js"></script>'
          '<link rel="stylesheet" href="/assets/vendor/leaflet/leaflet.css">'
          '<script src="/assets/vendor/leaflet/leaflet.js" defer></script>');
      final out = _tmpDir();
      addTearDown(() {
        d.deleteSync(recursive: true);
        out.deleteSync(recursive: true);
      });
      final r = designEject([d.path, out.path]);
      expect(r.exitCode, 0, reason: r.stderrLines.join('\n'));

      // The whole leaflet/ subdir ships: leaflet.css references its marker
      // sprites in images/ relative to itself.
      final vendor = p.join(out.path, 'runtime', 'vendor');
      expect(File(p.join(vendor, 'leaflet', 'leaflet.js')).existsSync(), isTrue);
      expect(
          File(p.join(vendor, 'leaflet', 'leaflet.css')).existsSync(), isTrue);
      expect(
          File(p.join(vendor, 'leaflet', 'images', 'marker-icon.png'))
              .existsSync(),
          isTrue,
          reason: 'leaflet.css references images/ relative to itself');

      // The narrowed manifest keeps both leaflet rows.
      final manifest = jsonDecode(
          File(p.join(vendor, 'manifest.json')).readAsStringSync()) as List;
      final files = manifest.map((e) => (e as Map)['file']).toSet();
      expect(files, containsAll(['leaflet/leaflet.js', 'leaflet/leaflet.css']));
    });

    // The plan-20.5 serve smoke: the ejected copy renders + serves htmx on
    // the Dart design server, booted in-process.
    test('serve smoke: ejected copy serves / and htmx (in-process)', () async {
      final out = _tmpDir();
      addTearDown(() => out.deleteSync(recursive: true));
      designEject([ejectFixture, out.path]);

      final srv = await DesignServer.start(
        artifactDir: out.path,
        port: 0,
        noWatch: true,
        runtimeVendorDir: p.join(out.path, 'runtime', 'vendor'),
      );
      try {
        final home = await _ejectGet(srv.url);
        expect(home.status, 200);
        expect(home.body.toLowerCase(), contains('<html'));

        final htmx = await _ejectGet('${srv.url}assets/vendor/htmx.min.js');
        expect(htmx.status, 200);
        expect(htmx.body, contains('htmx'));
      } finally {
        await srv.stop();
      }
    });
  });
}
