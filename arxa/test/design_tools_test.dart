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
import 'package:arxa/arxa_dial.dart';
import 'package:arxa/design_server.dart';
import 'package:arxa/design_tools.dart';
import 'package:arxa/design_cli.dart';
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
      // Four gates run under `design lint`, so a clean run says so four
      // times: the ADR-0002 client-JS lint (89e153c2: the three legal forms),
      // the W1–W9 widget/panel gate (13b90126 added W9; the sharpened law
      // kept the range), the S1–S4 style-placement gate and the P1–P5
      // palette-plane gate (the universal palette plane 2026-09-10; P5
      // contrast since 2026-09-11). A
      // silent gate is indistinguishable from a gate that never ran.
      expect(r.stdoutLines, [
        'lint clean: every script resolves (vendor/island/app module), no inline handlers in ${d.path}',
        'widget/panel gate clean: W1–W9 in ${d.path}',
        'style gate clean: S1–S4 in ${d.path}',
        'palette gate clean: P1–P5 in ${d.path}',
      ]);
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
      _write(d, 'c.tsx', '{/* hx-on:click explains the ban */}'
          '<!-- <script src=/x.js></script> -->');
      addTearDown(() => d.deleteSync(recursive: true));
      final r = designLint([d.path]);
      expect(r.exitCode, 0, reason: r.stderrLines.join('\n'));
    });

    test('missing arg → usage, exit 2', () {
      final r = designLint([]);
      expect(r.exitCode, 2);
      expect(r.stderrLines.single, 'usage: arxa design lint <artifact-dir>');
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
          '<div data-el="form-section" data-inspect-role="group" '
          'data-inspect-style="form" data-inspect-fn="Form section">'
          '<label>Name</label><label>Email</label>'
          '</div>'
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
      expect(c.stderrLines.skip(1).first,
          endsWith('10 interactive element(s) carry no data-el — inspect has '
              'nothing to bind to (coverage bar C)'));

      final b = designLint([d.path, '--coverage-b']);
      expect(b.exitCode, 0, reason: b.stderrLines.join('\n'));
    });

    test('D7 — input / hx-post / role=button are SEEN by the detector', () {
      final d = _tmpDir();
      addTearDown(() => d.deleteSync(recursive: true));
      _write(d, 'surfaces/form.html',
          '<div data-el="form-field" data-inspect-role="input" '
          'data-inspect-style="field" data-inspect-fn="Email input">'
          '<input type="email" placeholder="you@example.com">'
          '</div>'
          '<div hx-post="/subscribe">Subscribe</div>'
          '<div role="button">Dismiss</div>');

      final r = designLint([d.path]);
      expect(r.exitCode, 1, reason: 'the old regex saw none of these');
      expect(r.stderrLines.skip(1).first,
          endsWith('3 interactive element(s) carry no data-el — inspect has '
              'nothing to bind to (coverage bar C)'));
    });

    test('D18 — widget-coverage: uncovered leaves flagged, covered ones not', () {
      final d = _tmpDir();
      addTearDown(() => d.deleteSync(recursive: true));
      // <p> is a widget-coverage target but NOT interactive (D7 misses it).
      // The <button> is covered by its data-el ancestor; the <p> is not.
      _write(d, 'surfaces/blog.html',
          '<div data-el="post" data-inspect-role="group" '
          'data-inspect-style="post" data-inspect-fn="Blog post">'
          '<button>Read</button>'
          '</div>'
          '<p>Standalone paragraph with no widget ancestor</p>');

      final r = designLint([d.path]);
      expect(r.exitCode, 1, reason: r.stderrLines.join('\n'));
      // D18 flags the <p>; the <button> inside [data-el] is covered.
      expect(
          r.stderrLines.where((l) => l.contains('widget-coverage') ||
              l.contains('no data-el on self or any ancestor')),
          isNotEmpty);
      expect(r.stderrLines.any((l) => l.contains('<p>')),
          true);
      // The covered <button> is NOT flagged by D18.
      expect(r.stderrLines.any((l) => l.contains('<button>')),
          false);
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
      _write(d, 'design/surfaces/home.tsx',
          "{state === 'loading' && (<p {...inspectAttrs('loading', {role: 'text'})}>…</p>)}");
      _write(d, 'design/surfaces/cart.tsx',
          "{state === 'loading' && (<p {...inspectAttrs('loading', {role: 'text'})}>…</p>)}"
          "{state === 'error' && (<p {...inspectAttrs('error', {role: 'text'})}>oops</p>)}");

      final r = designLint([d.path]);
      expect(r.exitCode, 1);
      expect(r.stderrLines.skip(1), containsAll([
        endsWith("registry declares state 'empty' but the surface has no "
            "`state === 'empty'` branch"),
        endsWith("surface branches on state 'error' that the registry does "
            'not declare'),
      ]));
    });

    test('D10 — a ternary branch satisfies the declared state', () {
      final d = _tmpDir();
      addTearDown(() => d.deleteSync(recursive: true));
      _write(d, 'intake/registry.json', jsonEncode([
        {'id': 'portalo.home', 'states': ['empty']},
      ]));
      _write(d, 'design/surfaces/home.tsx',
          "{state === 'empty' ? (<p {...inspectAttrs('empty-msg', {role: 'text'})}>nothing yet</p>) : (<ul {...inspectAttrs('list', {role: 'list'})}>…</ul>)}");

      final r = designLint([d.path]);
      expect(r.exitCode, 0, reason: r.stderrLines.join('\n'));
    });

    test('D10 — no registry reachable leaves the rule off', () {
      final d = _tmpDir();
      addTearDown(() => d.deleteSync(recursive: true));
      _write(d, 'surfaces/loose.tsx',
          "{state === 'error' && (<p {...inspectAttrs('error-msg', {role: 'text'})}>oops</p>)}");
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

    test('manifest entry shape {file, package, version, integrity, category}',
        () {
      final entry = manifestEntry(
          file: 'htmx.min.js', pkg: 'htmx.org', version: '2.0.10',
          integrity: 'sha384-xxx');
      expect(entry.keys, unorderedEquals(
          ['file', 'package', 'version', 'integrity', 'category']));
      expect(entry['file'], 'htmx.min.js');
      expect(entry['package'], 'htmx.org');
      expect(entry['version'], '2.0.10');
      expect(entry['integrity'], 'sha384-xxx');
      // 89e153c2 (ADR-0009 categories) added the key; hypermedia is the
      // default for the vendored libraries the client-JS lint allows.
      expect(entry['category'], 'hypermedia');
    });

    test('manifest entry carries upstreamIntegrity only when patched', () {
      expect(
          manifestEntry(
              file: 'a.js', pkg: 'a', version: '1', integrity: 'sha384-on-disk',
              upstreamIntegrity: 'sha384-pristine')['upstreamIntegrity'],
          'sha384-pristine');
      // Presence IS the divergence flag, so an unpatched row must not carry
      // the key at all — an empty string would read as "diverges from nothing".
      expect(
          manifestEntry(file: 'a.js', pkg: 'a', version: '1', integrity: 'x')
              .containsKey('upstreamIntegrity'),
          isFalse);
    });
  });

  // ── local patches on vendored files ─────────────────────────────────
  //
  // Context for anyone changing these: `de28917a` committed a one-character
  // local edit to model-viewer.min.js and a hand-written SRI.md section
  // warning that vendor-fetch would revert it. Both were losable — vendor-fetch
  // re-downloads the file AND rewrites SRI.md wholesale, so the warning
  // deleted itself. The patch is now data (`vendorPatches`) and these four
  // tests are what keep it that way.

  group('vendor patches', () {
    const vendorDir = '../skills/arxa-designer/runtime/vendor';

    // The production registry is EMPTY since the far-plane patch was reverted
    // (verified: it could not fix clipping and was worse where it acted — see
    // docs/research/model-viewer-far-plane-verification.md). The machinery
    // must stay tested anyway, or it rots until the day a real patch needs it
    // — so the mechanism tests run on this synthetic entry via the `registry:`
    // parameter, and the registry-shaped tests below stay as vacuous-on-empty
    // guards over whatever entry is added next.
    const testPatch = VendorPatch(
      file: 'model-viewer.min.js',
      find: 'UPSTREAM_ANCHOR_TEXT',
      replace: 'LOCALLY_PATCHED_TEXT',
      why: 'synthetic patch exercising the vendor-patch machinery in tests',
    );

    List<Map<String, String>> committedManifest() =>
        (jsonDecode(File(p.join(vendorDir, 'manifest.json')).readAsStringSync())
                as List)
            .map((e) => (e as Map).cast<String, String>())
            .toList();

    test('every registry entry is a well-formed swap', () {
      // The class doc asserts find/replace cannot contain each other; that is
      // a comment where a check belongs, in the change whose whole point is
      // that a note is not an enforcement. If either contained the other, the
      // "already patched" branch could not tell the two states apart.
      for (final patch in vendorPatches) {
        expect(patch.replace.contains(patch.find), isFalse,
            reason: '${patch.file}: replace contains find');
        expect(patch.find.contains(patch.replace), isFalse,
            reason: '${patch.file}: find contains replace');
        expect(patch.find, isNot(patch.replace));
        expect(patch.why.trim(), isNotEmpty,
            reason: '${patch.file}: `why` is the only surviving record of the '
                'reasoning — SRI.md is generated from it');
      }
    });

    test('applyVendorPatches rewrites the upstream anchor exactly once', () {
      final upstream = latin1.encode('head;${testPatch.find};tail');
      expect(
          latin1.decode(applyVendorPatches(testPatch.file, upstream,
              registry: [testPatch])),
          'head;${testPatch.replace};tail');
    });

    test('applyVendorPatches is a no-op on an already-patched file', () {
      // Not the same as "anchor missing". Collapsing these two would fail
      // every run after the first, which is how a real check gets disabled.
      final already = latin1.encode('head;${testPatch.replace};tail');
      expect(
          latin1.decode(applyVendorPatches(testPatch.file, already,
              registry: [testPatch])),
          'head;${testPatch.replace};tail');
    });

    test('applyVendorPatches throws when upstream drifts past the anchor', () {
      expect(
          () => applyVendorPatches(
              testPatch.file, latin1.encode('unrelated bytes'),
              registry: [testPatch]),
          throwsA(predicate((e) =>
              '$e'.contains('no longer applies') &&
              '$e'.contains('do NOT drop'))));
      // Two anchors is drift too — replaceFirst would silently patch one.
      expect(
          () => applyVendorPatches(
              testPatch.file, latin1.encode('${testPatch.find}|${testPatch.find}'),
              registry: [testPatch]),
          throwsA(predicate((e) => '$e'.contains('occurs 2 times'))));
    });

    test('files with no registered patch pass through untouched', () {
      final bytes = latin1.encode('htmx bytes');
      expect(
          identical(
              applyVendorPatches('htmx.min.js', bytes, registry: [testPatch]),
              bytes),
          isTrue);
    });

    test('every committed vendored file still carries its local patch', () {
      // The backstop that does not care HOW the patch was lost — a stray
      // vendor-fetch, a bad merge, a manual re-download all fail here.
      for (final patch in vendorPatches) {
        final text = latin1
            .decode(File(p.join(vendorDir, patch.file)).readAsBytesSync());
        expect(text.contains(patch.replace), isTrue,
            reason: '${patch.file} lost its local patch — re-apply it with '
                '`arxa design vendor-fetch`, do not update this test.');
      }
    });

    test('committed SRI.md is byte-identical to its generator', () {
      // design_tools.dart:1089 promises re-running vendor-fetch rewrites
      // manifest.json + SRI.md byte-identically. This asserts it without a
      // network fetch, and it is the check that would have caught de28917a's
      // hand-written section the moment it was written.
      expect(vendorSriDoc(committedManifest()),
          File(p.join(vendorDir, 'SRI.md')).readAsStringSync(),
          reason: 'SRI.md is generated, not hand-written. If you edited a '
              "patch's `why` or added a registry entry, regenerate it: "
              'cd arxa && dart run tool/regen_vendor_docs.dart');
    });

    test('every patched file is named in THIRD-PARTY-NOTICES.md', () {
      // Apache-2.0 §4(b) wants modified files to carry prominent notice of the
      // change, and the notices file is the one artifact whose entire job is
      // provenance — it must not describe a patched bundle as the pristine
      // upstream release. Checked here so a second patch cannot be added
      // without the notice following it.
      final notices = File('../THIRD-PARTY-NOTICES.md').readAsStringSync();
      for (final patch in vendorPatches) {
        expect(notices, contains(patch.file),
            reason: '${patch.file} diverges from upstream but is not named in '
                'THIRD-PARTY-NOTICES.md');
      }
    });

    test('committed manifest records both hashes for a patched file', () {
      for (final patch in vendorPatches) {
        final row = committedManifest()
            .firstWhere((m) => m['file'] == patch.file);
        expect(row['upstreamIntegrity'], isNotNull,
            reason: '${patch.file} is patched, so the pristine hash must be '
                'recorded alongside the on-disk one');
        expect(row['integrity'], isNot(row['upstreamIntegrity']));
      }
    });

    test('no manifest row claims a divergence the registry does not own', () {
      // The inverse of the test above, and the one that bites after a REMOVED
      // patch: `upstreamIntegrity` is the divergence flag, so a row carrying
      // it with no matching registry entry is a stale claim — either the file
      // was reverted and the docs were not regenerated, or the registry entry
      // was dropped while the file still diverges (the lost-patch scenario).
      final registered = vendorPatches.map((p) => p.file).toSet();
      for (final row in committedManifest()) {
        if (row['upstreamIntegrity'] == null) continue;
        expect(registered, contains(row['file']),
            reason: '${row['file']} carries upstreamIntegrity but has no '
                'registered patch — run dart run tool/regen_vendor_docs.dart '
                '(it verifies the revert before erasing the record)');
      }
    });

    test('model-viewer.min.js is byte-identical to the pristine 4.3.1 release',
        () async {
      // Pinned to the release hash, not to the manifest, so this cannot drift
      // into self-consistency: the 60x far-plane edit was reverted after
      // verification (docs/research/model-viewer-far-plane-verification.md),
      // and this is what keeps the file reverted.
      expect(
          await sri(File(p.join(vendorDir, 'model-viewer.min.js'))
              .readAsBytesSync()),
          'sha384-cprcVQt7wbUl0xngF3PGP6yBB7n4/t+4AoAMG9biiMCGFiWOdzUH10Ie2COTqFNW');
    });

    test('vendor-fetch re-applies the local patch to the file it downloads',
        () async {
      // THE caller test. The three above prove applyVendorPatches works; only
      // this one proves vendorFetch actually calls it — which is precisely the
      // gap that hid the settle-freeze defect in d86d4d37. Runs on the
      // synthetic patch via `registry:` since the production registry is
      // empty; the wiring under test is identical.
      const patch = testPatch;
      final upstreamBody = latin1.encode('/*stub*/${patch.find}//end');

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((req) => req.response
        ..contentLength = upstreamBody.length
        ..add(upstreamBody)
        ..close());
      final base = 'http://${server.address.host}:${server.port}';

      final out = Directory.systemTemp.createTempSync('vf_patch_');
      addTearDown(() => out.deleteSync(recursive: true));
      // `only` narrows to the one package: a full run needs a real lucide
      // tarball and a working esbuild, neither of which a fake server has.
      final r = await vendorFetch(out.path,
          baseUrl: '$base/cdn',
          registryBase: '$base/npm',
          only: {'@google/model-viewer'},
          registry: [patch]);
      expect(r.exitCode, 0, reason: r.stderrLines.join('\n'));

      final written =
          latin1.decode(File(p.join(out.path, patch.file)).readAsBytesSync());
      expect(written.contains(patch.replace), isTrue,
          reason: 'vendor-fetch wrote the pristine download — the patch was '
              'silently reverted, which is the whole defect this guards');
      expect(written.contains(patch.find), isFalse);
      expect(r.stdoutLines.join('\n'), contains('local patch re-applied'));

      // …and the provenance travels with it, in both files.
      final row = (jsonDecode(
                  File(p.join(out.path, 'manifest.json')).readAsStringSync())
              as List)
          .single as Map;
      expect(row['upstreamIntegrity'], await sri(upstreamBody));
      expect(row['integrity'], isNot(row['upstreamIntegrity']));
      final sriMd = File(p.join(out.path, 'SRI.md')).readAsStringSync();
      expect(sriMd, contains('## Local patches'));
      expect(sriMd, contains(patch.replace));
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

    test('skillRuntimeDir resolves from a foreign CWD (script-anchored)',
        () {
      // The from-scratch story: the agent works in ~/their-app, not in the
      // arxa checkout. The skill runtime is a property of the arxa
      // INSTALLATION — doctor must find it regardless of CWD.
      final home = Directory.current;
      final foreign = Directory.systemTemp.createTempSync('foreign_cwd');
      try {
        Directory.current = foreign;
        final htmx =
            File(p.join(skillRuntimeDir(), 'vendor', 'htmx.min.js'));
        expect(htmx.existsSync(), isTrue,
            reason:
                'runtime must resolve via the script location when the CWD '
                'walk fails, not via the foreign CWD');
        final ladder = File(p.join(skillRuntimeDir(), 'ladder.json'));
        expect(ladder.existsSync(), isTrue);
      } finally {
        Directory.current = home;
        foreign.deleteSync(recursive: true);
      }
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
  // Ported from skills/arxa-designer/runtime/eject.mjs: copies the artifact,
  // narrows vendor/ to the libs its HTML actually loads (with the
  // htmx-required HARD FAIL), writes the narrowed manifest, and emits a
  // README carrying the `arxa design serve . --no-watch` line — no node.
  // The .mjs's package.json + node-runtime copy + smoke.test.mjs are dropped.

  final String ejectFixture =
      p.absolute('../skills/arxa-designer/examples/hello-hda');

/// Recursive directory copy for eject tests that must mutate a private
/// fixture copy (the shared ejectFixture is the repo's own tree — read-only).
void copyFixtureTree(Directory src, Directory dst) {
  dst.createSync(recursive: true);
  for (final e in src.listSync()) {
    final target = p.join(dst.path, p.basename(e.path));
    if (e is Directory) {
      copyFixtureTree(e, Directory(target));
    } else if (e is File) {
      e.copySync(target);
    }
  }
}

  group('design eject', () {
    test('missing args → usage, exit 2', () async {
      expect((await designEject([])).exitCode, 2);
      expect((await designEject(['only-one'])).exitCode, 2);
      expect((await designEject([])).stderrLines.first, contains('usage'));
    });

    test('ejects hello-hda: copied artifact + narrowed vendor + README', () async {
      final out = _tmpDir();
      addTearDown(() => out.deleteSync(recursive: true));
      final r = await designEject([ejectFixture, out.path]);
      expect(r.exitCode, 0, reason: r.stderrLines.join('\n'));

      // 1. the artifact itself is copied (routes + a nested view).
      expect(File(p.join(out.path, 'app.routes.js')).existsSync(), isTrue);
      expect(
          File(p.join(out.path, 'ui', 'views', 'main_shell', 'home',
                  'home_view.tsx'))
              .existsSync(),
          isTrue);

      // 2. narrowed vendor: hello-hda loads htmx 4 only (head-support and
      //    preload are htmx-2 extensions removed in the v4 migration — htmx 4
      //    handles titles natively). mustache.min.js is vendored but NOT
      //    referenced → must be absent. alien-signals.min.js is force-included
      //    because hello-hda's home view declares a toggle island (Phase 3).
      final vendor = Directory(p.join(out.path, 'runtime', 'vendor'));
      expect(vendor.existsSync(), isTrue);
      final jsFiles = vendor
          .listSync()
          .whereType<File>()
          .map((f) => p.basename(f.path))
          .where((n) => n.endsWith('.js'))
          .toSet();
      expect(jsFiles, {'htmx4.min.js', 'alien-signals.min.js'});
      expect(
          File(p.join(vendor.path, 'mustache.min.js')).existsSync(), isFalse);

      // narrowed manifest: htmx4 + alien-signals (island force-include).
      final manifest = jsonDecode(
          File(p.join(vendor.path, 'manifest.json')).readAsStringSync()) as List;
      final files = manifest.map((e) => (e as Map)['file']).toSet();
      expect(files, {'htmx4.min.js', 'alien-signals.min.js'});

      // 3. README carries the target-aware quick start (Phase 1 eject).
      final readme = File(p.join(out.path, 'README.md')).readAsStringSync();
      expect(readme.toLowerCase(), contains('npm install'));

      // 4. Phase 3 islands machinery: islands.js + island-kit.js copied to
      //    assets/, toggle island bundled by esbuild, manifest injected.
      expect(File(p.join(out.path, 'assets', 'islands.js')).existsSync(), isTrue);
      expect(File(p.join(out.path, 'assets', 'island-kit.js')).existsSync(), isTrue);
      final chunk = File(p.join(out.path, 'assets', 'islands', 'toggle.js'));
      expect(chunk.existsSync(), isTrue, reason: 'esbuild should bundle toggle island');
      expect(chunk.readAsStringSync(), contains('export'));

      final baseTsx =
          File(p.join(out.path, 'ui', 'common', 'base.tsx')).readAsStringSync();
      expect(baseTsx, contains('id="island-manifest"'));
      expect(baseTsx, contains('/assets/islands.js'));

      // stdout mentions islands.
      expect(r.stdoutLines.any((l) => l.contains('islands:')), isTrue);

      // stdout next: line points at npm start.
      expect(r.stdoutLines.last, contains('npm start'));
    });

    test('referencing a non-vendored lib → exit 1', () async {
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
      final r = await designEject([d.path, out.path]);
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

    test('no htmx referenced → exit 1 (htmx-required hard fail)', () async {
      final d = _tmpDir();
      _write(d, 'app.routes.js', "export default [['GET','/']];\n");
      _write(d, 'index.html',
          '<script src="/assets/vendor/preload.min.js"></script>');
      final out = _tmpDir();
      addTearDown(() {
        d.deleteSync(recursive: true);
        out.deleteSync(recursive: true);
      });
      final r = await designEject([d.path, out.path]);
      expect(r.exitCode, 1);
      expect(r.stderrLines.first, contains('htmx.min.js'));
      expect(r.stderrLines.first, contains('refusing to eject'));
    });

    test('map-island artifact ejects the leaflet subdir incl. images/', () async {
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
      final r = await designEject([d.path, out.path]);
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

    test('node eject: port 4399 default, preload stub, README realtime', () async {
      final out = _tmpDir();
      addTearDown(() => out.deleteSync(recursive: true));
      final r = await designEject([ejectFixture, out.path]);
      expect(r.exitCode, 0, reason: r.stderrLines.join('\n'));

      // 4319 is the Dart design server's port — the ejected default is 4399.
      final server = File(p.join(out.path, 'server.js')).readAsStringSync();
      expect(server, contains('process.env.PORT ?? 4399'));

      // The stub keeps icon.tsx's './preload.js' import resolvable at
      // esbuild-bundle and tsc time; `null` means "use the filesystem".
      expect(
          File(p.join(out.path, 'runtime', 'preload.js')).readAsStringSync(),
          contains('preload = null'));

      final readme = File(p.join(out.path, 'README.md')).readAsStringSync();
      expect(readme, contains('## Realtime (SSE)'));
      expect(readme, contains('h.sse.publishPatch'));
    });

    test('cloudflare eject: vendor mirrored into the [assets] tree', () async {
      final out = _tmpDir();
      addTearDown(() => out.deleteSync(recursive: true));
      final r = await designEject([ejectFixture, out.path, '--target=cloudflare']);
      expect(r.exitCode, 0, reason: r.stderrLines.join('\n'));

      // /assets/vendor/htmx4.min.js must resolve via the [assets] binding.
      expect(
          File(p.join(out.path, 'assets', 'vendor', 'htmx4.min.js'))
              .existsSync(),
          isTrue);
      // lucide stays server-side only (Workers icons come from preload).
      expect(
          Directory(p.join(out.path, 'assets', 'vendor', 'lucide')).existsSync(),
          isFalse);

      // Real preload bundle (not the node stub) + wrangler is a dev tool.
      expect(
          File(p.join(out.path, 'runtime', 'preload.js')).readAsStringSync(),
          contains('"iconSvg"'));
      final pkg = jsonDecode(
          File(p.join(out.path, 'package.json')).readAsStringSync()) as Map;
      expect((pkg['devDependencies'] as Map).containsKey('wrangler'), isTrue);
      expect((pkg['dependencies'] as Map).containsKey('wrangler'), isFalse);
    });

    test('cloudflare eject: the energize gaps are healed upstream', () async {
      // A PRIVATE copy of the fixture: this test grafts an artifact-authored
      // pure helper into fixture_reader.js and authors a styles-law barrel —
      // exactly the shapes the energize engagement had to patch by hand
      // (landing/deploy/cloudflare-workers-plan.md "Local patches").
      final d = _tmpDir();
      addTearDown(() => d.deleteSync(recursive: true));
      copyFixtureTree(Directory(ejectFixture), Directory(d.path));

      final reader =
          File(p.join(d.path, 'services', 'repositories', 'fixture_reader.js'));
      expect(reader.existsSync(), isTrue,
          reason: 'fixture must carry a fixture_reader to graft onto');
      reader.writeAsStringSync(
          '${reader.readAsStringSync()}'
          '\n// artifact-authored pure helper (the anchorInternalHrefs shape)\n'
          'export function probeHelper(x) { return x * 2; }\n');

      final barrel = Directory(p.join(d.path, 'ui', 'styles', 'common'))
        ..createSync(recursive: true);
      File(p.join(barrel.path, 'styles.css'))
          .writeAsStringSync('/* styles-law barrel */\n');

      final out = _tmpDir();
      addTearDown(() => out.deleteSync(recursive: true));
      final r = await designEject([d.path, out.path, '--target=cloudflare']);
      expect(r.exitCode, 0, reason: r.stderrLines.join('\n'));

      // Gap 1 — the CF replacement keeps ONLY readFixture semantics but must
      // carry the artifact's pure tail: the facades import it, and without it
      // the worker bundle dies at esbuild time.
      final cfReader = File(
              p.join(out.path, 'services', 'repositories', 'fixture_reader.js'))
          .readAsStringSync();
      expect(cfReader, contains("from '../../runtime/preload.js'"),
          reason: 'the CF replacement must be in place');
      expect(cfReader, contains('probeHelper'),
          reason: 'the pure tail must survive the replacement');

      // Gap 2 — l10n ships createT but types.d.ts + helpers.js call the
      // declared createTranslator contract; and resolveLocale must honor the
      // path prefix (route-based locales: /fr IS the fr edition).
      final l10n =
          File(p.join(out.path, 'runtime', 'l10n.js')).readAsStringSync();
      expect(l10n, contains('createTranslator: createT'));
      expect(l10n, contains('Path prefix is the strongest signal'));

      // Gap 3 — style barrels serve at /ui/styles/<owner>/ while the [assets]
      // root is ./assets: mirror in, delegate the prefix in worker.js.
      expect(File(p.join(out.path, 'assets', 'styles', 'common', 'styles.css'))
          .existsSync(), isTrue);
      final worker = File(p.join(out.path, 'worker.js')).readAsStringSync();
      expect(worker, contains("startsWith('/ui/styles/')"));
      // Literal locale routes have no trailing-slash twins — 308 to canonical.
      expect(worker, contains('Response.redirect(url.toString(), 308)'));
    });

    test('vercel eject: fetch-handler entry + public/ static root', () async {
      final out = _tmpDir();
      addTearDown(() => out.deleteSync(recursive: true));
      final r = await designEject([ejectFixture, out.path, '--target=vercel']);
      expect(r.exitCode, 0, reason: r.stderrLines.join('\n'));

      // Zero-config Hono preset: default export becomes the Function — no
      // listening server, no legacy builds/routes vercel.json.
      final server = File(p.join(out.path, 'server.js')).readAsStringSync();
      expect(server, contains('export default app'));
      expect(server, isNot(contains('serve(')));
      expect(File(p.join(out.path, 'vercel.json')).existsSync(), isFalse);
      // Static files serve from public/ only — assets (incl. vendor) move.
      expect(
          File(p.join(out.path, 'public', 'assets', 'vendor', 'htmx4.min.js'))
              .existsSync(),
          isTrue);
      expect(Directory(p.join(out.path, 'assets')).existsSync(), isFalse);
    });

    test('islands without a base.tsx anchor fail loudly', () async {
      final d = _tmpDir();
      _write(d, 'app.routes.js', "export default [['GET','/']];\n");
      _write(d, 'index.html',
          '<script src="/assets/vendor/htmx4.min.js"></script>'
          '<div hx-island="toggle"></div>');
      final out = _tmpDir();
      addTearDown(() {
        d.deleteSync(recursive: true);
        out.deleteSync(recursive: true);
      });
      final r = await designEject([d.path, out.path]);
      expect(r.exitCode, 1);
      expect(r.stderrLines.first, contains('island manifest'));
    });

    // The plan-20.5 serve smoke: the ejected copy renders + serves htmx on
    // the Dart design server, booted in-process.
    test('serve smoke: ejected copy serves / and htmx (in-process)', () async {      final out = _tmpDir();
      addTearDown(() => out.deleteSync(recursive: true));
      await designEject([ejectFixture, out.path]);

      final srv = await DesignServer.start(
        dialStore: MemoryDialStore(),
        artifactDir: out.path,
        port: 0,
        noWatch: true,
        runtimeVendorDir: p.join(out.path, 'runtime', 'vendor'),
      );
      try {
        final home = await _ejectGet(srv.url);
        expect(home.status, 200);
        expect(home.body.toLowerCase(), contains('<html'));

        final htmx = await _ejectGet('${srv.url}assets/vendor/htmx4.min.js');
        expect(htmx.status, 200);
        expect(htmx.body, contains('htmx'));
      } finally {
        await srv.stop();
      }
    });
  });

  // ── eject: R4/M6/M7/minors (2026-08-07 fix wave) ──────────────────────
  group('design eject — typing moat + kit facades', () {
    test('route manifest: hyphenated paths emit quoted keys, comments emit no false routes', () async {
      final d = _tmpDir();
      _write(d, 'app.routes.js', '''
export default [
  ['GET', '/', h.page],
  ['GET', '/order-items', h.list],
  // ['GET', '/ghost', h.ghost] — kept for reference; must NOT emit a route
  /* ['GET', '/ghost2', h.ghost2] */
];
''');
      _write(d, 'index.html',
          '<script src="/assets/vendor/htmx4.min.js"></script>');
      final out = _tmpDir();
      addTearDown(() {
        d.deleteSync(recursive: true);
        out.deleteSync(recursive: true);
      });
      final r = await designEject([d.path, out.path]);
      expect(r.exitCode, 0, reason: r.stderrLines.join('\n'));

      final routesJs =
          File(p.join(out.path, 'runtime', 'routes.js')).readAsStringSync();
      // A hyphenated segment is not a valid bare JS identifier — the key must
      // be quoted, or the emitted module is a syntax error.
      expect(routesJs, contains('"order-items": () => "/order-items"'));
      // Commented-out routes are comments, not routes.
      expect(routesJs, isNot(contains('ghost')));
      final routesDts =
          File(p.join(out.path, 'runtime', 'routes.d.ts')).readAsStringSync();
      expect(routesDts, contains('"order-items": () => "/order-items";'));
      expect(routesDts, isNot(contains('ghost')));
    });

    test('checkJs is on and the typecheck script drops the redundant --noEmit', () async {
      final out = _tmpDir();
      addTearDown(() => out.deleteSync(recursive: true));
      final r = await designEject([ejectFixture, out.path]);
      expect(r.exitCode, 0, reason: r.stderrLines.join('\n'));

      // R4: the moat is live — the whole ejected tree is typechecked.
      final tsconfig = jsonDecode(
          File(p.join(out.path, 'tsconfig.json')).readAsStringSync()) as Map;
      expect((tsconfig['compilerOptions'] as Map)['checkJs'], isTrue);

      // tsconfig sets noEmit; restating it in the script was redundant.
      final pkg = jsonDecode(
          File(p.join(out.path, 'package.json')).readAsStringSync()) as Map;
      expect((pkg['scripts'] as Map)['typecheck'], 'tsc -p .');
    });

    test('kit facades take env explicitly; publishable keys emit client config', () async {
      final out = _tmpDir();
      addTearDown(() => out.deleteSync(recursive: true));
      final r = await designEject(
          [ejectFixture, out.path, '--kits=maps,payments,data']);
      expect(r.exitCode, 0, reason: r.stderrLines.join('\n'));

      // M6: no module-scope process.env reads — facades take env as an
      // argument and fail at boot with a named error (Workers have no
      // process.env). Doc comments may NAME it; reads (`process.env.X`) may
      // not appear.
      for (final f in ['stripe.js', 'supabase.js', 'maps.js']) {
        final src = File(p.join(out.path, 'services', 'facades', f))
            .readAsStringSync();
        expect(src, isNot(contains('process.env.')),
            reason: '$f must not read process.env');
      }
      final stripe = File(p.join(out.path, 'services', 'facades', 'stripe.js'))
          .readAsStringSync();
      expect(stripe, contains('export function createStripe(env)'));
      // M7: the realtime bridges are code, not comments.
      expect(stripe, contains('constructEventAsync'));
      expect(stripe, contains('waitUntil'));
      final supabase =
          File(p.join(out.path, 'services', 'facades', 'supabase.js'))
              .readAsStringSync();
      expect(supabase, contains('handleDatabaseWebhook'));
      expect(supabase, contains('x-webhook-secret'));

      // Publishable → client config; secrets never land there.
      final clientConfig =
          File(p.join(out.path, 'runtime', 'client_config.js'))
              .readAsStringSync();
      expect(clientConfig, contains('MAPBOX_PUBLIC_TOKEN'));
      expect(clientConfig, contains('STRIPE_PUBLISHABLE_KEY'));
      expect(clientConfig, isNot(contains('STRIPE_SECRET_KEY')));
      expect(clientConfig, isNot(contains('SUPABASE_SERVICE_ROLE_KEY')));

      // The new webhook secrets are documented in .env.example.
      final envExample =
          File(p.join(out.path, '.env.example')).readAsStringSync();
      expect(envExample, contains('STRIPE_WEBHOOK_SECRET'));
      expect(envExample, contains('SUPABASE_WEBHOOK_SECRET'));
    });
  });

  group('generateRenderTsx — default-export name collisions', () {
    // The energize-studio defect: two view files default-exported a component
    // named AccessPage; the generated render module imported both bare and the
    // second binding stole both registry entries (one route rendered the
    // other view). Defaults now alias on repeat, like fragments already did.
    test('two views sharing a default-export name get distinct bindings', () {
      final app = _tmpDir();
      addTearDown(() => app.deleteSync(recursive: true));
      for (final dir in ['app_shell/access', 'staff_shell/access']) {
        _write(app, 'ui/views/$dir/${dir.contains('app_shell') ? 'access_view' : 'staff_access_view'}.tsx',
            "import type { FC } from 'hono/jsx';\n"
            'const AccessPage: FC = () => null;\n'
            'export default AccessPage;\n');
      }
      final out = generateRenderTsx(app.path);
      // one bare binding, one aliased — and the registry references BOTH
      expect(RegExp(r"import AccessPage from ").allMatches(out).length, 1);
      // 34082c57 aliased via { default as X } — `import X as Y` is not
      // valid ESM; this expectation tracks the real (valid) emit.
      expect(out,
          contains("import { default as AccessViewAccessPage } from"));
      expect(out, contains("'ui/views/staff_shell/access/staff_access_view.html': { default: AccessPage "));
      expect(out,
          contains("'ui/views/app_shell/access/access_view.html': { default: AccessViewAccessPage "));
    });
  });
}
