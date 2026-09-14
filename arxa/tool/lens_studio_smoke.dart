// arxa lens — live smoke of the RUNNING Arxa Studio desktop app.
//
// Walks the real shell surface with the app's own launch token: sidebar →
// org → project tree → track → session, capturing evidence at each step and
// asserting the git card renders with the seat's true local-only state.
//
// Auth: reads the per-boot token out of ~/.arxa/dsh/desktop-session.json —
// the same file the Tauri shell reads — and navigates it once so the engine's
// 303 mints the cookie. It does NOT use /?arxa-browser=<token>, the Settings
// override door, which CLAIMS the primary surface and would fight the live
// window. Set ARXA_LENS_UA to an ArxaShell UA before running, or the
// waiting-page referee parks this tab with "running as the desktop app".
//
// Usage: dart run tool/lens_studio_smoke.dart <outdir> [--discover]
//   --discover dumps the sidebar's clickable outline instead of asserting,
//   for when the DOM moves under the selectors below.
import 'dart:convert';
import 'dart:io';

import 'package:arxa/cdp.dart';

const _viewportW = 1280;
const _viewportH = 832;

int _failures = 0;
void check(String label, bool ok, [String extra = '']) {
  stdout.writeln('${ok ? 'PASS' : 'FAIL'}  $label${ok ? '' : '\n      $extra'}');
  if (!ok) _failures++;
}

String _sessionUrl() {
  final f = File(
      '${Platform.environment['HOME']}/.arxa/dsh/desktop-session.json');
  if (!f.existsSync()) {
    stderr.writeln('lens studio smoke: no desktop-session.json — app running?');
    exit(2);
  }
  return (jsonDecode(f.readAsStringSync()) as Map)['url'] as String;
}

/// Redact the token from anything we print, so evidence and logs stay safe.
String _redact(String s) =>
    s.replaceAll(RegExp(r'token=[A-Za-z0-9_.~+/-]+'), 'token=REDACTED');

Future<void> shot(CdpSession tab, String dir, String name) async {
  final png = await tab.screenshot();
  final f = File('$dir/$name.png')..writeAsBytesSync(png);
  stdout.writeln('      → ${f.path.split('/').last} (${png.length} bytes)');
}

