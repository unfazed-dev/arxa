/* flowwalk.js — the flow-walk island (ADR-0002 amendment 2026-08-02).
 *
 * WHY THIS EXISTS AT ALL. The design viewer's flows lens renders each flow as a
 * row of screen tiles. "Walking" a flow means: tap the thing the edge says
 * fires it (Continue on the auth screen) and watch the row's ACTIVE tile move
 * to the screen that edge points at. The tap happens inside a tile's iframe —
 * a separate document — and the row lives in the parent. A child document
 * cannot move the parent's state by ordinary markup, and ADR-0002 forbids
 * ad-hoc client JS, so this is a named, vendored island: the same sanctioned
 * escape `inspect.js` uses to pin an element to the parent's chat context.
 *
 * WHAT IT DOES NOT DO. It does not navigate the iframe. The whole point of the
 * walk is that the tile keeps showing the screen it is labelled with while the
 * ROW tracks position — so the in-frame navigation is suppressed and only the
 * parent re-renders. Letting the frame navigate too would show the destination
 * screen twice in the same row.
 *
 * WIRING. The stub renderer adds these when a tile is the current step:
 *   ?walk=<parent viewer URL to advance to>   (already a plain viewer GET)
 *   &walkel=<data-el value that fires the edge, may be empty>
 *   &walktrig=<the edge's prose trigger, the fallback matcher>
 * `walk` is a complete viewer URL rather than a set of parts, so this island
 * never has to know the viewer's param list — it hands the URL to the parent's
 * htmx untouched. Adding a viewer param cannot silently break the walk.
 *
 * MATCHING. `walkel` is the authored join to a data-el value and wins when
 * present. `walktrig` is prose written for a human ("continue" names an
 * element, "App launch" does not), so it is only ever a fuzzy fallback: an
 * unmatched click falls through to normal behaviour instead of guessing.
 */
(function () {
  'use strict';

  var qs = new URLSearchParams(location.search);
  var advance = qs.get('walk');
  if (!advance) return; // not a walked tile — this island stays inert

  var wantEl = (qs.get('walkel') || '').trim();
  var wantTrig = (qs.get('walktrig') || '').trim();

  // Compare on letters+digits only: "button:Continue" vs "continue" vs
  // "Continue with Apple" all normalise to something comparable, and the
  // authored casing/punctuation of either side stops mattering.
  function norm(s) {
    return (s || '').toLowerCase().replace(/[^a-z0-9]+/g, '');
  }

  // The data-el convention is "<kind>:<label>" (e.g. "button:Continue"), so the
  // label half is what a human-written trigger is most likely to echo.
  function label(v) {
    var i = (v || '').indexOf(':');
    return i === -1 ? v : v.slice(i + 1);
  }

  function fires(el) {
    var node = el && el.closest ? el.closest('[data-el]') : null;
    if (!node) return false;
    var v = node.getAttribute('data-el') || '';

    // Authored join: exact, on the whole value or its label half.
    if (wantEl) return norm(v) === norm(wantEl) || norm(label(v)) === norm(label(wantEl));

    // Fallback: the trigger is prose. Require one side to contain the other so
    // a short trigger ("continue") matches "button:Continue", while unrelated
    // pairs ("App launch" vs "button:Continue") do not. Guard the empty string
    // — "".includes("") is true and would match every element on the screen.
    var t = norm(wantTrig);
    var l = norm(label(v));
    if (!t || !l) return false;
    return l.indexOf(t) !== -1 || t.indexOf(l) !== -1;
  }

  document.addEventListener('click', function (e) {
    if (!fires(e.target)) return;
    e.preventDefault();
    e.stopPropagation();

    var p = window.parent;
    // No parent htmx means this stub is being viewed standalone (a direct hit
    // on /build/screens/... in a tab). Do nothing rather than throw: the walk
    // is a viewer affordance and has no meaning outside it.
    if (!p || p === window || !p.htmx) return;
    // No `select` here. inspect.js re-GETs the parent's whole page and selects
    // #panels out of it; this URL is the viewer route, which already returns
    // just the viewer fragment — asking for a DESCENDANT with that id finds
    // nothing and swaps nothing. Same shape as the tile toolbar's own links:
    // hx-target="#design-viewer" hx-swap="morph:outerHTML", no select.
    p.htmx.ajax('GET', advance, {
      target: '#design-viewer',
      swap: 'morph:outerHTML',
      // hx-sync="this:replace" on <body> aborts superseded XHRs; htmx rejects
      // the promise with undefined on abort. Real failures still log.
    }).catch((e) => { if (e !== undefined) console.error('appbox island htmx.ajax:', e); });
  }, true); // capture: beat the surface's own boosted link handler
})();
