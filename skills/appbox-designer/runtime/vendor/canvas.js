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
     mini-panel maximize button    → toggle the viewer's fullscreen

   Zoom scales the .dv-zoom wrapper (transform-origin 0 0) and re-anchors the
   scroll position so the point under the cursor stays put. Scale is paint-
   only: iframes keep their true device width and media queries.

   Deliberate ceiling: drag-pan can't START over the device iframes (pointer
   events go to the iframe document) — pan from free canvas space; upgrade
   path is a transparent drag-shield in a held pan mode. Wheel-zoom DOES work
   over the devices: same-origin iframe documents get their own ctrl+wheel
   listener that forwards into the stage's zoom. Zoom state SURVIVES htmx
   swaps of the viewer: stashed on htmx:beforeSwap, re-applied on afterSwap
   (the control toggles re-render #design-viewer; without the stash every
   toggle snapped back to 1×). */
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

  // viewer fullscreen (mini panel [data-action="viewer-fullscreen"] and the
  // fullscreen-only close button [data-action="viewer-fullscreen-exit"]) —
  // requested from buttons INSIDE the viewer, so a delegated click finds the
  // enclosing .design-viewer. Both actions toggle: exit when anything is
  // fullscreen, enter otherwise. The buttons render on every viewer swap, so
  // delegation never needs re-arming; the close button's visibility is pure
  // CSS (:fullscreen), so Esc needs no listener.
  document.addEventListener('click', (e) => {
    const btn = e.target.closest('[data-action="viewer-fullscreen"], [data-action="viewer-fullscreen-exit"]');
    if (!btn) return;
    if (document.fullscreenElement) { document.exitFullscreen(); return; }
    btn.closest('.design-viewer')?.requestFullscreen();
  });

  // zoom survival across viewer swaps: mode/device/bg/inspect toggles
  // re-render #design-viewer (outerHTML), which would drop the client-side
  // _z back to 1×. Stash the outgoing stage's zoom before the swap, re-apply
  // it to the incoming zoom child after (flow .dv-zoom or proto .device —
  // same zoomChild helper). A 1× stash is dropped so dblclick-reset sticks.
  let stashedZoom = null;
  document.addEventListener('htmx:beforeSwap', (e) => {
    const target = e.detail.target;
    if (target?.id !== 'design-viewer') return;
    const stage = target.querySelector(SEL);
    const t = stage && zoomChild(stage);
    stashedZoom = stage?._z && stage._z !== 1 && t
      ? { z: stage._z, transformOrigin: t.style.transformOrigin }
      : null;
  });
  document.addEventListener('htmx:afterSwap', (e) => {
    if (!stashedZoom || e.detail.target?.id !== 'design-viewer') return;
    // detail.target is the DETACHED pre-swap node on an outerHTML swap —
    // re-resolve the live viewer by id.
    const stage = document.getElementById('design-viewer')?.querySelector(SEL);
    const t = stage && zoomChild(stage);
    if (!t) return;
    stage._z = stashedZoom.z;
    t.style.transformOrigin = stashedZoom.transformOrigin || '0 0';
    t.style.transform = `scale(${stashedZoom.z})`;
  });

  const scan = (root) => {
    if (root.matches?.(SEL)) attach(root);
    root.querySelectorAll?.(SEL).forEach(attach);
  };
  document.addEventListener('DOMContentLoaded', () => scan(document));
  htmx.onLoad(scan); // re-arm after every htmx swap — the viewer re-renders
})();