Future<void> main(List<String> argv) async {
  final positional = argv.where((a) => !a.startsWith('--')).toList();
  if (positional.isEmpty) {
    stderr.writeln('usage: dart run tool/lens_studio_smoke.dart <outdir> [--discover]');
    exit(2);
  }
  final outDir = positional[0];
  Directory(outDir).createSync(recursive: true);
  final discover = argv.contains('--discover');
  final url = _sessionUrl();

  final client = await CdpClient.launch();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(_viewportW, _viewportH);
    await tab.navigate(url);
    // The studio is a live app: spinners and a pulsing logo mean settle never
    // converges, so wait on the surface being THERE rather than on stillness.
    final booted = await tab.waitForSelector('nav, aside, [class*="sidebar"]',
        timeout: const Duration(seconds: 20));
    check('the shell surface renders (not the parked browser card)', booted);

    final parked = await tab.evaluate(
        "document.body.innerText.includes('running as the desktop app')");
    check('not parked by the waiting-page referee', parked != true,
        'set ARXA_LENS_UA to an ArxaShell user agent');

    await shot(tab, outDir, '01-boot');

    if (discover) {
      final outline = await tab.evaluate(r"""
        (() => {
          const out = [];
          document.querySelectorAll('button,[role="button"],[role="treeitem"],a,li,summary')
            .forEach((el, i) => {
              const t = (el.innerText || '').trim().split('\n')[0].slice(0, 44);
              if (!t) return;
              const attrs = [...el.attributes]
                .filter(a => a.name.startsWith('data-') || a.name === 'role' || a.name === 'aria-label' || a.name === 'title')
                .map(a => a.name + '=' + a.value.slice(0, 40)).join(' ');
              out.push(`${el.tagName.toLowerCase()} | ${t} | ${attrs}`);
            });
          return out.slice(0, 90).join('\n');
        })()
      """);
      stdout.writeln('\n=== sidebar outline ===\n${_redact('$outline')}');
      await client.close();
      exit(0);
    }

    // 1. the org row
    final orgClicked = await tab.evaluate(r"""
      (() => {
        const el = [...document.querySelectorAll('[role="treeitem"]')]
          .find(e => (e.innerText||'').trim().split(/\r?\n/)[0] === 'WAW');
        if (!el) return false;
        el.click(); return true;
      })()
    """);
    check('the WAW organisation row is present and clickable', orgClicked == true);
    await Future<void>.delayed(const Duration(milliseconds: 2000));
    await shot(tab, outDir, '02-org-open');

    // 2. the track grammar, as RENDERED (98f2e93 seen through the lens, not
    //    asserted against a fixture): every stage container offers website +
    //    application, and `notes` offers neither — sessions bind to a track.
    final grammar = await tab.evaluate(r"""
      (() => {
        const rows = [...document.querySelectorAll('[role="treeitem"]')]
          .map(e => (e.innerText||'').trim().split(/\r?\n/)[0]);
        const stages = ['00-moodboard','01-intake','02-design','03-architecture',
                        '04-diagrams','05-scaffold','06-build','07-config','08-deploy'];
        const missing = [];
        for (const st of stages) {
          const i = rows.indexOf(st);
          if (i < 0) { missing.push(st + ':absent'); continue; }
          const next2 = rows.slice(i + 1, i + 3);
          if (!next2.includes('website') || !next2.includes('application')) {
            missing.push(st + ':' + JSON.stringify(next2));
          }
        }
        return JSON.stringify({ missing, tracks: rows.filter(r => r === 'application').length });
      })()
    """);
    final g = jsonDecode('$grammar') as Map;
    check('every stage container renders a website + application track row',
        (g['missing'] as List).isEmpty, '${g['missing']}');
    check('all nine stages carry a track row', g['tracks'] == 9, 'tracks=${g['tracks']}');

    await shot(tab, outDir, '03-track-grammar');

    // 3. the session under the track — the row the sidebar attaches by exact
    //    workspace string, so its presence proves the attachment too.
    final sid = await tab.evaluate(
        "(document.querySelector('[data-session-id]')||{}).dataset?.sessionId || ''");
    check('a session row is rendered under the application track',
        '$sid'.contains('/02-design/application/'),
        'no [data-session-id] under the track — exact-string row attachment failed');

    final opened = await tab.evaluate(r"""
      (() => {
        const el = document.querySelector('[data-session-id]');
        if (!el) return false;
        el.click(); return true;
      })()
    """);
    check('the session opens from the sidebar', opened == true);
    await Future<void>.delayed(const Duration(milliseconds: 4000));
    await shot(tab, outDir, '04-session-open');

    // 3b. Decision 1 — a session created while the conversation backend was
    //     down has dshSessionId: null. It is a LEGITIMATE session (its worktree
    //     and branch are real), so the row must still render and must SAY that
    //     its conversation is missing rather than click into silence. Measured
    //     against the live WAW row application-wt-260908-001, whose registry
    //     entry is {"dshSessionId": null, "dshStatus": "dsh-unavailable"}.
    final noConvo = await tab.evaluate(r"""
      (() => {
        const d = document.querySelector('.aXa_arxaNoConvoDot');
        return JSON.stringify({
          marked: !!d,
          label: d ? (d.getAttribute('aria-label') || '') : '',
          title: d ? (d.getAttribute('title') || '') : '',
          bailed: !!window.__arxaNoConversation,
          reason: (window.__arxaNoConversation || {}).reason || '',
        });
      })()
    """);
    final nc = jsonDecode('$noConvo') as Map;
    stdout.writeln('      no-convo: $nc');
    check('the row without a conversation carries the no-conversation mark',
        nc['marked'] == true,
        'no .aXa_arxaNoConvoDot — a session with dshSessionId:null renders '
        'indistinguishable from a healthy one');
    check('the mark is announced to assistive tech',
        '${nc['label']}'.isNotEmpty, 'aria-label="${nc['label']}"');
    check('the mark names WHY the conversation is missing, not just that it is',
        '${nc['title']}'.contains('dsh-unavailable'),
        'title="${nc['title']}" — dshStatus must reach the tooltip');
    check('clicking such a row is recorded as a refusal, not a silent return',
        nc['bailed'] == true,
        'window.__arxaNoConversation unset: arxaOpenConversation returned '
        'without leaving evidence, so nothing can distinguish "opened" from '
        '"gave up"');

    // The gap this pass exists to pin down. The console warn and the tooltip
    // are the ONLY signals; the composer keeps whatever conversation it held,
    // so the git card below correctly reports that OTHER seat (main) while the
    // user believes they selected their session. Nothing on screen contradicts
    // them. Passing needs a visible notice at click time, not a hover title.
    final toldOnClick = await tab.evaluate(r"""
      (() => {
        if (!window.__arxaNoConversation) return 'n/a';
        const t = document.body.innerText || '';
        return /no conversation|conversation (is )?(missing|unavailable)/i.test(t)
          ? 'visible' : 'silent';
      })()
    """);
    check('the refusal is visible on screen, not only in the console',
        toldOnClick == 'visible' || toldOnClick == 'n/a',
        'the click was refused ($toldOnClick) with no on-screen notice — the '
        'card below then reports a seat the user did not choose');

    // 3c. D117 — the tree carries VS Code-style decorations for the SELECTED
    //     session. The tree lists the ORG checkout, so only files that exist
    //     there can be decorated: a file created solely inside the session has
    //     no row to mark. Modified tracked files are the case that matters.
    final deco = await tab.evaluate(r"""
      (() => {
        const marks = [...document.querySelectorAll('.aXa_deco')].map((el) => ({
          letter: (el.textContent || '').trim(),
          label: el.getAttribute('aria-label') || '',
          row: ((el.closest('[role="treeitem"]') || {}).innerText || '').trim().split('\n')[0].slice(0, 30),
        }));
        return JSON.stringify({ count: marks.length, marks: marks.slice(0, 8) });
      })()
    """);
    final dc = jsonDecode('$deco') as Map;
    stdout.writeln('      decorations: $dc');
    check('the tree decorates the files this session changed',
        (dc['count'] as int) > 0,
        'no .aXa_deco in the tree — the map never reached the rows');
    check('every decoration is announced, not colour-only',
        (dc['marks'] as List).every((m) => '${(m as Map)['label']}'.isNotEmpty),
        '$dc');
    check('a decoration carries a letter, so it survives a colourblind reader',
        (dc['marks'] as List).every((m) => RegExp(r'^[MADR]$').hasMatch('${(m as Map)['letter']}')),
        '$dc');

    // 4. the git card itself (.aXa_gc_panel), expanded from its header
    final cardPresent = await tab.evaluate(
        "!!document.querySelector('.aXa_gc_panel')");
    check('the git card renders in the composer dock', cardPresent == true);

    final headerText = await tab.evaluate(
        "(document.querySelector('.aXa_gc_header')||{}).innerText || ''");
    // Was `RegExp('main').hasMatch(header)` — written against the value the
    // ORIGINAL BUG produced, so it went green precisely when the card was
    // showing the wrong seat. An assertion that ratifies the defect it was
    // meant to catch is worse than none. What is actually true: the header
    // always names SOME branch, and it may only say `main` when the composer
    // genuinely holds the org seat (which the refusal above explains).
    check('the card header reports a branch and a measured state',
        RegExp(r'\S').hasMatch('$headerText'), 'header is empty');
    check('the card does not present main as the seat of a session row the '
        'user selected',
        !RegExp(r'^\s*main\b').hasMatch('$headerText') || nc['bailed'] == true,
        'header="$headerText" while a session row was selected and its '
        'conversation DID open — the card bound to the org seat anyway');

    await tab.evaluate(
        "(()=>{const h=document.querySelector('.aXa_gc_header');if(h)h.click();return !!h})()");
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    await shot(tab, outDir, '05-git-card-open');

    final panel = await tab.evaluate(
        "(document.querySelector('.aXa_gc_panel')||{}).innerText || ''");
    final txt = '$panel'.replaceAll(RegExp(r'\s+'), ' ');
    stdout.writeln('      card: ${txt.length > 220 ? '${txt.substring(0, 220)}…' : txt}');

    check('the expanded card names the local-only state',
        txt.toLowerCase().contains('local-only') || txt.toLowerCase().contains('local only'),
        'card text: $txt');
    check('no GitHub-only affordance is offered on a local-only seat',
        !txt.contains('Open pull request') && !txt.contains('Merge pull request'),
        'a PR control was drawn for an unpublished org');

    // The + on a BARE stage row: the server refuses that workspace
    // (workspace-needs-track, 98f2e93), so the client must not offer a live
    // button there — a button that always errors is worse than no button.
    final bareCta = await tab.evaluate(r"""
      (() => {
        const b = [...document.querySelectorAll('button')]
          .find(e => (e.getAttribute('aria-label')||'') === 'New session in 02-design');
        if (!b) return 'absent';
        return b.disabled || b.getAttribute('aria-disabled') === 'true' ? 'disabled' : 'ENABLED';
      })()
    """);
    // Measured 2026-09-08: it is ENABLED, and clicking it creates nothing,
    // raises nothing and says nothing (session count 1 -> 1, no toast, no
    // console error). The server refuses the bare stage
    // (workspace-needs-track) and the dock CTA correctly disables itself with
    // the needsTrack tooltip, but this per-row + was never given the same
    // gate, so the user presses it and the app appears to ignore them. Silent
    // no-op, not a crash — and the honest fix is to disable it with the same
    // reason showing, in the bundled Rows region rather than here.
    check('the + on a bare stage row is disabled, not a silent no-op',
        bareCta == 'absent' || bareCta == 'disabled',
        'bare-stage + is $bareCta and clicking it does nothing, with no '
        'explanation — sessions must bind to website/application');

    // 5. lens doctrine: a runtime error fails the surface regardless of pixels
    check('no console errors', tab.consoleErrors.isEmpty,
        _redact(tab.consoleErrors.take(4).join(' | ')));
    check('no uncaught page errors', tab.pageErrors.isEmpty,
        _redact(tab.pageErrors.take(4).join(' | ')));
  } finally {
    await client.close();
  }

  stdout.writeln(_failures == 0
      ? '\nALL GREEN — evidence in $outDir'
      : '\n$_failures FAILURE(S) — evidence in $outDir');
  exit(_failures == 0 ? 0 : 1);
}
