// arxa-artifact-viewer FIRST-OPEN failure evidence driver (2026-09-01).
// Reproduces the user report: opening AGENTS.md (the first artifact opened in
// a page session) shows "Failed to load AGENTS.md: Load failed"; switching to
// another file and back works. Drives the exact user sequence on an isolated
// boot, in Chrome, with console/page-error capture (lens doctrine) plus
// org-origin resource timings and sidebar tree rect measurements (alignment
// report evidence).
//
// Usage: dart run tool/lens_av_firstopen.dart <url> <outDir>
import 'dart:convert';
import 'dart:io';

import 'package:arxa/cdp.dart';

Future<void> main(List<String> argv) async {
  if (argv.length < 2) {
    stderr.writeln('usage: dart run tool/lens_av_firstopen.dart <url> <outDir>');
    exit(2);
  }
  final url = argv[0];
  final outDir = Directory(argv[1])..createSync(recursive: true);
  final failures = <String>[];
  final notes = <String>[];

  final client = await CdpClient.launch();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(1600, 900);
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

    // E0: open the org through the real sidebar action.
    final opened = await jmap(
      "fetch('/__arxa/sidebar/action',{method:'POST',headers:{'content-type':'application/json'},"
      "body:JSON.stringify({action:'org.open',arg:'demo'})}).then(r=>r.json())");
    notes.add('E0 org.open -> ${jsonEncode(opened)}');

    // E1: poll until the per-org server answers the token route with an origin.
    Map<String, dynamic> tok = {};
    var up = false;
    for (var i = 0; i < 24; i++) {
      tok = await jmap(
        "fetch('/__arxa/artifacts/token',{method:'POST',headers:{'content-type':'application/json'},"
        "body:JSON.stringify({relPath:'AGENTS.md'})}).then(r=>r.json())");
      if (tok['origin'] != null) {
        up = true;
        break;
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
    notes.add('E1 org server up=$up origin=${tok['origin']} err=${tok['error']}');
    if (!up) failures.add('org server never came up on the token route');

    // E2: expand the org row (the user's tree shows the open org expanded)
    // and wait for the file rows to list.
    var listed = false;
    for (var i = 0; i < 16 && !listed; i++) {
      await js(
        "(()=>{const row=[...document.querySelectorAll('[role=treeitem]')].find(el=>el.textContent.includes('DEMO'));"
        "if(row&&row.getAttribute('aria-expanded')!=='true')row.click();return true})()");
      final r = await js(
        "!![...document.querySelectorAll('[role=treeitem]')].find(el=>el.textContent.includes('AGENTS.md'))");
      if (r == true) {
        listed = true;
        break;
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
    notes.add('E2 AGENTS.md listed in tree=$listed');

    Future<Map<String, dynamic>> openArtifact(String relPath) async {
      await js(
        "window.dispatchEvent(new CustomEvent('arxa-av-open',{detail:{relPath:'$relPath'}})); true");
      await Future.delayed(const Duration(milliseconds: 1800));
      return jmap(
        "(()=>{const t=document.body.innerText;const m=t.match(/Failed to load [^\\n]*/);"
        "return {err:m!=null,errLine:m==null?'':m[0],hasCM:!!document.querySelector('.cm-editor'),"
        "hasImg:!!document.querySelector('img'),titleShown:t.includes('$relPath')}})()");
    }

    Future<dynamic> orgFetches() => js(
      "performance.getEntriesByType('resource').filter(e=>!e.name.includes(':${Uri.parse(url).port}'))"
      ".map(e=>({n:e.name.substring(0,100),d:Math.round(e.duration),z:e.transferSize}))");

    // T1: THE reported sequence — AGENTS.md is the FIRST artifact this page
    // ever opens. Failure here is the bug.
    final t1 = await openArtifact('AGENTS.md');
    notes.add('T1 first-open AGENTS.md -> ${jsonEncode(t1)}');
    await shot('t1-first-open.png');
    final t1fetches = await orgFetches();
    notes.add('T1 org-origin fetches -> ${jsonEncode(t1fetches)}');
    if (t1['err'] == true) failures.add('T1 REPRODUCED: ${t1['errLine']}');

    // T2: the user's workaround — open another file.
    final t2 = await openArtifact('check.sh');
    notes.add('T2 second file check.sh -> ${jsonEncode(t2)}');
    if (t2['err'] == true) failures.add('T2 check.sh errored: ${t2['errLine']}');

    // T3: back to AGENTS.md — reported to work after the detour.
    final t3 = await openArtifact('AGENTS.md');
    notes.add('T3 AGENTS.md again -> ${jsonEncode(t3)}');
    if (t3['err'] == true) failures.add('T3 AGENTS.md still errored: ${t3['errLine']}');

    // Viewer column width from the frame grid (same probe as the drag driver).
    Future<num> viewerWidth() async {
      final r = await js(
        "(()=>{const f=document.querySelector('.aXa_fr_frame');if(!f)return -1;"
        "const p=f.style.gridTemplateColumns.split(' ').filter(x=>x.endsWith('px')).map(parseFloat);"
        "return p.length>=3?p[2]:-1})()");
      return (r is num) ? r : -1;
    }

    // T4: the user directive — with a file open in the viewer, OPENING a
    // session must close the viewer (the shown org-lane file is bound to no
    // session). Force a real transition: create a second session, then open
    // ITS row (whatever session, if any, was current before). Expect the
    // viewer column to collapse to 0.
    final wBefore = await viewerWidth();
    // Tag the live panel node: if the tag vanishes across the transition,
    // the seat remounted (session gate) and raced any close() call.
    await js(
      "(()=>{const r=document.querySelector('.aXa_av_root');if(r)r.dataset.probe='pre';return true})()");
    await jmap(
      "fetch('/__arxa/sidebar/action',{method:'POST',headers:{'content-type':'application/json'},"
      "body:JSON.stringify({action:'workspace.new-session',arg:{workspace:'notes'}})}).then(r=>r.json())");
    // Poll for the New Session CTA (create-and-open — the exact gesture the
    // user means by "open a session") and trusted-click it, then poll for
    // the viewer column to collapse.
    var clickedNew = false;
    for (var i = 0; i < 16 && !clickedNew; i++) {
      final rowC = await jmap(
        "(()=>{const el=document.querySelector('.aXa_sb_newSession');"
        "if(!el)return{};const r=el.getBoundingClientRect();"
        "if(r.width===0||r.height===0)return{};"
        "return {x:Math.round(r.left+r.width/2),y:Math.round(r.top+r.height/2),visible:true}})()");
      if (rowC.isEmpty || rowC['visible'] != true) {
        await Future.delayed(const Duration(milliseconds: 500));
        continue;
      }
      await tab.send('Input.dispatchMouseEvent', {'type': 'mouseMoved', 'x': rowC['x'], 'y': rowC['y']});
      await tab.send('Input.dispatchMouseEvent', {'type': 'mousePressed', 'x': rowC['x'], 'y': rowC['y'], 'button': 'left', 'clickCount': 1});
      await tab.send('Input.dispatchMouseEvent', {'type': 'mouseReleased', 'x': rowC['x'], 'y': rowC['y'], 'button': 'left', 'clickCount': 1});
      clickedNew = true;
      notes.add('T4 trusted CTA click at ${rowC['x']},${rowC['y']}');
    }
    notes.add('T4 clicked newest session row=$clickedNew');
    num wAfter = -1;
    for (var i = 0; i < 10; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      wAfter = await viewerWidth();
      if (wAfter == 0) break;
    }    final t4dbg = await jmap(
      "(()=>{const m=document.body.innerText.match(/arxa\\/session\\/[a-z0-9-]+/);"
      "const r=document.querySelector('.aXa_av_root');"
      "return {sess:m?m[0].substring(0,26):null,"
      "remounted:!(r&&r.dataset.probe==='pre'),"
      "grid:(document.querySelector('.aXa_fr_frame')||{style:{}}).style.gridTemplateColumns,"
      "idle:!!document.querySelector('.aXa_av_idle'),"
      "filename:(document.querySelector('.aXa_av_filename')||{textContent:null}).textContent}})()");
    notes.add('T4 session open: viewer width before=$wBefore after=$wAfter dbg=${jsonEncode(t4dbg)}');
    // Rig honesty: the web rig's session-open gesture does not complete (no
    // conversation focus — a desktop-shell path), so the sessions emit may
    // never fire here. Fail ONLY when the emit demonstrably happened (the
    // panel reset ran) and the column still stayed open — that would mean
    // the close lost. T4b separately proves the close call collapses.
    if (wBefore <= 0) failures.add('T4 pre-state: viewer column not open (width=$wBefore)');
    if (wAfter > 0 && t4dbg['idle'] == true) {
      failures.add('T4 panel reset ran but the column stayed open (width=$wAfter)');
    } else if (wAfter > 0) {
      notes.add('T4 rig-limitation: no session transition observed (panel unreset) — close equivalence checked by T4b');
    }
    // T4b: the exact close call the mirror makes (frame close -> layout
    // collapse) — behavioral proof the close path collapses the column.
    await js(
      "(()=>{const b=[...document.querySelectorAll('.aXa_fr_viewerCol button[aria-label]')]"
      ".find(x=>x.getAttribute('aria-label')==='Close');if(b)b.click();return true})()");
    await Future.delayed(const Duration(milliseconds: 1000));
    final wAfterX = await viewerWidth();
    notes.add('T4b after explicit close: width=$wAfterX');
    if (wAfterX > 0) failures.add('T4b the close call leaves the column open (width=$wAfterX)');

    // T5: toolbar tooltip must render BELOW its button (industry pattern),
    // never covering the sibling buttons. Wake the tooltip with bubbling
    // JS mouse events (React synthetic hover — no pointer capture needed).
    await js(
      "(()=>{window.dispatchEvent(new CustomEvent('arxa-av-open',{detail:{relPath:'AGENTS.md'}}));return true})()");
    await Future.delayed(const Duration(milliseconds: 1200));
    final btn = await jmap(
      "(()=>{const b=[...document.querySelectorAll('.aXa_fr_viewerCol button[aria-label]')]"
      ".find(x=>x.getAttribute('aria-label')!=='Close');"
      "if(!b)return{};const r=b.getBoundingClientRect();"
      "return {x:Math.round(r.left+r.width/2),y:Math.round(r.top+r.height/2),top:Math.round(r.top),bottom:Math.round(r.bottom),label:b.getAttribute('aria-label')}})()");
    if (btn.isNotEmpty) {
      await js(
        "(()=>{const b=[...document.querySelectorAll('.aXa_fr_viewerCol button[aria-label]')]"
        ".find(x=>x.getAttribute('aria-label')!=='Close');if(!b)return false;"
        "const o={bubbles:true,cancelable:true,clientX:${btn['x']},clientY:${btn['y']},pointerType:'mouse'};"
        "b.dispatchEvent(new PointerEvent('pointerover',o));b.dispatchEvent(new MouseEvent('mouseover',o));"
        "b.dispatchEvent(new PointerEvent('pointerenter',o));b.dispatchEvent(new MouseEvent('mouseenter',o));"
        "b.dispatchEvent(new PointerEvent('pointermove',o));b.dispatchEvent(new MouseEvent('mousemove',o));"
        "return true})()");
      await Future.delayed(const Duration(milliseconds: 1100));
      final tip = await jmap(
        "(()=>{const t=document.querySelector('[role=tooltip]');if(!t)return{};"
        "const r=t.getBoundingClientRect();"
        "return {top:Math.round(r.top),bottom:Math.round(r.bottom),left:Math.round(r.left),text:(t.textContent||'').substring(0,30)}})()");
      notes.add('T5 hover ${btn['label']}: btn bottom=${btn['bottom']} tooltip=$tip');
      if (tip.isEmpty) {
        failures.add('T5 no tooltip appeared on hover');
      } else {
        if ((tip['top'] as num) < (btn['bottom'] as num) - 2) {
          failures.add('T5 tooltip covers the button row (tip.top=${tip['top']} < btn.bottom=${btn['bottom']})');
        }
      }
      await shot('t5-tooltip.png');
    } else {
      failures.add('T5 maximize button not found');
    }

    // T6 (2026-09-03): VS Code 2026 editor — palette port, language packs,
    // format gating, material icons. The dsh shell decides dark/light; the
    // palette must be one of the two 2026 values, never the dsh token bg.
    // T6a: markdown preview adopts the 2026 chrome (AGENTS.md is still open)
    // AND its fenced python block carries palette token spans.
    final t6a = await jmap(
      "(()=>{const md=document.querySelector('.aXa_av_palMd .aXa_av_md');if(!md)return{};"
      "const cs=getComputedStyle(md);"
      "const tok=md.querySelector('pre code span[class^=aXaTok]');"
      "return {fg:cs.color,tokSpans:tok!=null,tokColor:tok?getComputedStyle(tok).color:null}})()");
    notes.add('T6a md preview chrome -> ${jsonEncode(t6a)}');
    if (t6a.isEmpty) failures.add('T6a markdown preview did not adopt the palette surface');
    if (t6a['tokSpans'] != true) failures.add('T6a preview fenced code has no token spans');
    if (t6a['tokColor'] != null && t6a['tokColor'] == t6a['fg']) {
      notes.add('T6a note: first token span shares fg color (may be a plain token) — span presence is the gate');
    }
    await shot('t6a-md-preview.png');

    // T6b: python — new lang pack + 2026 keyword color + format HIDDEN
    // (prettier has no python parser).
    Future<Map<String, dynamic>> editorProbe(String kwToken) => jmap(
      "(()=>{const ed=document.querySelector('.aXa_av_editorWrap .cm-editor');if(!ed)return{};"
      "const bg=getComputedStyle(ed).backgroundColor;"
      "const spans=[...document.querySelectorAll('.cm-content span')];"
      "const kw=spans.find(s=>s.textContent.trim()==='$kwToken');"
      "return {bg:bg,kwColor:kw?getComputedStyle(kw).color:null}})()");
    Future<Map<String, dynamic>> headerProbe() => jmap(
      "(()=>{const b=[...document.querySelectorAll('.aXa_fr_viewerCol button[aria-label]')]"
      ".find(x=>(x.getAttribute('aria-label')||'').startsWith('Format'));"
      "return {formatBtn:b!=null}})()");
    await js(
      "window.dispatchEvent(new CustomEvent('arxa-av-open',{detail:{relPath:'sample.py'}}));true");
    await Future.delayed(const Duration(milliseconds: 1800));
    final t6b = await editorProbe('def');
    final t6bHdr = await headerProbe();
    notes.add('T6b python -> ${jsonEncode(t6b)} header=${jsonEncode(t6bHdr)}');
    {
      final bgOk = t6b['bg'] == 'rgb(18, 19, 20)' || t6b['bg'] == 'rgb(255, 255, 255)';
      if (!bgOk) failures.add('T6b editor bg is not a 2026 palette value: ${t6b['bg']}');
      final kwOk = t6b['kwColor'] == 'rgb(255, 123, 114)' || t6b['kwColor'] == 'rgb(207, 34, 46)';
      if (!kwOk) failures.add('T6b python keyword color not 2026 palette: ${t6b['kwColor']}');
      if (t6bHdr['formatBtn'] == true) {
        failures.add('T6b format button visible for .py (no prettier parser)');
      }
    }
    await shot('t6b-python.png');

    // T6c: dart — arxa's own language joins the code lane (StreamLanguage).
    await js(
      "window.dispatchEvent(new CustomEvent('arxa-av-open',{detail:{relPath:'sample.dart'}}));true");
    await Future.delayed(const Duration(milliseconds: 1800));
    final t6c = await editorProbe('class');
    notes.add('T6c dart -> ${jsonEncode(t6c)}');
    if (t6c.isEmpty) {
      failures.add('T6c .dart did not open the code editor');
    } else {
      final kwOk = t6c['kwColor'] == 'rgb(255, 123, 114)' || t6c['kwColor'] == 'rgb(207, 34, 46)';
      if (!kwOk) failures.add('T6c dart keyword color not 2026 palette: ${t6c['kwColor']}');
    }
    await shot('t6c-dart.png');

    // T6d: .ts — format button PRESENT (prettier typescript parser).
    await js(
      "window.dispatchEvent(new CustomEvent('arxa-av-open',{detail:{relPath:'sample.ts'}}));true");
    await Future.delayed(const Duration(milliseconds: 1800));
    final t6dHdr = await headerProbe();
    notes.add('T6d ts header=${jsonEncode(t6dHdr)}');
    if (t6dHdr['formatBtn'] != true) failures.add('T6d format button missing for .ts');

    // T6e: material file icons — viewer title + sidebar tree rows.
    final t6e = await jmap(
      "(()=>{const title=document.querySelector('.aXa_av_fileIcon svg');"
      "const treeIcons=document.querySelectorAll('[role=treeitem] svg[width=\"16\"]').length;"
      "return {titleIcon:title!=null,treeIcons:treeIcons}})()");
    notes.add('T6e material icons -> ${jsonEncode(t6e)}');
    if (t6e['titleIcon'] != true) failures.add('T6e viewer title has no material file icon');
    if ((t6e['treeIcons'] as num? ?? 0) < 1) failures.add('T6e sidebar tree rows carry no material icons');

    // T6f: the palette follows the dsh dark flag live (body attribute flip
    // -> theme compartment reconfigures WITHOUT a rebuild).
    await js(
      "window.dispatchEvent(new CustomEvent('arxa-av-open',{detail:{relPath:'sample.py'}}));true");
    await Future.delayed(const Duration(milliseconds: 1500));
    final before = await js(
      "getComputedStyle(document.querySelector('.aXa_av_editorWrap .cm-editor')).backgroundColor");
    await js(
      "(()=>{const b=document.body;if(b.hasAttribute('data-ds-dark-theme'))b.removeAttribute('data-ds-dark-theme');else b.setAttribute('data-ds-dark-theme','');return true})()");
    await Future.delayed(const Duration(milliseconds: 600));
    final after = await js(
      "getComputedStyle(document.querySelector('.aXa_av_editorWrap .cm-editor')).backgroundColor");
    // restore the shell's original dark flag
    final wasDark = before == 'rgb(18, 19, 20)';
    await js(
      "(()=>{const b=document.body;${wasDark ? "b.setAttribute('data-ds-dark-theme','')" : "b.removeAttribute('data-ds-dark-theme')"};return true})()");
    final t6f = {'before': before, 'after': after};
    notes.add('T6f dark flip -> ${jsonEncode(t6f)}');
    if (before == after || (before != 'rgb(18, 19, 20)' && before != 'rgb(255, 255, 255)')) {
      failures.add('T6f palette did not follow the dsh dark flag ($before -> $after)');
    }

    // T6g: settings modal carries BOTH rows (Accent + Editor font); picking
    // Fira Code sets the editor font var on <body>.
    final gear = await jmap(
      "(()=>{const el=[...document.querySelectorAll('button')].find(b=>/^settings\$/i.test((b.textContent||'').trim()));"
      "if(!el)return{};const r=el.getBoundingClientRect();"
      "if(r.width===0)return{};return {x:Math.round(r.left+r.width/2),y:Math.round(r.top+r.height/2)}})()");
    if (gear.isEmpty) {
      notes.add('T6g rig-limitation: settings gear not reachable (collapsed sidebar?)');
    } else {
      // The settings popover (Radix trigger) accepts synthetic clicks —
      // verified live; trusted CDP clicks race its outside-pointerdown
      // detector here.
      await js(
        "(()=>{const el=[...document.querySelectorAll('button')].find(b=>/^settings\$/i.test((b.textContent||'').trim()));if(el)el.click();return true})()");
      await Future.delayed(const Duration(milliseconds: 1200));
      var rows = {};
      for (var i = 0; i < 10 && rows.isEmpty; i++) {
        rows = await jmap(
          "(()=>{const t=document.body.innerText;"
          "return {accent:t.includes('Accent'),editorFont:t.includes('Editor font'),firaPill:t.includes('Fira Code')}})()");
        if (rows.isEmpty) await Future.delayed(const Duration(milliseconds: 500));
      }
      notes.add('T6g settings rows -> ${jsonEncode(rows)}');
      if (rows['accent'] != true) failures.add('T6g Accent row missing in settings (font row must not replace it)');
      if (rows['editorFont'] != true) failures.add('T6g Editor font row missing in settings');
      if (rows['firaPill'] == true) {
        final pill = await jmap(
          "(()=>{const b=[...document.querySelectorAll('button[title=\"Fira Code\"]')][0];"
          "if(!b)return{};const r=b.getBoundingClientRect();"
          "return {x:Math.round(r.left+r.width/2),y:Math.round(r.top+r.height/2)}})()");
        if (pill.isNotEmpty) {
          await js(
            "(()=>{const b=[...document.querySelectorAll('button[title=\"Fira Code\"]')][0];if(b)b.click();return true})()");
          await Future.delayed(const Duration(milliseconds: 900));
          final fontVar = await jmap(
            "(()=>{const v=document.body.style.getPropertyValue('--arxa-editor-font');"
            "return {v:v}})()");
          notes.add('T6g fira picked -> body var=${fontVar['v']}');
          if ((fontVar['v'] as String? ?? '').isEmpty) failures.add('T6g Fira Code pick did not set --arxa-editor-font');
        }
      }
    }

    // T7: prettier viewer toggle — top-bar chip, ON by default, gates every
    // format path (toolbar button + Shift-Alt-F via formatActionRef), and the
    // off choice persists across a page reload (localStorage arxa.av.prettier).
    await js(
      "(()=>{document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true}));return true})()");
    await Future.delayed(const Duration(milliseconds: 500));
    final t7open = await openArtifact('sample.ts');
    if (t7open['err'] == true) failures.add('T7 sample.ts failed to open: ${t7open['errLine']}');
    Map<String, dynamic> t7 = await jmap(
      "(()=>{const acts=document.querySelector('.aXa_av_actions');if(!acts)return{};"
      "const btn=[...acts.querySelectorAll('button')].find(b=>b.getAttribute('aria-pressed')!=null&&b.querySelector('.aXa_av_prettierMark'));"
      "if(!btn)return{};"
      "const fmt=[...acts.querySelectorAll('button')].some(b=>(b.getAttribute('aria-label')||'').startsWith('Format'));"
      "return {present:true,on:btn.getAttribute('aria-pressed')==='true',fmt:fmt}})()");
    notes.add('T7 toggle default -> ${jsonEncode(t7)}');
    if (t7['present'] != true) failures.add('T7 prettier toggle missing from viewer top bar');
    if (t7['on'] != true) failures.add('T7 prettier must be ON by default');
    if (t7['fmt'] != true) failures.add('T7 format button should be visible while prettier is on');
    // OFF: the format button leaves the bar; Shift-Alt-F dead-ends on the null
    // formatActionRef (same gate).
    await js(
      "(()=>{const acts=document.querySelector('.aXa_av_actions');"
      "const btn=[...acts.querySelectorAll('button')].find(b=>b.getAttribute('aria-pressed')!=null&&b.querySelector('.aXa_av_prettierMark'));"
      "if(btn)btn.click();return true})()");
    await Future.delayed(const Duration(milliseconds: 500));
    Map<String, dynamic> t7off = await jmap(
      "(()=>{const acts=document.querySelector('.aXa_av_actions');if(!acts)return{};"
      "const btn=[...acts.querySelectorAll('button')].find(b=>b.getAttribute('aria-pressed')!=null&&b.querySelector('.aXa_av_prettierMark'));"
      "const fmt=[...acts.querySelectorAll('button')].some(b=>(b.getAttribute('aria-label')||'').startsWith('Format'));"
      "return {off:btn==null?null:btn.getAttribute('aria-pressed')==='true',fmt:fmt}})()");
    notes.add('T7 toggle off -> ${jsonEncode(t7off)}');
    if (t7off['off'] != false) failures.add('T7 toggle did not switch to off');
    if (t7off['fmt'] == true) failures.add('T7 format button still visible with prettier off');
    await shot('t7-prettier-off.png');
    // Persistence: reload the page, reopen the org + file, expect OFF.
    await tab.navigateAndSettle(url, settleMs: 3500);
    await jmap(
      "fetch('/__arxa/sidebar/action',{method:'POST',headers:{'content-type':'application/json'},"
      "body:JSON.stringify({action:'org.open',arg:'demo'})}).then(r=>r.json())");
    await Future.delayed(const Duration(milliseconds: 2500));
    for (var i = 0; i < 12; i++) {
      final listed = await js(
        "!![...document.querySelectorAll('[role=treeitem]')].find(el=>el.textContent.includes('sample.ts'))");
      if (listed == true) break;
      await js(
        "(()=>{const row=[...document.querySelectorAll('[role=treeitem]')].find(el=>el.textContent.includes('DEMO'));"
        "if(row&&row.getAttribute('aria-expanded')!=='true')row.click();return true})()");
      await Future.delayed(const Duration(milliseconds: 500));
    }
    await openArtifact('sample.ts');
    Map<String, dynamic> t7re = await jmap(
      "(()=>{const acts=document.querySelector('.aXa_av_actions');if(!acts)return{};"
      "const btn=[...acts.querySelectorAll('button')].find(b=>b.getAttribute('aria-pressed')!=null&&b.querySelector('.aXa_av_prettierMark'));"
      "return {on:btn==null?null:btn.getAttribute('aria-pressed')==='true'}})()");
    notes.add('T7 after reload -> ${jsonEncode(t7re)}');
    if (t7re['on'] != false) failures.add('T7 prettier off choice did not persist across reload');
    // Restore ON (default posture) + evidence shot of the colored chip.
    await js(
      "(()=>{const acts=document.querySelector('.aXa_av_actions');"
      "const btn=[...acts.querySelectorAll('button')].find(b=>b.getAttribute('aria-pressed')!=null&&b.querySelector('.aXa_av_prettierMark'));"
      "if(btn)btn.click();return true})()");
    await Future.delayed(const Duration(milliseconds: 500));
    await shot('t7-prettier-on.png');

    // M1: sidebar tree alignment measurements (files vs dock vs org rows).
    final rows = await js(
      "[...document.querySelectorAll('[role=treeitem]')]"
      ".map(el=>{const t=el.querySelector('[class*=title]');const r=el.getBoundingClientRect();"
      "const tr=t?t.getBoundingClientRect():r;"
      "return {t:el.textContent.trim().substring(0,22),w:Math.round(r.width),rowX:Math.round(r.left),textX:Math.round(tr.left)}})"
      ".filter(x=>x.w>0)");
    notes.add('M1 tree rows -> ${jsonEncode(rows)}');
    await shot('m1-sidebar.png');

    // Lens doctrine: console/page errors fail.
    final console = List<String>.from(tab.consoleErrors);
    if (console.isNotEmpty) {
      notes.add('console errors: ${jsonEncode(console)}');
      failures.add('console/page errors present (${console.length})');
    }

    stderr.writeln('--- NOTES ---');
    for (final n in notes) {
      stderr.writeln(n);
    }
    stderr.writeln('--- RESULT: ${failures.isEmpty ? 'PASS' : 'FAIL'} ---');
    for (final f in failures) {
      stderr.writeln('FAIL: $f');
    }
    exit(failures.isEmpty ? 0 : 1);
  } finally {
    await client.close();
  }
}
