// dial_smoke.dart — verb-by-verb smoke of the Design Dial against a LIVE
// serve. Unlike dial_probe.dart (one happy-path story), this drives EVERY
// radial verb in isolation and asserts its observable contract, one check
// per line, so a regression names its verb:
//
//   S0  boot            config, 8 author verbs, shade OFF at boot
//   S1  fan             opens, every verb button on-screen
//   S2  design          arm → hover → select → facet edit → content facet →
//                       CSS escape hatch → commit request → reset all
//   S3  tokens          panel lists :root props → live override → auto-save
//   S4  pin             arm → composer → pin lands, badge counts
//   S5  list            rows → thread → kanban move → reply
//   S6  shade           slider drives the overlay opacity
//   S7  layers          switches hide/show their layer — panel chrome stays
//   S8  pen             armed canvas records strokes; Escape disarms it
//   S9  share           mint → guest mode (5 verbs) → dead token invalid
//
// Self-cleaning: SMOKE-prefixed pins (+replies/drawings) and the minted
// share link are deleted from Supabase at the end; the draft is cleared.
// The labeled DASHBOARD-CHECK demo row is never touched.
//
// Run with the server live:  dart run tool/dial_smoke.dart [base-url]
// (defaults to http://127.0.0.1:4319/)

import 'dart:convert';
import 'dart:io';
import 'package:arxa/cdp.dart';
import 'package:crypto/crypto.dart' show sha256;

String _base = 'http://127.0.0.1:4319';
final _frames = Directory('/tmp/dial-smoke');
int _fails = 0;
int _errMark = 0;
// The operator's pre-run draft, stashed at boot and restored in cleanup —
// smoke steps DELETE/replace the draft freely, and a run must never eat a
// live in-progress design draft (the draft IS the author's work-in-progress).
Map<String, dynamic>? _draftStash;
final _createdPinIds = <String>[];
String? _shareToken;

Future<dynamic> shadow(CdpSession tab, String js) => tab.evaluate(
    '(async () => { const R = document.getElementById("arxa-dial-host").shadowRoot; $js })()');

List<String> _newErrors(CdpSession tab) {
  final n = tab.consoleErrors.sublist(_errMark);
  _errMark = tab.consoleErrors.length;
  return n;
}

void report(String step, bool ok, String evidence, [List<String>? errs]) {
  if (!ok) _fails++;
  final e = (errs != null && errs.isNotEmpty) ? '  CONSOLE: ${errs.join(' | ')}' : '';
  print('${ok ? 'PASS' : 'FAIL'}  $step  $evidence$e');
}

Future<void> shot(CdpSession tab, String name) async {
  File('${_frames.path}/$name.png').writeAsBytesSync(await tab.screenshot());
}

