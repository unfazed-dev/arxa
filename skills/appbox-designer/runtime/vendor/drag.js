/* drag.js — the gesture island (ADR-0002 amendment, 2026-07).
   The second named first-party script: marquee selection + free tile drag +
   rail resize, all pointer-based. Sibling to canvas.js; same island shape
   (view-state-only, no globals, no build step). Loaded defer from base.html.

   Scopes:
     .dv-flow-canvas — marquee select + Space/middle-drag pan + tile free-drag
     .panel-frame-handle — drag-resize the panel aside (live width badge, POST px on release)
     document        — Cmd/Ctrl+Z / Shift+Cmd/Ctrl+Z undo/redo, routed by
                       pointer focus (canvas vs chat) to /design/undo|redo/:stack

   Re-arms on every htmx swap (htmx.onLoad). */
(() => {
  const CANVAS = '.dv-flow-canvas';
  const RAIL = '.panel-frame-handle';
  const TILE = '.dv-tile';
  // let these keep their native behaviour; don't start a gesture over them
  const SKIP = '.dv-pin, a, iframe, button, .dv-bulk-pin';

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
    const base = document.querySelector('#mini-rail-actions .dv-bulk-pin')?.dataset.href
      || '/design/chat/context/bulk';
    btn.addEventListener('click', () => {
      htmx.ajax('POST', base + '?ids=' + encodeURIComponent(ids.join(',')), {
        target: '#panels', swap: 'outerHTML',
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

  // --- tile free-drag: move a tile, POST final {x,y} on release ---
  // Coordinates are GROUP-relative: .dv-tile-group is the positioned ancestor,
  // so offsetLeft/offsetTop measure against it and the server re-renders the
  // saved position absolute inside the same group — one coordinate space.
  // An in-flow tile (no saved layout yet) goes absolute on first grab; setting
  // left/top in the same frame keeps it visually put while its siblings
  // reflow into the gap.
  const startTileDrag = (e, tile) => {
    e.preventDefault();
    tile.setPointerCapture(e.pointerId);
    const sx = e.clientX, sy = e.clientY;
    const ox = tile.offsetLeft, oy = tile.offsetTop; // offsetParent == tile group
    tile.style.position = 'absolute';
    tile.style.left = ox + 'px';
    tile.style.top = oy + 'px';
    const move = (ev) => {
      tile.style.left = (ox + ev.clientX - sx) + 'px';
      tile.style.top = (oy + ev.clientY - sy) + 'px';
    };
    tile.addEventListener('pointermove', move);
    tile.addEventListener('pointerup', () => {
      tile.removeEventListener('pointermove', move);
      const id = tile.dataset.id;
      if (!id) return;
      htmx.ajax('POST', `/design/layout/artboard/${encodeURIComponent(id)}`, {
        values: { x: String(Math.round(tile.offsetLeft)), y: String(Math.round(tile.offsetTop)) },
        target: '#design-viewer', swap: 'outerHTML',
      });
    }, { once: true });
  };

  function attachCanvas(el) {
    if (el.dataset.static) return; // read-only canvas (build evidence): no marquee, no tile drag
    el.addEventListener('pointerdown', (e) => {
      if (e.target.closest(SKIP)) return;
      if (spaceDown || e.button === 1) { startPan(e, el); return; }
      const tile = e.target.closest(TILE);
      if (tile) { startTileDrag(e, tile); return; }
      if (e.button === 0) startMarquee(e, el);
    });
  }

  function attachRail(handle) {
    handle.addEventListener('pointerdown', (e) => {
      if (e.button !== 0) return;
      e.preventDefault();
      const side = handle.dataset.side || 'left'; // panel_views.html stamps data-side
      const rail = document.getElementById('panel-' + side);
      if (!rail) return;
      handle.setPointerCapture(e.pointerId);
      const sx = e.clientX;
      const startW = rail.getBoundingClientRect().width;
      let badge = handle.querySelector('.panel-frame-width');
      if (!badge) {
        badge = document.createElement('span');
        badge.className = 'panel-frame-width';
        handle.appendChild(badge);
      }
      badge.textContent = Math.round(startW) + 'px';
      const move = (ev) => {
        const w = Math.min(600, Math.max(200, startW + ev.clientX - sx));
        rail.style.width = w + 'px';
        badge.textContent = Math.round(w) + 'px';
      };
      handle.addEventListener('pointermove', move);
      handle.addEventListener('pointerup', () => {
        handle.removeEventListener('pointermove', move);
        const w = Math.round(rail.getBoundingClientRect().width);
        badge.remove();
        htmx.ajax('POST', '/design/panel/size/' + encodeURIComponent(side), {
          values: { width: String(w) }, target: '#panel-' + side, swap: 'outerHTML',
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
  // kimitail: pointer-iframes swallow hover, so "over the canvas" registers
  // only on chrome/free canvas — good enough; the buttons cover the rest.
  let pointerStack = 'canvas';
  document.addEventListener('pointerover', (e) => {
    if (e.target.closest?.('.panel-composer')) pointerStack = 'chat';
    else if (e.target.closest?.('.design-viewer')) pointerStack = 'canvas';
  });
  document.addEventListener('keydown', (e) => {
    if (!(e.metaKey || e.ctrlKey) || e.altKey || e.key.toLowerCase() !== 'z') return;
    if (e.target.closest?.('input, textarea, select, [contenteditable]')) return; // native text undo wins while typing
    if (!location.pathname.startsWith('/design')) return; // undo stacks are design-shell state
    e.preventDefault();
    htmx.ajax('POST', `/design/${e.shiftKey ? 'redo' : 'undo'}/${pointerStack}`,
      { target: '#panels', swap: 'outerHTML' });
  });
})();
