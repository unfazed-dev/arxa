/* reveal.js — the screen reveal-drawer island (Screen Reveal-Drawer plan,
 * increment 2).
 *
 * WHY THIS EXISTS AT ALL. The drawer's STATE is server session state and its
 * MOTION is pure CSS (viewer.css: transform-only transition, morph keeps the
 * node so the is-open class change animates). What neither can do is move
 * FOCUS: the plan's a11y defaults require focus to land inside the panel on
 * open, return to the trigger on close, and ESC to close the drawer. Focus is
 * a client concern by nature, so — per ADR-0002 — it is a named, vendored
 * island rather than ad-hoc script.
 *
 * WHAT IT DOES NOT DO. It never flips the open state itself: ESC is delegated
 * to the trigger's own click (the one htmx wiring), so there is exactly one
 * path that mutates drawer state and it is the server round-trip. It owns no
 * markup and no animation.
 *
 * WIRING. The trigger is `.dv-drawer-toggle` with aria-expanded and
 * aria-controls pointing at the drawer aside (tabindex="-1", focusable as a
 * region target). A trigger click arms an intent (opening/closing + which
 * drawer); htmx:afterSettle consumes it and moves focus. ESC anywhere inside
 * an open `.dv-reveal` clicks that drawer's trigger.
 */
(() => {
  'use strict';

  let pending = null; // { opening, id } — armed by a trigger click, consumed on settle

  const triggerFor = (id) =>
    document.querySelector('.dv-drawer-toggle[aria-controls="' + id + '"]');

  document.addEventListener('click', (e) => {
    const btn = e.target.closest && e.target.closest('.dv-drawer-toggle');
    if (!btn) return;
    pending = {
      opening: btn.getAttribute('aria-expanded') !== 'true',
      id: btn.getAttribute('aria-controls'),
    };
  });

  document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape') return;
    const wrap = e.target && e.target.closest && e.target.closest('.dv-reveal.is-open');
    if (!wrap) return;
    const aside = wrap.querySelector('.dv-drawer');
    const btn = aside && triggerFor(aside.id);
    if (btn) { e.stopPropagation(); btn.click(); }
  });

  document.addEventListener('htmx:afterSettle', () => {
    if (!pending) return;
    const p = pending;
    pending = null;
    if (p.opening) {
      const aside = document.getElementById(p.id);
      if (aside) aside.focus();
    } else {
      // Re-find the trigger: morph may have replaced the node.
      const btn = triggerFor(p.id);
      if (btn) btn.focus();
    }
  });
})();
