/* dial_island.js — the Design Dial island (first-party, ADR-0002 form;
   locked amendment 2026-08-23: 'the feedback dial becomes the Design Dial').

   WHY THIS EXISTS. Every appbox artifact carries one floating control so the
   Author can adjust the design live and clients can leave feedback on the
   shared design — one control, two modes. This file is the Feedback Mode
   slice: Pins anchored to W7 data-el identity (rect-snapshot fallback,
   Orphaned Pins survive removal), the kanban lifecycle (open / triaged /
   in_progress / resolved / wont_do) with threaded replies, the Review Shade
   with its opacity slider, per-layer toggles (pins / comments / drawings),
   Share Link minting (Author only), and the freehand draw-over. Drawings
   persist ONLY by attaching to a Pin (locked 2026-08-23: the pub.dev
   feedback model — sketch, then pin it): strokes pending while draw-over is
   armed attach to the next pin you place; strokes never pinned die with the
   session. A pinned drawing replays on the canvas while its thread is open.

   ISLAND SHAPE (per ADR-0002): one IIFE, no globals, no framework, no build
   step; configuration arrives in the injected #arxa-dial-config JSON script;
   it talks ONLY to this origin's /__dial/* endpoints. Everything renders
   inside a closed-ish shadow root so artifact styles can never restyle the
   dial and dial styles can never leak into the artifact. User-authored text
   (pin bodies, names, replies) is rendered with textContent only — never
   innerHTML.

   MODES. 'author' (no token on the URL — the loopback designer): full
   powers, including kanban moves and Share Link minting. 'guest' (a valid
   ?dial= token): pins + replies only. 'invalid' (a dead token): the dock
   boots to say so, nothing else. The store badge reads 'local' when the
   server runs its memory store, so nobody mistakes process-local pins for
   durable ones.

   The radial dock is draggable (pointer capture, click-vs-drag by a 6px
   threshold) and edge-snaps left/right; verbs fan out in an arc.

   DESIGN MODE (Author only; locked decisions 1-5). The design verb arms
   selection: hover shows the element under the cursor (data-arxa-id
   identity), click opens its facet editors in the panel. The selected
   element's kind (the data-el prefix, else its tag) picks a curated facet
   set; a raw-CSS escape hatch covers the unlisted; a content facet edits
   pure-text elements. The tokens verb edits the artifact's design tokens
   (:root custom properties). Every edit applies LIVE to the page and
   auto-saves (debounced) into the server-side Draft Overlay — artifact
   source is never touched by auto-save, and guests always see the last
   published state. 'Request commit' hands the patch set to the studio
   agent over the dial event stream; the agent commits to source with
   `design patch` and clears the draft. */
