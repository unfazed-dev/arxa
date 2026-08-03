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
      htmx.ajax('POST', base + '?ids=' + encodeURIComponent(ids.join(',')), {
        target: '#panels', swap: 'morph:outerHTML',
      });
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
      });
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
        });
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
      { target: '#panels', swap: 'morph:outerHTML' });
  });
})();
