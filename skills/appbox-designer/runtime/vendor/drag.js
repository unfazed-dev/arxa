/* drag.js — the gesture island (ADR-0002 amendment, 2026-07).
   The second named first-party script: marquee selection + axis-locked flow
   row drag + rail resize, all pointer-based. Sibling to canvas.js; same
   island shape (view-state-only, no globals, no build step). Loaded defer
   from base.html.

   Scopes:
     .dv-flow-canvas — marquee select + Space/middle-drag pan; tile drag only
                       inside a .dv-flow-row (flows lens), X-axis locked
     .panel-resize   — drag-resize a panel from one of its own EDGES (live
                       width badge). Three attributes, and the split between
                       them is deliberate: none of them names a panel's place
                       in the shell, so panels can swap columns without this
                       island changing.
                         data-target  element id of the panel to resize.
                                      Required — there is no default.
                         data-edge    start|end — which of the panel's own
                                      edges the rail sits on. Decides the SIGN
                                      of the drag, and nothing else.
                         data-persist when present, the server key to POST the
                                      px width to on release so it survives a
                                      reload; omit for panels with no
                                      server-side width (the composer, whose
                                      inline width rides morph as before)
     document        — Cmd/Ctrl+Z / Shift+Cmd/Ctrl+Z undo/redo, routed by
                       pointer focus (canvas vs chat) to /design/undo|redo/:stack

   Re-arms on every htmx swap (htmx.onLoad). */
