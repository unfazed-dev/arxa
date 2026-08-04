/* explode.js — the views-lens explode island (ADR-0002 amendment, 2026-08-02).
   The fifth named first-party script (sibling to canvas.js, drag.js,
   inspect.js, flowwalk.js), and the FIRST that runs in the PARENT document and
   reads a child's DOM rather than the other way round.

   Why an island at all. The views lens renders one row per screen with two
   columns: the screen tile, and the same screen exploded into its inspectable
   components. That component list cannot be produced on the server. `data-el`
   values are TEMPLATED in the project's surface partials —
   `data-el="card:{{ t('portalo.cat.' ~ pair[0]) }}"` inside a {% for %} over
   four pairs, and the tab bar arrives through {% include %} from a second
   file — so the authored source carries one unresolved string where the screen
   shows four resolved names, and misses whole regions. The only place the
   inventory exists resolved is the rendered document. The stub iframe is
   same-origin, so the parent may read it directly: no postMessage, no
   child-side counterpart, nothing added to the stub.

   Split of truth, and it is deliberate:
     - name / role / style / motion / fn  -> the rendered node's own data-*
     - box size                           -> the rendered node, ON CLICK
       (it does not exist until layout, so pre-rendering it would be a lie)
     - `fires` (which flow edge this element takes) -> the SERVER, handed down
       as data-joins, because flows.json is not in the DOM
     - `kit`                              -> the SERVER, registry `kits`

   Matching an element to an edge uses the SAME rule as flowwalk.js: exact
   `element` join first, fuzzy `trigger` second, and no match rather than a
   guess. Two lenses that disagreed about what a tap does would be worse than
   either alone.

   Island shape (per ADR-0002): dependency-free IIFE, no globals, no framework,
   no build step, re-arms on htmx:load, and no-ops on anything it does not
   understand. It never navigates and holds no truth of its own; since the
   widget-manager charter extension (2026-08) a row click ALSO posts the
   selection to the session and swaps the server-rendered property editor into
   the row's .dv-wedit slot — parent-side htmx.ajax, exactly the inspect.js
   channel, with every value and every write still server-side. */
