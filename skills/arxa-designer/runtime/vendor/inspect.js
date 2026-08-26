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

   Hover targets ONLY authored widgets ([data-el]). Resolution uses
   elementsFromPoint to walk the full paint-order stack, so even a widget
   occluded by a transparent overlapping sibling is reachable. SVG internals
   collapse to their owning <svg> before resolution, so hovering a <path>
   inside an icon badges the widget that owns the icon, never the path.
   Unannotated regions fall through to a screen-level sentinel (document.body)
   that outlines the full surface and badges it with the body's data-surface
   name — the single surviving inferred case.

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

  // Resolve the innermost inspectable widget at viewport coordinates (x, y)
  // via an elementsFromPoint stack-walk. Each hit in the stack collapses SVG
  // internals to the owning <svg>, then finds the nearest [data-el]. Overlay
  // nodes (tagged data-inspect-overlay) are skipped. When the stack is empty
  // or has no widget (every element is unannotated), falls back to the event
  // target's own closest [data-el], then to the document.body sentinel.
  //
  // Replaces the old inspectTarget(e.target): that only read the topmost
  // element, so a widget occluded by an overlapping sibling was unreachable.
  // elementsFromPoint returns the full paint-order stack, so the walker finds
  // the widget even when something transparent sits on top of it.
  const resolveAt = (x, y, fallbackTarget) => {
    const stack = document.elementsFromPoint(x, y);
    for (const raw of stack) {
      if (raw.closest('[data-inspect-overlay]')) continue;
      const el = raw.ownerSVGElement ? raw.ownerSVGElement : raw;
      const hit = el.closest('[data-el]');
      if (hit) return hit;
    }
    const el = fallbackTarget && (fallbackTarget.ownerSVGElement || fallbackTarget);
    return (el && el.closest('[data-el]')) || document.body;
  };

  // Compute the instance path of [el] among same-name siblings in its widget
  // tree. For each level in the ancestor chain (outermost→innermost):
  //   scope = nearest [data-el] ancestor (or document for top-level)
  //   siblings = same-name [data-el] elements whose nearest widget ancestor IS scope
  //   k = 0-based index of this element among those siblings
  // Returns { instance: "0/1/2", instanceCount: n } where n is the leaf's sibling count.
  const instanceOf = (el) => {
    if (!el.dataset || !el.dataset.el) return { instance: '', instanceCount: 1 };
    const chain = [];
    let cur = el;
    while (cur && cur !== document.body && cur.parentElement) {
      if (cur.dataset && cur.dataset.el) chain.unshift(cur);
      cur = cur.parentElement;
    }
    if (chain.length === 0) return { instance: '', instanceCount: 1 };
    const parts = [];
    var leafCount = 1;
    for (const node of chain) {
      const name = node.dataset.el;
      let scope = node.parentElement;
      while (scope && scope !== document.body && !(scope.dataset && scope.dataset.el)) {
        scope = scope.parentElement;
      }
      const scopeEl = scope || document;
      const all = scopeEl.querySelectorAll('[data-el="' + name + '"]');
      const siblings = [];
      for (const c of all) {
        var a = c.parentElement;
        while (a && !(a.dataset && a.dataset.el)) a = a.parentElement;
        if (a === scope) siblings.push(c);
      }
      parts.push(String(siblings.indexOf(node)));
      if (node === el) leafCount = siblings.length;
    }
    return { instance: parts.join('/'), instanceCount: leafCount };
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

  let overlayContainer = null; // position:fixed at viewport 0,0 — holds rect divs
  let labelEl = null;
  let rectPool = [];           // reusable highlight rect divs (one per line fragment)
  let lastHovered = null;
  let momentary = false; // true only while Alt is the thing that armed us

  const ensureOverlay = () => {
    // isConnected, not a plain truthiness check: under boosted navigation htmx
    // replaces the body's children, which detaches these nodes while our
    // references stay live. A `if (overlayContainer) return;` would then keep
    // handing back an orphan that renders nowhere, and inspect would silently
    // stop drawing after the first in-frame navigation.
    if (overlayContainer && overlayContainer.isConnected && labelEl && labelEl.isConnected) return;
    overlayContainer = document.createElement('div');
    overlayContainer.setAttribute('data-inspect-overlay', '');
    overlayContainer.style.cssText =
      'position:fixed;left:0;top:0;pointer-events:none;z-index:99998;';
    labelEl = document.createElement('div');
    labelEl.className = 'inspect-label';
    labelEl.setAttribute('data-inspect-overlay', '');
    document.body.appendChild(overlayContainer);
    document.body.appendChild(labelEl);
    rectPool = [];
  };

  const hideOverlay = () => {
    if (overlayContainer) overlayContainer.style.display = 'none';
    if (labelEl) labelEl.style.display = 'none';
  };

  // overlay off + hover cache cleared — used by every disarm path so a later
  // re-arm reliably re-shows the badge without needing a pointer move
  const clearHover = () => {
    hideOverlay();
    lastHovered = null;
  };

  // The badge: the widget's name (or surface name for the screen fallback),
  // with a · k/n suffix when multiple same-name instances exist.
  // Inferred (screen fallback) dims the name line; the role travels in the
  // POST and is rendered by the server in the pane.
  const fillReadout = (el) => {
    const info = synthesize(el);
    const inst = instanceOf(el);
    labelEl.replaceChildren();
    const name = document.createElement('div');
    name.style.cssText = 'font-weight:600;color:inherit;' + (info.inferred ? ' opacity:.7;' : '');
    const leafK = inst.instance ? Number(inst.instance.split('/').pop()) : 0;
    name.textContent = inst.instanceCount > 1
      ? info.name + ' · ' + (leafK + 1) + '/' + inst.instanceCount
      : info.name;
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
    const inst = instanceOf(el);
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
    if (inst.instance) v.instance = inst.instance;
    if (inst.instanceCount > 1) v.instanceCount = String(inst.instanceCount);
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
    }).catch((e) => { if (e !== undefined) console.error('arxa island htmx.ajax:', e); });
  };

  const showOverlay = (el) => {
    ensureOverlay();
    const a = accents();

    // Batch-read all rects before writing anything (avoids layout thrashing).
    // getClientRects returns one rect per line fragment for wrapped inline
    // content; block elements yield exactly one rect — visual parity with the
    // old single-rect overlay.
    var rects = Array.from(el.getClientRects());
    // Empty inline / display:contents → fall back to the nearest block
    // container's rect, but keep the leaf's name/identity in the badge and POST.
    if (rects.length === 0) {
      var block = el.parentElement;
      while (block && getComputedStyle(block).display === 'inline') block = block.parentElement;
      if (block) rects = Array.from(block.getClientRects());
      if (rects.length === 0) rects = [el.getBoundingClientRect()];
    }

    // Grow the reusable pool as needed (pool survives htmx morphs via the
    // isConnected guard in ensureOverlay).
    while (rectPool.length < rects.length) {
      var d = document.createElement('div');
      overlayContainer.appendChild(d);
      rectPool.push(d);
    }

    // Position each rect in a single write pass.
    overlayContainer.style.display = 'block';
    var rectCss = 'display:block;position:absolute;' +
      'pointer-events:none;' +
      'box-shadow:inset 0 0 0 2px ' + a.accent + ';' +
      'background:' + a.accent + '1a;border-radius:4px;';
    for (var i = 0; i < rects.length; i++) {
      var r = rects[i];
      rectPool[i].style.cssText = rectCss +
        'left:' + r.left + 'px;top:' + r.top + 'px;' +
        'width:' + r.width + 'px;height:' + r.height + 'px;';
    }
    // Hide surplus pool divs from a previous hover.
    for (var j = rects.length; j < rectPool.length; j++) {
      rectPool[j].style.display = 'none';
    }

    // Badge follows the first (topmost) rect.
    var firstRect = rects[0];
    labelEl.style.cssText =
      'display:block;position:fixed;pointer-events:none;z-index:99999;' +
      'left:' + firstRect.left + 'px;top:' + Math.max(0, firstRect.top - 28) + 'px;' +
      'background:' + a.accent + ';color:' + a.onAccent + ';' +
      'font-size:11px;line-height:1.4;padding:4px 10px;' +
      'border-radius:6px 6px 6px 0;white-space:nowrap;' +
      'box-shadow:0 2px 8px rgba(0,0,0,.25);' +
      "font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;";
    fillReadout(el);
    // multi-line readouts grow downward from the element's top edge
    labelEl.style.top = Math.max(0, firstRect.top - labelEl.offsetHeight - 6) + 'px';
  };

  // hover tracking — only acts while armed. Resolves to the nearest [data-el]
  // widget (or screen fallback) via elementsFromPoint stack-walk. One request
  // per element CHANGE, not per pointer move — the identity check is the whole
  // throttle. Hovering while the pane is locked is a no-op server-side, so it
  // costs a request and swaps nothing.
  //
  // Capture phase so we run before any boosted-navigation handler on the
  // element — without it, a link's click suppresses our pointermove before we
  // read the target.
  document.addEventListener('pointermove', (e) => {
    if (!armed()) { clearHover(); return; }
    const el = resolveAt(e.clientX, e.clientY, e.target);
    if (el !== lastHovered) {
      lastHovered = el;
      if (el) { showOverlay(el); feedPane(el, false); } else hideOverlay();
    }
  }, true);

  // click to LOCK — capture phase so we run before any navigation handler.
  // Clicking used to pin to chat context; pinning is now an explicit button on
  // the pane, so a click here only says "hold this one". The lock is stored in
  // the SESSION by the route, never in this document or the parent's DOM,
  // which is what lets it survive the htmx morphs that rebuild the panel.
  document.addEventListener('click', (e) => {
    if (!armed()) return;
    const el = resolveAt(e.clientX, e.clientY, e.target);
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
