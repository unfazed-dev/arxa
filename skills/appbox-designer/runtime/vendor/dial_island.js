/* dial_island.js — the Design Dial island (first-party, ADR-0002 form;
   locked amendment 2026-08-23: 'the feedback dial becomes the Design Dial').

   WHY THIS EXISTS. Every appbox artifact carries one floating control so the
   Author can adjust the design live and clients can leave feedback on the
   shared design — one control, two modes. This file is the Feedback Mode
   slice: Pins anchored to W7 data-el identity (rect-snapshot fallback,
   Orphaned Pins survive removal), the kanban lifecycle (open / triaged /
   in_progress / resolved / wont_do) with threaded replies, the Review Shade
   with its opacity slider, per-layer toggles (pins / comments / drawings),
   Share Link minting (Author only), and the freehand draw-over.

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
   threshold) and edge-snaps left/right; verbs fan out in an arc. Design Mode
   verbs are stubbed off in this slice — the dock is the same dock Design
   Mode will expand. */
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
    shade: 0.3, // review shade opacity 0..0.6
    layers: { pins: true, comments: true, drawings: true },
    activePin: null, // id whose thread popover is open
    name: '',
    strokes: [], // draw-over strokes (ephemeral — see header)
    dockSide: 'right',
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
    const res = await fetch(apiUrl(sub), {
      method,
      headers: body ? { 'Content-Type': 'application/json' } : undefined,
      body: body ? JSON.stringify(body) : undefined,
    });
    return res.json();
  }
  async function loadPins() {
    const r = await api('GET', '/pins');
    if (r && r.pins) {
      S.pins = r.pins;
      renderPins();
      if (S.panel === 'feedback') renderPanelBody();
      updateBadge();
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
    // The fan lives ENTIRELY in the inward upper quadrant: right-docked
    // spans -178°..-93°, left-docked mirrors it — no verb ever lands
    // right of a right-docked dial (screen-edge clip) or left of a
    // left-docked one. Arc spacing = R·Δθ = 150·0.297 ≈ 44.5px ≥ the 44px
    // buttons, so neighbors never overlap.
    const spacing = 17;
    const start = S.dockSide === 'right' ? -178 : -2 - (n - 1) * spacing;
    const R = 150;
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
    renderPanelBody();
  }

  function renderPanelBody() {
    pbody.textContent = '';
    if (S.panel === 'feedback') return renderFeedbackList();
    if (S.panel === 'shade') return renderShadeCtl();
    if (S.panel === 'layers') return renderLayersCtl();
    if (S.panel === 'share') return renderShareCtl();
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
    panel.style.display = S.layers.comments ? '' : 'none';
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
      const r = await api('POST', '/pins', {
        route: location.pathname,
        viewport: { w: innerWidth, h: innerHeight },
        anchor: { el: target.el, rect: target.rect },
        body,
        name: S.name || undefined,
      });
      composer.classList.remove('open');
      if (r && r.pin) {
        say('Pin added');
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
    ctx.strokeStyle = '#f59e0b';
    S.strokes.forEach((stroke) => {
      ctx.beginPath();
      stroke.forEach((pt, i) => {
        const x = (pt[0] - scrollX) * devicePixelRatio;
        const y = (pt[1] - scrollY) * devicePixelRatio;
        if (i === 0) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
      });
      ctx.stroke();
    });
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
    if (id === 'share') return setPanel('share', 'Share this design');
  }

  // Outside click closes thread/composer; Escape disarms everything.
  document.addEventListener('click', (e) => {
    if (!S.arming && S.activePin && !thread.contains(e.target)) closeThread();
  });
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
      if (S.arming) disarm();
      closeThread();
      composer.classList.remove('open');
      S.panel = null;
      panel.classList.remove('open');
    }
  });

  // ── realtime: the server's own writes arrive over SSE ─────────────────
  try {
    const es = new EventSource(apiUrl('/events'));
    es.addEventListener('dial', () => loadPins());
  } catch (_) {}

  // ── boot ───────────────────────────────────────────────────────────────
  if (S.mode === 'invalid') {
    say('This share link is expired or invalid');
  }
  document.body.appendChild(host);
  applyShade();
  applyLayers();
  loadPins();
})();
