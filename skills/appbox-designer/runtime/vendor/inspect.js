/* inspect.js — the element-inspect island (ADR-0002 amendment, 2026-07).
   The third named first-party script (sibling to canvas.js and drag.js).
   Included in stub screen renders only when the inspect server param is on
   (a conditional <script> in screen_stub_view.html). Runs inside the
   same-origin iframe document — the stub is same-origin, so it may read the
   DOM and reach window.parent.

   While armed (data-inspect-armed on <body>): hover outlines the nearest
   authored widget ([data-el]) with an accent-tinted overlay carrying the
   widget's NAME, and POSTs what it measured to the parent's inspector
   endpoint so the inspector pane (activity panel, 4th view) shows the
   widget's full story. Click LOCKS the pane to that widget (navigation
   suppressed) so it survives further hovers. Stays armed for multi-pick
   until disarmed.

   The overlay badge is the name and nothing else. The metadata this island
   reads off the widget's data-attributes (data-inspect-role / -style /
   -motion / -fn — see DESIGN-ARCHITECTURE.md "Inspect metadata") is no longer
   drawn on the screen: it travels in the POST and is RENDERED BY THE SERVER
   in the pane, joined there with registry states, kits and flow edges the
   client cannot see. The server cannot derive the client half either —
   data-el="hero:{{ t(…) }}" is unresolved and per-locale server-side — so the
   client measures and the server renders. That split is why the pane needs no
   second ADR-0002 amendment: this island still only POSTs and asks the parent
   to swap, exactly as before.

   The name in the badge is `el.dataset.el`, the same string the composer's
   context chip renders (composer.html, .cs-el-name) — what you see on the
   screen is what gets pinned.

   Hover targets ONLY authored widgets ([data-el]). SVG internals collapse to
   their owning <svg> before resolution, so hovering a <path> inside an icon
   badges the widget that owns the icon, never the path. Unannotated regions
   fall through to a screen-level sentinel (document.body) that outlines the
   full surface and badges it with the body's data-surface name — the single
   surviving inferred case.

   The badge follows the studio accent: reads --accent and --on-accent off the
   parent document's #app element (same-origin), falling back to the local
   [data-accent] host, then to literals. Text uses --on-accent so it stays
   legible on any swatch; the font is pinned so it never inherits the designed
   app's typeface.

   Arming: the parent page sets document.body.dataset.inspectArmed = 'true'
   (or removes it). Momentary: hold Alt to temporarily arm, release to disarm.

   Island shape (per ADR-0002): no globals, no framework, no build step, talks
   to nothing outside its contract. Same IIFE shape as canvas.js. */