(() => {
  if (window._explode) return; // guard against double-include
  window._explode = 1;

  const FLASH_MS = 1100;

  // Stable colour per role without a hardcoded map — an unknown role still
  // gets a consistent swatch instead of falling back to grey. ponytail: hue
  // hash, not a palette; swap for a real token map if roles ever need to match
  // the kit's own colours.
  const hue = (s) => {
    let h = 0;
    for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) % 360;
    return h;
  };

  // Same normalisation flowwalk.js uses, for the same reason: authored triggers
  // are prose ("Add to bag, then review bag") and data-el labels are terse.
  const norm = (s) => (s || '').toLowerCase().replace(/[^a-z0-9]/g, '');
  const label = (s) => { const i = (s || '').indexOf(':'); return i < 0 ? s : s.slice(i + 1); };

  const parse = (el, attr) => {
    try { return JSON.parse(el.dataset[attr] || 'null'); } catch { return null; }
  };

  // Which authored edge does this element fire? Exact `element` wins; fuzzy
  // trigger match is the fallback; ambiguity resolves to nothing.
  const edgeFor = (name, joins) => {
    if (!Array.isArray(joins) || !joins.length) return null;
    const exact = joins.find((j) => j.element && j.element === name);
    if (exact) return exact;
    const n = norm(label(name));
    if (!n) return null;
    const fuzzy = joins.filter((j) => {
      const t = norm(j.trigger);
      return t && (t === n || t.includes(n) || n.includes(t));
    });
    return fuzzy.length === 1 ? fuzzy[0] : null;
  };

  const row = (node, joins, kits, L) => {
    const name = node.getAttribute('data-el') || '';
    const role = node.getAttribute('data-inspect-role') || label(name).split(' ')[0] || '?';
    const li = document.createElement('li');
    li.className = 'dv-explode-el';
    li.style.setProperty('--el-hue', hue(role));
    li.tabIndex = 0;

    const head = document.createElement('span');
    head.className = 'dv-explode-el-head';
    head.innerHTML = '<i class="dv-explode-dot"></i>';
    const nm = document.createElement('b');
    nm.textContent = name;
    head.appendChild(nm);
    const rl = document.createElement('em');
    rl.textContent = role;
    head.appendChild(rl);
    li.appendChild(head);

    const detail = document.createElement('dl');
    detail.className = 'dv-explode-detail';
    li.appendChild(detail);

    const put = (k, v) => {
      if (!v) return;
      const dt = document.createElement('dt'); dt.textContent = k;
      const dd = document.createElement('dd'); dd.textContent = v;
      detail.append(dt, dd);
    };

    // Click fills the detail from the LIVE node, so `box` reflects the rung the
    // tile is actually rendered at rather than an authored guess.
    const open = () => {
      const already = li.classList.contains('is-open');
      li.closest('.dv-explode')?.querySelectorAll('.dv-explode-el.is-open')
        .forEach((o) => { o.classList.remove('is-open'); o.querySelector('.dv-explode-detail').replaceChildren(); });
      if (already) return;
      li.classList.add('is-open');
      detail.replaceChildren();
      put(L.role, node.getAttribute('data-inspect-role'));
      put(L.fn, node.getAttribute('data-inspect-fn'));
      const e = edgeFor(name, joins);
      put(L.fires, e ? `${e.flowName} → ${e.to}` : '—');
      put(L.kit, kits.length ? kits.map((k) => 'kit/' + k).join(', ') : '—');
      let box = '';
      try {
        const r = node.getBoundingClientRect();
        const cs = node.ownerDocument.defaultView.getComputedStyle(node);
        box = `${Math.round(r.width)}×${Math.round(r.height)}`;
        const rad = parseFloat(cs.borderRadius);
        if (rad) box += ` · r${Math.round(rad)}`;
      } catch { /* frame went away mid-click — leave box blank, never throw */ }
      put(L.box, box);
      put(L.style, node.getAttribute('data-inspect-style'));
      put(L.motion, node.getAttribute('data-inspect-motion'));
      flash(node);
      // Widget-manager selection (charter extension, 2026-08): the same click
      // selects the widget server-side and morphs the viewer, which re-renders
      // this screen's .dv-wedit slot inline AND refreshes the canvas body's
      // data-wedit-sel that drag.js hangs the handles off — a slot-only swap
      // opened the editor with no handles. Identity crossing the wire is the
      // STATIC data-el kind prefix — the piece that survives templating and
      // names the SOURCE element (the definition every screen shares).
      // index 0 = first source element of that kind in the file; per-node
      // disambiguation arrives with the canvas resize handles.
      const panel = li.closest('.dv-explode');
      const sid = panel?.dataset.explodeFor || '';
      panel?.querySelectorAll('.dv-explode-el.is-selected').forEach((s) => s.classList.remove('is-selected'));
      li.classList.add('is-selected');
      const ci = name.indexOf(':');
      if (sid && typeof htmx !== 'undefined') {
        htmx.ajax('POST', '/design/widget/select', {
          target: '#design-viewer',
          swap: 'morph:outerHTML',
          values: { screen: sid, kind: ci < 0 ? name : name.slice(0, ci), name: label(name), index: 0 },
          // hx-sync="this:replace" on <body> aborts this XHR whenever a newer
          // request supersedes it; htmx rejects the returned promise with
          // undefined on abort. Superseded selection is not an error.
        }).catch(() => {});
      }
    };
    li.addEventListener('click', open);
    li.addEventListener('keydown', (ev) => { if (ev.key === 'Enter' || ev.key === ' ') { ev.preventDefault(); open(); } });
    // Hovering the list entry outlines the real thing, so the mapping between
    // the two columns never has to be guessed from position.
    li.addEventListener('pointerenter', () => mark(node, true));
    li.addEventListener('pointerleave', () => mark(node, false));
    return li;
  };

  // Inline styles rather than a class: this writes into the STUB's document,
  // and the stub must not have to ship CSS for a parent-side island.
  const mark = (node, on) => {
    try {
      node.style.outline = on ? '2px solid var(--accent, #0891b2)' : '';
      node.style.outlineOffset = on ? '2px' : '';
    } catch { /* frame gone */ }
  };
  const flash = (node) => {
    mark(node, true);
    try { node.scrollIntoView({ block: 'nearest', behavior: 'smooth' }); } catch { /* ignore */ }
    setTimeout(() => mark(node, false), FLASH_MS);
  };

  const fill = (panel) => {
    const list = panel.querySelector('.dv-explode-list');
    const frame = panel.closest('.dv-views-row')?.querySelector('iframe');
    if (!list || !frame) return;
    // One dataset key per label rather than a JSON blob — see the comment in
    // design_viewer.html: t() returns a nunjucks SafeString and `| dump` would
    // serialise the wrapper object, not its text.
    const d = panel.dataset;
    const L = { role: d.lRole, style: d.lStyle, motion: d.lMotion, fn: d.lFn,
      fires: d.lFires, kit: d.lKit, box: d.lBox, empty: d.lEmpty };
    const joins = parse(panel, 'joins') || [];
    const kits = [...panel.querySelectorAll('.dv-explode-kit')].map((k) => k.textContent.replace(/^kit\//, ''));
    let doc;
    // Cross-origin or not-yet-navigated frames throw here. That is a no-op, not
    // an error: the load listener below re-runs once the document exists.
    try { doc = frame.contentDocument; } catch { return; }
    if (!doc || doc.readyState === 'loading') return;
    const nodes = [...doc.querySelectorAll('[data-el]')];
    list.replaceChildren();
    if (!nodes.length) {
      const li = document.createElement('li');
      li.className = 'dv-explode-empty';
      // splash and startup genuinely have zero inspectable elements. Say so
      // rather than render an empty box that reads as a failure.
      li.textContent = L.empty || '';
      list.appendChild(li);
      return;
    }
    nodes.forEach((n) => list.appendChild(row(n, joins, kits, L)));
  };

  const arm = (root) => {
    (root || document).querySelectorAll?.('.dv-explode').forEach((panel) => {
      const frame = panel.closest('.dv-views-row')?.querySelector('iframe');
      if (!frame) return;
      fill(panel);
      if (frame._explodeBound) return;
      frame._explodeBound = 1;
      frame.addEventListener('load', () => fill(panel));
    });
  };

  document.addEventListener('DOMContentLoaded', () => arm(document));
  document.body?.addEventListener?.('htmx:load', (e) => arm(e.target));
  document.addEventListener('htmx:load', (e) => arm(e.target));
  arm(document);
})();
