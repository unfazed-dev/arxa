/* inspect.js — the element-inspect island (ADR-0002 amendment, 2026-07).
   The third named first-party script (sibling to canvas.js and drag.js).
   Included in stub screen renders only when the inspect server param is on
   (a conditional <script> in screen_stub_view.html). Runs inside the
   same-origin iframe document — the stub is same-origin, so it may read the
   DOM and reach window.parent.

   While armed (data-inspect-armed on <body>): hover outlines any [data-el]
   element with an accent-tinted overlay carrying the element's NAME, and
   POSTs what it measured to the parent's inspector endpoint so the inspector
   pane (activity panel, 4th view) shows the element's full story. Click LOCKS
   the pane to that element (navigation suppressed) so it survives further
   hovers. Stays armed for multi-pick until disarmed.

   The overlay badge is the name and nothing else. The metadata this island
   reads off the element's data-attributes (data-inspect-role / -style /
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

   Clicking no longer pins: pin is an explicit button on the pane. Multi-pick
   is unchanged — lock one, pin it, lock the next, pin it.

   The overlay tint follows the document's data-accent: app.css maps
   [data-accent] on #app to the --accent custom property, so the island reads
   the computed value off that host element (documentElement carries no
   --accent — reading it there would silently fall back).

   Arming: the parent page sets document.body.dataset.inspectArmed = 'true'
   (or removes it). Momentary: hold Alt to temporarily arm, release to disarm.

   Island shape (per ADR-0002): no globals, no framework, no build step, talks
   to nothing outside its contract. Same IIFE shape as canvas.js. */
(() => {
  if (document._inspect) return; // guard against double-include
  document._inspect = 1;

  const ACCENT_FALLBACK = '#0891b2'; // cyan-600 — the design shell accent
  const armed = () => document.body.dataset.inspectArmed === 'true';
  const accent = () => {
    const host = document.querySelector('[data-accent]');
    const v = host && getComputedStyle(host).getPropertyValue('--accent').trim();
    return v || ACCENT_FALLBACK;
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

  // The badge: the element's name, nothing else. The role/style/motion/fn
  // rows moved to the inspector pane, where there is room for them and for
  // the server-side joins that give them meaning.
  const fillReadout = (el) => {
    labelEl.replaceChildren();
    const name = document.createElement('div');
    name.style.cssText = 'font-weight:600;';
    name.textContent = el.dataset.el;
    labelEl.appendChild(name);
  };

  // What the pane renders. Only what the element actually declares is sent —
  // the SERVER owns the inferred/authored distinction, so a value this island
  // guessed would be indistinguishable from an authored one.
  const measure = (el, lock) => {
    const v = {
      screen: document.body.dataset.surface || '',
      name: el.dataset.el,
      kind: el.tagName.toLowerCase(),
    };
    if (el.dataset.inspectRole) v.role = el.dataset.inspectRole;
    if (el.dataset.inspectStyle) v.style = el.dataset.inspectStyle;
    if (el.dataset.inspectMotion) v.motion = el.dataset.inspectMotion;
    if (el.dataset.inspectFn) v.fn = el.dataset.inspectFn;
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
    });
  };

  const showOverlay = (el) => {
    ensureOverlay();
    const r = el.getBoundingClientRect();
    const a = accent();
    outlineEl.style.cssText =
      'display:block;position:fixed;' +
      `left:${r.left}px;top:${r.top}px;width:${r.width}px;height:${r.height}px;` +
      'pointer-events:none;z-index:99998;' +
      `box-shadow:inset 0 0 0 2px ${a};background:${a}1a;border-radius:4px;`;
    labelEl.style.cssText =
      'display:block;position:fixed;pointer-events:none;z-index:99999;' +
      `left:${r.left}px;top:${Math.max(0, r.top - 24)}px;` +
      `background:${a};color:#fff;font-size:11px;line-height:18px;` +
      'padding:2px 8px;border-radius:4px 4px 4px 0;white-space:nowrap;';
    fillReadout(el);
    // multi-line readouts grow downward from the element's top edge
    labelEl.style.top = Math.max(0, r.top - labelEl.offsetHeight - 6) + 'px';
  };

  // hover tracking — only acts while armed
  document.addEventListener('pointermove', (e) => {
    if (!armed()) { clearHover(); return; }
    const el = e.target.closest('[data-el]');
    if (el !== lastHovered) {
      lastHovered = el;
      // One request per element CHANGE, not per pointer move — the identity
      // check above is the whole throttle. Hovering while the pane is locked
      // is a no-op server-side, so it costs a request and swaps nothing.
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
    const el = e.target.closest('[data-el]');
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