(() => {
  if (document._arxaDial) return; // guard against double-include
  document._arxaDial = 1;

  const cfgEl = document.getElementById('arxa-dial-config');
  if (!cfgEl) return;
  let cfg;
  try {
    cfg = JSON.parse(cfgEl.textContent);
  } catch (_) {
    return;
  }

  // ── state ──────────────────────────────────────────────────────────────
  const S = {
    mode: cfg.mode, // 'author' | 'guest' | 'invalid'
    artifact: cfg.artifact,
    store: cfg.store, // 'memory' | 'supabase'
    token: cfg.token || null,
    pins: [],
    open: false, // radial fan expanded
    panel: null, // null | 'feedback' | 'layers' | 'shade' | 'share'
    arming: false, // pin-placement armed
    drawing: false, // draw-over armed
    shade: 0, // review shade opacity 0..0.6 — OFF at boot; the shade is a review aid the user dials up, never a default dim over the design
    layers: { pins: true, comments: true, drawings: true },
    activePin: null, // id whose thread popover is open
    name: '',
    strokes: [], // PENDING strokes — persist only by attaching to a pin (see header)
    activeDrawing: null, // strokes of the pin whose thread is open
    dockSide: 'right',
    design: false, // Design Mode armed (author only)
    selected: null, // { id, el, label, group } — the element being edited
    selOutline: '', // inline outline the selection highlight borrowed
    draft: { tokens: {}, patches: {} }, // the Draft Overlay (server-side)
    draftWarnings: [], // preview-commit parity: el: keys whose name= is not exactly one source site
    draftDirty: false,
    ownSave: 0, // suppress refetch loops on our own PUT's broadcast
    inlineEditing: null, // original text of the element being edited on-canvas
  };
  try {
    S.name = localStorage.getItem('arxa-dial-name') || '';
  } catch (_) {}

  const KANBAN = [
    ['open', 'Open'],
    ['triaged', 'Triaged'],
    ['in_progress', 'In progress'],
    ['resolved', 'Resolved'],
    ['wont_do', "Won't do"],
  ];

  // ── the shadow host ────────────────────────────────────────────────────
  const host = document.createElement('div');
  host.id = 'arxa-dial-host';
  host.style.cssText =
    'position:fixed;inset:0;z-index:2147483000;pointer-events:none;' +
    'font-family:ui-sans-serif,system-ui,sans-serif;';
  const root = host.attachShadow({ mode: 'open' });

  const CSS = [
    '*{box-sizing:border-box;margin:0;padding:0;font:inherit}',
    '.pe{pointer-events:auto}',
    'button{cursor:pointer;border:0;background:none;color:inherit}',
    /* the review shade */
    '#shade{position:fixed;inset:0;background:#0b0b10;pointer-events:none;',
    '  opacity:0;transition:opacity .18s ease}',
    /* pin badges */
    '#pins{position:fixed;inset:0;pointer-events:none}',
    '.pin{position:absolute;width:26px;height:26px;border-radius:50%;',
    '  background:#0891b2;color:#FFFCF0;font-size:12px;font-weight:700;',
    '  display:flex;align-items:center;justify-content:center;',
    '  box-shadow:0 1px 6px rgba(0,0,0,.35);pointer-events:auto;',
    '  transform:translate(-50%,-50%);border:2px solid #FFFCF0}',
    '.pin.resolved{opacity:.45}',
    '.pin.wontdo{opacity:.45;text-decoration:line-through}',
    '.pin.orphan{background:#8a8f98;border-style:dashed}',
    '.pin.active{outline:3px solid #f59e0b}',
    '.pin.drawn::after{content:"✎";position:absolute;bottom:-6px;right:-6px;',
    '  font-size:9px;background:#f59e0b;color:#0b0b10;border-radius:6px;',
    '  padding:0 3px;font-weight:800}',
    /* the hover highlight while arming */
    '#hover{position:fixed;border:2px solid #0891b2;border-radius:4px;',
    '  background:rgba(8,145,178,.12);pointer-events:none;display:none}',
    '#hovertag{position:absolute;top:-22px;left:-2px;background:#0891b2;',
    '  color:#FFFCF0;font-size:11px;padding:2px 7px;border-radius:3px;',
    '  white-space:nowrap;font-weight:600}',
    /* the dock */
    '#dock{position:fixed;bottom:24px;right:24px;width:56px;height:56px;',
    '  pointer-events:auto;touch-action:none;z-index:10}',
    '#dockbtn{width:56px;height:56px;border-radius:50%;background:#0b0b10;',
    '  color:#FFFCF0;display:flex;align-items:center;justify-content:center;',
    '  box-shadow:0 4px 18px rgba(0,0,0,.4);border:2px solid #0891b2;',
    '  transition:transform .15s ease}',
    '#dockbtn:hover{transform:scale(1.06)}',
    '#dockbtn svg{width:26px;height:26px}',
    '#dockbtn .dot{position:absolute;top:-3px;right:-3px;min-width:20px;',
    '  height:20px;border-radius:10px;background:#f59e0b;color:#0b0b10;',
    '  font-size:11px;font-weight:800;display:flex;align-items:center;',
    '  justify-content:center;padding:0 5px}',
    /* the radial fan */
    '.verb{position:absolute;left:50%;top:50%;width:44px;height:44px;',
    '  border-radius:50%;background:#14141c;color:#FFFCF0;',
    '  border:1.5px solid #0891b2;display:flex;align-items:center;',
    '  justify-content:center;box-shadow:0 2px 10px rgba(0,0,0,.4);',
    '  transform:translate(-50%,-50%) scale(0);opacity:0;',
    '  transition:transform .22s cubic-bezier(.34,1.56,.64,1),opacity .18s}',
    '.verb svg{width:20px;height:20px}',
    '.verb.on{background:#0891b2}',
    '#dock.open .verb{transform:translate(-50%,-50%) scale(1);opacity:1}',
    '.verb .tip{position:absolute;right:52px;top:50%;',
    '  transform:translateY(-50%);background:#0b0b10;color:#FFFCF0;',
    '  font-size:11px;padding:3px 8px;border-radius:4px;white-space:nowrap;',
    '  opacity:0;pointer-events:none;transition:opacity .15s}',
    '.verb:hover .tip{opacity:1}',
    '#dock.left .verb .tip{right:auto;left:52px}',
    /* the panel */
    '#panel{position:fixed;bottom:92px;right:24px;width:320px;max-height:',
    '  min(520px,70vh);background:#14141c;color:#FFFCF0;border-radius:12px;',
    '  border:1px solid #2a2a35;box-shadow:0 12px 40px rgba(0,0,0,.5);',
    '  display:none;flex-direction:column;overflow:hidden;pointer-events:auto}',
    '#panel.open{display:flex}',
    '#panel.left{right:auto;left:24px}',
    '#phead{display:flex;align-items:center;gap:8px;padding:10px 12px;',
    '  border-bottom:1px solid #2a2a35;font-size:13px;font-weight:700}',
    '#phead .badge{margin-left:auto;font-size:10px;font-weight:600;',
    '  background:#2a2a35;padding:2px 8px;border-radius:8px;color:#9aa0ab}',
    '#phead .badge.local{background:#7c2d12;color:#ffd9c2}',
    '#pbody{overflow-y:auto;flex:1;padding:8px}',
    '.row{padding:8px 10px;border-radius:8px;cursor:pointer;',
    '  border:1px solid transparent;margin-bottom:4px}',
    '.row:hover{background:#1d1d27}',
    '.row.active{border-color:#0891b2;background:#1d1d27}',
    '.row .txt{font-size:12.5px;line-height:1.35;display:block}',
    '.row .meta{display:flex;gap:6px;align-items:center;margin-top:5px;',
    '  font-size:10.5px;color:#9aa0ab}',
    '.chip{font-size:10px;font-weight:700;padding:2px 7px;border-radius:8px;',
    '  text-transform:uppercase;letter-spacing:.03em}',
    '.chip.open{background:#7c2d12;color:#ffd9c2}',
    '.chip.triaged{background:#713f12;color:#fde68a}',
    '.chip.inprogress{background:#1e3a5f;color:#bfdbfe}',
    '.chip.resolved{background:#14532d;color:#bbf7d0}',
    '.chip.wontdo{background:#3f3f46;color:#d4d4d8}',
    '.orphan-tag{color:#f59e0b;font-weight:700}',
    /* thread popover */
    '#thread{position:fixed;width:300px;background:#14141c;color:#FFFCF0;',
    '  border-radius:12px;border:1px solid #2a2a35;padding:12px;',
    '  box-shadow:0 12px 40px rgba(0,0,0,.55);display:none;',
    '  pointer-events:auto;z-index:20}',
    '#thread.open{display:block}',
    '#thread .body{font-size:13px;line-height:1.45;margin:6px 0 10px}',
    '#thread .who{font-size:11px;color:#9aa0ab}',
    '#thread .replies{max-height:140px;overflow-y:auto;margin:8px 0;',
    '  border-top:1px solid #2a2a35;padding-top:8px}',
    '#thread .reply{font-size:12px;margin-bottom:6px;line-height:1.4}',
    '#thread .reply .who{margin-right:5px}',
    '#statusrow{display:flex;gap:4px;flex-wrap:wrap;margin:8px 0}',
    '.stbtn{font-size:10px;font-weight:700;padding:4px 8px;border-radius:8px;',
    '  background:#2a2a35;color:#9aa0ab;text-transform:uppercase}',
    '.stbtn.cur{background:#0891b2;color:#FFFCF0}',
    'textarea,input[type=text]{width:100%;background:#0b0b10;color:#FFFCF0;',
    '  border:1px solid #2a2a35;border-radius:8px;padding:8px;font-size:12.5px;',
    '  resize:vertical;outline:none;font-family:inherit}',
    'textarea:focus,input[type=text]:focus{border-color:#0891b2}',
    '.btn{background:#0891b2;color:#FFFCF0;font-weight:700;font-size:12px;',
    '  padding:8px 14px;border-radius:8px}',
    '.btn.ghost{background:#2a2a35}',
    '.btnrow{display:flex;gap:8px;margin-top:8px;justify-content:flex-end}',
    /* the composer (new pin) */
    '#composer{position:fixed;width:280px;background:#14141c;color:#FFFCF0;',
    '  border-radius:12px;border:1px solid #0891b2;padding:12px;',
    '  box-shadow:0 12px 40px rgba(0,0,0,.55);display:none;',
    '  pointer-events:auto;z-index:30}',
    '#composer.open{display:block}',
    /* draw-over canvas */
    '#draw{position:fixed;inset:0;pointer-events:none;z-index:5}',
    '#draw.armed{pointer-events:auto;cursor:crosshair}',
    /* shade + layer panels */
    '.ctl{display:flex;align-items:center;gap:10px;padding:10px 12px;',
    '  font-size:12.5px}',
    '.ctl input[type=range]{flex:1;accent-color:#0891b2}',
    '.switch{margin-left:auto;position:relative;width:36px;height:20px;',
    '  background:#2a2a35;border-radius:10px;transition:background .15s}',
    '.switch.on{background:#0891b2}',
    '.switch::after{content:"";position:absolute;top:2px;left:2px;width:16px;',
    '  height:16px;border-radius:50%;background:#FFFCF0;transition:left .15s}',
    '.switch.on::after{left:18px}',
    '.linkbox{word-break:break-all;font-size:11px;background:#0b0b10;',
    '  border:1px solid #2a2a35;border-radius:8px;padding:8px;margin-top:8px}',
    '#toast{position:fixed;bottom:96px;left:50%;transform:translateX(-50%);',
    '  background:#0b0b10;color:#FFFCF0;font-size:12.5px;padding:10px 16px;',
    '  border-radius:10px;border:1px solid #0891b2;opacity:0;',
    '  transition:opacity .2s;pointer-events:none;z-index:40}',
    /* Design Mode: selection hover tint, facet editors, token rows */
    '#hover.design{border-color:#f59e0b;background:rgba(245,158,11,.12)}',
    '#hover.design #hovertag{background:#f59e0b;color:#0b0b10}',
    '.sect{font-size:10.5px;font-weight:700;color:#9aa0ab;padding:10px 10px 4px;',
    '  text-transform:uppercase;letter-spacing:.05em}',
    '.idline{font-family:ui-monospace,monospace;font-size:10px;color:#6b7280;',
    '  padding:2px 10px 8px;word-break:break-all}',
    '.facet{display:flex;align-items:center;gap:8px;padding:4px 10px}',
    '.facet label{width:92px;color:#9aa0ab;font-size:11px;flex:none}',
    '.facet input[type=text]{flex:1;padding:5px 8px;font-size:12px}',
    '.facet input[type=color]{width:28px;height:26px;padding:0;flex:none;',
    '  border:1px solid #2a2a35;border-radius:6px;background:#0b0b10}',
    '.facet select{flex:1;background:#0b0b10;color:#FFFCF0;',
    '  border:1px solid #2a2a35;border-radius:8px;padding:5px;font-size:12px}',
    '.draftmeta{font-size:10.5px;color:#6b7280;padding:8px 10px 0}',
    /* Design Mode direct manipulation: resize handles on the selection and
       the inline text-editing cue (locked decision 2). Handles live in the
       shadow root so the design can never restyle them and the selection
       walk never picks them (host children are skipped). */
    '#handles{position:fixed;inset:0;pointer-events:none;z-index:15}',
    '.hnd{position:absolute;width:10px;height:10px;background:#f59e0b;',
    '  border:2px solid #0b0b10;border-radius:2px;pointer-events:auto;',
    '  transform:translate(-50%,-50%);box-shadow:0 1px 4px rgba(0,0,0,.4)}',
    '.hnd[data-d=n]{cursor:n-resize}.hnd[data-d=s]{cursor:s-resize}',
    '.hnd[data-d=e]{cursor:e-resize}.hnd[data-d=w]{cursor:w-resize}',
    '.hnd[data-d=ne]{cursor:ne-resize}.hnd[data-d=sw]{cursor:sw-resize}',
    '.hnd[data-d=nw]{cursor:nw-resize}.hnd[data-d=se]{cursor:se-resize}',
    '[data-arxa-inline-editing]{outline:2px dashed #f59e0b !important;',
    '  cursor:text;caret-color:#f59e0b}',
  ];
  const style = document.createElement('style');
  style.textContent = CSS.join('\n');
  root.appendChild(style);

  // ── tiny DOM helper: text is textContent, always ───────────────────────
  function h(tag, attrs, kids) {
    const el = document.createElement(tag);
    if (attrs) {
      for (const k in attrs) {
        if (k === 'class') el.className = attrs[k];
        else if (k === 'text') el.textContent = attrs[k];
        else el.setAttribute(k, attrs[k]);
      }
    }
    for (const kid of kids || []) {
      if (kid) el.appendChild(kid);
    }
    return el;
  }

  // ── API ────────────────────────────────────────────────────────────────
  function apiUrl(sub) {
    return '/__dial' + sub + (S.token ? '?dial=' + encodeURIComponent(S.token) : '');
  }
  async function api(method, sub, body) {
    // Never throw: a transient network failure must surface as the caller's
    // error path (toast, composer stays open), not as an unhandled rejection
    // that leaves the verb silently stuck (smoke S9a: mint died mid-flight
    // and the button read 'Minting…' forever). Every caller already guards
    // on the fields it needs, so null degrades cleanly everywhere.
    try {
      const res = await fetch(apiUrl(sub), {
        method,
        headers: body ? { 'Content-Type': 'application/json' } : undefined,
        body: body ? JSON.stringify(body) : undefined,
      });
      return await res.json();
    } catch (_) {
      return null;
    }
  }
  // One read in flight at a time: pins SSE frames can land while a previous
  // read is still out, and stacked reads multiply connection pressure for no
  // newer truth (the server broadcasts on mutations only — a read loop here
  // once kept every rung's socket pool busy enough to starve edits).
  let pinsLoading = false;
  async function loadPins() {
    if (pinsLoading) return;
    pinsLoading = true;
    try {
      const r = await api('GET', '/pins');
      if (r && r.pins) {
        S.pins = r.pins;
        renderPins();
        if (S.panel === 'feedback') renderPanelBody();
        updateBadge();
      }
    } finally {
      pinsLoading = false;
    }
  }

  // ── layer hosts ────────────────────────────────────────────────────────
  const shade = h('div', { id: 'shade' });
  const pinsLayer = h('div', { id: 'pins' });
  const drawCanvas = h('canvas', { id: 'draw' });
  const hover = h('div', { id: 'hover' }, [h('span', { id: 'hovertag' })]);
  root.appendChild(shade);
  root.appendChild(drawCanvas);
  root.appendChild(pinsLayer);
  root.appendChild(hover);

  // ── the dock (radial, draggable, edge-snapping) ───────────────────────
  const ICONS = {
    dial: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="3" fill="currentColor"/><line x1="12" y1="3" x2="12" y2="7"/><line x1="12" y1="17" x2="12" y2="21"/><line x1="3" y1="12" x2="7" y2="12"/><line x1="17" y1="12" x2="21" y2="12"/></svg>',
    pin: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 21s-7-6.1-7-11a7 7 0 0 1 14 0c0 4.9-7 11-7 11z"/><circle cx="12" cy="10" r="2.5"/></svg>',
    list: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="8" y1="6" x2="21" y2="6"/><line x1="8" y1="12" x2="21" y2="12"/><line x1="8" y1="18" x2="21" y2="18"/><circle cx="4" cy="6" r="1.4" fill="currentColor"/><circle cx="4" cy="12" r="1.4" fill="currentColor"/><circle cx="4" cy="18" r="1.4" fill="currentColor"/></svg>',
    shade: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="9"/><path d="M12 3a9 9 0 0 1 0 18z" fill="currentColor"/></svg>',
    layers: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 2 2 8l10 6 10-6z"/><path d="m2 14 10 6 10-6"/></svg>',
    pen: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 19l7-7a2.1 2.1 0 0 0-3-3l-7 7-1 4z"/><path d="M18 13l-6-6"/></svg>',
    share: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="18" cy="5" r="3"/><circle cx="6" cy="12" r="3"/><circle cx="18" cy="19" r="3"/><line x1="8.6" y1="10.7" x2="15.4" y2="6.3"/><line x1="8.6" y1="13.3" x2="15.4" y2="17.7"/></svg>',
    design: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 4l7 17 2.5-6.5L20 12z"/><path d="M13.5 14.5 19 20"/></svg>',
    tokens: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="9"/><path d="M12 3a9 9 0 0 1 0 18"/><circle cx="8.5" cy="9.5" r="1.3" fill="currentColor"/><circle cx="8.5" cy="14.5" r="1.3" fill="currentColor"/><circle cx="12" cy="17.5" r="1.3" fill="currentColor"/></svg>',
  };
  function icon(name) {
    const span = document.createElement('span');
    span.innerHTML = ICONS[name];
    return span;
  }

  const dock = h('div', { id: 'dock' });
  const dockBtn = h('button', { id: 'dockbtn', title: 'Design Dial' }, [
    icon('dial'),
  ]);
  const badge = h('span', { class: 'dot', text: '0' });
  badge.style.display = 'none';
  dockBtn.appendChild(badge);
  dock.appendChild(dockBtn);
  root.appendChild(dock);

  // Radial verbs: angle fan upward from the dock.
  const VERBS = [
    { id: 'design', icon: 'design', tip: 'Design Mode — select & edit', modes: ['author'] },
    { id: 'tokens', icon: 'tokens', tip: 'Design tokens', modes: ['author'] },
    { id: 'pin', icon: 'pin', tip: 'Add a pin', modes: ['author', 'guest'] },
    { id: 'list', icon: 'list', tip: 'Feedback', modes: ['author', 'guest'] },
    { id: 'shade', icon: 'shade', tip: 'Review shade', modes: ['author', 'guest'] },
    { id: 'layers', icon: 'layers', tip: 'Layers', modes: ['author', 'guest'] },
    { id: 'pen', icon: 'pen', tip: 'Draw over', modes: ['author', 'guest'] },
    { id: 'share', icon: 'share', tip: 'Share link', modes: ['author'] },
  ];
  const verbEls = {};
  const verbOrder = [];
  VERBS.forEach((v, i) => {
    if (v.modes.indexOf(S.mode) === -1) return;
    const el = h('button', { class: 'verb', 'data-verb': v.id, title: v.tip }, [
      icon(v.icon),
      h('span', { class: 'tip', text: v.tip }),
    ]);
    el.addEventListener('click', (e) => {
      e.stopPropagation();
      onVerb(v.id, el);
    });
    verbEls[v.id] = el;
    verbOrder.push(el);
    dock.appendChild(el);
  });

  // The fan biases AWAY from the docked edge: right-docked fans up-left
  // (-175°..-85°), left-docked fans up-right (-95°..-5°) — verbs never clip
  // off-screen. Re-runs on every edge snap.
  function layoutFan() {
    const n = verbOrder.length;
    // The fan lives ENTIRELY in the inward upper quadrant: no verb ever
    // lands right of a right-docked dial (screen-edge clip) or left of a
    // left-docked one, and neighbor chords stay ≥ the 44px buttons so they
    // never overlap. The author's eight verbs (Design Mode added two) no
    // longer fit the 6-verb geometry — past -93° a 150px radius clips the
    // right edge — so a full fan tightens its spacing and widens its arc:
    // -178°..-83.5° at R=190 keeps every center ≥ 30px off the edge and
    // chords at 44.7px.
    const full = n > 7;
    const spacing = full ? 13.5 : 17;
    const start = S.dockSide === 'right' ? -178 : -2 - (n - 1) * spacing;
    const R = full ? 190 : 150;
    verbOrder.forEach((el, i) => {
      const rad = ((start + i * spacing) * Math.PI) / 180;
      el.style.left = 50 + (Math.cos(rad) * R * 100) / 56 + '%';
      el.style.top = 50 + (Math.sin(rad) * R * 100) / 56 + '%';
    });
  }
  layoutFan();

  function updateBadge() {
    const open = S.pins.filter(
      (p) => p.status === 'open' || p.status === 'in_progress',
    ).length;
    badge.textContent = String(open);
    badge.style.display = open ? 'flex' : 'none';
  }

  // Dock drag: pointer capture, 6px click threshold, edge snap. The fan
  // toggle lives on 'click', not pointerup: a keyboard or synthetic click
  // (no pointer events at all) must open the dial too.
  {
    let dragStart = null;
    let suppressClick = false;
    dockBtn.addEventListener('click', () => {
      if (suppressClick) {
        suppressClick = false;
        return;
      }
      S.open = !S.open;
      dock.classList.toggle('open', S.open);
    });
    dockBtn.addEventListener('pointerdown', (e) => {
      dragStart = { x: e.clientX, y: e.clientY, moved: false };
      dockBtn.setPointerCapture(e.pointerId);
    });
    dockBtn.addEventListener('pointermove', (e) => {
      if (!dragStart) return;
      const dx = e.clientX - dragStart.x;
      const dy = e.clientY - dragStart.y;
      if (!dragStart.moved && Math.hypot(dx, dy) > 6) dragStart.moved = true;
      if (dragStart.moved) {
        dock.style.right = 'auto';
        dock.style.left = e.clientX - 28 + 'px';
        dock.style.bottom = 'auto';
        dock.style.top = e.clientY - 28 + 'px';
      }
    });
    dockBtn.addEventListener('pointerup', (e) => {
      if (!dragStart) return;
      if (dragStart.moved) {
        // Edge snap: nearest horizontal edge, clamped inside the viewport.
        const r = dock.getBoundingClientRect();
        const side = r.left + r.width / 2 < innerWidth / 2 ? 'left' : 'right';
        S.dockSide = side;
        dock.classList.toggle('left', side === 'left');
        layoutFan();
        dock.style.left = side === 'left' ? '24px' : 'auto';
        dock.style.right = side === 'right' ? '24px' : 'auto';
        dock.style.top =
          Math.min(Math.max(r.top, 24), innerHeight - 80) + 'px';
        dock.style.bottom = 'auto';
        panel.classList.toggle('left', side === 'left');
        // Persist nothing — dock position is session state, not design state.
        suppressClick = true; // the trailing click is the drag's tail, not a toggle
      }
      dragStart = null;
    });
  }

  // ── toast ──────────────────────────────────────────────────────────────
  const toast = h('div', { id: 'toast' });
  root.appendChild(toast);
  let toastTimer = null;
  function say(msg) {
    toast.textContent = msg;
    toast.style.opacity = '1';
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => {
      toast.style.opacity = '0';
    }, 2600);
  }

  // ── the panel ──────────────────────────────────────────────────────────
  const panel = h('div', { id: 'panel' });
  const phead = h('div', { id: 'phead' });
  const pbody = h('div', { id: 'pbody' });
  panel.appendChild(phead);
  panel.appendChild(pbody);
  root.appendChild(panel);

  function setPanel(which, title) {
    if (S.panel === which) {
      S.panel = null;
      panel.classList.remove('open');
      return;
    }
    S.panel = which;
    phead.textContent = '';
    phead.appendChild(h('span', { text: title }));
    const badgeEl = h('span', {
      class: 'badge' + (S.store === 'memory' ? ' local' : ''),
      text:
        S.store === 'memory'
          ? 'local — pins die with this server'
          : S.mode === 'guest'
            ? 'shared'
            : 'live',
    });
    phead.appendChild(badgeEl);
    panel.classList.add('open');
    // An open panel owns the screen corner — an expanded fan would float
    // over it (eight verbs at R=190 reach the panel's right edge).
    dock.classList.remove('open');
    S.open = false;
    renderPanelBody();
  }

  function renderPanelBody() {
    pbody.textContent = '';
    if (S.panel === 'feedback') return renderFeedbackList();
    if (S.panel === 'shade') return renderShadeCtl();
    if (S.panel === 'layers') return renderLayersCtl();
    if (S.panel === 'share') return renderShareCtl();
    if (S.panel === 'design') return renderDesignPanel();
    if (S.panel === 'tokens') return renderTokensPanel();
  }

  function chip(status) {
    return h('span', {
      class: 'chip ' + status.replace('_', ''),
      text: (KANBAN.find((k) => k[0] === status) || ['?', status])[1],
    });
  }

  function renderFeedbackList() {
    const route = location.pathname;
    const here = S.pins.filter((p) => p.route === route);
    const elsewhere = S.pins.filter((p) => p.route !== route);
    if (!S.pins.length) {
      pbody.appendChild(
        h('div', { class: 'ctl', text: 'No pins yet — arm the pin verb and click the design.' }),
      );
      return;
    }
    const section = (title, list) => {
      if (!list.length) return;
      if (title) {
        pbody.appendChild(
          h('div', {
            class: 'ctl',
            text: title,
            style: 'color:#9aa0ab;font-size:11px;padding:6px 10px 2px',
          }),
        );
      }
      list.forEach((p, i) => {
        const row = h('div', { class: 'row' + (S.activePin === p.id ? ' active' : '') });
        const txt = h('span', { class: 'txt', text: p.body });
        const meta = h('div', { class: 'meta' }, [
          chip(p.status),
          h('span', { text: p.name + ' · #' + (S.pins.indexOf(p) + 1) }),
        ]);
        if (!p.anchor.el) meta.appendChild(h('span', { class: 'orphan-tag', text: 'surface' }));
        else if (!resolveAnchor(p)) meta.appendChild(h('span', { class: 'orphan-tag', text: 'orphaned' }));
        row.appendChild(txt);
        row.appendChild(meta);
        row.addEventListener('click', () => openThread(p));
        pbody.appendChild(row);
      });
    };
    section(null, here);
    section('Other routes', elsewhere);
  }

  function renderShadeCtl() {
    const row = h('div', { class: 'ctl' });
    row.appendChild(h('span', { text: 'Review shade' }));
    const slider = h('input', { type: 'range', min: '0', max: '60', value: String(S.shade * 100) });
    slider.addEventListener('input', () => {
      S.shade = slider.value / 100;
      applyShade();
    });
    row.appendChild(slider);
    pbody.appendChild(row);
    pbody.appendChild(
      h('div', { class: 'ctl', style: 'color:#9aa0ab;font-size:11px', text: 'Dims the design so pins and drawings stand out. 0 is off.' }),
    );
  }

  function renderLayersCtl() {
    for (const layer of ['pins', 'comments', 'drawings']) {
      const row = h('div', { class: 'ctl' });
      row.appendChild(h('span', { text: layer[0].toUpperCase() + layer.slice(1) }));
      const sw = h('button', {
        class: 'switch' + (S.layers[layer] ? ' on' : ''),
        'aria-label': 'toggle ' + layer,
      });
      sw.addEventListener('click', () => {
        S.layers[layer] = !S.layers[layer];
        sw.classList.toggle('on', S.layers[layer]);
        applyLayers();
      });
      row.appendChild(sw);
      pbody.appendChild(row);
    }
  }

  function renderShareCtl() {
    pbody.appendChild(
      h('div', { class: 'ctl', style: 'font-size:12px;color:#9aa0ab', text: 'Mint a link your client opens to pin comments on this design. View + comment only; 30 days.' }),
    );
    const btn = h('button', { class: 'btn', text: 'Mint share link' });
    btn.addEventListener('click', async () => {
      btn.textContent = 'Minting…';
      const r = await api('POST', '/share', {});
      if (r && r.token) {
        const url = location.origin + location.pathname + '?dial=' + r.token;
        const box = h('div', { class: 'linkbox', text: url });
        const copy = h('button', { class: 'btn ghost', text: 'Copy' });
        copy.addEventListener('click', async () => {
          try {
            await navigator.clipboard.writeText(url);
            say('Link copied');
          } catch (_) {
            say('Copy failed — select the link manually');
          }
        });
        pbody.appendChild(box);
        pbody.appendChild(h('div', { class: 'btnrow' }, [copy]));
      } else {
        say('Could not mint a link');
      }
      btn.textContent = 'Mint share link';
    });
    pbody.appendChild(h('div', { class: 'ctl' }, [btn]));
  }

  // ── shade + layers application ─────────────────────────────────────────
  function applyShade() {
    shade.style.opacity = String(S.shade);
  }
  function applyLayers() {
    pinsLayer.style.display = S.layers.pins ? '' : 'none';
    // 'comments' is the THREAD layer. The panel is the dial's own chrome —
    // hiding it from applyLayers vanished the very Layers panel the user was
    // clicking in (smoke S7b).
    thread.style.display = S.layers.comments ? '' : 'none';
    if (!S.layers.comments) closeThread();
    drawCanvas.style.display = S.layers.drawings ? '' : 'none';
  }

  // ── pin anchoring: data-el identity + rect snapshot (decision 6) ──────
  function resolveAnchor(pin) {
    if (!pin.anchor.el) return null;
    const sel = '[data-el="' + pin.anchor.el.replace(/"/g, '') + '"]';
    const el = document.querySelector(sel);
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return { x: r.left + scrollX + r.width / 2, y: r.top + scrollY };
  }

  // Anchor point in PAGE coords: element center when resolvable, else the
  // stored snapshot's center (orphaned pins hold their last known spot).
  function anchorPoint(pin) {
    const live = resolveAnchor(pin);
    if (live) return { p: live, orphan: false };
    const rc = pin.anchor.rect;
    return { p: { x: rc.x + rc.w / 2, y: rc.y + rc.h / 2 }, orphan: !!pin.anchor.el };
  }

  function renderPins() {
    pinsLayer.textContent = '';
    const route = location.pathname;
    S.pins.forEach((pin, i) => {
      if (pin.route !== route) return;
      const pt = anchorPoint(pin);
      const b = h('button', {
        class:
          'pin ' +
          pin.status.replace('_', '') +
          (pt.orphan ? ' orphan' : '') +
          (pin.drawing ? ' drawn' : '') +
          (S.activePin === pin.id ? ' active' : ''),
        text: String(i + 1),
        title: pin.name + ': ' + pin.body,
      });
      b.style.left = pt.p.x - scrollX + 'px';
      b.style.top = pt.p.y - scrollY + 'px';
      b.addEventListener('click', (e) => {
        e.stopPropagation();
        openThread(pin);
      });
      pinsLayer.appendChild(b);
    });
  }

  let rafPending = false;
  function scheduleRepin() {
    if (rafPending) return;
    rafPending = true;
    requestAnimationFrame(() => {
      rafPending = false;
      renderPins();
      redrawStrokes();
      renderHandles();
    });
  }
  addEventListener('scroll', scheduleRepin, { passive: true, capture: true });
  addEventListener('resize', scheduleRepin);

  // ── pin placement (the inspect.js walk, trimmed) ───────────────────────
  function targetAt(x, y) {
    const stack = document.elementsFromPoint(x, y);
    for (const el of stack) {
      if (host.contains(el) || el === host) continue;
      let node = el;
      if (node.namespaceURI && node.namespaceURI.indexOf('svg') !== -1 && node.tagName !== 'svg') {
        node = node.closest('svg') || node;
      }
      const hit = node.closest && node.closest('[data-el]');
      if (hit) {
        const r = hit.getBoundingClientRect();
        return {
          el: hit.getAttribute('data-el'),
          rect: { x: r.left + scrollX, y: r.top + scrollY, w: r.width, h: r.height },
          screenRect: r,
        };
      }
    }
    const r = document.body.getBoundingClientRect();
    return {
      el: null,
      rect: { x: r.left + scrollX, y: r.top + scrollY, w: r.width, h: r.height },
      screenRect: r,
    };
  }

  function onArmMove(e) {
    const t = targetAt(e.clientX, e.clientY);
    hover.style.display = 'block';
    hover.style.left = t.screenRect.left + 'px';
    hover.style.top = t.screenRect.top + 'px';
    hover.style.width = t.screenRect.width + 'px';
    hover.style.height = t.screenRect.height + 'px';
    hover.firstChild.textContent = t.el || 'surface';
  }

  function onArmClick(e) {
    e.preventDefault();
    e.stopPropagation();
    const t = targetAt(e.clientX, e.clientY);
    disarm();
    openComposer(e.clientX, e.clientY, t);
  }

  function arm() {
    if (S.design) designOff();
    S.arming = true;
    verbEls.pin.classList.add('on');
    document.addEventListener('pointermove', onArmMove, true);
    document.addEventListener('click', onArmClick, true);
  }
  function disarm() {
    S.arming = false;
    verbEls.pin.classList.remove('on');
    hover.style.display = 'none';
    document.removeEventListener('pointermove', onArmMove, true);
    document.removeEventListener('click', onArmClick, true);
  }

  // ── the composer (new pin) ─────────────────────────────────────────────
  const composer = h('div', { id: 'composer' });
  root.appendChild(composer);

  function openComposer(x, y, target) {
    composer.textContent = '';
    composer.style.left = Math.min(x + 12, innerWidth - 300) + 'px';
    composer.style.top = Math.min(y + 12, innerHeight - 260) + 'px';
    composer.appendChild(
      h('div', { class: 'who', style: 'font-size:11px;color:#9aa0ab', text: 'Pin on: ' + (target.el || 'whole surface') }),
    );
    const area = h('textarea', { rows: '3', placeholder: 'What should change?' });
    composer.appendChild(area);
    let nameInput = null;
    if (S.mode === 'guest' && !S.name) {
      nameInput = h('input', { type: 'text', placeholder: 'Your name', style: 'margin-top:8px' });
      composer.appendChild(nameInput);
    }
    if (S.strokes.length) {
      composer.appendChild(
        h('div', { class: 'who', style: 'font-size:11px;color:#f59e0b;margin-top:8px', text: '✎ ' + S.strokes.length + ' stroke(s) will attach to this pin' }),
      );
    }
    const add = h('button', { class: 'btn', text: 'Add pin' });
    const cancel = h('button', { class: 'btn ghost', text: 'Cancel' });
    composer.appendChild(h('div', { class: 'btnrow' }, [cancel, add]));
    composer.classList.add('open');
    area.focus();
    cancel.addEventListener('click', () => composer.classList.remove('open'));
    add.addEventListener('click', async () => {
      const body = area.value.trim();
      if (!body) return;
      if (nameInput) {
        S.name = nameInput.value.trim() || 'guest';
        try {
          localStorage.setItem('arxa-dial-name', S.name);
        } catch (_) {}
      }
      const drawing = S.strokes.length
        ? S.strokes.map((st) => st.map((pt) => [Math.round(pt[0] * 10) / 10, Math.round(pt[1] * 10) / 10]))
        : undefined;
      const r = await api('POST', '/pins', {
        route: location.pathname,
        viewport: { w: innerWidth, h: innerHeight },
        anchor: { el: target.el, rect: target.rect },
        body,
        name: S.name || undefined,
        drawing,
      });
      composer.classList.remove('open');
      if (r && r.pin) {
        if (drawing) {
          S.strokes = [];
          redrawStrokes();
        }
        say(drawing ? 'Pin added with your drawing' : 'Pin added');
        await loadPins();
      } else {
        say((r && r.error) || 'Pin failed');
      }
    });
  }

  // ── the thread popover ─────────────────────────────────────────────────
  const thread = h('div', { id: 'thread' });
  root.appendChild(thread);

  function openThread(pin) {
    S.activePin = pin.id;
    S.activeDrawing = pin.drawing || null;
    redrawStrokes();
    renderPins();
    const pt = anchorPoint(pin);
    thread.textContent = '';
    const head = h('div', { class: 'who', text: pin.name + ' · ' + pin.route });
    thread.appendChild(head);
    thread.appendChild(h('div', { class: 'body', text: pin.body }));
    const replies = h('div', { class: 'replies' });
    (pin.replies || []).forEach((r) => {
      replies.appendChild(
        h('div', { class: 'reply' }, [
          h('span', { class: 'who', text: r.name + ' (' + r.author + '):' }),
          h('span', { text: r.body }),
        ]),
      );
    });
    thread.appendChild(replies);
    // Kanban row — Author only (locked decision 1).
    if (S.mode === 'author') {
      const row = h('div', { id: 'statusrow' });
      KANBAN.forEach(([st, label]) => {
        const b = h('button', {
          class: 'stbtn' + (pin.status === st ? ' cur' : ''),
          text: label,
        });
        b.addEventListener('click', async () => {
          await api('POST', '/pins/status', { id: pin.id, status: st });
          await loadPins();
          const fresh = S.pins.find((p) => p.id === pin.id);
          if (fresh) openThread(fresh);
        });
        row.appendChild(b);
      });
      thread.appendChild(row);
    }
    const input = h('input', { type: 'text', placeholder: 'Reply…' });
    input.addEventListener('keydown', async (e) => {
      if (e.key !== 'Enter' || !input.value.trim()) return;
      await api('POST', '/pins/reply', {
        id: pin.id,
        body: input.value.trim(),
        name: S.name || undefined,
      });
      input.value = '';
      await loadPins();
      const fresh = S.pins.find((p) => p.id === pin.id);
      if (fresh) openThread(fresh);
    });
    thread.appendChild(input);
    thread.classList.add('open');
    // Position near the pin, clamped into the viewport.
    const sx = pt.p.x - scrollX;
    const sy = pt.p.y - scrollY;
    thread.style.left = Math.min(Math.max(sx + 18, 8), innerWidth - 316) + 'px';
    thread.style.top = Math.min(Math.max(sy + 18, 8), innerHeight - 320) + 'px';
  }
  function closeThread() {
    S.activePin = null;
    S.activeDrawing = null;
    redrawStrokes();
    thread.classList.remove('open');
    renderPins();
  }

  // ── the draw-over (ephemeral by design — see header) ──────────────────
  const ctx = drawCanvas.getContext('2d');
  function sizeCanvas() {
    drawCanvas.width = innerWidth * devicePixelRatio;
    drawCanvas.height = innerHeight * devicePixelRatio;
    drawCanvas.style.width = innerWidth + 'px';
    drawCanvas.style.height = innerHeight + 'px';
    redrawStrokes();
  }
  function redrawStrokes() {
    if (!ctx) return;
    ctx.clearRect(0, 0, drawCanvas.width, drawCanvas.height);
    ctx.lineWidth = 2.5 * devicePixelRatio;
    ctx.lineCap = 'round';
    const paint = (strokes, color) => {
      ctx.strokeStyle = color;
      strokes.forEach((stroke) => {
        ctx.beginPath();
        stroke.forEach((pt, i) => {
          const x = (pt[0] - scrollX) * devicePixelRatio;
          const y = (pt[1] - scrollY) * devicePixelRatio;
          if (i === 0) ctx.moveTo(x, y);
          else ctx.lineTo(x, y);
        });
        ctx.stroke();
      });
    };
    // Pending strokes (not yet pinned) are amber; the open pin's attached
    // drawing replays in the dial's cyan so the two are never confused.
    paint(S.strokes, '#f59e0b');
    if (S.activeDrawing) paint(S.activeDrawing, '#38bdf8');
  }
  {
    let current = null;
    drawCanvas.addEventListener('pointerdown', (e) => {
      current = [[e.clientX + scrollX, e.clientY + scrollY]];
      S.strokes.push(current);
      drawCanvas.setPointerCapture(e.pointerId);
    });
    drawCanvas.addEventListener('pointermove', (e) => {
      if (!current) return;
      current.push([e.clientX + scrollX, e.clientY + scrollY]);
      redrawStrokes();
    });
    drawCanvas.addEventListener('pointerup', () => {
      current = null;
    });
  }
  sizeCanvas();

  // ── Design Mode (author only; locked decisions 1-5) ────────────────────
  // Selection walks data-arxa-id (the machine identity design patch rides),
  // facet sets are curated per element kind, and every edit applies live,
  // then auto-saves into the server-side Draft Overlay. Artifact source is
  // only ever touched by the studio-socket commit — never from this island.

  const FACET_GROUPS = {
    text: ['color', 'font-size', 'font-weight', 'line-height', 'letter-spacing', 'text-align'],
    action: ['background', 'color', 'font-size', 'font-weight', 'padding', 'border-radius'],
    surface: ['background', 'padding', 'gap', 'width', 'height', 'border-radius', 'border-color'],
    field: ['background', 'color', 'font-size', 'padding', 'border-color', 'border-radius'],
    media: ['width', 'height', 'opacity'],
    generic: ['color', 'background', 'font-size', 'width', 'height', 'padding', 'margin', 'border-radius'],
  };
  // The 15-kind widget vocabulary plus the simple data-el names and tag
  // kinds real artifacts carry; anything unlisted edits as 'generic'.
  const KIND_GROUP = {
    card: 'surface', 'panel-activity': 'surface', modal: 'surface', dialog: 'surface',
    'bottom-sheet': 'surface', 'empty-state': 'surface', toast: 'surface', panel: 'surface',
    'list-row': 'surface', frame: 'surface',
    'cta-link': 'action', chip: 'action', appbar: 'action', tabbar: 'action', tabs: 'action',
    'nav-rail': 'action', action: 'action', button: 'action', link: 'action',
    text: 'text', heading: 'text', label: 'text', title: 'text',
    'form-field': 'field', input: 'field', field: 'field',
    icon: 'media', image: 'media', media: 'media',
  };
  const TAG_KIND = {
    h1: 'heading', h2: 'heading', h3: 'heading', h4: 'heading', h5: 'heading', h6: 'heading',
    p: 'text', span: 'text', label: 'label', a: 'link', button: 'button',
    img: 'image', svg: 'icon', input: 'input', textarea: 'input', select: 'input',
    nav: 'nav-rail', header: 'appbar', li: 'list-row',
  };
  const COLOR_PROPS = { background: 1, color: 1, 'border-color': 1 };
  const SELECT_OPTS = {
    'font-weight': ['300', '400', '500', '600', '700', '800'],
    'text-align': ['left', 'center', 'right', 'start', 'end'],
  };

  function kindOf(el) {
    const de = el.getAttribute('data-el');
    if (de) {
      const k = de.split(':')[0].toLowerCase();
      if (KIND_GROUP[k]) return { kind: k, group: KIND_GROUP[k] };
    }
    const tag = el.tagName.toLowerCase();
    const kind = TAG_KIND[tag] || tag;
    return { kind: kind, group: KIND_GROUP[kind] || 'generic' };
  }

  // The selection walk: data-arxa-id identity, SVG collapse, island skipped.
  function designTargetAt(x, y) {
    const stack = document.elementsFromPoint(x, y);
    for (const el of stack) {
      if (host.contains(el) || el === host) continue;
      let node = el;
      if (node.namespaceURI && node.namespaceURI.indexOf('svg') !== -1 && node.tagName !== 'svg') {
        node = node.closest('svg') || node;
      }
      const hit = node.closest && node.closest('[data-arxa-id]');
      if (hit) {
        const k = kindOf(hit);
        return {
          id: hit.getAttribute('data-arxa-id'),
          el: hit,
          label: (hit.getAttribute('data-el') || hit.tagName.toLowerCase()) + ' · ' + k.kind,
          group: k.group,
          rect: hit.getBoundingClientRect(),
        };
      }
    }
    return null;
  }

  function onDesignMove(e) {
    if (e.composedPath().indexOf(host) !== -1) { hover.style.display = 'none'; return; }
    const t = designTargetAt(e.clientX, e.clientY);
    if (!t) { hover.style.display = 'none'; return; }
    hover.classList.add('design');
    hover.style.display = 'block';
    hover.style.left = t.rect.left + 'px';
    hover.style.top = t.rect.top + 'px';
    hover.style.width = t.rect.width + 'px';
    hover.style.height = t.rect.height + 'px';
    hover.firstChild.textContent = t.label;
  }

  function onDesignClick(e) {
    if (e.composedPath().indexOf(host) !== -1) return; // the panel stays usable
    // While editing text on-canvas, clicks INSIDE the edited element are
    // cursor placement — the page keeps them. A click anywhere else commits.
    if (S.inlineEditing != null && S.selected) {
      if (S.selected.el.contains(e.target)) return;
      inlineEditEnd(true);
    }
    const t = designTargetAt(e.clientX, e.clientY);
    if (!t) return; // unstamped spot — let the page have the click
    e.preventDefault();
    e.stopPropagation();
    selectEl(t);
  }

  // Which identity a patch binds to (amended 2026-08-24 — authored identity
  // wins on divergence): when one machine id fans out over instances with
  // DIFFERENT authored meanings, keying the patch by machine id would commit
  // the edit over every sibling slot at once (the operator's copyright edit
  // on the shared wordmark id nearly rewrote the statement text too). A
  // divergent selection binds to its data-el; homogeneous loops keep the
  // machine id and its every-row-at-once fan-out.
  function bindingFor(el, id) {
    const inst = [...document.querySelectorAll('[data-arxa-id="' + id + '"]')];
    if (inst.length > 1) {
      const meanings = new Set(inst.map((x) => x.getAttribute('data-el') || ''));
      if (meanings.size > 1) {
        const de = el.getAttribute('data-el');
        if (de) return 'el:' + de;
      }
    }
    return id;
  }

  function selectEl(t) {
    if (S.inlineEditing != null) inlineEditEnd(true); // commit before switching
    clearSelOutline();
    S.selected = { id: t.id, key: bindingFor(t.el, t.id), el: t.el, label: t.label, group: t.group };
    S.selOutline = t.el.style.outline;
    t.el.style.outline = '2px solid #f59e0b';
    renderHandles();
    trackHandles();
    if (S.panel === 'design') renderPanelBody();
    else setPanel('design', 'Design Mode');
  }
  function clearSelOutline() {
    if (S.inlineEditing != null) inlineEditEnd(true);
    if (S.selected) S.selected.el.style.outline = S.selOutline || '';
    S.selected = null;
    handlesLayer.textContent = '';
  }

  // ── direct manipulation: resize handles + on-canvas text editing ─────
  // Locked decision 2 ("direct manipulation + studio socket") read literally:
  // the Author drags the selection's amber handles to resize it and
  // double-clicks pure-text elements to type in place. Every change still
  // flows through the SAME patch functions (setStyleProp / setTextContent),
  // so live-apply, Draft Overlay auto-save, and the commit socket are
  // identical to panel edits — the handles are a gesture, not a write path.
  const handlesLayer = h('div', { id: 'handles' });
  root.appendChild(handlesLayer);
  const DIRS = ['nw', 'n', 'ne', 'e', 'se', 's', 'sw', 'w'];
  function renderHandles() {
    handlesLayer.textContent = '';
    if (!S.selected || !S.design) return;
    if (!document.contains(S.selected.el)) return; // hot-reload swapped the DOM
    const r = S.selected.el.getBoundingClientRect();
    if (r.width < 4 || r.height < 4) return;
    const pts = {
      nw: [r.left, r.top], n: [r.left + r.width / 2, r.top], ne: [r.right, r.top],
      e: [r.right, r.top + r.height / 2], se: [r.right, r.bottom],
      s: [r.left + r.width / 2, r.bottom], sw: [r.left, r.bottom],
      w: [r.left, r.top + r.height / 2],
    };
    for (const d of DIRS) {
      const hd = h('div', { class: 'hnd', 'data-d': d });
      hd.style.left = pts[d][0] + 'px';
      hd.style.top = pts[d][1] + 'px';
      hd.addEventListener('pointerdown', (e) => startHandleDrag(e, d));
      handlesLayer.appendChild(hd);
    }
  }
  // Handles must TRACK the selection, not snapshot it: artifacts animate
  // their own elements (this one's intro flies the wordmark in), and a
  // render-at-click-time handle set freezes where the element WAS. A rAF
  // loop repositions the existing handles every frame while a selection is
  // live; it parks itself when the selection clears.
  let handleRaf = 0;
  function positionHandles() {
    const kids = handlesLayer.children;
    if (!S.selected || kids.length !== 8) return;
    if (!document.contains(S.selected.el)) return;
    const r = S.selected.el.getBoundingClientRect();
    const pts = {
      nw: [r.left, r.top], n: [r.left + r.width / 2, r.top], ne: [r.right, r.top],
      e: [r.right, r.top + r.height / 2], se: [r.right, r.bottom],
      s: [r.left + r.width / 2, r.bottom], sw: [r.left, r.bottom],
      w: [r.left, r.top + r.height / 2],
    };
    for (let i = 0; i < DIRS.length; i++) {
      kids[i].style.left = pts[DIRS[i]][0] + 'px';
      kids[i].style.top = pts[DIRS[i]][1] + 'px';
    }
  }
  function trackHandles() {
    cancelAnimationFrame(handleRaf);
    const tick = () => {
      if (!S.selected || !S.design) return;
      positionHandles();
      handleRaf = requestAnimationFrame(tick);
    };
    handleRaf = requestAnimationFrame(tick);
  }
  function startHandleDrag(e, dir) {
    e.preventDefault();
    e.stopPropagation();
    const sel = S.selected;
    if (!sel) return;
    const r0 = sel.el.getBoundingClientRect();
    const x0 = e.clientX, y0 = e.clientY;
    const w0 = r0.width, h0 = r0.height;
    const move = (ev) => {
      const dx = ev.clientX - x0, dy = ev.clientY - y0;
      if (dir.indexOf('e') !== -1) setStyleProp(sel.key, 'width', Math.max(10, Math.round(w0 + dx)) + 'px');
      if (dir.indexOf('w') !== -1) setStyleProp(sel.key, 'width', Math.max(10, Math.round(w0 - dx)) + 'px');
      if (dir.indexOf('s') !== -1) setStyleProp(sel.key, 'height', Math.max(10, Math.round(h0 + dy)) + 'px');
      if (dir.indexOf('n') !== -1) setStyleProp(sel.key, 'height', Math.max(10, Math.round(h0 - dy)) + 'px');
      renderHandles();
    };
    const up = () => {
      document.removeEventListener('pointermove', move, true);
      document.removeEventListener('pointerup', up, true);
      renderPanelBody(); // the facet inputs catch up with the dragged values
    };
    document.addEventListener('pointermove', move, true);
    document.addEventListener('pointerup', up, true);
  }

  // Text-editable means: no STAMPED descendant. Runtime line/word splitters
  // (the artifact's own intro animator wraps "SUCZKA" in unstamped .line
  // divs) nest markup the source never had — the text is still one authored
  // string, the patch applies to source, and the animator re-splits the new
  // text on next serve. Genuine composites carry stamped children and stay
  // refused, the same refusal the patch grammar enforces on --text.
  function isTextEditable(el) {
    return (el.textContent || '').trim().length > 0 &&
      !el.querySelector('[data-arxa-id], [data-el]');
  }
  function inlineEditStart() {
    const sel = S.selected;
    if (!sel || S.inlineEditing != null) return;
    if (!isTextEditable(sel.el)) {
      say('Composite element — edit its parts, not its text');
      return;
    }
    S.inlineEditing = sel.el.textContent;
    sel.el.setAttribute('contenteditable', 'true');
    sel.el.setAttribute('data-arxa-inline-editing', '1');
    sel.el.focus();
    const range = document.createRange();
    range.selectNodeContents(sel.el);
    const s = getSelection();
    s.removeAllRanges();
    s.addRange(range);
    sel.el.addEventListener('focusout', onInlineFocusOut);
  }
  function onInlineFocusOut(e) {
    // relatedTarget null means focus left the DOCUMENT (OS focus change,
    // DevTools, headless quirk) — not the author clicking the design. Page
    // clicks already commit via onDesignClick; a blur-to-nowhere must not
    // slam the editor shut the moment it opens.
    if (e && e.relatedTarget == null) return;
    if (S.inlineEditing != null) inlineEditEnd(true);
  }
  function inlineEditEnd(commit) {
    const sel = S.selected;
    if (!sel || S.inlineEditing == null) return;
    const original = S.inlineEditing;
    S.inlineEditing = null;
    const el = sel.el;
    el.removeEventListener('focusout', onInlineFocusOut);
    el.removeAttribute('contenteditable');
    el.removeAttribute('data-arxa-inline-editing');
    if (commit) {
      // setTextContent normalizes whatever markup contenteditable produced,
      // patches the draft, and schedules the auto-save.
      setTextContent(sel.key, el.textContent, el);
    } else {
      el.textContent = original;
    }
    if (S.panel === 'design') renderPanelBody();
  }
  function onDesignDblClick(e) {
    if (e.composedPath().indexOf(host) !== -1) return;
    const t = designTargetAt(e.clientX, e.clientY);
    if (!t) return;
    e.preventDefault();
    e.stopPropagation();
    if (!S.selected || S.selected.el !== t.el) selectEl(t);
    inlineEditStart();
  }

  function designOn() {
    if (S.arming) disarm();
    S.design = true;
    verbEls.design.classList.add('on');
    document.addEventListener('pointermove', onDesignMove, true);
    document.addEventListener('click', onDesignClick, true);
    document.addEventListener('dblclick', onDesignDblClick, true);
    if (S.panel !== 'design') setPanel('design', 'Design Mode');
    say('Design Mode — click to select, double-click text to edit, drag the handles');
  }
  function designOff() {
    S.design = false;
    if (verbEls.design) verbEls.design.classList.remove('on');
    hover.style.display = 'none';
    hover.classList.remove('design');
    clearSelOutline();
    document.removeEventListener('pointermove', onDesignMove, true);
    document.removeEventListener('click', onDesignClick, true);
    document.removeEventListener('dblclick', onDesignDblClick, true);
  }

  // ── the Draft Overlay: live apply + debounced auto-save ────────────────
  function patchFor(id) {
    let p = S.draft.patches[id];
    if (!p) { p = { style: {}, attrs: {} }; S.draft.patches[id] = p; }
    if (!p.style) p.style = {};
    if (!p.attrs) p.attrs = {};
    return p;
  }

  let saveTimer = null;
  function scheduleSave() {
    S.draftDirty = true;
    clearTimeout(saveTimer);
    saveTimer = setTimeout(saveDraft, 700);
    renderDraftMeta();
  }
  // The text patches' current signature — used to tell "this save changed
  // text" apart from style-only saves, because only text changes need the
  // reload converge (animator-owned nodes; see syncRemoteDraft).
  function textSig(d) {
    const parts = [];
    for (const k of Object.keys(d.patches).sort()) {
      const t = (d.patches[k] || {}).text;
      if (t != null) parts.push(k + '=' + t);
    }
    return parts.join('|');
  }
  let lastTextSig = null;
  let textReloadTimer = null;

  async function saveDraft() {
    if (!S.draftDirty) return;
    S.draftDirty = false;
    S.ownSave = Date.now();
    const r = await api('PUT', '/draft', { tokens: S.draft.tokens, patches: S.draft.patches });
    if (r && r.ok) {
      S.draftMeta = r;
      S.draftWarnings = r.warnings || [];
      renderDraftMeta();
    }
    else say(r && r.error ? 'Draft refused: ' + r.error : 'Draft save failed');
    // A text edit the author just committed will be fought by the artifact's
    // own animator (it re-renders split text from its boot capture — the
    // edit looks like it "did nothing" or duplicates). Once typing pauses,
    // reload so the author sees the animator rendering the NEW text — the
    // same converge the sibling rungs do. Style-only saves never reload.
    const sig = textSig(S.draft);
    if (r && r.ok && lastTextSig != null && sig !== lastTextSig) {
      lastTextSig = sig;
      clearTimeout(textReloadTimer);
      textReloadTimer = setTimeout(resumeReload, 1400);
    } else {
      lastTextSig = sig;
    }
  }

  // The editing rung's text-converge reload must not cost the author his
  // place: stash the design session, reload, and resumeAfterReload (boot)
  // re-arms and re-selects — the reload reads as a flicker, not a reset.
  function resumeReload() {
    try {
      sessionStorage.setItem('arxa-dial-resume', JSON.stringify({
        design: S.design,
        key: S.selected ? S.selected.key : null,
      }));
    } catch (_) {}
    location.reload();
  }
  function resumeAfterReload() {
    let r = null;
    try { r = JSON.parse(sessionStorage.getItem('arxa-dial-resume') || 'null'); } catch (_) {}
    try { sessionStorage.removeItem('arxa-dial-resume'); } catch (_) {}
    if (!r || S.mode !== 'author') return;
    if (r.design) designOn();
    if (r.key) {
      const el = targetsForKey(r.key)[0];
      const id = el && el.getAttribute('data-arxa-id');
      if (el && id) {
        const k = kindOf(el);
        selectEl({
          id: id, el: el,
          label: (el.getAttribute('data-el') || el.tagName.toLowerCase()) + ' · ' + k.kind,
          group: k.group,
        });
      }
    }
  }
  async function loadDraft() {
    if (S.mode !== 'author') return false;
    const r = await probeCapable('/draft');
    // Capability, not content: {"draft":null} is a REAL author answer (no
    // draft saved yet) and must boot the dock. Only the server's quiet
    // mirror marker or a dead network means this context has no dial.
    if (r == null || r.mirror === true) return false;
    S.draftWarnings = r.warnings || []; // parity: computed server-side on every draft read
    if (r.draft) {
      S.draft.tokens = r.draft.tokens || {};
      S.draft.patches = r.draft.patches || {};
      lastTextSig = textSig(S.draft); // boot truth — only CHANGES reload
    }
    return true;
  }

  // Apply the CURRENT draft patch set to this document. The serve-time
  // overlay does this for page loads; this is the live path for frames that
  // are already open (the other rungs of the ladder, another author tab).
  function applyPatchesLive() {
    for (const key of Object.keys(S.draft.patches)) {
      const p = S.draft.patches[key] || {};
      for (const el of targetsForKey(key)) {
        if (p.style) {
          for (const prop of Object.keys(p.style)) {
            const v = p.style[prop];
            if (v == null) el.style.removeProperty(prop);
            else el.style.setProperty(prop, v);
          }
        }
        // Text lands only on text-editable targets; composite instances are
        // the serve-time overlay's job (it refuses them loudly, by design).
        if (p.text != null && isTextEditable(el)) el.textContent = p.text;
      }
    }
  }

  // Another author context saved its draft (a sibling rung of the viewport
  // ladder, a second tab): pull it and apply — the operator's law is that
  // every platform the design was authored at shows the same thing LIVE
  // (amended 2026-08-24). Removals can't be un-applied from a live DOM we
  // never snapshotted, so a shrinking draft converges by reload — the same
  // thing the resetting rung itself does.
  let syncing = false;
  function patchPropCount(d) {
    let n = 0;
    for (const k of Object.keys(d.patches)) {
      const p = d.patches[k] || {};
      n += (p.style ? Object.keys(p.style).length : 0) + (p.attrs ? Object.keys(p.attrs).length : 0) + (p.text != null ? 1 : 0);
    }
    return n;
  }
  async function syncRemoteDraft() {
    if (syncing || S.mode !== 'author') return;
    syncing = true;
    try {
      const r = await api('GET', '/draft');
      if (!r || !r.draft) return;
      const next = { tokens: r.draft.tokens || {}, patches: r.draft.patches || {} };
      const had = Object.keys(S.draft.patches).length + Object.keys(S.draft.tokens).length;
      const has = Object.keys(next.patches).length + Object.keys(next.tokens).length;
      const shrink = has < had || patchPropCount(next) < patchPropCount(S.draft);
      // Text patches converge ONLY by reload: artifact animators own their
      // text nodes (this one's intro re-splits the wordmark every pass from
      // its boot capture — a live textContent write is reverted, duplicated,
      // or collapsed within seconds, worst on wide rungs). A reload re-serves
      // with the overlay applied and the animator boots on the NEW text.
      // Style/token patches have no such owner — they stay live.
      //
      // Reload only when the incoming TEXT SIGNATURE differs from the one
      // this document rendered with (lastTextSig — set at boot and after own
      // saves). The earlier "any text patch exists" test reloaded every rung
      // on every frame — duplicate frames and style-only saves included —
      // yet could still leave a rung that had MISSED frames stale forever,
      // because nothing re-checked divergence. The signature check both
      // spares the pointless reloads and catches the missed-frame rung.
      if (shrink || textSig(next) !== lastTextSig) { location.reload(); return; }
      S.draft.tokens = next.tokens;
      S.draft.patches = next.patches;
      applyTokensLive();
      applyPatchesLive();
      if (S.panel === 'design' || S.panel === 'tokens') renderPanelBody();
    } finally {
      syncing = false;
    }
  }

  function renderDraftMeta() {
    const el = root.getElementById('draftmeta');
    if (!el) return;
    const np = Object.keys(S.draft.patches).length;
    const nt = Object.keys(S.draft.tokens).length;
    const nw = (S.draftWarnings || []).filter(w =>
      Object.keys(S.draft.patches).indexOf('el:' + w.el) >= 0).length;
    let txt = S.draftDirty
      ? 'unsaved changes…'
      : np + ' patches · ' + nt + ' tokens' + (S.draftMeta ? ' · saved' : '');
    if (nw > 0) {
      const detail = S.draftWarnings
        .map(w => w.el + ': ' + w.sites + ' name= sites (' + w.problem + ')')
        .join('; ');
      txt += ' · ⚠ ' + nw + ' uncommittable';
      el.title = 'These el: edits cannot commit - ' + detail;
    } else {
      el.removeAttribute('title');
    }
    el.textContent = txt;
  }

  // Every instance a patch key governs. el:-keys fan out over their data-el
  // (homogeneous rows share one authored meaning); machine ids fan out over
  // every instance of the id — live apply must match what the serve-time
  // overlay will do, or the design changes personality on reload.
  function targetsForKey(key) {
    if (key.indexOf('el:') === 0) {
      return [...document.querySelectorAll('[data-el="' + key.slice(3) + '"]')];
    }
    return [...document.querySelectorAll('[data-arxa-id="' + key + '"]')];
  }

  function setStyleProp(key, prop, value) {
    const p = patchFor(key);
    p.style[prop] = value || null; // empty clears the property (removal)
    for (const el of targetsForKey(key)) {
      if (value) el.style.setProperty(prop, value);
      else el.style.removeProperty(prop);
    }
    scheduleSave();
  }
  function setTextContent(key, value, origin) {
    const p = patchFor(key);
    const insts = targetsForKey(key);
    if (p.text == null && insts.length) {
      // First text edit captures seed-route provenance: was = this
      // instance's pre-edit text (the commit-time value anchor); nth =
      // its occurrence index, recorded ONLY when instances diverge —
      // data-backed rows get per-instance commits and per-instance live
      // apply, homogeneous repeats keep every-row semantics; page rides
      // for slug correlation.
      const o = origin && insts.indexOf(origin) >= 0 ? origin : insts[0];
      p.was = o.textContent;
      if (origin && insts.some((el) => el.textContent !== insts[0].textContent)) {
        p.nth = Math.max(0, insts.indexOf(origin));
      }
      p.page = location.pathname;
      // Locale targeting (2026-08-24): the commit writes ONLY the locale
      // being edited — <html lang> first, else the leading /xx/ pathname
      // segment. Absent both, the commit updates every locale (old law).
      const hl = (document.documentElement.lang || '').toLowerCase().slice(0, 2);
      if (/^[a-z]{2}$/.test(hl)) p.locale = hl;
      else {
        const seg = location.pathname.split('/')[1] || '';
        if (/^[a-z]{2}$/.test(seg)) p.locale = seg;
      }
    }
    p.text = value;
    const scoped = p.nth != null && insts[p.nth] ? [insts[p.nth]] : insts;
    for (const el of scoped) {
      if (isTextEditable(el)) el.textContent = value;
    }
    scheduleSave();
  }

  function rgbToHex(s) {
    const m = /rgba?\((\d+),\s*(\d+),\s*(\d+)/.exec(s || '');
    if (!m) return null;
    const to = (n) => ('0' + Number(n).toString(16)).slice(-2);
    return '#' + to(m[1]) + to(m[2]) + to(m[3]);
  }
  // The escape hatch parses declarations into STRUCTURED style patches —
  // the grammar underneath stays the only write path.
  function parseCss(text) {
    const out = {};
    text.split(';').forEach((decl) => {
      const i = decl.indexOf(':');
      if (i < 1) return;
      const k = decl.slice(0, i).trim();
      const v = decl.slice(i + 1).trim();
      if (/^[a-zA-Z-]+$/.test(k) && v) out[k] = v;
    });
    return out;
  }

  function draftFooter() {
    pbody.appendChild(h('div', { class: 'draftmeta', id: 'draftmeta' }));
    const kids = [];
    const commit = h('button', { class: 'btn', text: 'Request commit', title: 'Hand the draft to the studio agent — it patches artifact source' });
    commit.addEventListener('click', async () => {
      await saveDraft();
      const r = await api('POST', '/commit', {});
      if (r && r.ok) say('Commit requested — ' + r.ops.length + ' ops handed to the studio agent');
      else say(r && r.error ? r.error : 'Commit request failed');
    });
    kids.push(commit);
    if (S.selected && S.draft.patches[S.selected.key]) {
      const resetEl = h('button', { class: 'btn ghost', text: 'Reset element' });
      resetEl.addEventListener('click', async () => {
        delete S.draft.patches[S.selected.key];
        S.draftDirty = true;
        await saveDraft();
        location.reload(); // re-served without this patch — source state
      });
      kids.push(resetEl);
    }
    const reset = h('button', { class: 'btn ghost', text: 'Reset all' });
    reset.addEventListener('click', async () => {
      await api('DELETE', '/draft');
      S.draft.tokens = {};
      S.draft.patches = {};
      location.reload();
    });
    kids.push(reset);
    pbody.appendChild(h('div', { class: 'btnrow' }, kids));
    renderDraftMeta();
  }

  function renderDesignPanel() {
    const sel = S.selected;
    if (!sel) {
      pbody.appendChild(h('div', { class: 'ctl', style: 'font-size:12px;color:#9aa0ab', text: 'Click any element to edit it here. Double-click text to type in place; drag the amber handles to resize. Esc exits Design Mode.' }));
      draftFooter();
      return;
    }
    pbody.appendChild(h('div', { class: 'sect', text: sel.label }));
    pbody.appendChild(h('div', { class: 'idline', text: sel.key === sel.id ? sel.id : sel.id + ' → ' + sel.key }));
    const draft = S.draft.patches[sel.key] || {};

    // Content facet — text-bearing elements with no stamped descendants
    // (see isTextEditable: runtime splitter wrappers are not authored
    // structure; genuine composites are refused like the grammar's --text).
    if (isTextEditable(sel.el)) {
      pbody.appendChild(h('div', { class: 'sect', text: 'Content' }));
      const ta = h('textarea', { rows: '2' });
      ta.value = draft.text != null ? draft.text : sel.el.textContent;
      ta.addEventListener('input', () => setTextContent(sel.key, ta.value, sel.el));
      pbody.appendChild(h('div', { class: 'facet' }, [ta]));
    }

    pbody.appendChild(h('div', { class: 'sect', text: 'Facets · ' + sel.group }));
    const cs = getComputedStyle(sel.el);
    const facets = FACET_GROUPS[sel.group] || FACET_GROUPS.generic;
    for (const prop of facets) {
      const has = draft.style && Object.prototype.hasOwnProperty.call(draft.style, prop);
      const cur = has ? draft.style[prop] : null;
      const row = h('div', { class: 'facet' }, [h('label', { text: prop })]);
      let input;
      if (SELECT_OPTS[prop]) {
        input = h('select');
        input.appendChild(h('option', { value: '', text: '—' }));
        for (const o of SELECT_OPTS[prop]) input.appendChild(h('option', { value: o, text: o }));
        input.value = cur || '';
      } else {
        input = h('input', { type: 'text', placeholder: cs.getPropertyValue(prop) || 'unset' });
        input.value = cur || '';
      }
      input.addEventListener('input', () => setStyleProp(sel.key, prop, input.value.trim()));
      if (COLOR_PROPS[prop]) {
        const sw = h('input', { type: 'color', title: 'pick ' + prop });
        sw.value = rgbToHex(cur || cs.getPropertyValue(prop)) || '#000000';
        sw.addEventListener('input', () => {
          input.value = sw.value;
          setStyleProp(sel.key, prop, sw.value);
        });
        row.appendChild(sw);
      }
      row.appendChild(input);
      pbody.appendChild(row);
    }

    pbody.appendChild(h('div', { class: 'sect', text: 'CSS escape hatch' }));
    const css = h('textarea', { rows: '3' });
    css.placeholder = 'prop: value; prop: value;';
    if (draft.style) {
      css.value = Object.keys(draft.style)
        .map((k) => k + ': ' + (draft.style[k] == null ? '' : draft.style[k]))
        .join('; ');
    }
    const applyCss = h('button', { class: 'btn', text: 'Apply CSS' });
    applyCss.addEventListener('click', () => {
      const parsed = parseCss(css.value);
      const keys = Object.keys(parsed);
      if (!keys.length) { say('No valid declarations parsed'); return; }
      for (const k of keys) setStyleProp(sel.key, k, parsed[k]);
      say(keys.length + (keys.length === 1 ? ' property' : ' properties') + ' applied');
      renderPanelBody();
    });
    pbody.appendChild(h('div', { class: 'facet' }, [css]));
    pbody.appendChild(h('div', { class: 'btnrow' }, [applyCss]));
    draftFooter();
  }

  // ── the token tier (global design tokens, decision 3) ──────────────────
  function pageTokenNames() {
    const names = [];
    for (const sheet of document.styleSheets) {
      let rules;
      try { rules = sheet.cssRules; } catch (_) { continue; } // cross-origin sheet
      for (const r of rules) {
        if (r.selectorText && (r.selectorText === ':root' || r.selectorText === 'html')) {
          for (const p of r.style) {
            if (p.indexOf('--') === 0 && names.indexOf(p) === -1) names.push(p);
          }
        }
      }
    }
    for (const k of Object.keys(S.draft.tokens)) if (names.indexOf(k) === -1) names.push(k);
    return names.sort();
  }

  let tokenStyleEl = null;
  function applyTokensLive() {
    if (!tokenStyleEl) {
      tokenStyleEl = document.createElement('style');
      tokenStyleEl.id = 'arxa-draft-tokens-live';
      document.head.appendChild(tokenStyleEl); // page-level: shadow styles cannot reach the design
    }
    const decls = Object.keys(S.draft.tokens).map((k) => k + ': ' + S.draft.tokens[k]).join('; ');
    tokenStyleEl.textContent = ':root{' + decls + '}';
  }

  function renderTokensPanel() {
    pbody.appendChild(h('div', { class: 'ctl', style: 'font-size:12px;color:#9aa0ab', text: 'The design tokens this page declares (:root custom properties). Edits override live and auto-save to the Draft Overlay.' }));
    const rootCs = getComputedStyle(document.documentElement);
    const names = pageTokenNames();
    if (!names.length) {
      pbody.appendChild(h('div', { class: 'ctl', style: 'font-size:12px', text: 'No :root custom properties found — add an override below.' }));
    }
    for (const name of names) {
      const row = h('div', { class: 'facet' }, [h('label', { text: name, title: name })]);
      const input = h('input', { type: 'text', placeholder: rootCs.getPropertyValue(name).trim() || 'unset' });
      input.value = S.draft.tokens[name] || '';
      input.addEventListener('input', () => {
        const v = input.value.trim();
        if (v) S.draft.tokens[name] = v;
        else delete S.draft.tokens[name];
        applyTokensLive();
        scheduleSave();
      });
      row.appendChild(input);
      pbody.appendChild(row);
    }
    pbody.appendChild(h('div', { class: 'sect', text: 'New token override' }));
    const nameIn = h('input', { type: 'text', placeholder: '--token-name' });
    const valIn = h('input', { type: 'text', placeholder: 'value' });
    const add = h('button', { class: 'btn', text: 'Add' });
    add.addEventListener('click', () => {
      const n = nameIn.value.trim();
      const v = valIn.value.trim();
      if (!/^--[a-zA-Z0-9-]+$/.test(n) || !v) { say('A token needs a --name and a value'); return; }
      S.draft.tokens[n] = v;
      applyTokensLive();
      scheduleSave();
      renderPanelBody();
    });
    pbody.appendChild(h('div', { class: 'facet' }, [nameIn]));
    pbody.appendChild(h('div', { class: 'facet' }, [valIn]));
    pbody.appendChild(h('div', { class: 'btnrow' }, [add]));
    draftFooter();
  }

  // ── verbs ──────────────────────────────────────────────────────────────
  function onVerb(id, el) {
    if (id === 'pin') {
      if (S.arming) disarm();
      else {
        arm();
        say('Click the design to drop a pin');
      }
      return;
    }
    if (id === 'list') return setPanel('feedback', 'Feedback');
    if (id === 'shade') {
      applyShade();
      return setPanel('shade', 'Review shade');
    }
    if (id === 'layers') return setPanel('layers', 'Layers');
    if (id === 'pen') {
      S.drawing = !S.drawing;
      el.classList.toggle('on', S.drawing);
      drawCanvas.classList.toggle('armed', S.drawing);
      say(S.drawing ? 'Draw-over armed — drag to sketch' : 'Draw-over off');
      return;
    }
    if (id === 'design') {
      if (S.design) designOff();
      else designOn();
      return;
    }
    if (id === 'tokens') return setPanel('tokens', 'Design tokens');
    if (id === 'share') return setPanel('share', 'Share this design');
  }

  // Outside click closes the thread; Escape disarms everything. "Outside"
  // means outside THE DIAL, not outside the thread popover: the thread is a
  // sibling of the panel, so a click on a feedback ROW (which opens the
  // thread) is never inside it, and shadow retargeting hides every dial
  // element behind the host for document-level listeners anyway. Guarding on
  // the composed path's HOST covers both at once (smoke S5a).
  document.addEventListener('click', (e) => {
    if (!S.arming && S.activePin && e.composedPath().indexOf(host) === -1) {
      closeThread();
    }
  });
  document.addEventListener('keydown', (e) => {
    // On-canvas text editing owns Enter (commit — a newline would inject
    // markup the --text grammar refuses) and Escape (revert, keep editing
    // mode armed).
    if (S.inlineEditing != null) {
      if (e.key === 'Enter') {
        e.preventDefault();
        inlineEditEnd(true);
      } else if (e.key === 'Escape') {
        e.preventDefault();
        inlineEditEnd(false);
      }
      return;
    }
    if (e.key === 'Escape') {
      if (S.arming) disarm();
      if (S.design) designOff();
      if (S.drawing) onVerb('pen', verbEls.pen); // Escape must disarm the pen too — an armed canvas swallows every page click (smoke S8b)
      closeThread();
      composer.classList.remove('open');
      S.panel = null;
      panel.classList.remove('open');
    }
  });

  // ── realtime: the server's own writes arrive over SSE ─────────────────
  // Subscribe only after a pins read SUCCEEDED. Inside a sandboxed frame
  // (opaque origin — a gen_ui RungLadder pointing at this server) every
  // guarded /__dial/* call is refused by design, and a bare EventSource
  // would retry the 403 forever: a refusal storm per frame, forever. No
  // pins answer → this frame cannot use the dial API at all → stay quiet.
  function subscribeEvents() {
    try {
      const es = new EventSource(apiUrl('/events'));
    // A RECONNECT is the certain sign frames were missed (socket-pool
    // starvation, a server restart, laptop sleep) — resync instead of
    // trusting the stream. The first open is boot truth: loadDraft already
    // read it, and the signature check makes a no-divergence resync a
    // no-op, so a flapping connection never reload-loops.
    let esOpened = false;
    es.addEventListener('open', () => {
      if (esOpened) syncRemoteDraft();
      esOpened = true;
    });
    es.addEventListener('dial', (ev) => {
      let d = null;
      try { d = JSON.parse(ev.data); } catch (_) {}
      if (!d || d.kind === 'pins') return loadPins();
      // Another author context saved its draft — sync it INTO this
      // document, unless the frame was this document's own save.
      if (d.kind === 'draft' && Date.now() - S.ownSave > 1500) syncRemoteDraft();
      // 'commit' frames feed the studio agent — the requester already
      // heard its toast, there is nothing for this page to do.
    });
    } catch (_) {}
  }

  // ── boot ───────────────────────────────────────────────────────────────
  // CAPABILITY-GATED BOOT. Sandboxed mirror frames must stay out of the
  // DOM, but origin-string heuristics cannot detect them: Brave reports a
  // REAL location.origin inside frames whose network requests are still
  // refused as null-origin (measured 2026-08-24; Chromium says 'null',
  // Brave doesn't). So ask the API instead: an author page proves itself
  // with the draft read (file-backed — no pins store needed), a guest with
  // the pins read. Any context where the proof cannot come back —
  // sandboxed mirror, hard refusal, server down — stays a silent
  // view-only mirror; the server answers those reads with a quiet
  // CORS-clean 200 so not even a console line escapes.
  function mirrorNote() {
    try {
      console.info('[arxa dial] unavailable in this context — view-only mirror');
    } catch (_) {}
  }
  // A boot can collide with a design-server restart or a stalled renderer,
  // and one failed probe used to mute the rung FOREVER while the server sat
  // perfectly healthy ("unavailable although available"). Retry with
  // backoff across ~25s before concluding mirror; the server answers
  // refused reads instantly, so genuine mirrors just burn a few quiet GETs.
  const CAP_RETRY_WAITS = [250, 500, 1000, 2000, 4000, 8000, 8000];
  function probeCapable(sub) {
    let step = -1;
    const attempt = () => {
      step++;
      return api('GET', sub).then((r) => {
        if ((r != null && r.mirror !== true) || step >= CAP_RETRY_WAITS.length) return r;
        return new Promise((res) => setTimeout(res, CAP_RETRY_WAITS[step]))
            .then(attempt);
      });
    };
    return attempt();
  }
  function finishBoot() {
    document.documentElement.appendChild(host); // off-body: hx-boost swaps wipe body children
    applyShade();
    applyLayers();
    resumeAfterReload(); // no-op unless the last text edit converged by reload
  }
  if (S.mode === 'invalid') {
    document.documentElement.appendChild(host); // off-body: hx-boost swaps wipe body children
    applyShade();
    applyLayers();
    say('This share link is expired or invalid');
    return;
  }
  if (S.mode === 'guest') {
    probeCapable('/pins').then((r) => {
      if (!(r && r.pins)) { mirrorNote(); return; }
      S.pins = r.pins;
      finishBoot();
      renderPins();
      updateBadge();
      subscribeEvents();
    });
    return;
  }
  loadDraft().then((ok) => {
    if (!ok) { mirrorNote(); return; }
    finishBoot();
    api('GET', '/pins').then((r) => {
      if (r && r.pins) { S.pins = r.pins; renderPins(); updateBadge(); }
      subscribeEvents();
    });
  });
})();