(() => {
  const CANVAS = '.dv-flow-canvas';
  const RAIL = '.panel-resize';
  const TILE = '.dv-tile';
  const ROW = '.dv-flow-row';
  // let these keep their native behaviour; don't start a gesture over them
  const SKIP = '.dv-pin, a, iframe, button, .dv-tile-tools, .dv-bulk-pin';

  // Space arms pan mode (Figma idiom); Esc clears any marquee selection.
  // Excluded over form fields / buttons so keyboard activation still works.
  let spaceDown = false;
  document.addEventListener('keydown', (e) => {
    if (e.code === 'Space') {
      const tag = (e.target.tagName || '').toLowerCase();
      if (tag !== 'input' && tag !== 'textarea' && tag !== 'button' && tag !== 'select' && !e.target.isContentEditable) {
        spaceDown = true;
        e.preventDefault();
      }
    } else if (e.key === 'Escape') {
      document.querySelectorAll(CANVAS).forEach(clearSelection);
    }
  });
  document.addEventListener('keyup', (e) => { if (e.code === 'Space') spaceDown = false; });

  const clearSelection = (el) => {
    el.querySelectorAll(`${TILE}.is-selected`).forEach((t) => t.classList.remove('is-selected'));
    el.querySelector('.dv-bulk-pin')?.remove();
  };

  // floating "Pin N screens" action near the tail of the selection; click POSTs
  // the selected ids and swaps the whole stage (re-arms via htmx.onLoad).
  const showBulkPin = (el, selected) => {
    el.querySelector('.dv-bulk-pin')?.remove();
    const ids = [...selected].map((t) => t.dataset.id).filter(Boolean);
    if (!ids.length) return;
    const last = selected[selected.length - 1].getBoundingClientRect();
    const cr = el.getBoundingClientRect();
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'dv-bulk-pin';
    btn.textContent = `Pin ${ids.length} screen${ids.length > 1 ? 's' : ''}`;
    btn.style.left = (last.right - cr.left + el.scrollLeft) + 'px';
    btn.style.top = (last.bottom - cr.top + el.scrollTop + 12) + 'px';
    // the POST base is server-rendered (v.rail.actions.bulkPinHref, carried on
    // the actions panel's own pin button); the selected ids go on the query.
    const base = document.querySelector('#mini-panel-actions .dv-bulk-pin')?.dataset.href
      || '/design/chat/context/bulk';
    btn.addEventListener('click', () => {
      // Every htmx.ajax promise here catches: hx-sync="this:replace" on
      // <body> aborts in-flight XHRs when a newer request supersedes them,
      // and htmx rejects the promise with undefined. Not an error.
      htmx.ajax('POST', base + '?ids=' + encodeURIComponent(ids.join(',')), {
        target: '#panels', swap: 'morph:outerHTML',
      }).catch((e) => { if (e !== undefined) console.error('appbox island htmx.ajax:', e); });
    });
    el.appendChild(btn);
  };

  // --- pan: Space+drag or middle-drag — same pointer-capture idiom as canvas.js ---
  const startPan = (e, el) => {
    el.setPointerCapture(e.pointerId);
    const sx = e.clientX, sy = e.clientY, sl = el.scrollLeft, st = el.scrollTop;
    const move = (ev) => {
      el.scrollLeft = sl - (ev.clientX - sx);
      el.scrollTop = st - (ev.clientY - sy);
    };
    el.addEventListener('pointermove', move);
    el.addEventListener('pointerup', () => el.removeEventListener('pointermove', move), { once: true });
  };

  // --- marquee: drag a rect on empty canvas, tiles whose bounds intersect get .is-selected ---
  const startMarquee = (e, el) => {
    e.preventDefault();
    clearSelection(el);
    el.setPointerCapture(e.pointerId);
    const sx = e.clientX, sy = e.clientY;
    const box = document.createElement('div');
    box.className = 'dv-marquee';
    el.appendChild(box);
    const tiles = el.querySelectorAll(TILE);
    const move = (ev) => {
      const mx = Math.min(sx, ev.clientX), my = Math.min(sy, ev.clientY);
      const mw = Math.abs(ev.clientX - sx), mh = Math.abs(ev.clientY - sy);
      const cr = el.getBoundingClientRect();
      box.style.left = (mx - cr.left + el.scrollLeft) + 'px';
      box.style.top = (my - cr.top + el.scrollTop) + 'px';
      box.style.width = mw + 'px';
      box.style.height = mh + 'px';
      tiles.forEach((t) => {
        const tr = t.getBoundingClientRect();
        const hit = mx < tr.right && mx + mw > tr.left && my < tr.bottom && my + mh > tr.top;
        t.classList.toggle('is-selected', hit);
      });
    };
    el.addEventListener('pointermove', move);
    el.addEventListener('pointerup', () => {
      el.removeEventListener('pointermove', move);
      box.remove();
      const selected = el.querySelectorAll(`${TILE}.is-selected`);
      if (selected.length) showBulkPin(el, selected);
    }, { once: true });
  };

  // --- tile row-drag (flows lens only): a tile grabbed inside a .dv-flow-row
  // shifts horizontally (translateX — Y is clamped to the row by
  // construction, no reflow); on drop the target slot is the count of sibling
  // tiles whose midpoint sits left of the drop x, and ONE htmx POST to the
  // move endpoint (index) re-renders the stage. Views-mode tiles don't drag.
  const startRowDrag = (e, tile, row) => {
    e.preventDefault();
    tile.setPointerCapture(e.pointerId);
    const sx = e.clientX;
    let dragged = false;
    const move = (ev) => {
      const dx = ev.clientX - sx;
      if (Math.abs(dx) < 4 && !dragged) return; // click jitter, not a drag
      dragged = true;
      tile.style.zIndex = 5;
      tile.style.transform = `translateX(${dx}px)`;
    };
    tile.addEventListener('pointermove', move);
    tile.addEventListener('pointerup', (ev) => {
      tile.removeEventListener('pointermove', move);
      tile.style.transform = '';
      tile.style.zIndex = '';
      const id = tile.dataset.id;
      const flow = row.dataset.flow;
      if (!dragged || !id || !flow) return;
      const siblings = [...row.querySelectorAll(TILE)];
      const current = siblings.indexOf(tile);
      // the index among the OTHER tiles == the slot in the post-move order
      const index = siblings.filter((t) => {
        if (t === tile) return false;
        const r = t.getBoundingClientRect();
        return r.left + r.width / 2 < ev.clientX;
      }).length;
      if (index === current) return;
      htmx.ajax('POST', `/design/flows/${encodeURIComponent(flow)}/move/${encodeURIComponent(id)}`, {
        values: { index: String(index) },
        target: '#panels', swap: 'morph:outerHTML',
      }).catch((e) => { if (e !== undefined) console.error('appbox island htmx.ajax:', e); }); // superseded-request abort; see bulk-pin note
    }, { once: true });
  };

  function attachCanvas(el) {
    if (el.dataset.static) return; // read-only canvas (build evidence): no marquee, no tile drag
    el.addEventListener('pointerdown', (e) => {
      if (e.target.closest(SKIP)) return;
      if (spaceDown || e.button === 1) { startPan(e, el); return; }
      const tile = e.target.closest(TILE);
      if (tile) {
        const row = tile.closest(ROW);
        if (row && e.button === 0) startRowDrag(e, tile, row);
        return;
      }
      if (e.button === 0) startMarquee(e, el);
    });
  }

  function attachRail(handle) {
    handle.addEventListener('pointerdown', (e) => {
      if (e.button !== 0) return;
      e.preventDefault();
      const persist = handle.dataset.persist || ''; // '' — resize only, nothing to record
      // No default target. The old fallback composed an id from a position
      // word, so a rail that forgot the attribute still resolved to a REAL
      // panel — a typo resized the wrong one instead of failing. Explicit id
      // or nothing.
      const panel = document.getElementById(handle.dataset.target);
      if (!panel) return;
      // Which edge you grabbed decides the sign. Dragging a panel's END edge
      // rightwards widens it; dragging its START edge rightwards NARROWS it.
      // The sign comes from the edge, never from which column the panel is in
      // — that is what let the two panels swap columns without touching this.
      const sign = handle.dataset.edge === 'start' ? -1 : 1;
      handle.setPointerCapture(e.pointerId);
      const sx = e.clientX;
      const startW = panel.getBoundingClientRect().width;
      // .panel-activity animates `width` for the s/m/l steps. Left on during a
      // drag it makes the edge lag the pointer, and — worse — the release
      // below used to read the still-animating width and persist THAT, so a
      // drag to 420px saved 369px. Off for the drag, restored after.
      const prevTransition = panel.style.transition;
      panel.style.transition = 'none';
      let last = startW;
      // The drag range is the panel's OWN CSS min/max width, read live. This
      // used to clamp to a hardcoded [200, 600] — a pair of numbers that
      // matched NO panel: the composer floors at 360px and ceilings at 576px,
      // the activity panel floors at 340px. Below the floor `min-width` held
      // the element still while the badge kept counting down to 200, so the
      // readout reported 160px of travel that never happened. The badge was
      // never wrong about the drag; the drag was wrong about the panel.
      //
      // CSS owns the limits — one source of truth, and a panel can restyle its
      // width without a matching edit here. An unstated bound (`auto`/`none`,
      // both NaN) means the panel declares no limit at that end, so fall
      // through to none rather than inventing one: a constant here is exactly
      // the bug above.
      const cs = getComputedStyle(panel);
      const bound = (v, fallback) => (Number.isFinite(parseFloat(v)) ? parseFloat(v) : fallback);
      const lo = bound(cs.minWidth, 0);
      const hi = bound(cs.maxWidth, Infinity);
      let badge = handle.querySelector('.panel-resize-width');
      if (!badge) {
        badge = document.createElement('span');
        badge.className = 'panel-resize-width';
        handle.appendChild(badge);
      }
      badge.textContent = Math.round(startW) + 'px';
      const move = (ev) => {
        const w = Math.min(hi, Math.max(lo, startW + sign * (ev.clientX - sx)));
        last = w;
        panel.style.width = w + 'px';
        badge.textContent = Math.round(w) + 'px';
      };
      handle.addEventListener('pointermove', move);
      handle.addEventListener('pointerup', () => {
        handle.removeEventListener('pointermove', move);
        panel.style.transition = prevTransition;
        // `last`, not the measured box: the box can be mid-transition, and a
        // flex row may also be shrinking the panel below the width we asked
        // for. What the user dragged to is what gets saved.
        const w = Math.round(last);
        badge.remove();
        if (!persist) return; // no server-side width for this panel; the inline style rides morph
        // RECORD ONLY — swap:'none'. Swapping the panel back in looked like the
        // whole app reloading on every release: htmx runs with
        // globalViewTransitions, and .panel-activity has no view-transition-name,
        // so it was captured in the ROOT snapshot and the browser cross-faded
        // the entire page. There is nothing to swap in anyway — the drag
        // already put the final width on the element, and the server only
        // needs to remember it for the next full render.
        htmx.ajax('POST', '/design/panel/size/' + encodeURIComponent(persist), {
          values: { width: String(w) }, swap: 'none transition:false',
        }).catch((e) => { if (e !== undefined) console.error('appbox island htmx.ajax:', e); }); // superseded-request abort; see bulk-pin note
      }, { once: true });
    });
  }

  const attach = (el) => {
    if (el._dz) return;
    el._dz = 1;
    if (el.matches(CANVAS)) attachCanvas(el);
    else if (el.matches(RAIL)) attachRail(el);
  };

  const scan = (root) => {
    root.querySelectorAll?.(`${CANVAS}, ${RAIL}`).forEach(attach);
    if (root.matches?.(`${CANVAS}, ${RAIL}`)) attach(root);
  };
  document.addEventListener('DOMContentLoaded', () => scan(document));
  htmx.onLoad(scan); // re-arm after every htmx swap — the viewer re-renders

  /* ---------- widget resize handles (edit arming, D2) -------------------
     Eight handles hung over the SELECTED widget while the canvas is armed.

     MODE, not measurement. The Auto Layout contract has no size-bearing
     attribute — there is no data-w/data-h, only [data-resize-x|y] =
     hug|fill|fixed. So a drag cannot commit a pixel figure without inventing
     a second vocabulary, and forking the contract to make a gesture feel
     familiar is a bad trade. The gesture therefore expresses INTENT and the
     direction picks the mode:

       drag outward  → fill  (grow into the space the parent gives you)
       drag inward   → hug   (shrink to your own content)
       under DEAD_PX → nothing (a click that wobbled is not an edit)

     `fixed` is deliberately NOT reachable by drag: it means "keep the size
     you have", which is what you already see, so no drag direction honestly
     denotes it. It stays an explicit chip in the editor.

     Everything commits through the EXISTING /design/widget/attr, so the
     facade's W_ATTR_VALUES table stays the single enforcement point — the
     handles cannot write a value the chips could not. */
  const DEAD_PX = 6;
  const HANDLES = [
    ['nw', 'y', -1], ['n', 'y', -1], ['ne', 'y', -1],
    ['w', 'x', -1], ['e', 'x', 1],
    ['sw', 'y', 1], ['s', 'y', 1], ['se', 'y', 1],
  ];
  let hbox = null;

  const selOf = (canvas) => {
    try { return JSON.parse(canvas.getAttribute('data-wedit-sel') || 'null'); }
    catch { return null; }
  };

  // Re-find the node from the SERVER's selection every time. A committed edit
  // rewrites the source, the watcher reloads the frame ~200ms later, and any
  // marker we had put on the old node dies with the old document — handles
  // that hung off a client-side class would disappear after every edit.
  const findSel = (canvas, sel) => {
    const f = canvas.querySelector(`iframe[data-screen="${sel.screen}"]`);
    const doc = f?.contentDocument;
    if (!doc) return null;
    const kindOf = (n) => {
      const raw = n.getAttribute('data-el') || '';
      const ci = raw.indexOf(':');
      return ci < 0 ? raw : raw.slice(0, ci);
    };
    const hits = [...doc.querySelectorAll('[data-el]')].filter((n) => kindOf(n) === sel.kind);
    const node = hits[sel.index || 0];
    return node ? { f, node } : null;
  };

  // Selection outline, INSIDE the frame document. Inline styles, not a class:
  // the stub carries none of the studio's stylesheets, so a class would name
  // a rule that does not exist there (explode.js marks the same way).
  let marked = null;
  const markSel = (node) => {
    if (marked === node) return;
    try { if (marked) { marked.style.outline = ''; marked.style.outlineOffset = ''; } } catch { /* frame gone */ }
    marked = node;
    try {
      if (node) { node.style.outline = '2px solid var(--accent, #0891b2)'; node.style.outlineOffset = '2px'; }
    } catch { /* frame gone */ }
  };

  const killBox = () => { hbox?.remove(); hbox = null; markSel(null); };

  // The overlay is position:fixed on <body>, in VIEWPORT coordinates, and
  // lives OUTSIDE .dv-zoom on purpose: inside the transformed subtree the
  // browser would apply the canvas zoom to it a second time, because
  // getBoundingClientRect already returns post-transform pixels.
  const place = (canvas, sel) => {
    const hit = findSel(canvas, sel);
    if (!hit) return killBox();
    markSel(hit.node);
    const fr = hit.f.getBoundingClientRect();
    const r = hit.node.getBoundingClientRect();
    const top = fr.top + r.top;
    const left = fr.left + r.left;
    // Clipped out of view by the tile's own scroll/overflow — don't float a
    // detached box over unrelated chrome.
    if (r.width <= 0 || r.height <= 0 || top > fr.bottom || top + r.height < fr.top) return killBox();
    if (!hbox) {
      hbox = document.createElement('div');
      hbox.className = 'dv-wedit-handles';
      for (const [dir, axis, sign] of HANDLES) {
        const h = document.createElement('span');
        h.className = `dv-wh dv-wh-${dir}`;
        h.dataset.axis = axis;
        h.dataset.sign = String(sign);
        hbox.appendChild(h);
      }
      // Parent to #app, NOT <body>: the theme custom properties (--accent,
      // --bg) are declared on #app, and custom properties only inherit
      // DOWNWARD — a body-parented overlay sits above that declaration and
      // would render with no border colour and a transparent fill, i.e.
      // handles present in the DOM and invisible on screen. Nothing in the
      // chain sets transform/filter/contain, so position:fixed still
      // resolves against the viewport here.
      (document.getElementById('app') || document.body).appendChild(hbox);
      wireBox(canvas);
    }
    Object.assign(hbox.style, {
      top: `${top}px`, left: `${left}px`,
      width: `${r.width}px`, height: `${r.height}px`,
    });
  };

  const commit = (canvas, sel, attr, value) => {
    if (typeof htmx === 'undefined') return;
    htmx.ajax('POST', '/design/widget/attr', {
      target: '#dv-wedit-' + String(sel.screen).replace(/\./g, '-'),
      swap: 'innerHTML',
      values: { attr, value },
    }).catch((e) => { if (e !== undefined) console.error('appbox island htmx.ajax:', e); }); // superseded-request abort; see bulk-pin note
  };

  function wireBox(canvas) {
    hbox.addEventListener('pointerdown', (e) => {
      const h = e.target.closest('.dv-wh');
      if (!h) return;
      e.preventDefault();
      const sel = selOf(canvas);
      if (!sel) return;
      const axis = h.dataset.axis;
      const sign = Number(h.dataset.sign);
      const start = axis === 'x' ? e.clientX : e.clientY;
      h.setPointerCapture(e.pointerId);
      hbox.classList.add('is-dragging');
      const move = (ev) => {
        const d = ((axis === 'x' ? ev.clientX : ev.clientY) - start) * sign;
        // Live intent readout: the user sees which mode the release commits
        // BEFORE releasing, which is the only honest preview available when
        // the commit is a mode rather than a measurement.
        hbox.dataset.intent = Math.abs(d) < DEAD_PX ? '' : (d > 0 ? 'fill' : 'hug');
      };
      const up = (ev) => {
        h.removeEventListener('pointermove', move);
        h.removeEventListener('pointerup', up);
        hbox.classList.remove('is-dragging');
        const intent = hbox.dataset.intent;
        delete hbox.dataset.intent;
        const d = ((axis === 'x' ? ev.clientX : ev.clientY) - start) * sign;
        if (Math.abs(d) < DEAD_PX || !intent) return;
        commit(canvas, sel, axis === 'x' ? 'data-resize-x' : 'data-resize-y', intent);
      };
      h.addEventListener('pointermove', move);
      h.addEventListener('pointerup', up);
    });
  }

  // One re-derive path for every reason the box could be stale: a swap, a
  // frame reload after a write-through, a pan/zoom, a window resize.
  const syncHandles = () => {
    const canvas = document.querySelector(`${CANVAS}[data-wedit-armed][data-wedit-sel]`);
    const sel = canvas && selOf(canvas);
    if (!canvas || !sel) return killBox();
    place(canvas, sel);
  };
  htmx.onLoad(syncHandles);
  document.addEventListener('DOMContentLoaded', syncHandles);
  addEventListener('resize', syncHandles);
  addEventListener('scroll', syncHandles, true);
  // The frame reloads on its own clock (~200ms watcher re-prefetch), long
  // after the htmx swap that caused it, so a swap-time sync alone would
  // measure the OLD layout. Re-place on the tile's own load event too.
  document.addEventListener('load', (e) => {
    if (e.target?.classList?.contains('dv-tile-frame')) syncHandles();
  }, true);

  // Inspect keyboard shortcut: "i" toggles armed state on all same-origin
  // iframe bodies (the stubs are same-origin so we can reach into them). This
  // is the parent-page arming path the plan names alongside the server-param
  // toggle and the momentary Alt-hold inside inspect.js.
  const toggleInspect = () => {
    document.querySelectorAll('iframe').forEach((f) => {
      const doc = f.contentDocument;
      if (!doc) return;
      if (doc.body.dataset.inspectArmed === 'true') delete doc.body.dataset.inspectArmed;
      else doc.body.dataset.inspectArmed = 'true';
    });
  };
  document.addEventListener('keydown', (e) => {
    if (e.target.matches?.('input, textarea, [contenteditable], select')) return;
    if (e.key === 'i' || e.key === 'I') { e.preventDefault(); toggleInspect(); }
  });

  // Keyboard undo/redo (Cmd/Ctrl+Z, Shift+Cmd/Ctrl+Z) routed by pointer focus:
  // the stack under the pointer wins — over the chat → chat stack (design
  // changes), over the viewer/canvas → canvas stack (tile moves, pins). Same
  // panels swap as the icon-button pairs. The stacks and their routes are
  // design-shell-only, so the keys engage only there — posting them from
  // intake/build would swap design markup into another shell's #panels.
  // Deliberate simplification: pointer-iframes swallow hover, so "over the
  // canvas" registers only on chrome/free canvas — good enough; the buttons
  // cover the rest.
  let pointerStack = 'canvas';
  document.addEventListener('pointerover', (e) => {
    if (e.target.closest?.('.panel-composer')) pointerStack = 'chat';
    else if (e.target.closest?.('.panel-viewer')) pointerStack = 'canvas';
  });
  document.addEventListener('keydown', (e) => {
    if (!(e.metaKey || e.ctrlKey) || e.altKey || e.key.toLowerCase() !== 'z') return;
    if (e.target.closest?.('input, textarea, select, [contenteditable]')) return; // native text undo wins while typing
    if (!location.pathname.startsWith('/design')) return; // undo stacks are design-shell state
    e.preventDefault();
    htmx.ajax('POST', `/design/${e.shiftKey ? 'redo' : 'undo'}/${pointerStack}`,
      { target: '#panels', swap: 'morph:outerHTML' })
      .catch((e) => { if (e !== undefined) console.error('appbox island htmx.ajax:', e); }); // superseded-request abort; see bulk-pin note
  });
})();