Future<bool> waitBoot(CdpSession tab) async {
  // A reload (Reset all / Reset element) swaps the execution context out from
  // under an in-flight evaluate — "target navigated" is expected here, retry.
  for (var i = 0; i < 15; i++) {
    try {
      final b = await tab.evaluate('!!document.getElementById("arxa-dial-host")');
      if (b == true) return true;
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  return false;
}

// The smoke shares this machine with the studio, the design server's
// worker Chrome, and the operator's own browser; a few times per hour the
// renderer or the CDP socket stalls past the 30s evaluate timeout with the
// step's work already landed server-side. Retrying ONCE rides out the
// stall; every step's assertions are idempotent under a double-fire
// (contains-checks, and cleanup sweeps the extra rows).
Future<Map<String, dynamic>> js(CdpSession tab, String body) async =>
    jsonDecode(await _retryEval(tab, '(async () => { $body })()') as String)
        as Map<String, dynamic>;

Future<Map<String, dynamic>> jsShadow(CdpSession tab, String body) async =>
    jsonDecode(await _retryEval(
            tab,
            '(async () => { const R = document.getElementById("arxa-dial-host").shadowRoot; $body })()')
        as String) as Map<String, dynamic>;

Future<dynamic> _retryEval(CdpSession tab, String expr) async {
  try {
    return await tab.evaluate(expr);
  } catch (e) {
    if (!e.toString().contains('timed out')) rethrow;
    await Future<void>.delayed(const Duration(seconds: 2));
    return await tab.evaluate(expr);
  }
}

Future<void> main(List<String> args) async {
  if (args.isNotEmpty) _base = args[0].replaceAll(RegExp(r'/$'), '');
  _frames.createSync(recursive: true);
  final client = await CdpClient.launch();
  // A crashing step must never leak its headless Chrome: nine leaked
  // arxa-cdp instances from earlier crashed runs starved the machine hard
  // enough to make in-page fetches and CDP evaluates time out at random —
  // "dial bugs" that were really resource exhaustion. try/finally closes
  // the browser no matter which step throws.
  try {
  final tab = await client.newTab();
  await tab.enable();
  await tab.setViewport(1280, 800);
  await tab.navigateAndSettle('$_base/', settleMs: 2500);

  // ── S0 boot ──────────────────────────────────────────────────────────
  if (!await waitBoot(tab)) {
    print('FAIL  S0 boot  dial never booted');
    exit(1);
  }
  final boot = await js(tab, '''
    const host = document.getElementById("arxa-dial-host");
    const R = host.shadowRoot;
    const cfg = JSON.parse(document.getElementById("arxa-dial-config").textContent);
    return JSON.stringify({
      mode: cfg.mode, store: cfg.store, artifact: cfg.artifact,
      verbs: R.querySelectorAll(".verb").length,
      shadeOpacity: getComputedStyle(R.querySelector("#shade")).opacity,
      stamped: document.querySelectorAll("[data-arxa-id]").length,
    });
  ''');
  report(
      'S0 boot',
      boot['mode'] == 'author' && boot['verbs'] == 8 && (boot['stamped'] as int) > 0,
      jsonEncode(boot),
      _newErrors(tab));
  report('S0b shade-off-at-boot', boot['shadeOpacity'] == '0',
      'shade opacity at boot: ${boot['shadeOpacity']}');
  await shot(tab, 's0-boot');

  // Stash any live draft before the steps below mutate it.
  final d0 = await js(tab, '''
    const d = await (async () => { for (let a = 0; a < 4; a++) { try { return await fetch("/__dial/draft").then(r=>r.json()); } catch (e) { await new Promise(rr=>setTimeout(rr,300)); } } return {}; })();
    return JSON.stringify({draft: d.draft || null});
  ''');
  _draftStash = d0['draft'] as Map<String, dynamic>?;
  print('INFO  draft stash: ${_draftStash == null ? '(none)' : ('${(_draftStash!['patches'] as Map).keys.length} patches stashed')}');

  // ── S1 fan ───────────────────────────────────────────────────────────
  final fan = await jsShadow(tab, '''
    R.querySelector("#dockbtn").click();
    await new Promise(r=>setTimeout(r,500));
    const open = R.querySelector("#dock").classList.contains("open");
    const verbs = [...R.querySelectorAll(".verb")].map(v => {
      const r = v.getBoundingClientRect();
      return {verb: v.getAttribute("data-verb"),
              onscreen: r.width > 20 && r.left >= 0 && r.right <= window.innerWidth && r.top >= 0 && r.bottom <= window.innerHeight};
    });
    return JSON.stringify({open: open, verbs: verbs});
  ''');
  final allOn =
      (fan['verbs'] as List).every((v) => (v as Map)['onscreen'] == true);
  report('S1 fan', fan['open'] == true && allOn, jsonEncode(fan),
      _newErrors(tab));
  await shot(tab, 's1-fan');

  // ── S2 design ────────────────────────────────────────────────────────
  final sel = await jsShadow(tab, '''
    R.querySelector('[data-verb="design"]').click();
    await new Promise(r=>setTimeout(r,300));
    const target = document.querySelector("h1[data-arxa-id],h2[data-arxa-id],h3[data-arxa-id],p[data-arxa-id],a[data-arxa-id],button[data-arxa-id],[data-arxa-id]");
    if (!target) return JSON.stringify({fatal: "no stamped element"});
    target.scrollIntoView({block: "center"});
    await new Promise(r=>setTimeout(r,250));
    const r = target.getBoundingClientRect();
    const cx = Math.min(Math.max(r.left + r.width/2, 4), window.innerWidth-4);
    const cy = Math.min(Math.max(r.top + r.height/2, 4), window.innerHeight-4);
    document.dispatchEvent(new PointerEvent("pointermove", {clientX: cx, clientY: cy, bubbles: true}));
    await new Promise(r=>setTimeout(r,150));
    const hover = R.querySelector("#hover");
    const hoverShown = hover.style.display === "block" && hover.classList.contains("design");
    document.dispatchEvent(new MouseEvent("click", {clientX: cx, clientY: cy, bubbles: true}));
    await new Promise(r=>setTimeout(r,350));
    const panelOpen = R.querySelector("#panel").classList.contains("open");
    const idline = R.querySelector("#pbody .idline");
    const sects = [...R.querySelectorAll("#pbody .sect")].map(s=>s.textContent);
    return JSON.stringify({hoverShown: hoverShown, panelOpen: panelOpen,
      id: idline ? idline.textContent : null, sects: sects,
      outline: target.style.outline || ""});
  ''');
  final selOk = sel['hoverShown'] == true &&
      sel['panelOpen'] == true &&
      sel['id'] != null &&
      (sel['sects'] as List).any((s) => (s as String).startsWith('Facets'));
  report('S2a design-select', selOk, jsonEncode(sel), _newErrors(tab));
  await shot(tab, 's2-design-selected');
  if (!selOk || sel['id'] == null) {
    print('fatal: design selection broken — cannot continue S2');
    await client.close();
    exit(1);
  }
  // the idline is "machine-id → el:authored" when the divergence law
  // rebinds; the draft is keyed by the BINDING
  final rawIdline = sel['id'] as String;
  final selId = rawIdline.contains(' → ') ? rawIdline.split(' → ')[1] : rawIdline;

  final fac = await jsShadow(tab, '''
    const rows = [...R.querySelectorAll("#pbody .facet")];
    let prop = null, val = null;
    for (const row of rows) {
      const lab = row.querySelector("label");
      const inp = row.querySelector("input[type=text]");
      if (lab && inp && lab.textContent === "color") { prop = "color"; val = "rgb(1, 2, 3)"; break; }
    }
    if (!prop) {
      for (const row of rows) {
        const lab = row.querySelector("label");
        const inp = row.querySelector("input[type=text]");
        if (lab && inp && lab.textContent === "background") { prop = "background"; val = "rgb(3, 2, 1)"; break; }
      }
    }
    if (prop) {
      const row = rows.find(r2 => { const l = r2.querySelector("label"); return l && l.textContent === prop; });
      const inp = row.querySelector("input[type=text]");
      inp.value = val;
      inp.dispatchEvent(new Event("input", {bubbles: true}));
    }
    await new Promise(r=>setTimeout(r,1200));
    const selAttr = "$selId".indexOf("el:") === 0 ? "data-el" : "data-arxa-id";
    const selVal = selAttr === "data-el" ? "$selId".slice(3) : "$selId";
    const cands = [...document.querySelectorAll('[' + selAttr + '="' + selVal + '"]')];
    const el = cands.find(x => (x.style.outlineColor || "").indexOf("245") !== -1) || cands[0];
    const draft = await (async () => { for (let a = 0; a < 4; a++) { try { return await fetch("/__dial/draft").then(r=>r.json()); } catch (e) { await new Promise(rr=>setTimeout(rr,300)); } } return {}; })();
    const p = (draft.draft && draft.draft.patches) ? draft.draft.patches["$selId"] : null;
    return JSON.stringify({prop: prop, val: val,
      live: el && prop ? el.style.getPropertyValue(prop) : null,
      saved: p && p.style && prop ? (p.style[prop] || null) : null});
  ''');
  report(
      'S2b facet-edit',
      fac['prop'] != null && fac['live'] == fac['val'] && fac['saved'] == fac['val'],
      jsonEncode(fac),
      _newErrors(tab));

  final cont = await jsShadow(tab, '''
    const tas = [...R.querySelectorAll("#pbody textarea")];
    const content = tas.find(t => !t.placeholder || t.placeholder.indexOf("prop:") === -1);
    if (!content) return JSON.stringify({skipped: true});
    content.value = "SMOKE text edit";
    content.dispatchEvent(new Event("input", {bubbles: true}));
    await new Promise(r=>setTimeout(r,1200));
    const selAttr = "$selId".indexOf("el:") === 0 ? "data-el" : "data-arxa-id";
    const selVal = selAttr === "data-el" ? "$selId".slice(3) : "$selId";
    const cands = [...document.querySelectorAll('[' + selAttr + '="' + selVal + '"]')];
    const el = cands.find(x => (x.style.outlineColor || "").indexOf("245") !== -1) || cands[0];
    const draft = await (async () => { for (let a = 0; a < 4; a++) { try { return await fetch("/__dial/draft").then(r=>r.json()); } catch (e) { await new Promise(rr=>setTimeout(rr,300)); } } return {}; })();
    const p = (draft.draft && draft.draft.patches) ? draft.draft.patches["$selId"] : null;
    return JSON.stringify({skipped: false, live: el ? el.textContent : null,
      saved: p ? p.text : null});
  ''');
  report(
      'S2c content-facet',
      cont['skipped'] == true ||
          (cont['live'] == 'SMOKE text edit' && cont['saved'] == 'SMOKE text edit'),
      jsonEncode(cont),
      _newErrors(tab));

  final esc = await jsShadow(tab, '''
    const tas = [...R.querySelectorAll("#pbody textarea")];
    const css = tas.find(t => t.placeholder && t.placeholder.indexOf("prop:") !== -1);
    if (!css) return JSON.stringify({fatal: "no escape hatch"});
    css.value = "letter-spacing: 0.5px";
    [...R.querySelectorAll("#pbody .btn")].find(b => b.textContent === "Apply CSS").click();
    await new Promise(r=>setTimeout(r,1200));
    const selAttr = "$selId".indexOf("el:") === 0 ? "data-el" : "data-arxa-id";
    const selVal = selAttr === "data-el" ? "$selId".slice(3) : "$selId";
    const cands = [...document.querySelectorAll('[' + selAttr + '="' + selVal + '"]')];
    const el = cands.find(x => (x.style.outlineColor || "").indexOf("245") !== -1) || cands[0];
    const draft = await (async () => { for (let a = 0; a < 4; a++) { try { return await fetch("/__dial/draft").then(r=>r.json()); } catch (e) { await new Promise(rr=>setTimeout(rr,300)); } } return {}; })();
    const p = (draft.draft && draft.draft.patches) ? draft.draft.patches["$selId"] : null;
    return JSON.stringify({live: el ? el.style.getPropertyValue("letter-spacing") : null,
      saved: p && p.style ? p.style["letter-spacing"] : null});
  ''');
  report('S2d css-escape-hatch',
      esc['live'] == '0.5px' && esc['saved'] == '0.5px', jsonEncode(esc),
      _newErrors(tab));

  final com = await jsShadow(tab, '''
    [...R.querySelectorAll("#pbody .btn")].find(b => b.textContent === "Request commit").click();
    await new Promise(r=>setTimeout(r,900));
    return JSON.stringify({toast: R.querySelector("#toast").textContent});
  ''');
  report('S2e commit-request',
      (com['toast'] as String).contains('Commit requested'), jsonEncode(com),
      _newErrors(tab));
  await shot(tab, 's2e-commit');

  try {
    await shadow(tab, '''
      [...R.querySelectorAll("#pbody .btn")].find(b => b.textContent === "Reset all").click();
      await new Promise(r=>setTimeout(r,300));
      return "ok";
    ''');
  } catch (_) {} // the click's reload can swap the target mid-eval
  await Future<void>.delayed(const Duration(seconds: 2));
  await waitBoot(tab);
  final cleared = await js(tab, '''
    const d = await (async () => { for (let a = 0; a < 4; a++) { try { return await fetch("/__dial/draft").then(r=>r.json()); } catch (e) { await new Promise(rr=>setTimeout(rr,300)); } } return {}; })();
    return JSON.stringify({patches: Object.keys((d.draft && d.draft.patches) || {}).length,
      tokens: Object.keys((d.draft && d.draft.tokens) || {}).length});
  ''');
  report('S2f reset-all', cleared['patches'] == 0 && cleared['tokens'] == 0,
      jsonEncode(cleared), _newErrors(tab));

  // ── S3 tokens ────────────────────────────────────────────────────────
  // The verb's contract does not require the artifact to declare :root
  // tokens — suczka-studio declares none, and the panel must then show its
  // empty state and still take a NEW override. Test both paths: edit the
  // first listed token when there is one, else mint --smoke-token via the
  // override row.
  final tok = await jsShadow(tab, '''
    R.querySelector('[data-verb="tokens"]').click();
    await new Promise(r=>setTimeout(r,400));
    const inputs = [...R.querySelectorAll("#pbody .facet input[type=text]")]
      .filter(i => i.placeholder !== "--token-name" && i.placeholder !== "value");
    let name = null, emptyState = false;
    if (inputs.length) {
      const inp = inputs[0];
      name = inp.closest(".facet").querySelector("label").textContent;
      inp.value = "rgb(9, 8, 7)";
      inp.dispatchEvent(new Event("input", {bubbles: true}));
    } else {
      emptyState = R.querySelector("#pbody").textContent.indexOf("No :root custom properties") !== -1;
      const nameIn = R.querySelector('#pbody input[placeholder="--token-name"]');
      const valIn = R.querySelector('#pbody input[placeholder="value"]');
      nameIn.value = "--smoke-token";
      valIn.value = "rgb(9, 8, 7)";
      [...R.querySelectorAll("#pbody .btn")].find(b => b.textContent === "Add").click();
      name = "--smoke-token";
    }
    await new Promise(r=>setTimeout(r,1200));
    const live = document.getElementById("arxa-draft-tokens-live");
    const draft = await (async () => { for (let a = 0; a < 4; a++) { try { return await fetch("/__dial/draft").then(r=>r.json()); } catch (e) { await new Promise(rr=>setTimeout(rr,300)); } } return {}; })();
    const tokens = (draft.draft && draft.draft.tokens) || {};
    return JSON.stringify({listed: inputs.length, emptyState: emptyState, edited: name,
      liveEl: live ? live.textContent : null,
      saved: name ? (tokens[name] || null) : null});
  ''');
  final tokOk = tok['edited'] != null &&
      tok['saved'] == 'rgb(9, 8, 7)' &&
      (tok['liveEl'] as String? ?? '').contains(tok['edited'] as String? ?? '§none§') &&
      ((tok['listed'] as int) > 0 || tok['emptyState'] == true);
  report('S3 tokens', tokOk, jsonEncode(tok), _newErrors(tab));
  await shot(tab, 's3-tokens');
  await shadow(tab,
      'await fetch("/__dial/draft", {method: "DELETE"}); return "ok";');
  await tab.navigateAndSettle('$_base/', settleMs: 2500);
  await waitBoot(tab);

  // ── S4 pin ───────────────────────────────────────────────────────────
  final pinArm = await jsShadow(tab, '''
    R.querySelector('[data-verb="pin"]').click();
    await new Promise(r=>setTimeout(r,200));
    const target = document.querySelector("h1[data-el],h2[data-el],p[data-el],[data-el]");
    if (!target) return JSON.stringify({fatal: "no data-el element"});
    target.scrollIntoView({block: "center"});
    await new Promise(r=>setTimeout(r,250));
    const r = target.getBoundingClientRect();
    const cx = Math.min(Math.max(r.left + r.width/2, 4), window.innerWidth-4);
    const cy = Math.min(Math.max(r.top + r.height/2, 4), window.innerHeight-4);
    document.dispatchEvent(new PointerEvent("pointermove", {clientX: cx, clientY: cy, bubbles: true}));
    await new Promise(r=>setTimeout(r,120));
    const hoverShown = R.querySelector("#hover").style.display === "block";
    document.dispatchEvent(new MouseEvent("click", {clientX: cx, clientY: cy, bubbles: true}));
    await new Promise(r=>setTimeout(r,300));
    return JSON.stringify({hoverShown: hoverShown,
      composer: R.querySelector("#composer").classList.contains("open")});
  ''');
  report('S4a pin-arm', pinArm['hoverShown'] == true && pinArm['composer'] == true,
      jsonEncode(pinArm), _newErrors(tab));

  final pinAdd = await jsShadow(tab, '''
    const area = R.querySelector("#composer textarea");
    area.value = "SMOKE pin — verb smoke";
    [...R.querySelectorAll("#composer .btn")].find(b => b.textContent === "Add pin").click();
    await new Promise(r=>setTimeout(r,1000));
    const pins = await (async () => { let err = null; for (let a = 0; a < 4; a++) { try { return await fetch("/__dial/pins").then(r=>r.json()); } catch (e) { err = e.name + ":" + e.message; await new Promise(rr=>setTimeout(rr,300)); } } return {pins: [], fetchErr: err}; })();
    const mine = pins.pins.filter(p => p.body && p.body.indexOf("SMOKE") === 0);
    return JSON.stringify({created: mine.map(p => p.id),
      badge: R.querySelector("#dockbtn .dot").textContent,
      badges: R.querySelectorAll("#pins .pin").length,
      composerClosed: !R.querySelector("#composer").classList.contains("open")});
  ''');
  _createdPinIds.addAll((pinAdd['created'] as List).cast<String>());
  report(
      'S4b pin-add',
      _createdPinIds.isNotEmpty &&
          pinAdd['composerClosed'] == true &&
          (pinAdd['badges'] as int) > 0,
      jsonEncode(pinAdd),
      _newErrors(tab));
  await shot(tab, 's4-pin');

  // ── S5 list / thread / kanban / reply ────────────────────────────────
  final pinId = _createdPinIds.isNotEmpty ? _createdPinIds.first : '§none§';
  final lst = await jsShadow(tab, '''
    R.querySelector('[data-verb="list"]').click();
    await new Promise(r=>setTimeout(r,400));
    const rows = [...R.querySelectorAll("#pbody .row")];
    const row = rows.find(r2 => r2.textContent.indexOf("SMOKE") !== -1) || rows[0];
    if (row) row.click();
    await new Promise(r=>setTimeout(r,400));
    const thread = R.querySelector("#thread");
    return JSON.stringify({rows: rows.length,
      threadOpen: thread.classList.contains("open"),
      kanban: [...thread.querySelectorAll(".stbtn")].map(b=>b.textContent)});
  ''');
  report(
      'S5a list-thread',
      (lst['rows'] as int) > 0 &&
          lst['threadOpen'] == true &&
          (lst['kanban'] as List).length == 5,
      jsonEncode(lst),
      _newErrors(tab));
  await shot(tab, 's5-thread');

  final kan = await jsShadow(tab, '''
    [...R.querySelectorAll("#thread .stbtn")].find(b=>b.textContent==="Triaged").click();
    await new Promise(r=>setTimeout(r,1000));
    const pins = await (async () => { let err = null; for (let a = 0; a < 4; a++) { try { return await fetch("/__dial/pins").then(r=>r.json()); } catch (e) { err = e.name + ":" + e.message; await new Promise(rr=>setTimeout(rr,300)); } } return {pins: [], fetchErr: err}; })();
    const mine = pins.pins.find(p => p.id === "$pinId");
    return JSON.stringify({status: mine ? mine.status : null,
      threadStillOpen: R.querySelector("#thread").classList.contains("open")});
  ''');
  report('S5b kanban', kan['status'] == 'triaged', jsonEncode(kan),
      _newErrors(tab));

  final rep = await jsShadow(tab, '''
    const inp = R.querySelector("#thread input[type=text]");
    inp.value = "smoke reply";
    inp.dispatchEvent(new KeyboardEvent("keydown", {key: "Enter", bubbles: true}));
    await new Promise(r=>setTimeout(r,1000));
    const pins = await (async () => { let err = null; for (let a = 0; a < 4; a++) { try { return await fetch("/__dial/pins").then(r=>r.json()); } catch (e) { err = e.name + ":" + e.message; await new Promise(rr=>setTimeout(rr,300)); } } return {pins: [], fetchErr: err}; })();
    const mine = pins.pins.find(p => p.id === "$pinId");
    const bodies = mine && mine.replies ? mine.replies.map(r2 => r2.body) : [];
    return JSON.stringify({replies: bodies, fetchErr: pins.fetchErr || null,
      pinCount: pins.pins.length, wantedId: "$pinId",
      echoed: R.querySelector("#thread").textContent.indexOf("smoke reply") !== -1});
  ''');
  // The thread echo IS the stronger proof: the island re-fetches pins from
  // the server after replying and re-renders from that data, so an echoed
  // reply is a persisted reply. The probe fetch is corroboration only — on
  // a memory-pressed machine it is the first thing the network stack drops.
  report(
      'S5c reply',
      (rep['replies'] as List).contains('smoke reply') || rep['echoed'] == true,
      jsonEncode(rep),
      _newErrors(tab));

  // ── S6 shade ─────────────────────────────────────────────────────────
  final shd = await jsShadow(tab, '''
    document.dispatchEvent(new KeyboardEvent("keydown", {key: "Escape", bubbles: true}));
    await new Promise(r=>setTimeout(r,150));
    R.querySelector('[data-verb="shade"]').click();
    await new Promise(r=>setTimeout(r,400));
    const slider = R.querySelector("#pbody input[type=range]");
    if (!slider) return JSON.stringify({fatal: "no slider"});
    slider.value = "60"; slider.dispatchEvent(new Event("input", {bubbles: true}));
    await new Promise(r=>setTimeout(r,400));
    const on = getComputedStyle(R.querySelector("#shade")).opacity;
    slider.value = "0"; slider.dispatchEvent(new Event("input", {bubbles: true}));
    await new Promise(r=>setTimeout(r,400));
    const off = getComputedStyle(R.querySelector("#shade")).opacity;
    return JSON.stringify({on: on, off: off});
  ''');
  report('S6 shade', shd['on'] == '0.6' && shd['off'] == '0', jsonEncode(shd),
      _newErrors(tab));

  // ── S7 layers ────────────────────────────────────────────────────────
  final lay = await jsShadow(tab, '''
    R.querySelector('[data-verb="layers"]').click();
    await new Promise(r=>setTimeout(r,400));
    const rows = [...R.querySelectorAll("#pbody .ctl")];
    const sw = (label) => { const row = rows.find(r2 => r2.textContent.indexOf(label) !== -1); return row ? row.querySelector(".switch") : null; };
    const out = {};
    sw("Pins").click(); await new Promise(r=>setTimeout(r,150));
    out.pinsHidden = R.querySelector("#pins").style.display === "none";
    sw("Pins").click(); await new Promise(r=>setTimeout(r,150));
    out.pinsBack = R.querySelector("#pins").style.display !== "none";
    sw("Drawings").click(); await new Promise(r=>setTimeout(r,150));
    out.drawHidden = R.querySelector("#draw").style.display === "none";
    sw("Drawings").click(); await new Promise(r=>setTimeout(r,150));
    sw("Comments").click(); await new Promise(r=>setTimeout(r,150));
    // the LAYERS panel is open right now — does its own chrome survive?
    out.panelHiddenWithLayersOpen = getComputedStyle(R.querySelector("#panel")).display === "none";
    sw("Comments").click(); await new Promise(r=>setTimeout(r,150));
    return JSON.stringify(out);
  ''');
  report('S7a layers-pins-drawings',
      lay['pinsHidden'] == true && lay['pinsBack'] == true && lay['drawHidden'] == true,
      jsonEncode(lay), _newErrors(tab));
  report('S7b layers-panel-survives', lay['panelHiddenWithLayersOpen'] == false,
      'panel hidden while layers panel open: ${lay['panelHiddenWithLayersOpen']}');

  // ── S8 pen ───────────────────────────────────────────────────────────
  final pen = await jsShadow(tab, '''
    R.querySelector('[data-verb="pen"]').click();
    await new Promise(r=>setTimeout(r,200));
    const cv = R.querySelector("#draw");
    const armed = cv.classList.contains("armed");
    cv.dispatchEvent(new PointerEvent("pointerdown", {clientX: 420, clientY: 300, bubbles: true, pointerId: 1}));
    for (let i=1;i<=8;i++) cv.dispatchEvent(new PointerEvent("pointermove", {clientX: 420+i*20, clientY: 300-i*6, bubbles: true, pointerId: 1}));
    cv.dispatchEvent(new PointerEvent("pointerup", {clientX: 580, clientY: 252, bubbles: true, pointerId: 1}));
    await new Promise(r=>setTimeout(r,200));
    const ctx = cv.getContext("2d");
    const d = ctx.getImageData(0, 0, cv.width, cv.height).data;
    let alpha = 0; for (let i=3;i<d.length;i+=997) alpha += d[i];
    document.dispatchEvent(new KeyboardEvent("keydown", {key: "Escape", bubbles: true}));
    await new Promise(r=>setTimeout(r,150));
    return JSON.stringify({armed: armed, painted: alpha > 0,
      armedAfterEscape: cv.classList.contains("armed")});
  ''');
  report('S8a pen-draws', pen['armed'] == true && pen['painted'] == true,
      jsonEncode(pen), _newErrors(tab));
  report('S8b pen-escape-disarms', pen['armedAfterEscape'] == false,
      'canvas still armed after Escape: ${pen['armedAfterEscape']}');
  await shadow(tab, '''
    if (R.querySelector("#draw").classList.contains("armed")) R.querySelector('[data-verb="pen"]').click();
    return "ok";
  ''');
  await shot(tab, 's8-pen');

  // ── S10 direct manipulation: inline text edit + drag-resize ─────────
  // Locked decision 2: the Author double-clicks pure text to type in place
  // and drags the selection's amber handles to resize — same patch path as
  // panel edits.
  // Fresh page: the hero sits above the fold at scroll 0. scrollIntoView is
  // NOT used to reach it — this artifact scroll-jacks (transform-driven), so
  // a programmatic scroll gets re-asserted mid-read and the rect lies about
  // where the glyphs are.
  await tab.navigateAndSettle('$_base/', settleMs: 2500);
  await waitBoot(tab);
  final inl = await jsShadow(tab, '''
    R.querySelector('[data-verb="design"]').click();
    await new Promise(r=>setTimeout(r,300));
    const lead = document.querySelector('[data-el="wordmark-lead"]') || document.querySelector("h1[data-arxa-id],h2[data-arxa-id],p[data-arxa-id]");
    if (!lead) return JSON.stringify({fatal: "no pure-text target"});
    const rc = lead.getBoundingClientRect();
    const cx = Math.min(Math.max(rc.left + rc.width/2, 4), window.innerWidth-4);
    const cy = Math.min(Math.max(rc.top + rc.height/2, 4), window.innerHeight-4);
    const leadKidsBefore = lead.children.length;
    const leadHtmlBefore = lead.innerHTML.slice(0, 90);
    document.dispatchEvent(new MouseEvent("click", {clientX: cx, clientY: cy, bubbles: true}));
    await new Promise(r=>setTimeout(r,300));
    document.dispatchEvent(new MouseEvent("dblclick", {clientX: cx, clientY: cy, bubbles: true}));
    await new Promise(r=>setTimeout(r,250));
    const editing = lead.getAttribute("contenteditable") === "true";
    lead.textContent = "SMOKE inline";
    document.dispatchEvent(new KeyboardEvent("keydown", {key: "Enter", bubbles: true}));
    await new Promise(r=>setTimeout(r,1100));
    const idlineText = (R.querySelector("#pbody .idline") || {}).textContent;
    // the idline shows "machine-id → el:authored" when the divergence law
    // rebinds — the draft is keyed by the BINDING, not the machine id
    const selId = idlineText && idlineText.indexOf(" → ") !== -1 ? idlineText.split(" → ")[1] : idlineText;
    const draft = await (async () => { for (let a = 0; a < 4; a++) { try { return await fetch("/__dial/draft").then(r=>r.json()); } catch (e) { await new Promise(rr=>setTimeout(rr,300)); } } return {}; })();
    const p = selId && draft.draft && draft.draft.patches ? draft.draft.patches[selId] : null;
    return JSON.stringify({editing: editing,
      committed: lead.getAttribute("contenteditable") !== "true",
      selLabel: (R.querySelector("#pbody .sect") || {}).textContent || null,
      leadKidsBefore: leadKidsBefore, leadHtmlBefore: leadHtmlBefore,
      toast: R.querySelector("#toast").textContent,
      live: lead.textContent, saved: p ? p.text : null});
  ''');
  report('S10a inline-text-edit',
      inl['editing'] == true && inl['committed'] == true &&
      inl['live'] == 'SMOKE inline' && inl['saved'] == 'SMOKE inline',
      jsonEncode(inl), _newErrors(tab));

  // S10a's text commit schedules the converge reload ~1.4s after the save
  // (animator-owned text). Wait it out; the resume stash re-arms Design
  // Mode and re-selects the wordmark, so the drag below finds its handles.
  await Future<void>.delayed(const Duration(seconds: 3));
  await waitBoot(tab);
  await Future<void>.delayed(const Duration(milliseconds: 800));

  final drg = await jsShadow(tab, '''
    const idline = R.querySelector("#pbody .idline");
    const idlineText = idline ? idline.textContent : null;
    const selId = idlineText && idlineText.indexOf(" → ") !== -1 ? idlineText.split(" → ")[1] : idlineText;
    // ids are loop-shared — querySelector would return the FIRST instance,
    // not the SELECTED one. The selection wears the amber outline. The
    // binding decides which attribute the candidate set rides.
    const selAttr = selId && selId.indexOf("el:") === 0 ? "data-el" : "data-arxa-id";
    const selVal = selAttr === "data-el" ? selId.slice(3) : selId;
    const els = selId ? [...document.querySelectorAll('[' + selAttr + '="' + selVal + '"]')] : [];
    const el = els.find(x => (x.style.outlineColor || "").indexOf("245") !== -1) || els[0];
    if (!el) return JSON.stringify({fatal: "no selection", idline: idlineText});
    const handle = R.querySelector('.hnd[data-d="e"]');
    if (!handle) return JSON.stringify({fatal: "no e handle"});
    const w0 = el.getBoundingClientRect().width;
    const hr = handle.getBoundingClientRect();
    const hx = hr.left + 5, hy = hr.top + 5;
    handle.dispatchEvent(new PointerEvent("pointerdown", {clientX: hx, clientY: hy, bubbles: true, pointerId: 1}));
    for (let i = 1; i <= 4; i++) document.dispatchEvent(new PointerEvent("pointermove", {clientX: hx + i*10, clientY: hy, bubbles: true, pointerId: 1}));
    document.dispatchEvent(new PointerEvent("pointerup", {clientX: hx + 40, clientY: hy, bubbles: true, pointerId: 1}));
    await new Promise(r=>setTimeout(r,1100));
    const draft = await (async () => { for (let a = 0; a < 4; a++) { try { return await fetch("/__dial/draft").then(r=>r.json()); } catch (e) { await new Promise(rr=>setTimeout(rr,300)); } } return {}; })();
    const p = draft.draft && draft.draft.patches ? draft.draft.patches[selId] : null;
    return JSON.stringify({w0: Math.round(w0),
      liveWidth: el.style.width || null,
      savedWidth: p && p.style ? p.style.width : null});
  ''');
  // The contract is that the live style and the saved patch carry the SAME
  // dragged value — the absolute number is at the mercy of the artifact's
  // intro animator re-laying-out mid-drag, so it is not asserted.
  final dragOk = drg['liveWidth'] != null &&
      drg['savedWidth'] != null &&
      drg['liveWidth'] == drg['savedWidth'];
  report('S10b drag-resize', dragOk, jsonEncode(drg), _newErrors(tab));
  await shadow(tab,
      'await fetch("/__dial/draft", {method: "DELETE"}); return "ok";');
  await tab.navigateAndSettle('$_base/', settleMs: 2500);
  await waitBoot(tab);

  // ── S11 cross-rung live sync (amended 2026-08-24) ────────────────────
  // An edit in one author document must appear in every OTHER open author
  // document without a reload — the ladder's rungs are separate documents.
  final clientSync = await CdpClient.launch();
  String syncSeen = 'not-run';
  try {
    final btab = await clientSync.newTab();
    await btab.enable();
    await btab.setViewport(744, 1133); // a different rung, by shape
    await btab.navigateAndSettle('$_base/', settleMs: 2500);
    await waitBoot(btab);
    // edit in the MAIN tab: select the wordmark, type in its content facet
    await jsShadow(tab, '''
      R.querySelector('[data-verb="design"]').click();
      await new Promise(r=>setTimeout(r,300));
      const lead = document.querySelector('[data-el="wordmark-lead"]');
      const rc = lead.getBoundingClientRect();
      document.dispatchEvent(new MouseEvent("click", {clientX: rc.left+rc.width/2, clientY: rc.top+rc.height/2, bubbles: true}));
      await new Promise(r=>setTimeout(r,400));
      const ta = [...R.querySelectorAll("#pbody textarea")].find(t => !t.placeholder || t.placeholder.indexOf("prop:") === -1);
      if (!ta) return JSON.stringify({fatal: "no content facet"});
      ta.value = "SMOKE SYNC";
      ta.dispatchEvent(new Event("input", {bubbles: true}));
      return JSON.stringify({ok: true});
    ''');
    // Both documents converge by reload for text patches: B as the remote
    // sibling, the editing tab via its own post-save timer. Wait both out.
    await Future<void>.delayed(const Duration(milliseconds: 2200));
    await waitBoot(btab);
    final seen = await js(btab, '''
      const el = document.querySelector('[data-el="wordmark-lead"]');
      return JSON.stringify({text: el ? el.textContent : null});
    ''');
    syncSeen = (seen['text'] as String? ?? 'null');
  } finally {
    await clientSync.close();
  }
  report('S11 cross-rung sync', syncSeen == 'SMOKE SYNC',
      'second document saw: $syncSeen');
  await waitBoot(tab); // the editing rung's own converge reload
  await shadow(tab,
      'await fetch("/__dial/draft", {method: "DELETE"}); return "ok";');
  await tab.navigateAndSettle('$_base/', settleMs: 2500);
  await waitBoot(tab);

  // ── S12 divergence binding: authored identity wins ───────────────────
  // intro-copyright shares its machine id with four other slots; editing
  // its text must bind el:intro-copyright and leave the wordmark alone.
  final div = await jsShadow(tab, '''
    R.querySelector('[data-verb="design"]').click();
    await new Promise(r=>setTimeout(r,300));
    const target = document.querySelector('[data-el="intro-copyright"]');
    if (!target) return JSON.stringify({fatal: "no intro-copyright"});
    const rc = target.getBoundingClientRect();
    const cx = Math.min(Math.max(rc.left + rc.width/2, 4), window.innerWidth-4);
    const cy = Math.min(Math.max(rc.top + rc.height/2, 4), window.innerHeight-4);
    document.dispatchEvent(new MouseEvent("click", {clientX: cx, clientY: cy, bubbles: true}));
    await new Promise(r=>setTimeout(r,400));
    const idline = (R.querySelector("#pbody .idline") || {}).textContent || "";
    const wmBefore = (document.querySelector('[data-el="wordmark-lead"]') || {}).textContent || null;
    const ta = [...R.querySelectorAll("#pbody textarea")].find(t => !t.placeholder || t.placeholder.indexOf("prop:") === -1);
    if (!ta) return JSON.stringify({fatal: "no content facet", idline: idline});
    ta.value = "SMOKE ©2099";
    ta.dispatchEvent(new Event("input", {bubbles: true}));
    await new Promise(r=>setTimeout(r,1300));
    const draft = await (async () => { for (let a = 0; a < 4; a++) { try { return await fetch("/__dial/draft").then(r=>r.json()); } catch (e) { await new Promise(rr=>setTimeout(rr,300)); } } return {}; })();
    const keys = Object.keys((draft.draft && draft.draft.patches) || {});
    const wm = document.querySelector('[data-el="wordmark-lead"]');
    return JSON.stringify({idline: idline, keys: keys,
      wordmarkBefore: wmBefore,
      wordmarkText: wm ? wm.textContent : null,
      copyrightText: target.textContent});
  ''');
  report(
      'S12 divergence binding',
      (div['keys'] as List).contains('el:intro-copyright') &&
          div['wordmarkText'] == div['wordmarkBefore'] &&
          div['copyrightText'] == 'SMOKE ©2099',
      jsonEncode(div),
      _newErrors(tab));
  await shadow(tab,
      'await fetch("/__dial/draft", {method: "DELETE"}); return "ok";');
  await tab.navigateAndSettle('$_base/', settleMs: 2500);
  await waitBoot(tab);

  // ── S13 text patches survive the animator at desktop ─────────────────
  // The operator's bug: a wordmark text edit synced to mobile/tablet but
  // reverted on desktop — the intro animator re-splits text from its boot
  // capture and fights live DOM writes (revert/duplicate/collapse). The
  // converge law: text patches reload the document so the animator boots
  // on the NEW text. This drives a REMOTE text edit at 1280 and asserts
  // the wordmark is exactly the new text, laid out (not collapsed), and
  // visible, seconds later.
  {
    final put = await HttpClient().openUrl('PUT', Uri.parse('$_base/__dial/draft'));
    put.headers.contentType = ContentType.json;
    put.write(jsonEncode({
      'tokens': {},
      'patches': {
        'ui-widgets-suczka_site_shell_widgets-chrome_atoms-e3': {'text': 'SMOKE-DESKTOP'}
      }
    }));
    await (await put.close()).drain<void>();
  }
  await Future<void>.delayed(const Duration(milliseconds: 1500));
  await waitBoot(tab); // the remote-draft frame reloads this document
  // The intro choreography holds the wordmark collapsed until its moment —
  // poll for layout instead of racing it (condition-based, not a sleep).
  String? s13raw;
  for (var i = 0; i < 25; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    s13raw = await tab.evaluate('''
      const e3 = document.querySelector('[data-arxa-id="ui-widgets-suczka_site_shell_widgets-chrome_atoms-e3"]');
      const rc = e3 ? e3.getBoundingClientRect() : null;
      JSON.stringify({w: rc ? Math.round(rc.width) : -1})
    ''') as String;
    if (jsonDecode(s13raw)['w'] > 0) break;
  }
  final s13 = await js(tab, '''
    const e3 = document.querySelector('[data-arxa-id="ui-widgets-suczka_site_shell_widgets-chrome_atoms-e3"]');
    const rc = e3 ? e3.getBoundingClientRect() : null;
    let visible = null;
    if (rc && rc.width > 0 && rc.top < window.innerHeight) {
      const stack = document.elementsFromPoint(rc.left + rc.width/2, Math.min(Math.max(rc.top + rc.height/2, 2), window.innerHeight - 2));
      const hit = stack.find(x => x.textContent && x.textContent.indexOf("SMOKE") !== -1);
      visible = hit ? hit.textContent.trim() : null;
    }
    return JSON.stringify({text: e3 ? e3.textContent.trim() : null,
      rect: rc ? {x: Math.round(rc.x), y: Math.round(rc.y), w: Math.round(rc.width)} : null,
      visible: visible});
  ''');
  report(
      'S13 text survives animator (desktop)',
      s13['text'] == 'SMOKE-DESKTOP' &&
          s13['rect'] != null &&
          (s13['rect'] as Map)['w'] != 0 &&
          s13['visible'] != null,
      jsonEncode(s13),
      _newErrors(tab));
  await shadow(tab,
      'await fetch("/__dial/draft", {method: "DELETE"}); return "ok";');
  await tab.navigateAndSettle('$_base/', settleMs: 2500);
  await waitBoot(tab);

  // ── S9 share → guest → dead token ────────────────────────────────────
  final shr = await jsShadow(tab, '''
    R.querySelector('[data-verb="share"]').click();
    await new Promise(r=>setTimeout(r,300));
    const mintBtn = [...R.querySelectorAll("#pbody .btn")].find(b => b.textContent === "Mint share link");
    if (mintBtn) mintBtn.click();
    // condition-based wait: the linkbox appears when the mint resolves — a
    // fixed sleep races a loaded machine (this step flaked at 1200ms).
    let box = null;
    for (let i = 0; i < 24 && !box; i++) {
      await new Promise(r=>setTimeout(r,250));
      box = R.querySelector("#pbody .linkbox");
      if (R.querySelector("#toast").textContent.indexOf("Could not mint") !== -1) break;
    }
    // direct probe: can THIS tab reach the dial API at all right now?
    // (GET pins — a POST /share probe would mint a real link on success)
    let probe = null;
    try {
      const res = await fetch("/__dial/pins");
      probe = res.status;
    } catch (e) { probe = "ERR:" + e.name; }
    return JSON.stringify({url: box ? box.textContent : null,
      btnFound: !!mintBtn, btnLabel: mintBtn ? mintBtn.textContent : null,
      phead: R.querySelector("#phead").textContent,
      panelClasses: R.querySelector("#panel").className,
      pbodyKids: [...R.querySelector("#pbody").children].map(c => c.className + ":" + (c.textContent || "").slice(0, 24)),
      toast: R.querySelector("#toast").textContent, probe: probe});
  ''');
  final shareUrl = shr['url'] as String?;
  report('S9a share-mint', shareUrl != null && shareUrl.contains('?dial='),
      jsonEncode(shr), _newErrors(tab));
  if (shareUrl != null && shareUrl.contains('?dial=')) {
    _shareToken = shareUrl.split('?dial=').last;

    // A second tab in the SAME headless Chrome is a background tab: Chrome
    // throttles it, and Page.loadEventFired can stall past the 30s navigate
    // timeout. Guest + dead-token checks get their OWN browser instead.
    final client2 = await CdpClient.launch();
    try {
    final gtab = await client2.newTab();
    await gtab.enable();
    await gtab.setViewport(1280, 800);
    await gtab.navigateAndSettle(shareUrl, settleMs: 2500);
    final g = await js(gtab, '''
      const host = document.getElementById("arxa-dial-host");
      if (!host) return JSON.stringify({boot: false});
      const R = host.shadowRoot;
      const cfg = JSON.parse(document.getElementById("arxa-dial-config").textContent);
      return JSON.stringify({boot: true, mode: cfg.mode,
        verbs: [...R.querySelectorAll(".verb")].map(v=>v.getAttribute("data-verb"))});
    ''');
    final gv = (g['verbs'] as List? ?? []).cast<String>();
    report(
        'S9b guest-mode',
        g['mode'] == 'guest' &&
            gv.length == 5 &&
            !gv.contains('design') &&
            !gv.contains('tokens') &&
            !gv.contains('share'),
        jsonEncode(g));
    File('${_frames.path}/s9-guest.png')
        .writeAsBytesSync(await gtab.screenshot());

    final dtab = await client2.newTab();
    await dtab.enable();
    await dtab.setViewport(1280, 800);
    await dtab.navigateAndSettle('$_base/?dial=deadbeefdeadbeefdeadbeef',
        settleMs: 2500);
    final dead = await js(dtab, '''
      const el = document.getElementById("arxa-dial-config");
      if (!el) return JSON.stringify({boot: false});
      const cfg = JSON.parse(el.textContent);
      const host = document.getElementById("arxa-dial-host");
      return JSON.stringify({boot: true, mode: cfg.mode,
        toast: host && host.shadowRoot ? host.shadowRoot.querySelector("#toast").textContent : null});
    ''');
    report('S9c dead-token', dead['mode'] == 'invalid', jsonEncode(dead));
    } finally {
      await client2.close();
    }
  }

  } finally {
    await client.close();
  }

  // ── cleanup: SMOKE rows out of Supabase, draft cleared ──────────────
  await _cleanup();

  print('');
  print(_fails == 0 ? 'SMOKE GREEN — no failures' : 'SMOKE: $_fails failure(s)');
  exit(_fails == 0 ? 0 : 1);
}

Future<void> _cleanup() async {
  // Restore the operator's pre-run draft FIRST — the Supabase sweep below
  // says nothing about the draft overlay.
  try {
    final req = await HttpClient().openUrl(
        _draftStash == null ? 'DELETE' : 'PUT',
        Uri.parse('$_base/__dial/draft'));
    if (_draftStash != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({
        'tokens': _draftStash!['tokens'] ?? {},
        'patches': _draftStash!['patches'] ?? {},
      }));
    }
    final res = await req.close();
    await res.drain<void>();
    print('cleanup draft restore: ${res.statusCode}');
  } catch (e) {
    print('cleanup draft restore FAILED: $e');
  }
  final home = Platform.environment['HOME'];
  if (home == null) return;
  final credsFile = File('$home/.arxa/supabase');
  if (!credsFile.existsSync()) return;
  String? url, key;
  for (final line in credsFile.readAsStringSync().split('\n')) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#') || !t.contains('=')) continue;
    final i = t.indexOf('=');
    final k = t.substring(0, i).trim(), v = t.substring(i + 1).trim();
    if (k == 'ARXA_SUPABASE_URL' || k == 'url') url = v;
    if (k == 'ARXA_SUPABASE_SERVICE_KEY' || k == 'service_key') key = v;
  }
  if (url == null || key == null) return;
  final http = HttpClient();
  Future<void> del(String table, String filter) async {
    final req = await http.deleteUrl(Uri.parse('${url!}/rest/v1/$table?$filter'));
    req.headers.set('apikey', key!);
    req.headers.set('Authorization', 'Bearer $key');
    final res = await req.close();
    await res.drain<void>();
    print('cleanup $table: ${res.statusCode}');
  }

  if (_createdPinIds.isNotEmpty) {
    final ids = _createdPinIds.map((i) => '%22$i%22').join(',');
    await del('design_dial_drawings', 'pin_id=in.($ids)');
    await del('design_dial_replies', 'pin_id=in.($ids)');
    await del('design_dial_pins', 'id=in.($ids)');
  }
  if (_shareToken != null) {
    // the table stores token_hash = sha256(token), never the raw token
    final digest = sha256.convert(ascii.encode(_shareToken!)).toString(); // matches _hashToken in design_dial.dart
    await del('design_dial_share_links', 'token_hash=eq.$digest');
  }
  http.close();
}
