/* canvas.js — the ONE sanctioned island (ADR-0002 amendment, 2026-07).
   The only first-party script an artifact may carry: a dependency-free
   pan/zoom module scoped to the design canvas (.dv-stage / .dv-rungs inside
   #design-viewer). It exposes no globals, talks to no server, and touches
   nothing outside the canvas — the "island" shape from htmx's
   hypermedia-friendly-scripting essay. Everything else stays zero-custom-JS.

   Figma idiom:
     scroll / two-finger trackpad  → native pan (overflow:auto, untouched)
     pinch (ctrl+wheel)            → zoom around the cursor, 0.25×–4×
     drag on free canvas           → pan (pointer capture)
     double-click on free canvas   → reset zoom to 1×
     mini-panel zoom-fit button    → fit the content to the stage, centered

   Zoom scales the .dv-zoom wrapper (transform-origin 0 0) and re-anchors the
   scroll position so the point under the cursor stays put. Scale is paint-
   only: iframes keep their true device width and media queries.

   Deliberate ceiling: drag-pan can't START over the device iframes (pointer
   events go to the iframe document) — pan from free canvas space; upgrade
   path is a transparent drag-shield in a held pan mode. Wheel-zoom DOES work
   over the devices: same-origin iframe documents get their own ctrl+wheel
   listener that forwards into the stage's zoom. Zoom state resets to 1× when
   htmx swaps the viewer (new element). */
(() => {
  const SEL = '.dv-stage, .dv-rungs, .dv-flow-canvas, .dv-proto-stage';
  const clamp = (z) => Math.min(4, Math.max(0.25, z));

  // the zoomable child: the flow canvas wraps tiles in .dv-zoom; the proto
  // stage's .device IS the zoom child.
  const zoomChild = (el) => el.querySelector(':scope > .dv-zoom, :scope > .device');

  // cursor-anchored zoom: scale the wrapper, then re-anchor the scroll so the
  // point under (clientX, clientY) stays put
  const zoomAt = (el, t, clientX, clientY, deltaY) => {
    const z0 = el._z || 1;
    const z1 = clamp(z0 * (deltaY < 0 ? 1.1 : 1 / 1.1));
    if (z1 === z0) return;
    const r = el.getBoundingClientRect();
    const cx = clientX - r.left, cy = clientY - r.top, k = z1 / z0;
    el._z = z1;
    t.style.transformOrigin = '0 0';
    t.style.transform = `scale(${z1})`;
    el.scrollLeft = (el.scrollLeft + cx) * k - cx;
    el.scrollTop = (el.scrollTop + cy) * k - cy;
  };

  // zoom-fit (mini panel [data-action="zoom-fit"]): scale the zoom child so
  // the content fills the stage's padding box, then scroll to center it.
  // Same _z + transform mechanism as the wheel zoom, so ctrl+wheel/dblclick
  // pick up from the fitted scale.
  const zoomFit = (el) => {
    const t = zoomChild(el);
    if (!t) return;
    const z0 = el._z || 1;
    const cw = t.offsetWidth / z0, ch = t.offsetHeight / z0; // unscaled content size
    if (!cw || !ch) return;
    const cs = getComputedStyle(el);
    const availW = el.clientWidth - parseFloat(cs.paddingLeft) - parseFloat(cs.paddingRight);
    const availH = el.clientHeight - parseFloat(cs.paddingTop) - parseFloat(cs.paddingBottom);
    const z1 = clamp(Math.min(availW / cw, availH / ch));
    el._z = z1;
    t.style.transformOrigin = '0 0';
    t.style.transform = `scale(${z1})`;
    el.scrollLeft = Math.max(0, t.offsetLeft + (z1 * cw - el.clientWidth) / 2);
    el.scrollTop = Math.max(0, t.offsetTop + (z1 * ch - el.clientHeight) / 2);
  };

  function attach(el) {
    if (el._cz) return;
    el._cz = 1;

    const t = zoomChild(el);

    el.addEventListener('wheel', (e) => {
      if (!e.ctrlKey) return; // plain wheel/trackpad = native pan
      if (!t) return;
      e.preventDefault();
      zoomAt(el, t, e.clientX, e.clientY, e.deltaY);
    }, { passive: false });

    // pinch-over-the-device: iframe documents swallow the wheel before the
    // stage sees it. The stubs are same-origin, so listen inside each frame
    // and forward into the stage zoom, translated to page coordinates.
    t?.querySelectorAll('iframe').forEach((f) => {
      const wire = () => {
        const doc = f.contentDocument;
        if (!doc || doc._cz) return;
        doc._cz = 1;
        doc.addEventListener('wheel', (e) => {
          if (!e.ctrlKey) return;
          e.preventDefault();
          const fr = f.getBoundingClientRect();
          zoomAt(el, t, e.clientX + fr.left, e.clientY + fr.top, e.deltaY);
        }, { passive: false });
      };
      if (f.contentDocument) wire();
      f.addEventListener('load', wire);
    });

    el.addEventListener('pointerdown', (e) => {
      // .dv-flow-canvas pointer gestures belong to drag.js (tile drag,
      // marquee, Space/middle pan — the decided Figma mapping); here a plain
      // left-drag would pan WHILE the tile drags. Wheel-zoom above stays.
      if (el.matches('.dv-flow-canvas')) return;
      if (e.button !== 0 || e.target.closest('a, iframe, .dv-strip')) return;
      el.setPointerCapture(e.pointerId);
      const sx = e.clientX, sy = e.clientY, sl = el.scrollLeft, st = el.scrollTop;
      const move = (ev) => {
        el.scrollLeft = sl - (ev.clientX - sx);
        el.scrollTop = st - (ev.clientY - sy);
      };
      el.addEventListener('pointermove', move);
      el.addEventListener('pointerup', () => el.removeEventListener('pointermove', move), { once: true });
    });

    el.addEventListener('dblclick', (e) => {
      if (e.target.closest('a, iframe, .dv-strip')) return;
      el._z = 1;
      if (t) { t.style.transform = ''; t.style.transformOrigin = ''; }
    });
  }

  // zoom-fit is requested from the mini panel, OUTSIDE the stage — a document-
  // delegated click finds the enclosing viewer's stage. The button renders on
  // every viewer swap, so delegation never needs re-arming.
  document.addEventListener('click', (e) => {
    if (!e.target.closest('[data-action="zoom-fit"]')) return;
    const stage = e.target.closest('.design-viewer')?.querySelector(SEL);
    if (stage) zoomFit(stage);
  });

  const scan = (root) => {
    if (root.matches?.(SEL)) attach(root);
    root.querySelectorAll?.(SEL).forEach(attach);
  };
  document.addEventListener('DOMContentLoaded', () => scan(document));
  htmx.onLoad(scan); // re-arm after every htmx swap — the viewer re-renders
})();
