// arxa-studio EDITOR FONT wiring driver (2026-09-03).
// User report: "the editor font fira code is not wired up" — picking Fira Code
// in Settings seemingly does nothing to the artifact-viewer editor.
// Probes EVERY layer of the chain so the failing layer names itself:
//   L1 storage        localStorage 'arxa.editorFont' after the click
//   L2 body inline    body.style --arxa-editor-font
//   L3 computed       getComputedStyle(.cm-content).fontFamily
//   L4 face reg'd     document.fonts families + check()
//   L5 network        HEAD the vendored woff2 on the page origin
//   L6 real load      document.fonts.load(...) resolved faces
//
// Usage: dart run tool/lens_av_font.dart <url> <outDir>
import 'dart:convert';
import 'dart:io';

import 'package:arxa/cdp.dart';

Future<void> main(List<String> argv) async {
  if (argv.length < 2) {
    stderr.writeln('usage: dart run tool/lens_av_font.dart <url> <outDir>');
    exit(2);
  }
  final url = argv[0];
  final outDir = Directory(argv[1])..createSync(recursive: true);
  final notes = <String>[];
  final failures = <String>[];

  String probe2wrap(String body) => body; // probes are self-calling IIFEs already

  final client = await CdpClient.launch();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(1280, 800);
    await tab.navigateAndSettle(url, settleMs: 3500);

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

    await js(
      "(()=>{const b=[...document.querySelectorAll('button')].find(x=>x.textContent.trim()==='Continue');if(b)b.click();return true})()");
    await Future.delayed(const Duration(milliseconds: 500));
    await js("document.body.setAttribute('data-ds-dark-theme',''); true");

    // Open the demo org + a code file so the CodeMirror editor exists.
    await jmap(
      "fetch('/__arxa/sidebar/action',{method:'POST',headers:{'content-type':'application/json'},"
      "body:JSON.stringify({action:'org.open',arg:'demo'})}).then(r=>r.json())");
    for (var i = 0; i < 16; i++) {
      await js(
        "(()=>{const row=[...document.querySelectorAll('[role=treeitem]')].find(el=>el.textContent.includes('DEMO'));"
        "if(row&&row.getAttribute('aria-expanded')!=='true')row.click();return true})()");
      final listed = await js(
        "!![...document.querySelectorAll('[role=treeitem]')].find(el=>el.textContent.includes('sample.ts'))");
      if (listed == true) break;
      await Future.delayed(const Duration(milliseconds: 500));
    }
    await js(
      "window.dispatchEvent(new CustomEvent('arxa-av-open',{detail:{relPath:'sample.ts'}})); true");
    await Future.delayed(const Duration(milliseconds: 1800));

    // BASELINE (before touching the font row).
    const probe = '''(async () => {
  const cm = document.querySelector('.aXa_av_editorWrap .cm-content');
  const bodyVar = document.body.style.getPropertyValue('--arxa-editor-font');
  const faces = [...document.fonts].map(f => f.family + ' [' + f.status + ']');
  const heads = [];
  for (const f of ['fira-code-latin.woff2', 'fira-code-latin-ext.woff2']) {
    try { const r = await fetch('/__arxa/artifacts/vendor/' + f, { method: 'HEAD' });
      heads.push(f + ':' + r.status + ':' + (r.headers.get('content-type') || '')); }
    catch (e) { heads.push(f + ':ERR:' + e.message); }
  }
  let loaded = null;
  try { loaded = (await document.fonts.load("14px 'Fira Code Variable'", '=>')).length; } catch (e) { loaded = 'ERR:' + e.message; }
  return {
    hasCM: !!cm,
    computed: cm == null ? null : getComputedStyle(cm).fontFamily,
    bodyVar: bodyVar || '(unset)',
    faces: faces,
    heads: heads,
    loadedCount: loaded,
    check: document.fonts.check("14px 'Fira Code Variable'"),
    stored: localStorage.getItem('arxa.editorFont')
  };
})()''';
    final baseline = await jmap(probe);
    // evaluate needs a plain expression — wrap handled below if needed.
    notes.add('BASELINE -> ${jsonEncode(baseline)}');

    // THE USER PATH: open Settings, click the Fira Code pill.
    final openedSettings = await jmap(
      "(()=>{const b=[...document.querySelectorAll('button,[role=button]')].find(x=>(x.getAttribute('aria-label')||'').toLowerCase().includes('setting')||x.textContent.trim()==='Settings');if(b){b.click();return{ok:true}}return{ok:false}})()");
    await Future.delayed(const Duration(milliseconds: 800));
    notes.add('settings open -> ${jsonEncode(openedSettings)}');

    final clicked = await jmap(
      "(()=>{const g=[...document.querySelectorAll('[role=radiogroup]')].find(x=>x.getAttribute('aria-label')==='Editor font');"
      "if(!g)return{ok:false,why:'no Editor font radiogroup'};"
      "const pill=[...g.querySelectorAll('button')].find(b=>b.textContent.includes('Fira'));"
      "if(!pill)return{ok:false,why:'no Fira pill',pills:g.querySelectorAll('button').length};"
      "pill.click();return{ok:true}})()");
    await Future.delayed(const Duration(milliseconds: 800));
    notes.add('fira click -> ${jsonEncode(clicked)}');

    final after = await jmap(probe);
    notes.add('AFTER -> ${jsonEncode(after)}');
    await shot('font-after-fira.png');

    // Phase-2 evidence: WHO sets font-family on cm-content/cm-editor?
    // CM's StyleModule uses hashed selectors (.ͼN) — match rules against the
    // live elements instead of grepping selector text.
    const cascade = '''
(() => {
  const cm = document.querySelector('.aXa_av_editorWrap .cm-content');
  const ed = document.querySelector('.aXa_av_editorWrap .cm-editor');
  const sc = document.querySelector(".aXa_av_editorWrap .cm-scroller");
  if (!cm || !ed) return { err: 'no editor' };
  const hits = [];
  const walk = (rules, sheetName) => {
    for (const r of rules) {
      if (r.selectorText) {
        if (!/font-family/.test(r.cssText || '')) continue;
        for (const [name, el] of [['cm-content', cm], ['cm-scroller', sc], ['cm-editor', ed]]) {
          if (!el) continue;
          let m = false;
          try { m = el.matches(r.selectorText) } catch {}
          if (m) hits.push({ on: name, sheet: sheetName, sel: r.selectorText.slice(0, 70),
            ff: (r.cssText.match(/font-family:[^;]+/) || [''])[0].slice(0, 90) });
        }
      }
      if (r.cssRules && r.cssRules.length) { try { walk(r.cssRules, sheetName) } catch {} }
    }
  };
  for (const s of document.styleSheets) {
    const nm = (s.ownerNode && s.ownerNode.dataset && (s.ownerNode.dataset.pluginCss || s.ownerNode.dataset.plugin))
      || (s.href || 'inline').slice(-44);
    try { walk(s.cssRules, nm) } catch (e) { hits.push({ on: '?', sheet: 'CORS:' + String(s.href).slice(-30) }) }
  }
  for (const s of document.adoptedStyleSheets || []) walk(s.cssRules, 'adopted');
  return { rules: hits,
    contentFF: getComputedStyle(cm).fontFamily,
    editorFF: getComputedStyle(ed).fontFamily };
})()''';
    final casc = await jmap(probe2wrap(cascade));
    notes.add('CASCADE -> ${jsonEncode(casc)}');

    // Shadow-root check: document.styleSheets can't see shadow sheets.
    const shadow = '''
(() => {
  const cm = document.querySelector('.aXa_av_editorWrap .cm-content');
  if (!cm) return { err: 'no cm' };
  const root = cm.getRootNode();
  const isShadow = root !== document;
  const out = { isShadow, mode: isShadow ? (root.mode || '?') : 'document',
    host: isShadow ? root.host.tagName + '.' + String(root.host.className).slice(0, 40) : null };
  if (isShadow) {
    const hits = [];
    for (const s of root.styleSheets || []) {
      for (const r of s.cssRules || []) {
        if (/font-family/.test(r.cssText || '')) hits.push({ sel: (r.selectorText || '').slice(0, 60),
          ff: (r.cssText.match(/font-family:[^;]+/) || [''])[0].slice(0, 90) });
      }
    }
    out.rules = hits;
  }
  return out;
})()''';
    final sh = await jmap(shadow);
    notes.add('SHADOW -> ${jsonEncode(sh)}');

    // Round 3: ancestor inheritance trace + shorthand `font:` rules +
    // is OUR rule (aXa_av_editorWrap) mounted at all?
    const inherit = '''
(() => {
  const cm = document.querySelector('.aXa_av_editorWrap .cm-content');
  if (!cm) return { err: 'no cm' };
  const chain = [];
  let el = cm;
  for (let i = 0; el && i < 8; i++, el = el.parentElement) {
    chain.push({ tag: el.tagName.toLowerCase(), cls: String(el.className).slice(0, 44),
      ff: getComputedStyle(el).fontFamily.slice(0, 60) });
  }
  const ours = [];
  const fontShorthand = [];
  const walk = (rules, sheetName) => {
    for (const r of rules) {
      if (r.cssRules) { try { walk(r.cssRules, sheetName) } catch {} continue }
      const sel = r.selectorText || '';
      const css = r.cssText || '';
      if (sel.includes('aXa_av_editorWrap')) ours.push({ sheet: sheetName, sel: sel.slice(0, 80) });
      if (/font\\s*:/.test(css) && !/font-family/.test(css)) {
        let m = false; try { m = cm.matches(sel) } catch {}
        if (m) fontShorthand.push({ sheet: sheetName, sel: sel.slice(0, 70), css: css.slice(0, 100) });
      }
    }
  };
  for (const s of document.styleSheets) {
    const nm = (s.ownerNode && s.ownerNode.dataset && (s.ownerNode.dataset.pluginCss || s.ownerNode.dataset.plugin))
      || (s.href || 'inline').slice(-44);
    try { walk(s.cssRules, nm) } catch {}
  }
  for (const s of document.adoptedStyleSheets || []) walk(s.cssRules, 'adopted');
  return { chain, ourEditorWrapRules: ours, fontShorthandMatches: fontShorthand };
})()''';
    final inh = await jmap(inherit);
    notes.add('INHERIT -> ${jsonEncode(inh)}');

    // Round 4: what does the MOUNTED panel.css actually contain?
    const mounted = '''
(() => {
  const tags = [...document.querySelectorAll('style[data-plugin]')].map(t => ({
    id: t.dataset.pluginCss || t.dataset.plugin, len: t.textContent.length,
    hasEditorWrap: t.textContent.includes('aXa_av_editorWrap'),
    hasCmContent: t.textContent.includes('cm-content'),
    hasScroller: t.textContent.includes('cm-scroller'),
    cmRules: (t.textContent.match(/[^{}]*cm-(?:content|scroller|editor)[^{]*\\{[^}]*\\}/g) || []).map(s => s.slice(0, 120))
  })).filter(t => t.id && t.id.includes('artifact') || t.hasCmContent);
  return { tags };
})()''';
    final mountedRes = await jmap(mounted);
    notes.add('MOUNTED -> ${jsonEncode(mountedRes)}');

    // Round 5: parse-error hunt — text selectors vs CSSOM selectors.
    const parsediff = '''
(() => {
  const tag = [...document.querySelectorAll('style[data-plugin-css]')].find(t => t.dataset.pluginCss === 'arxa-artifact-viewer/panel.css');
  if (!tag) return { err: 'no panel.css tag' };
  const sheet = tag.sheet;
  const parsed = [];
  const walk = (rules) => { for (const r of rules) { if (r.cssRules) { walk(r.cssRules); continue } if (r.selectorText) parsed.push(r.selectorText) } };
  try { walk(sheet.cssRules) } catch (e) { return { err: 'cssRules: ' + e.message } }
  const textSel = (tag.textContent.match(/[^{}@;]+\\{/g) || []).map(s => s.slice(0, -1).trim());
  const missing = [];
  for (let i = 0; i < textSel.length; i++) {
    const sel = textSel[i];
    if (!parsed.includes(sel)) missing.push({ i, sel: sel.slice(0, 80) });
  }
  const idx = tag.textContent.indexOf('aXa_av_editorWrap .cm-content{font-family');
  return {
    textSelectorCount: textSel.length, parsedRuleCount: parsed.length,
    firstMissing: missing.slice(0, 6),
    charIndexInText: idx,
    contextBefore: idx > 0 ? tag.textContent.slice(Math.max(0, idx - 220), idx).slice(-220) : null
  };
})()''';
    final pd = await jmap(parsediff);
    notes.add('PARSEDIFF -> ${jsonEncode(pd)}');

    // Phase-3 hypothesis test: is --dsw-font-mono an UNDEFINED token (IACVT)?
    const iacvt = '''
(async () => {
  const cs = getComputedStyle(document.documentElement);
  const body = getComputedStyle(document.body);
  const allRoot = [...new Set([...Array(cs.length).keys()].map(i => cs[i]))].filter(p => p.includes('font'));
  const cm = document.querySelector('.aXa_av_editorWrap .cm-content');
  const before = cm ? getComputedStyle(cm).fontFamily : null;
  // Minimal experiment: literal stack (no var()) on the same custom property.
  document.body.style.setProperty('--arxa-editor-font', "'Fira Code Variable', monospace");
  await new Promise(r => setTimeout(r, 120));
  const literalResult = cm ? getComputedStyle(cm).fontFamily : null;
  // And the exact current value for reference.
  document.body.style.setProperty('--arxa-editor-font', "var(--dsw-font-mono)");
  await new Promise(r => setTimeout(r, 120));
  const dswOnlyResult = cm ? getComputedStyle(cm).fontFamily : null;
  document.body.style.removeProperty('--arxa-editor-font');
  return { rootFontTokens: allRoot,
    dswFontMonoOnRoot: cs.getPropertyValue('--dsw-font-mono') || '(undefined)',
    dswFontMonoOnBody: body.getPropertyValue('--dsw-font-mono') || '(undefined)',
    dsFontFamilyCode: cs.getPropertyValue('--ds-font-family-code') || '(undefined)',
    computedWithLiteral: before,
    computedAfterLiteral: literalResult,
    computedWithDswVarOnly: dswOnlyResult };
})()''';
    final iv = await jmap(iacvt);
    notes.add('IACVT -> ${jsonEncode(iv)}');

    // Verdicts: the editor must COMPUTE Fira and the face must actually load.
    final computed = '${after['computed'] ?? baseline['computed'] ?? ''}';
    if (clicked['ok'] != true) failures.add('could not click the Fira pill: ${clicked['why']}');
    if (!computed.contains('Fira Code Variable')) {
      failures.add('cm-content computed font does not use Fira: $computed');
    }
    if (after['loadedCount'] == 0 || '${after['loadedCount']}'.startsWith('ERR')) {
      failures.add('Fira face did not LOAD: ${after['loadedCount']}');
    }
    final headStatus = '${(after['heads'] as List?)?.join(' ')}';
    if (!headStatus.contains('fira-code-latin.woff2:200')) {
      failures.add('woff2 route not 200 on page origin: $headStatus');
    }

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
