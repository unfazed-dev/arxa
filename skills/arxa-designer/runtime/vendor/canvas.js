/* canvas.js — sanctioned island (ADR-0002 amendment, 2026-07; first of the
   named set). A dependency-free pan/zoom-and-sync module scoped to the design
   canvas (.dv-stage / .dv-rungs inside #design-viewer). It exposes no
   globals, talks to no server, and touches nothing outside the viewer
   panel — the "island" shape from htmx's hypermedia-friendly-scripting
   essay. Everything else stays zero-custom-JS.

   Figma idiom:
     scroll / two-finger trackpad  → native pan (overflow:auto, untouched)
     pinch (ctrl+wheel)            → zoom around the cursor, 0.25×–4×
     drag on free canvas           → pan (pointer capture)
     double-click on free canvas   → reset zoom to 1×
     mini-panel maximize button    → toggle the viewer's fullscreen
     filmstrip thumb click         → smooth-center that screen (views lens)
     scroll (views lens)           → strip tracks the current screen, `.on`
                                     accent mark on tile and thumb alike
     tap/scroll inside a tile      → interact-in-place (views/flows): still
                                     frames take taps, hover and scroll
                                     natively, but navigation is inert —
                                     anchor clicks and form submits are
                                     cancelled from here (same-origin), so
                                     the stub stays script-free and a tap
                                     never walks the tile to another screen

   Zoom scales the .dv-zoom wrapper (transform-origin 0 0) and re-anchors the
   scroll position so the point under the cursor stays put. Scale is paint-
   only: iframes keep their true device width and media queries.

   Deliberate ceiling: drag-pan can't START over the device iframes (pointer
   events go to the iframe document) — pan from free canvas space; upgrade
   path is a transparent drag-shield in a held pan mode. Wheel-zoom DOES work
   over the devices: same-origin iframe documents get their own ctrl+wheel
   listener that forwards into the stage's zoom. Zoom state SURVIVES htmx
   swaps of the viewer: stashed on htmx:before:swap, re-applied on after:swap
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

  // filmstrip ↔ canvas sync (views lens). The strip's thumbs point at their
  // tiles by fragment href (#dvt-views--<id>) — the DOM id is the whole
  // contract, no data attributes. "Current screen" = the tile whose center
  // sits nearest the canvas viewport's center; `.on` marks it on BOTH sides
  // (the accent vocabulary the thumbs already carry). A click smooth-centers
  // the tile and latches scroll detection until the glide settles, so the
  // screens passed on the way don't flash. Morphs wipe client-set classes,
  // so sync() re-derives the mark on every scan (htmx.onLoad); the armed
  // listeners survive on morph-preserved nodes behind the _ss guards.
  const stripOf = (el) => el.closest('.panel-viewer')?.querySelector('.dv-vstrip');
  const thumbTile = (a) => document.getElementById((a.getAttribute('href') || '#').slice(1));
  const markCurrent = (el, strip, id) => {
    el.querySelectorAll('.dv-tile').forEach((t) => t.classList.toggle('on', t.id === id));
    strip.querySelectorAll('.dv-thumb').forEach((a) => {
      const on = thumbTile(a)?.id === id;
      a.classList.toggle('on', on);
      if (on) a.scrollIntoView({ block: 'nearest' });
    });
  };
  const nearestTile = (el) => {
    const mid = ((r) => r.top + r.height / 2)(el.getBoundingClientRect());
    let best = null, gap = Infinity;
    el.querySelectorAll('.dv-tile').forEach((t) => {
      const b = t.getBoundingClientRect();
      const d = Math.abs(b.top + b.height / 2 - mid);
      if (d < gap) { gap = d; best = t; }
    });
    return best;
  };
  const sync = (el) => {
    const strip = stripOf(el);
    if (!strip) return; // flows lens shares the canvas class but has no strip
    if (!el._ss) {
      el._ss = 1;
      let raf = 0;
      el.addEventListener('scroll', () => {
        if (el._latch || raf) return;
        raf = requestAnimationFrame(() => {
          raf = 0;
          const t = nearestTile(el);
          if (t) markCurrent(el, stripOf(el) || strip, t.id);
        });
      }, { passive: true });
    }
    if (!strip._ss) {
      strip._ss = 1;
      strip.addEventListener('click', (e) => {
        const a = e.target.closest('.dv-thumb');
        const tile = a && thumbTile(a);
        if (!tile) return; // no tile → let the fragment navigation try
        e.preventDefault();
        el._latch = 1;
        markCurrent(el, strip, tile.id);
        tile.scrollIntoView({ behavior: 'smooth', block: 'center' });
        const settle = () => { el._latch = 0; el.removeEventListener('scrollend', settle); };
        el.addEventListener('scrollend', settle);
        setTimeout(settle, 900); // scrollend fallback (long glides, old engines)
      });
    }
    const t = nearestTile(el);
    if (t) markCurrent(el, strip, t.id);
  };

  // viewer fullscreen (mini panel [data-action="viewer-fullscreen"] and the
  // fullscreen-only close button [data-action="viewer-fullscreen-exit"]) —
  // requested from buttons INSIDE the viewer, so a delegated click finds the
  // enclosing .panel-viewer (the main panel's card). Both actions toggle: exit when anything is
  // fullscreen, enter otherwise. The buttons render on every viewer swap, so
  // delegation never needs re-arming; the close button's visibility is pure
  // CSS (:fullscreen), so Esc needs no listener.
  document.addEventListener('click', (e) => {
    const btn = e.target.closest('[data-action="viewer-fullscreen"], [data-action="viewer-fullscreen-exit"]');
    if (!btn) return;
    if (document.fullscreenElement) { document.exitFullscreen(); return; }
    btn.closest('.panel-viewer')?.requestFullscreen();
  });

  // zoom survival across viewer swaps: mode/device/bg/inspect toggles
  // re-render #design-viewer (outerHTML), which would drop the client-side
  // _z back to 1×. Stash the outgoing stage's zoom before the swap, re-apply
  // it to the incoming zoom child after (flow .dv-zoom or proto .device —
  // same zoomChild helper). A 1× stash is dropped so dblclick-reset sticks.
  let stashedZoom = null;
  document.addEventListener('htmx:before:swap', (e) => {
    const target = e.detail.ctx?.target;
    if (target?.id !== 'design-viewer') return;
    const stage = target.querySelector(SEL);
    const t = stage && zoomChild(stage);
    stashedZoom = stage?._z && stage._z !== 1 && t
      ? { z: stage._z, transformOrigin: t.style.transformOrigin }
      : null;
  });
  document.addEventListener('htmx:after:swap', (e) => {
    if (!stashedZoom || e.detail.ctx?.target?.id !== 'design-viewer') return;
    // detail.ctx.target is the DETACHED pre-swap node on an outerHTML swap —
    // re-resolve the live viewer by id.
    const stage = document.getElementById('design-viewer')?.querySelector(SEL);
    const t = stage && zoomChild(stage);
    if (!t) return;
    stage._z = stashedZoom.z;
    t.style.transformOrigin = stashedZoom.transformOrigin || '0 0';
    t.style.transform = `scale(${stashedZoom.z})`;
  });

  // per-frame same-origin wiring. Runs on EVERY scan, not inside attach():
  // attach's el._cz one-shot guard skips morph-preserved canvases, so frames
  // ADDED by a swap (a lens switch morphs new tiles in) would never be wired
  // — pinch forwarding and inert navigation both went dead on them. The
  // per-iframe _cw guard keeps re-scans idempotent; the per-document _cz
  // guard keeps re-loads idempotent.
  const wireFrames = (el) => {
    const t = zoomChild(el);
    t?.querySelectorAll('iframe').forEach((f) => {
      if (f._cw) return;
      f._cw = 1;
      const wire = () => {
        const doc = f.contentDocument;
        if (!doc || doc._cz) return;
        doc._cz = 1;
        // pinch-over-the-device: iframe documents swallow the wheel before
        // the stage sees it. The stubs are same-origin, so listen inside
        // each frame and forward into the stage zoom, in page coordinates.
        doc.addEventListener('wheel', (e) => {
          if (!e.ctrlKey) return;
          e.preventDefault();
          const fr = f.getBoundingClientRect();
          zoomAt(el, t, e.clientX + fr.left, e.clientY + fr.top, e.deltaY);
        }, { passive: false });
        // interact-in-place: still frames (canvas tiles) take taps, hover
        // and scroll natively, but navigation stays inert — anchors and
        // form submits are cancelled here in the parent (same-origin), so
        // the stub stays script-free and a tap never full-loads another
        // screen into the tile. Gate on the DOCUMENT url, not the src
        // attribute: it stays correct if a frame ever re-navigates. Live
        // tiles drop still=1 (real prototype nav) and inspected frames keep
        // navigation (pqs deliberately carries inspect=1 across hops).
        // Edit arming (D2): armed, a click inside a tile SELECTS the widget
        // under the pointer instead of reaching the app under design. The
        // two readings of a click are mutually exclusive, so this runs FIRST
        // and stops propagation — the interact-in-place handlers below never
        // see an armed click.
        //
        // Armed-ness is read at CLICK time, never captured here. The _cw/_cz
        // guards make this wire once per frame, but arming flips many times
        // per session: a value captured now would freeze the tile in
        // whatever mode it happened to be wired in, and the tile would keep
        // that mode across every later arm/disarm.
        doc.addEventListener('click', (e) => {
          // closest(), not hasAttribute(): in the views/flows lenses `el` IS
          // the attributed canvas body, but in proto `el` is .dv-proto-stage,
          // a CHILD of it — hasAttribute would read false there forever.
          if (!el.closest('[data-wedit-armed]')) return;
          e.preventDefault();
          // stopImmediatePropagation, not stopPropagation: the
          // interact-in-place handlers below are registered on this SAME
          // node in this SAME phase, and stopPropagation only blocks
          // DESCENDANT nodes — it would not stop a co-registered listener.
          e.stopImmediatePropagation();
          const node = e.target.closest?.('[data-el]');
          const sid = f.dataset.screen || '';
          if (!node || !sid || typeof htmx === 'undefined') return;
          // Identity on the wire is the STATIC data-el kind prefix — the
          // part that survives templating and names the SOURCE element every
          // screen shares. Same shape the drawer strip posts, so a strip pick
          // and a canvas click select the same thing.
          const raw = node.getAttribute('data-el') || '';
          const ci = raw.indexOf(':');
          // No selection marker is painted here on purpose. The frame
          // document carries none of the studio's CSS, so a class would style
          // nothing (drag.js marks with inline styles for exactly
          // this reason), and anything set at click time dies when the
          // write-through reloads the frame. drag.js paints the selection
          // instead, re-derived from server state on every scan.
          // Same target/swap as the arm chip: the selection lives in the
          // canvas body's data-wedit-sel, which only the viewer fragment
          // renders. Swapping just the editor slot opened the editor but left
          // the canvas attribute stale, so drag.js never hung the handles.
          // morph (not outerHTML) is what keeps the tiles from reloading.
          htmx.ajax('POST', '/design/widget/select', {
            target: '#design-viewer',
            swap: 'outerMorph',
            values: {
              screen: sid,
              kind: ci < 0 ? raw : raw.slice(0, ci),
              name: ci < 0 ? raw : raw.slice(ci + 1),
              index: 0,
            },
            // hx-sync="this:replace" on <body> aborts this XHR whenever a
            // newer request supersedes it; htmx rejects the returned promise
            // with undefined on abort. Superseded selection is not an error.
          }).catch((e) => { if (e !== undefined) console.error('arxa island htmx.ajax:', e); });
        }, true);
        const q = f.contentWindow?.location?.search || '';
        if (q.includes('still=1') && !q.includes('inspect=1')) {
          doc.addEventListener('click', (e) => {
            if (e.target.closest('a[href]')) e.preventDefault();
          }, true);
          doc.addEventListener('submit', (e) => e.preventDefault(), true);
        }
      };
      if (f.contentDocument) wire();
      f.addEventListener('load', wire);
    });
  };

  const arm = (el) => { attach(el); wireFrames(el); if (el.matches('.dv-flow-canvas')) sync(el); };
  const scan = (root) => {
    if (root.matches?.(SEL)) arm(root);
    root.querySelectorAll?.(SEL).forEach(arm);
  };
  document.addEventListener('DOMContentLoaded', () => scan(document));
  htmx.onLoad(scan); // re-arm after every htmx swap — the viewer re-renders
})();