(() => {
  if (document._inspect) return; // guard against double-include
  document._inspect = 1;

  const ACCENT_FALLBACK = '#0891b2'; // cyan-600 — the design shell accent
  const ON_ACCENT_FALLBACK = '#FFFCF0';
  const armed = () => document.body.dataset.inspectArmed === 'true';

  // Resolve accent + onAccent from the studio chrome. Order: (1) parent
  // document's #app computed --accent/--on-accent (same-origin; the island
  // already reaches window.parent.htmx — try/catch for detached frames),
  // (2) local [data-accent] host, (3) literals.
  const accents = () => {
    try {
      const pApp = window.parent.document.querySelector('#app');
      if (pApp) {
        const cs = getComputedStyle(pApp);
        const a = cs.getPropertyValue('--accent').trim();
        const oa = cs.getPropertyValue('--on-accent').trim();
        if (a) return { accent: a, onAccent: oa || ON_ACCENT_FALLBACK };
      }
    } catch (_) { /* cross-origin or detached frame */ }
    const host = document.querySelector('[data-accent]');
    if (host) {
      const cs = getComputedStyle(host);
      const a = cs.getPropertyValue('--accent').trim();
      const oa = cs.getPropertyValue('--on-accent').trim();
      if (a) return { accent: a, onAccent: oa || ON_ACCENT_FALLBACK };
    }
    return { accent: ACCENT_FALLBACK, onAccent: ON_ACCENT_FALLBACK };
  };

  // Infer identity for an inspect target. Authored widgets carry data-el;
  // the body sentinel (screen fallback) is the single inferred case.
  const synthesize = (el) => {
    if (el === document.body) {
      return {
        name: document.body.dataset.surface || 'screen',
        role: 'unannotated region',
        inferred: '1',
      };
    }
    return {
      name: el.dataset.el || el.tagName.toLowerCase(),
      role: el.dataset.inspectRole || 'group',
      inferred: el.dataset.el ? '' : '1',
    };
  };

  // Resolve the innermost inspectable target from a pointer event target.
  // SVG internals collapse to the owning <svg>, then the nearest [data-el]
  // ancestor is the widget. No widget → document.body sentinel (screen
  // fallback). Overlay nodes (inspect-*) carry no data-el and are never the
  // pointer target anyway (pointer-events:none).
  const inspectTarget = (raw) => {
    const el = raw.ownerSVGElement ? raw.ownerSVGElement : raw;
    return el.closest('[data-el]') || document.body;
  };

  // Build the ancestor chain outermost→innermost, [data-el] widgets only.
  const buildChain = (el) => {
    const chain = [];
    let cur = el;
    while (cur && cur !== document.body) {
      if (cur.dataset && cur.dataset.el) {
        const info = synthesize(cur);
        chain.push({ el: info.name, role: info.role });
      }
      cur = cur.parentElement;
    }
    chain.reverse(); // outermost→innermost
    return chain;
  };

  let outlineEl = null;
  let labelEl = null;
  let lastHovered = null;
  let momentary = false; // true only while Alt is the thing that armed us

  const ensureOverlay = () => {
    // isConnected, not a plain truthiness check: under boosted navigation htmx
    // replaces the body's children, which detaches these nodes while our
    // references stay live. A `if (outlineEl) return;` would then keep handing
    // back an orphan that renders nowhere, and inspect would silently stop
    // drawing after the first in-frame navigation.
    if (outlineEl && outlineEl.isConnected && labelEl && labelEl.isConnected) return;
    outlineEl = document.createElement('div');
    outlineEl.className = 'inspect-outline';
    labelEl = document.createElement('div');
    labelEl.className = 'inspect-label';
    document.body.appendChild(outlineEl);
    document.body.appendChild(labelEl);
  };

  const hideOverlay = () => {
    if (outlineEl) outlineEl.style.display = 'none';
    if (labelEl) labelEl.style.display = 'none';
  };

  // overlay off + hover cache cleared — used by every disarm path so a later
  // re-arm reliably re-shows the badge without needing a pointer move
  const clearHover = () => {
    hideOverlay();
    lastHovered = null;
  };

  // The badge: the widget's name (or surface name for the screen fallback).
  // Inferred (screen fallback) dims the name line; the role travels in the
  // POST and is rendered by the server in the pane.
  const fillReadout = (el) => {
    const info = synthesize(el);
    labelEl.replaceChildren();
    const name = document.createElement('div');
    name.style.cssText = 'font-weight:600;color:inherit;' + (info.inferred ? ' opacity:.7;' : '');
    name.textContent = info.name;
    labelEl.appendChild(name);
    const sub = document.createElement('div');
    sub.style.cssText = 'font-size:10px;opacity:.75;color:inherit;';
    sub.textContent = info.role;
    labelEl.appendChild(sub);
  };

  // What the pane renders. Identified widgets send their authored name; the
  // screen-fallback sentinel sends the surface name + inferred flag. The
  // SERVER owns the final authored/inferred distinction in its joins.
  const measure = (el, lock) => {
    const info = synthesize(el);
    const v = {
      screen: document.body.dataset.surface || '',
      name: info.name,
      kind: el.tagName.toLowerCase(),
    };
    if (info.role) v.role = info.role;
    if (el.dataset.inspectStyle) v.style = el.dataset.inspectStyle;
    if (el.dataset.inspectMotion) v.motion = el.dataset.inspectMotion;
    if (el.dataset.inspectFn) v.fn = el.dataset.inspectFn;
    if (info.inferred) v.inferred = '1';
    v.chain = JSON.stringify(buildChain(el));
    if (lock) v.lock = '1';
    return v;
  };

  // Feed the pane. Targets the ACTIVITY PANEL'S BODY SECTION, never #panels:
  // re-swapping the stage rebuilds every screen iframe including the one under
  // the pointer (the bug the click handler's comment records), and a hover
  // doing that would hit it on every element. The route answers 204 when the
  // inspector is not the active view, so this can fire freely.
  //
  // This id is a SERVER CONTRACT and it is silent when it breaks: htmx.ajax
  // resolves the target before it sends, so a stale selector here makes the
  // request never happen — no console error, no failed fetch, just an
  // inspector that quietly stops updating. It was `#panel-left-body` until the
  // panels were renamed by role; if you rename a panel again, this line is one
  // of the two places outside the templates that must move with it (drag.js's
  // data-target is the other).
  const feedPane = (el, lock) => {
    const p = window.parent;
    if (!p || !p.htmx) return;
    p.htmx.ajax('POST', '/design/inspector/select', {
      target: '#panel-activity-body', swap: 'innerHTML', values: measure(el, lock),
      // hx-sync="this:replace" on <body> aborts superseded XHRs; htmx rejects
      // the promise with undefined on abort. Real failures still log.
    }).catch((e) => { if (e !== undefined) console.error('appbox island htmx.ajax:', e); });
  };

  const showOverlay = (el) => {
    ensureOverlay();
    const r = el.getBoundingClientRect();
    const a = accents();
    outlineEl.style.cssText =
      'display:block;position:fixed;' +
      `left:${r.left}px;top:${r.top}px;width:${r.width}px;height:${r.height}px;` +
      'pointer-events:none;z-index:99998;' +
      `box-shadow:inset 0 0 0 2px ${a.accent};background:${a.accent}1a;border-radius:4px;`;
    labelEl.style.cssText =
      'display:block;position:fixed;pointer-events:none;z-index:99999;' +
      `left:${r.left}px;top:${Math.max(0, r.top - 28)}px;` +
      `background:${a.accent};color:${a.onAccent};` +
      'font-size:11px;line-height:1.4;padding:4px 10px;' +
      'border-radius:6px 6px 6px 0;white-space:nowrap;' +
      'box-shadow:0 2px 8px rgba(0,0,0,.25);' +
      "font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;";
    fillReadout(el);
    // multi-line readouts grow downward from the element's top edge
    labelEl.style.top = Math.max(0, r.top - labelEl.offsetHeight - 6) + 'px';
  };

  // hover tracking — only acts while armed. Resolves to the nearest [data-el]
  // widget (or screen fallback). One request per element CHANGE, not per
  // pointer move — the identity check is the whole throttle. Hovering while
  // the pane is locked is a no-op server-side, so it costs a request and
  // swaps nothing.
  document.addEventListener('pointermove', (e) => {
    if (!armed()) { clearHover(); return; }
    const el = inspectTarget(e.target);
    if (el !== lastHovered) {
      lastHovered = el;
      if (el) { showOverlay(el); feedPane(el, false); } else hideOverlay();
    }
  });

  // click to LOCK — capture phase so we run before any navigation handler.
  // Clicking used to pin to chat context; pinning is now an explicit button on
  // the pane, so a click here only says "hold this one". The lock is stored in
  // the SESSION by the route, never in this document or the parent's DOM,
  // which is what lets it survive the htmx morphs that rebuild the panel.
  document.addEventListener('click', (e) => {
    if (!armed()) return;
    const el = inspectTarget(e.target);
    if (!el) return;
    e.preventDefault();
    e.stopPropagation();
    feedPane(el, true);
  }, true);

  // momentary mode: hold Alt to arm, release to disarm. Only engages when the
  // parent hasn't already armed us, so releasing Alt never disarms a
  // parent-armed session.
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Alt' && !momentary && !armed()) {
      momentary = true;
      document.body.dataset.inspectArmed = 'true';
    }
  });
  document.addEventListener('keyup', (e) => {
    if (e.key === 'Alt' && momentary) {
      momentary = false;
      delete document.body.dataset.inspectArmed;
      clearHover();
    }
  });

  // the instant the parent disarms us, drop the overlay
  const watchArmed = () =>
    new MutationObserver(() => { if (!armed()) clearHover(); })
      .observe(document.body, { attributes: true, attributeFilter: ['data-inspect-armed'] });
  if (document.body) watchArmed();
  else document.addEventListener('DOMContentLoaded', watchArmed, { once: true });
})();
