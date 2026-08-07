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

  // heuristic: tag-map, extend the map before reaching for anything smarter
  const ROLE_BY_TAG = { H1:'heading',H2:'heading',H3:'heading',H4:'heading',H5:'heading',H6:'heading',
    P:'text',SPAN:'text',LABEL:'label',BUTTON:'action',A:'action',IMG:'image',SVG:'image',
    UL:'list',OL:'list',LI:'list row',NAV:'nav',HEADER:'nav',FOOTER:'group',SECTION:'group',
    INPUT:'input',SELECT:'input',TEXTAREA:'input' };

  const SKIP_TAGS = new Set(['SCRIPT','STYLE','BODY','HTML']);

  // Infer identity for elements that may lack data-el. Identified elements keep
  // their data-el name; unannotated ones get the tag name as a structural label,
  // tagged "inferred" so the pane and overlay can dim them.
  const synthesize = (el) => ({
    name: el.dataset.el || el.tagName.toLowerCase(),
    role: el.dataset.inspectRole || ROLE_BY_TAG[el.tagName] || 'group',
    inferred: el.dataset.el ? '' : '1',
  });

  // Resolve the innermost inspectable element from a pointer event target.
  // Walks up from the raw target, skipping overlay nodes, script/style/body/html.
  const inspectTarget = (raw) => {
    let el = raw;
    while (el && el !== document.body) {
      if (SKIP_TAGS.has(el.tagName)) { el = el.parentElement; continue; }
      if (el.className && typeof el.className === 'string' && el.className.startsWith('inspect-')) {
        el = el.parentElement; continue;
      }
      return el; // first non-skipped element is the innermost
    }
    return null;
  };

  // Build the ancestor chain outermost→innermost for the breadcrumb.
  // Keep every element with data-el, plus the immediate parent if it lacks
  // data-el. The hovered element is always included.
  const buildChain = (el) => {
    const chain = [];
    let cur = el;
    let grabbedNonDataEl = false;
    // Walk from el upward; collect into chain, then reverse at the end
    while (cur && cur !== document.body) {
      if (SKIP_TAGS.has(cur.tagName)) break;
      if (cur.className && typeof cur.className === 'string' && cur.className.startsWith('inspect-')) {
        cur = cur.parentElement; continue;
      }
      const hasDataEl = !!cur.dataset.el;
      if (hasDataEl || !grabbedNonDataEl) {
        const info = synthesize(cur);
        chain.push({ el: info.name, role: info.role, inferred: info.inferred || undefined });
        if (!hasDataEl) grabbedNonDataEl = true;
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

  // The badge: the element's name, nothing else. The role/style/motion/fn
  // rows moved to the inspector pane, where there is room for them and for
  // the server-side joins that give them meaning. Inferred elements (no
  // data-el) render at reduced opacity so the composer can tell at a glance
  // which names are authored vs guessed.
  const fillReadout = (el) => {
    const info = synthesize(el);
    labelEl.replaceChildren();
    const name = document.createElement('div');
    name.style.cssText = 'font-weight:600;' + (info.inferred ? ' opacity:.6;' : '');
    name.textContent = info.name;
    labelEl.appendChild(name);
    const sub = document.createElement('div');
    sub.style.cssText = 'font-size:10px;opacity:.85;';
    sub.textContent = info.role + (info.inferred ? ' · inferred' : '');
    labelEl.appendChild(sub);
  };

  // What the pane renders. Identified elements (data-el) send their authored
  // name; unannotated elements send an inferred name + role so the pane can
  // still show a breadcrumb. The SERVER owns the final authored/inferred
  // distinction in its joins — the inferred flag here is the client's best
  // guess, consistent with what the overlay badge dims.
  const measure = (el, lock) => {
    const info = synthesize(el);
    const v = {
      screen: document.body.dataset.surface || '',
      name: info.name,
      kind: el.tagName.toLowerCase(),
    };
    if (el.dataset.inspectRole) v.role = el.dataset.inspectRole;
    else if (info.role && info.inferred) v.role = info.role; // inferred role
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

  // hover tracking — only acts while armed. Resolves the innermost element
  // (not just [data-el]) so unannotated elements are still inspectable; their
  // identity is inferred by synthesize().
  document.addEventListener('pointermove', (e) => {
    if (!armed()) { clearHover(); return; }
    const el = inspectTarget(e.target);
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
