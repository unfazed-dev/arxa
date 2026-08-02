/* inspect.js — the element-inspect island (ADR-0002 amendment, 2026-07).
   The third named first-party script (sibling to canvas.js and drag.js).
   Included in stub screen renders only when the inspect server param is on
   (a conditional <script> in screen_stub_view.html). Runs inside the
   same-origin iframe document — the stub is same-origin, so it may read the
   DOM and reach window.parent.

   While armed (data-inspect-armed on <body>): hover outlines any [data-el]
   element with an accent-tinted overlay + a readout card; click pins it to
   the parent's chat context (navigation suppressed) via a POST to the
   parent's element-context endpoint, then triggers a parent htmx re-swap of
   #panels so the chat tray picks up the new element chip. Stays armed for
   multi-pick until disarmed.

   The readout card is the element's own story (see DESIGN-ARCHITECTURE.md
   "Inspect metadata"), read off its data-attributes: data-el (name), plus
   data-inspect-role / -style / -motion / -fn — what it is, its key styles,
   its motion (Motion Vocabulary closed set, or none), its function. Only the
   lines the element carries are shown; the role falls back to the data-el
   prefix.

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

  // The readout card: name + the inspect metadata lines the element carries
  // (role / style / motion / fn — role falls back to the data-el prefix).
  const fillReadout = (el) => {
    labelEl.replaceChildren();
    const name = document.createElement('div');
    name.style.cssText = 'font-weight:600;';
    name.textContent = el.dataset.el;
    labelEl.appendChild(name);
    const role = el.dataset.inspectRole || (el.dataset.el || '').split(':')[0];
    const rows = [
      ['role', role],
      ['style', el.dataset.inspectStyle],
      ['motion', el.dataset.inspectMotion],
      ['fn', el.dataset.inspectFn],
    ];
    for (const [k, v] of rows) {
      if (!v) continue;
      const line = document.createElement('div');
      line.style.cssText = 'font-weight:400;opacity:.92;';
      line.textContent = `${k}: ${v}`;
      labelEl.appendChild(line);
    }
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
      if (el) showOverlay(el); else hideOverlay();
    }
  });

  // click to pin — capture phase so we run before any navigation handler
  document.addEventListener('click', (e) => {
    if (!armed()) return;
    const el = e.target.closest('[data-el]');
    if (!el) return;
    e.preventDefault();
    e.stopPropagation();
    const name = el.dataset.el;
    const screen = document.body.dataset.surface || '';
    const kind = el.tagName.toLowerCase();
    fetch('/design/chat/context/element', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: `screen=${encodeURIComponent(screen)}` +
            `&name=${encodeURIComponent(name)}` +
            `&kind=${encodeURIComponent(kind)}`,
    }).then(() => {
      // re-swap the parent stage so the chat tray picks up the element chip.
      // htmx lives on the parent (the stub document need not load it). The
      // pin is session state, so re-GETting the parent's own URL re-renders
      // it; select: extracts #panels out of the full-page response.
      // morph:outerHTML, not outerHTML — a replace-style swap here rebuilds
      // every screen iframe INCLUDING the one being inspected, so pinning an
      // element reloaded the screen out from under the user mid-inspection.
      // Programmatic htmx.ajax() takes its swap style from this option, not
      // from the hx-swap attributes in the templates, so it has to be named
      // here too.
      const p = window.parent;
      if (p && p.htmx) {
        p.htmx.ajax('GET', p.location.pathname + p.location.search,
          { target: '#panels', swap: 'morph:outerHTML', select: '#panels' });
      }
    });
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
