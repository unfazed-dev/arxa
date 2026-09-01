// arxa-studio EDITOR FONT smoke test (2026-09-03) — the USER flow, end to end.
// Drives the real UI only (no console shortcuts for the state change):
//   open org -> open sample.ts (editor visible) -> measure editor glyphs
//   -> sidebar Settings -> click the Fira Code pill -> close modal
//   -> assert the OPEN editor changed live (computed font + glyph widths + shot)
//   -> reload the page (no settings touched) -> assert the choice persisted
//   -> settings -> Default -> close -> assert restored.
//
// Usage: dart run tool/lens_av_font_smoke.dart <url> <outDir> [orgId] [relPath]
import 'dart:convert';
import 'dart:io';

import 'package:arxa/cdp.dart';

Future<void> main(List<String> argv) async {
  if (argv.length < 2) {
    stderr.writeln('usage: dart run tool/lens_av_font_smoke.dart <url> <outDir>');
    exit(2);
  }
  final url = argv[0];
  final outDir = Directory(argv[1])..createSync(recursive: true);
  final orgId = argv.length > 2 ? argv[2] : 'demo';
  final relPath = argv.length > 3 ? argv[3] : 'sample.ts';
  final orgName = argv.length > 4 ? argv[4] : orgId;
  final notes = <String>[];
  final failures = <String>[];

  final client = await CdpClient.launch();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(1280, 800);

    Future<dynamic> js(String expr) => tab.evaluate(expr);
    Future<Map<String, dynamic>> jmap(String expr) async {
      final r = await js(expr);
      if (r is Map<String, dynamic>) return r;
      return {};
    }

    Future<void> shot(String name) async {
      final png = await tab.screenshot();
      File('${outDir.path}/$name').writeAsBytesSync(png);
    }

    // Geometry + computed-font snapshot of the LIVE editor. Block .cm-line
    // divs always fill their container, so measure the TEXT advance via a
    // Range; note SF Mono and Fira Code are both 0.6em-advance monos, so
    // equal widths on ligature-free lines are expected — the wiring proof is
    // the computed family + the face actually loading (browsers only load a
    // face that is used).
    const editorProbe = '''
(async () => {
  const cm = document.querySelector('.aXa_av_editorWrap .cm-content');
  if (!cm) return { err: 'no cm-content' };
  const line = cm.querySelector('.cm-line');
  let textW = null;
  if (line) { const r = document.createRange(); r.selectNodeContents(line);
    textW = +r.getBoundingClientRect().width.toFixed(1); }
  const ligW = (fam) => { const s = document.createElement('span');
    s.style.cssText = 'position:absolute;visibility:hidden;white-space:pre;font-size:14px;font-family:' + fam;
    s.textContent = 'a => b => c  !==  !==';
    document.body.appendChild(s); const w = +s.getBoundingClientRect().width.toFixed(1);
    s.remove(); return w; };
  const faces = [...document.fonts].filter(f => f.family.includes('Fira')).map(f => f.status);
  return { computed: getComputedStyle(cm).fontFamily.slice(0, 60),
    fira: getComputedStyle(cm).fontFamily.includes('Fira Code Variable'),
    firaFaces: faces,
    textWidth: textW,
    ligFira: ligW("'Fira Code Variable'"), ligSfMono: ligW("'SF Mono'") };
})()''';

    Future<void> closeSettings() async {
      await js(
        "(()=>{const b=[...document.querySelectorAll('button')].find(x=>x.getAttribute('aria-label')==='Close'||x.closest('[role=dialog]'));return true})()");
      await js("(()=>{document.activeElement&&document.activeElement.blur();"
          "document.body.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true}));return true})()");
      await Future.delayed(const Duration(milliseconds: 400));
      // If the DSH modal is still open, click its close affordance.
      await js(
        "(()=>{const d=[...document.querySelectorAll('[role=dialog],.ds-modal,[class*=modal]')].find(x=>x.textContent.includes('Settings'));"
        "if(!d)return true;const b=[...d.querySelectorAll('button')].find(x=>{const s=getComputedStyle(x);return (x.textContent.trim()===''||x.textContent.includes('✕'))&&s.width!=='auto'});"
        "if(b)b.click();return true})()");
      await Future.delayed(const Duration(milliseconds: 400));
    }

    Future<Map<String, dynamic>> pickPill(String label) async {
      // Open settings via the sidebar footer button (the real entry point).
      await js(
        "(()=>{const b=[...document.querySelectorAll('button,[role=button]')].find(x=>(x.getAttribute('aria-label')||'').toLowerCase().includes('setting')||x.textContent.trim()==='Settings');if(b)b.click();return true})()");
      await Future.delayed(const Duration(milliseconds: 900));
      final r = await jmap(
        "(()=>{const g=[...document.querySelectorAll('[role=radiogroup]')].find(x=>x.getAttribute('aria-label')==='Editor font');"
        "if(!g)return{ok:false,why:'no Editor font radiogroup (settings not open?)'};"
        "const pill=[...g.querySelectorAll('button')].find(b=>b.textContent.includes('$label'));"
        "if(!pill)return{ok:false,why:'no $label pill',pills:[...g.querySelectorAll('button')].map(x=>x.textContent.trim())};"
        "pill.click();return{ok:true}})()");
      await Future.delayed(const Duration(milliseconds: 600));
      await closeSettings();
      return r;
    }

    await tab.navigateAndSettle(url, settleMs: 3500);
    await js(
      "(()=>{const b=[...document.querySelectorAll('button')].find(x=>x.textContent.trim()==='Continue');if(b)b.click();return true})()");
    await Future.delayed(const Duration(milliseconds: 500));
    await js("document.body.setAttribute('data-ds-dark-theme',''); true");

    await jmap(
      "fetch('/__arxa/sidebar/action',{method:'POST',headers:{'content-type':'application/json'},"
      "body:JSON.stringify({action:'org.open',arg:'$orgId'})}).then(r=>r.json())");
    for (var i = 0; i < 16; i++) {
      await js(
        "(()=>{const row=[...document.querySelectorAll('[role=treeitem]')].find(el=>el.textContent.includes('$orgName'));"
        "if(row&&row.getAttribute('aria-expanded')!=='true')row.click();return true})()");
      final listed = await js(
        "!![...document.querySelectorAll('[role=treeitem]')].find(el=>el.textContent.includes('$relPath'))");
      if (listed == true) break;
      await Future.delayed(const Duration(milliseconds: 500));
    }
    await js(
      "window.dispatchEvent(new CustomEvent('arxa-av-open',{detail:{relPath:'$relPath'}})); true");
    await Future.delayed(const Duration(milliseconds: 2000));

    // S0: baseline (default mono).
    final s0 = await jmap(editorProbe);
    notes.add('S0 default -> ${jsonEncode(s0)}');
    await shot('smoke-0-default.png');

    // S1: pick Fira Code — the editor must change LIVE (no reload).
    final p1 = await pickPill('Fira');
    final s1 = await jmap(editorProbe);
    notes.add('S1 pick fira -> ${jsonEncode(p1)} ${jsonEncode(s1)}');
    await shot('smoke-1-fira-live.png');
    if (p1['ok'] != true) failures.add('fira pick failed: ${p1['why']}');
    if (s1['fira'] != true) {
      failures.add('editor did NOT switch to Fira live (computed: ${s1['computed']})');
    }
    final loaded = (s1['firaFaces'] as List?)?.contains('loaded') ?? false;
    if (!loaded) failures.add('Fira face not loaded after switch (only used faces load): ${s1['firaFaces']}');
    notes.add('   text advance: default=${s0['textWidth']} fira=${s1['textWidth']} '
        '(equal is expected: both 0.6em-advance monos on ligature-free lines); '
        'ligature string width fira=${s1['ligFira']} sfMono=${s1['ligSfMono']}');

    // S2: reload — no settings interaction — choice must persist.
    await tab.navigateAndSettle(url, settleMs: 3500);
    await js(
      "(()=>{const b=[...document.querySelectorAll('button')].find(x=>x.textContent.trim()==='Continue');if(b)b.click();return true})()");
    await Future.delayed(const Duration(milliseconds: 400));
    await jmap(
      "fetch('/__arxa/sidebar/action',{method:'POST',headers:{'content-type':'application/json'},"
      "body:JSON.stringify({action:'org.open',arg:'$orgId'})}).then(r=>r.json())");
    await Future.delayed(const Duration(milliseconds: 800));
    await js(
      "window.dispatchEvent(new CustomEvent('arxa-av-open',{detail:{relPath:'$relPath'}})); true");
    await Future.delayed(const Duration(milliseconds: 2000));
    final s2 = await jmap(editorProbe);
    notes.add('S2 after reload -> ${jsonEncode(s2)}');
    await shot('smoke-2-fira-after-reload.png');
    if (s2['fira'] != true) {
      failures.add('Fira choice did not persist across reload (computed: ${s2['computed']})');
    }

    // S3: restore Default.
    final p3 = await pickPill('Default');
    final s3 = await jmap(editorProbe);
    notes.add('S3 pick default -> ${jsonEncode(p3)} ${jsonEncode(s3)}');
    if (p3['ok'] != true) failures.add('default pick failed: ${p3['why']}');
    if (s3['fira'] == true) failures.add('editor still Fira after picking Default');

    stdout.writeln('RESULT: ${failures.isEmpty ? 'PASS' : 'FAIL'}');
    for (final f in failures) {
      stdout.writeln('FAIL: $f');
    }
    for (final n in notes) {
      stdout.writeln(n);
    }
  } finally {
    await client.close();
  }
}
