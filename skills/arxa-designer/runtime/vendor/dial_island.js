/* dial_island.js — the Design Dial island (first-party, ADR-0002 form;
   locked amendment 2026-08-23: 'the feedback dial becomes the Design Dial').

   WHY THIS EXISTS. Every arxa artifact carries one floating control so the
   Author can adjust the design live and clients can leave feedback on the
   shared design. REWORK LOCKED 2026-08-24 (19 decisions, grilled): the dial
   does exactly three things — a 3-trigger radial fan (Edit / Comment /
   Studio); per-element editing happens in a floating smart CARD anchored to
   the clicked element (dropdown-style flip/clamp, capability matrix per
   element kind, live apply, draft auto-save); Studio opens the TRAY, a
   glass bottom sheet (translucent, blurred, moss accent glow, close button
   top-right, drag grabber + hairline divider + top bar with a contextual
   CTA) holding a native scroll-snap carousel of five slides: Edit (element
   outline + draft ledger, CTA Commit), Comments (pin board across routes,
   3-state lifecycle, CTA Share), Settings (environment & session), Tweak
   (theme tokens, motion, surface), Ship (branch/PR/gates autopilot, CTA
   Deploy — lands with slice 5/6). Pins keep W7 data-el identity, rect
   snapshots, orphan survival, threaded replies. The 6 displaced verbs
   (pen/shade/layers/share-as-verb/tokens/design-as-verb) are DELETED —
   their capabilities moved into the tray or died by operator decision.

   ISLAND SHAPE (per ADR-0002): one IIFE, no globals, no framework, no build
   step; configuration arrives in the injected #arxa-dial-config JSON script;
   it talks ONLY to this origin's /__dial/* endpoints. Everything renders
   inside a closed-ish shadow root so artifact styles can never restyle the
   dial and dial styles can never leak into the artifact. User-authored text
   (pin bodies, names, replies) is rendered with textContent only — never
   innerHTML.

   MODES. 'author' (no token on the URL — the loopback designer): full
   powers. 'guest' (a valid ?dial= token): comments only — the Comment.
   Arc 2: a PERSONAL ?dial= token additionally carries the registered
   guest identity (email) — attribution comes from the link, never a
   typed name, and revoking the guest deletes their email but keeps
   their feedback, de-attributed
   trigger and a Comments-only tray; no Edit, no Studio slides beyond
   Comments. 'invalid' (a dead token): the dock boots to say so, nothing
   else. The store badge reads 'local' when the server runs its memory
   store, so nobody mistakes process-local pins for durable ones.

   VISIBILITY LAW (operator, 2026-08-24; card amendment 2026-08-26). The
   dial is corner-pinned bottom-right, NOT draggable, and renders as a
   SQUARE ARXA CARD: the studio's moss gradient, an 'A' mark + wordmark at
   rest, flipping (animated) to the armed mode's face — Edit's icon while
   Edit Mode is armed, Comment's while pin-drop is armed; Studio has no
   face because the sheet swaps the dial out entirely. Hidden until the
   cursor enters a 50px hot
   corner; Apple-physics spring reveal; pointer-leave NEVER hides; the 30s
   timer is the ONLY tuck-away; never-hide while the fan is open, a mode is
   armed (Edit select / Comment pin-drop), the card is up, or inline text
   editing is active. THE TRAY SWAPS THE DIAL OUT: tray open → dial parks
   (spring) and the timer suspends; tray close → dial springs back in and
   the 30s timer re-arms fresh. The park pose is scoped to #dock only, and
   while the tray is open the corner reveal stays suspended (2026-08-26:
   a host-wide pose hid the open sheet with the dial). Sheet close closes
   its children — card + selection, thread popover, composer (2026-08-26):
   nothing floats on after the sheet.

   EDIT MODE (Author only). The Edit trigger arms selection: hover outlines
   the element under the cursor (data-arxa-id identity), click selects it
   and opens the floating smart card — the capability matrix per kind
   (content, curated facets, color swatches, CSS escape hatch), every edit
   applied LIVE and auto-saved (debounced) into the server-side Draft
   Overlay. Source is never touched by auto-save; guests always see the
   last published state. Commit (tray Edit slide CTA) hands the patch set
   to the studio agent over the dial event stream; the agent commits to
   source with `design patch` and clears the draft. */
(() => {
  if (document._arxaDial) return; // guard against double-include
  document._arxaDial = 1;

  const cfgEl = document.getElementById('arxa-dial-config');
  if (!cfgEl) return;
  let cfg;
  try {
    cfg = JSON.parse(cfgEl.textContent);
  } catch (_) {
    return;
  }

  // ── state ──────────────────────────────────────────────────────────────
  const S = {
    mode: cfg.mode, // 'author' | 'guest' | 'invalid'
    artifact: cfg.artifact,
    store: cfg.store, // 'memory' | 'supabase'
    axes: cfg.axes // the style/theme plane (arc 1): null = undeclared or kind-gated off
      ? {
          styles: cfg.axes.styles,
          themes: cfg.axes.themes || [],
          published: cfg.axes.published,
          current: cfg.axes.active,
        }
      : null,
    token: cfg.token || null,
    guest: cfg.guest || null, // arc 2: personal-link identity {email, name} — attribution by construction
    guests: null, // arc 2: author's roster cache (null = not loaded)
    pins: [],
    open: false, // radial fan expanded
    tray: null, // null | 'edit' | 'comments' | 'settings' | 'tweak' | 'ship'
    arming: false, // pin-placement armed
    activePin: null, // id whose thread popover is open
    name: '',
    dockSide: 'right',
    deployReady: false, // /ship/deploy/ready answer
    deployBlockers: [],
    design: false, // Edit Mode armed (author only)
    selected: null, // { id, el, label, group } — the element being edited
    selOutline: '', // inline outline the selection highlight borrowed
    draft: { tokens: {}, patches: {} }, // the Draft Overlay (server-side)
    draftWarnings: [], // preview-commit parity: el: keys whose name= is not exactly one source site
    draftDirty: false,
    ownSave: 0, // suppress refetch loops on our own PUT's broadcast
    inlineEditing: null, // original text of the element being edited on-canvas
    cardTab: 'customise', // the floating card's active tab
    cardTabs: {}, // per-element tab memory (key -> 'customise' | 'arxa')
    arxa: {}, // per-element handoff state (key -> {id, fetch, label, route,
    //   kind, group, png, text, status}) — survives card close in-session
  };
  try {
    S.name = localStorage.getItem('arxa-dial-name') || '';
  } catch (_) {}
  // A personal link IS the identity: the registry knows who this is, so
  // the guest is never asked for a name and their pins attribute by
  // construction (the server stamps it; a typed name cannot forge it).
  if (S.guest) S.name = S.guest.name || (S.guest.email.split('@')[0] || 'guest');

  const KANBAN = [
    ['open', 'Open'],
    ['resolved', 'Resolved'],
    ['wont_do', "Won't do"],
  ];

  // ── the shadow host ────────────────────────────────────────────────────
  const host = document.createElement('div');
  host.id = 'arxa-dial-host';
  host.style.cssText =
    'position:fixed;inset:0;z-index:2147483000;pointer-events:none;' +
    'font-family:ui-sans-serif,system-ui,sans-serif;';
  const root = host.attachShadow({ mode: 'open' });

  const CSS = [
    '*{box-sizing:border-box;margin:0;padding:0;font:inherit}',
    '.pe{pointer-events:auto}',
    'button{cursor:pointer;border:0;background:none;color:inherit}',
    /* pin badges */
    '#pins{position:fixed;inset:0;pointer-events:none}',
    '.pin{position:absolute;width:26px;height:26px;border-radius:50%;',
    '  background:#0891b2;color:#FFFCF0;font-size:12px;font-weight:700;',
    '  display:flex;align-items:center;justify-content:center;',
    '  box-shadow:0 1px 6px rgba(0,0,0,.35);pointer-events:auto;',
    '  transform:translate(-50%,-50%);border:2px solid #FFFCF0}',
    '.pin.resolved{opacity:.45}',
    '.pin.wontdo{opacity:.45;text-decoration:line-through}',
    '.pin.orphan{background:#8a8f98;border-style:dashed}',
    '.pin.active{outline:3px solid #f59e0b}',
    '.pin.drawn::after{content:"✎";position:absolute;bottom:-6px;right:-6px;',
    '  font-size:9px;background:#f59e0b;color:#0b0b10;border-radius:6px;',
    '  padding:0 3px;font-weight:800}',
    /* the hover highlight while arming */
    '#hover{position:fixed;border:2px solid #0891b2;border-radius:4px;',
    '  background:rgba(8,145,178,.12);pointer-events:none;display:none}',
    '#hovertag{position:absolute;top:-22px;left:-2px;background:#0891b2;',
    '  color:#FFFCF0;font-size:11px;padding:2px 7px;border-radius:3px;',
    '  white-space:nowrap;font-weight:600}',
    /* the dock: a square ARXA CARD (operator, 2026-08-26) — the arxa
       studio moss gradient, an 'A' mark + wordmark at rest, and the armed
       mode's icon while Edit or Comment is active. Studio needs no face:
       the sheet swaps the dial out entirely. Brand ramp ground-truthed
       from arxa-studio plugins/brand + gen-ui: rgb(139,165,101) accent,
       rgb(106,133,74) the favicon field, off-white rgb(243,246,238). */
    '#dock{position:fixed;bottom:20px;right:20px;width:64px;height:64px;',
    '  pointer-events:auto;touch-action:none;z-index:10}',
    '#dockbtn{position:relative;width:64px;height:64px;border-radius:14px;',
    '  background:linear-gradient(135deg,rgb(139,165,101) 0%,',
    '  rgb(106,133,74) 55%,rgb(64,80,44) 100%);color:rgb(243,246,238);',
    '  box-shadow:0 6px 20px rgba(0,0,0,.42);',
    '  border:1px solid rgba(227,238,222,.4);',
    '  transition:transform .15s ease,box-shadow .25s ease}',
    '#dockbtn:hover{transform:scale(1.05)}',
    '#dockbtn[data-mode]{box-shadow:0 6px 20px rgba(0,0,0,.42),',
    '  0 0 18px -5px rgb(122,149,87)}',
    '#dockbtn .face{position:absolute;inset:0;display:flex;flex-direction:column;',
    '  align-items:center;justify-content:center;gap:1px;',
    '  transition:opacity .2s ease,transform .3s cubic-bezier(.34,1.56,.64,1)}',
    '#dockbtn .face .mark{font-size:22px;font-weight:800;line-height:1}',
    '#dockbtn .face .word{font-size:9.5px;font-weight:700;letter-spacing:.12em}',
    '#dockbtn .face svg{width:20px;height:20px}',
    '#dockbtn .face .mlabel{font-size:9px;font-weight:700;letter-spacing:.06em}',
    '#dockbtn .face.mode{opacity:0;transform:translateY(9px) scale(.7);',
    '  pointer-events:none}',
    '#dockbtn[data-mode="edit"] .face.edit{opacity:1;transform:none}',
    '#dockbtn[data-mode="comment"] .face.comment{opacity:1;transform:none}',
    '#dockbtn[data-mode] .face.rest{opacity:0;transform:translateY(-9px) scale(.7)}',
    '#dockbtn .dot{position:absolute;top:-3px;right:-3px;min-width:20px;',
    '  height:20px;border-radius:10px;background:#f59e0b;color:#0b0b10;',
    '  font-size:11px;font-weight:800;display:flex;align-items:center;',
    '  justify-content:center;padding:0 5px}',
    /* the radial fan — same treatment as the card (operator, 2026-08-26):
       square, card radius, the arxa moss gradient. The armed verb keeps
       the gradient and lights up (glow + brighter border) instead of the
       old solid teal. */
    '.verb{position:absolute;left:50%;top:50%;width:44px;height:44px;',
    '  border-radius:10px;background:linear-gradient(135deg,rgb(139,165,101),',
    '  rgb(106,133,74) 60%,rgb(64,80,44));color:rgb(243,246,238);',
    '  border:1px solid rgba(227,238,222,.4);display:flex;align-items:center;',
    '  justify-content:center;box-shadow:0 2px 10px rgba(0,0,0,.4);',
    '  transform:translate(-50%,-50%) scale(0);opacity:0;',
    '  transition:transform .22s cubic-bezier(.34,1.56,.64,1),opacity .18s}',
    '.verb svg{width:20px;height:20px}',
    '.verb.on{border-color:rgba(243,246,238,.8);',
    '  box-shadow:0 2px 10px rgba(0,0,0,.4),0 0 14px -3px rgb(122,149,87)}',
    '#dock.open .verb{transform:translate(-50%,-50%) scale(1);opacity:1;',
    '  transition-delay:calc(var(--i,0)*40ms)}',
    '.verb .tip{position:absolute;right:52px;top:50%;',
    '  transform:translateY(-50%);background:#0b0b10;color:#FFFCF0;',
    '  font-size:11px;padding:3px 8px;border-radius:4px;white-space:nowrap;',
    '  opacity:0;pointer-events:none;transition:opacity .15s}',
    '.verb:hover .tip{opacity:1}',
    '#dock.left .verb .tip{right:auto;left:52px}',
    '@media (prefers-reduced-motion:reduce){.verb{transition:none!important}',
    '  #dock.open .verb{transition-delay:0s!important}}',
    ':host(.nomotion) *{transition:none!important;animation:none!important}',
    /* the tray (glass bottom sheet — 19-decision rework 2026-08-24) */
    '#tray{position:fixed;left:0;right:0;bottom:0;z-index:25;display:none;',
    '  flex-direction:column;pointer-events:auto;color:#FFFCF0;',
    '  background:rgba(20,20,28,var(--tint,.82));',
    '  backdrop-filter:blur(var(--tblur,16px)) saturate(1.4);',
    '  -webkit-backdrop-filter:blur(var(--tblur,16px)) saturate(1.4);',
    '  border:1px solid rgba(110,136,76,.45);',
    '  border-radius:var(--trayrad,16px) var(--trayrad,16px) 0 0;',
    '  box-shadow:0 -1px 0 rgba(110,136,76,.55),',
    '    0 -14px 56px rgba(110,136,76,var(--glow,.22)),',
    '    0 -24px 64px rgba(0,0,0,.5);max-height:70vh}',
    '#tray.open{display:flex}',
    '#grabber{display:flex;justify-content:center;padding:8px 0 4px;',
    '  cursor:grab;touch-action:none}',
    '#grabber .gbar{width:40px;height:4px;border-radius:2px;',
    '  background:#3a3a46}',
    '#tbar{display:flex;align-items:center;gap:10px;padding:6px 14px 10px;',
    '  border-bottom:1px solid rgba(110,136,76,.28);flex:none}',
    '#ttitle{font-size:13px;font-weight:700}',
    '#dots{display:flex;gap:6px;margin:0 auto}',
    '.dotbtn{width:8px;height:8px;border-radius:5px;background:#9aa0ab;',
    '  opacity:.4;padding:0;transition:all .18s}',
    '.dotbtn.cur{opacity:1;width:20px;background:#8fb35a}',
    '.dotbtn:focus-visible{outline:2px solid #8fb35a;outline-offset:2px}',
    '#track:focus-visible{outline:1px solid rgba(143,179,90,.7);',
    '  outline-offset:-1px}',
    '#cta{background:#6e884c;color:#0b0b10;font-weight:700;font-size:12px;',
    '  padding:6px 12px;border-radius:8px}',
    '#cta:disabled{opacity:.4;cursor:not-allowed}',
    '#cta.off{display:none}',
    '#tclose{width:28px;height:28px;border-radius:50%;background:#2a2a35;',
    '  color:#FFFCF0;font-size:14px;line-height:1;display:flex;',
    '  align-items:center;justify-content:center}',
    '#track{display:flex;overflow-x:auto;overflow-y:hidden;',
    '  scroll-snap-type:x mandatory;scrollbar-width:none;',
    '  overscroll-behavior-x:contain}',
    '#track::-webkit-scrollbar{display:none}',
    '.slide{flex:0 0 100%;scroll-snap-align:center;overflow-y:auto;',
    '  overscroll-behavior:contain;padding:10px 14px 16px;min-height:200px;',
    '  scrollbar-width:thin;scrollbar-color:rgba(110,136,76,.5) transparent}',
    /* Sheet scrollbars in phase with the sheet (operator, 2026-08-25):
       the track is NOTHING (the glass shows through); the thumb carries
       the sheet's own accent — moss at half opacity over the dark glass,
       solid moss on hover. Scoped to the tray so the page's own
       scrollbars are untouched. */
    '#tray ::-webkit-scrollbar{width:6px;height:6px}',
    '#tray ::-webkit-scrollbar-track{background:transparent}',
    '#tray ::-webkit-scrollbar-thumb{background:rgba(110,136,76,.5);',
    '  border-radius:3px}',
    '#tray ::-webkit-scrollbar-thumb:hover{background:rgba(110,136,76,.8)}',
    '@media (min-width:640px){#tray{left:24px;right:24px;margin:0 auto;',
    '  max-width:720px;border-radius:var(--trayrad,16px);',
    '  max-height:65vh;bottom:20px}}',
    '@media (min-width:1024px){#tray{max-width:880px;max-height:60vh}',
    '  .slide{flex-basis:calc(100% - 96px)}}',
    '@media (prefers-reduced-transparency:reduce){#tray{',
    '  background:#14141c;backdrop-filter:none;-webkit-backdrop-filter:none}',
    '  #card{background:rgb(106,133,74)}}',
    '@media (prefers-reduced-motion:reduce){#track{scroll-behavior:auto}}',
    /* the floating smart card — a card of the studio now (operator,
       2026-08-26): the same arxa moss gradient the dock card won, the
       off-white brand text, and a header that doubles as a grab handle
       (drag law below). No more glass: the gradient is opaque, so the
       blur/tint glass retired with the old background. */
    '#card{position:fixed;width:300px;z-index:26;display:none;',
    '  flex-direction:column;pointer-events:auto;color:rgb(243,246,238);',
    '  background:linear-gradient(135deg,rgb(139,165,101) 0%,',
    '  rgb(106,133,74) 55%,rgb(64,80,44) 100%);',
    '  border:1px solid rgba(227,238,222,.4);border-radius:12px;',
    '  box-shadow:0 12px 40px rgba(0,0,0,.5),',
    '    0 0 32px rgba(110,136,76,var(--glow,.22));',
    /* fixed dimensions law (operator, 2026-08-26): the card is one
       constant size — it never grows or shrinks between tabs, states,
       or content; the body alone scrolls inside the fixed frame. */
    '  height:min(440px,62vh)}',
    '#card.open{display:flex}',
    '#chead{display:flex;align-items:center;gap:6px;padding:8px 10px;',
    '  border-bottom:1px solid rgba(43,54,29,.35);flex:none;',
    '  cursor:grab;user-select:none;-webkit-user-select:none;touch-action:none}',
    '#chead:active{cursor:grabbing}',
    '#chead button{cursor:pointer}',
    /* the tab pair (operator, 2026-08-26): Customise + Arxa left, ×
       right; the whole bar stays the drag handle and buttons never
       start a drag (the closest('button') guard in the pointerdown). */
    '#chead .tab{font-size:11.5px;font-weight:700;padding:5px 10px;',
    '  border-radius:8px;background:transparent;color:rgba(243,246,238,.72);',
    '  border:1px solid transparent}',
    '#chead .tab.on{background:rgba(243,246,238,.16);color:rgb(243,246,238);',
    '  border-color:rgba(227,238,222,.35)}',
    /* the identity row: element label + kind chip + idline, shared by
       both tabs, fixed above the scrolling body (the header is tabs). */
    '#cidrow{display:flex;align-items:center;gap:8px;padding:9px 12px 0;',
    '  flex:none;font-size:12.5px;font-weight:700;flex-wrap:wrap}',
    '#cidrow .kchip{font-size:9.5px;font-weight:700;text-transform:uppercase;',
    '  letter-spacing:.04em;background:rgba(243,246,238,.16);',
    '  color:rgba(243,246,238,.85);padding:2px 7px;border-radius:8px}',
    '#cidrow .idline{flex-basis:100%;margin-top:-2px}',
    /* the bottom CTA bar (operator, 2026-08-26): fixed like the top
       bar, per-tab actions; the body alone scrolls. */
    '#cfoot{display:flex;gap:8px;align-items:center;padding:10px 12px;',
    '  border-top:1px solid rgba(43,54,29,.35);flex:none}',
    '#cfoot .btn{flex:none}',
    '.tabpane{display:none}',
    '.tabpane.on{display:block}',
    '.arxaid{font-size:11px;font-weight:700;color:rgba(243,246,238,.85)}',
    '.arxaline{font-size:10.5px;color:rgba(243,246,238,.78);',
    '  padding:2px 10px;line-height:1.45}',
    '.arxastatus{font-size:11px;font-weight:700;padding:6px 10px;',
    '  border-radius:8px;background:rgba(243,246,238,.12);margin:6px 10px}',
    '.arxastatus.ok{background:rgba(43,54,29,.45)}',
    '#chead .kchip{font-size:9.5px;font-weight:700;text-transform:uppercase;',
    '  letter-spacing:.04em;background:#2a2a35;color:#9aa0ab;',
    '  padding:2px 7px;border-radius:8px}',
    '#chead .cclose{background:#2a2a35;color:#FFFCF0;',
    '  width:22px;height:22px;border-radius:50%;font-size:12px;',
    '  line-height:1;display:flex;align-items:center;justify-content:center}',
    /* the track-back button (operator, 2026-08-26): one tap returns
       the author to the selected element — scrolled away on this page
       or stranded by a boosted navigation to another route. It takes
       the right-push; the close button sits beside it. */
    '#chead .cgo{margin-left:auto;background:transparent;',
    '  color:rgba(243,246,238,.72);width:22px;height:22px;border-radius:50%;',
    '  display:flex;align-items:center;justify-content:center;padding:0}',
    '#chead .cgo svg{width:13px;height:13px}',
    '#chead .cgo:hover{background:rgba(243,246,238,.16);color:rgb(243,246,238)}',
    '.cbody{overflow-y:auto;overscroll-behavior:contain;flex:1;',
    '  scrollbar-width:thin;scrollbar-color:rgba(43,54,29,.55) transparent}',
    '.row{padding:8px 10px;border-radius:8px;cursor:pointer;',
    '  border:1px solid transparent;margin-bottom:4px}',
    '.row:hover{background:#1d1d27}',
    '.row.active{border-color:#0891b2;background:#1d1d27}',
    '.row .txt{font-size:12.5px;line-height:1.35;display:block}',
    '.row .meta{display:flex;gap:6px;align-items:center;margin-top:5px;',
    '  font-size:10.5px;color:#9aa0ab}',
    /* on the moss card, chrome must read against green (operator,
       2026-08-26): the dark-panel greys (#9aa0ab, #1d1d27, cyan) belong
       to #thread/#composer — the card re-skins its rows and secondary
       text in translucent off-whites so nothing goes grey-on-moss. */
    '#card .row:hover{background:rgba(243,246,238,.14)}',
    '#card .row.active{border-color:rgba(243,246,238,.75);',
    '  background:rgba(243,246,238,.1)}',
    '#card .row .meta,#card .sect,#card .facet label,',
    '  #card .draftmeta{color:rgba(243,246,238,.78)}',
    '#card .idline{color:rgba(243,246,238,.6)}',
    /* card scrollbars in phase with the moss card (operator, 2026-08-26):
       the track is NOTHING (the gradient shows through); the thumb is
       DEEP moss — moss-on-moss, never grey-on-moss — darkening on
       hover. The tray keeps its own glass-phase law above. */
    '#card ::-webkit-scrollbar{width:6px;height:6px}',
    '#card ::-webkit-scrollbar-track{background:transparent}',
    '#card ::-webkit-scrollbar-thumb{background:rgba(43,54,29,.55);',
    '  border-radius:3px}',
    '#card ::-webkit-scrollbar-thumb:hover{background:rgba(43,54,29,.8)}',
    '.chip{font-size:10px;font-weight:700;padding:2px 7px;border-radius:8px;',
    '  text-transform:uppercase;letter-spacing:.03em}',
    '.chip.open{background:#7c2d12;color:#ffd9c2}',
    '.chip.resolved{background:#14532d;color:#bbf7d0}',
    '.chip.wontdo{background:#3f3f46;color:#d4d4d8}',
    '.orphan-tag{color:#f59e0b;font-weight:700}',
    /* thread popover */
    '#thread{position:fixed;width:300px;background:#14141c;color:#FFFCF0;',
    '  border-radius:12px;border:1px solid #2a2a35;padding:12px;',
    '  box-shadow:0 12px 40px rgba(0,0,0,.55);display:none;',
    '  pointer-events:auto;z-index:20}',
    '#thread.open{display:block}',
    '#thread .body{font-size:13px;line-height:1.45;margin:6px 0 10px}',
    '#thread .ctx,#composer .ctx{margin:-4px 0 10px;padding:6px 10px;font-size:11px;',
    '  line-height:1.45;font-style:italic;color:#b9c2cf;',
    '  border-left:2px solid #8fb35a;background:rgba(255,255,255,.04);',
    '  border-radius:0 6px 6px 0;max-height:72px;overflow-y:auto;',
    '  white-space:pre-wrap;word-break:break-word}',
    '#thread .who{font-size:11px;color:#9aa0ab}',
    '#thread .replies{max-height:140px;overflow-y:auto;margin:8px 0;',
    '  border-top:1px solid #2a2a35;padding-top:8px}',
    '#thread .reply{font-size:12px;margin-bottom:6px;line-height:1.4}',
    '#thread .reply .who{margin-right:5px}',
    '#statusrow{display:flex;gap:4px;flex-wrap:wrap;margin:8px 0}',
    '.stbtn{font-size:10px;font-weight:700;padding:4px 8px;border-radius:8px;',
    '  background:#2a2a35;color:#9aa0ab;text-transform:uppercase}',
    '.stbtn.cur{background:#0891b2;color:#FFFCF0}',
    'textarea,input[type=text]{width:100%;background:#0b0b10;color:#FFFCF0;',
    '  border:1px solid #2a2a35;border-radius:8px;padding:8px;font-size:12.5px;',
    '  resize:vertical;outline:none;font-family:inherit}',
    'textarea:focus,input[type=text]:focus{border-color:#0891b2}',
    '.btn{background:#0891b2;color:#FFFCF0;font-weight:700;font-size:12px;',
    '  padding:8px 14px;border-radius:8px}',
    '.btn.ghost{background:#2a2a35}',
    '.btnrow{display:flex;gap:8px;margin-top:8px;justify-content:flex-end}',
    /* the composer (new pin) */
    '#composer{position:fixed;width:280px;background:#14141c;color:#FFFCF0;',
    '  border-radius:12px;border:1px solid #0891b2;padding:12px;',
    '  box-shadow:0 12px 40px rgba(0,0,0,.55);display:none;',
    '  pointer-events:auto;z-index:30}',
    '#composer.open{display:block}',
    /* the axes plane: segmented pickers + the persistent preview badge */
    '.seg{display:flex;flex-wrap:wrap;gap:6px;margin:8px 0 4px}',
    '.seg button{padding:6px 14px;border-radius:999px;border:1px solid rgba(255,255,255,.16);background:rgba(255,255,255,.06);color:#e8ebf0;font:600 12px inherit;cursor:pointer}',
    '.seg button.on{background:rgba(110,136,76,.85);border-color:rgba(110,136,76,.9);color:#f4f7ee}',
    '.pvnote{display:flex;align-items:center;gap:10px;margin-top:12px;padding:8px 12px;border-radius:10px;background:rgba(243,180,76,.12);border:1px solid rgba(243,180,76,.4);color:#e8c98a;font-size:12px}',
    '.pvnote button{margin-left:auto;padding:4px 10px;border-radius:8px;border:1px solid rgba(243,180,76,.5);background:transparent;color:#e8c98a;cursor:pointer;white-space:nowrap}',
    '#dock.previewing #dockbtn{outline:2px solid rgba(243,180,76,.9);outline-offset:2px;border-radius:14px}',
    /* control rows (tray slides + card) */
    '.ctl{display:flex;align-items:center;gap:10px;padding:10px 12px;',
    '  font-size:12.5px}',
    '.ctl input[type=range]{flex:1;accent-color:#0891b2}',
    '.switch{margin-left:auto;position:relative;width:36px;height:20px;',
    '  background:#2a2a35;border-radius:10px;transition:background .15s}',
    '.switch.on{background:#0891b2}',
    '.switch::after{content:"";position:absolute;top:2px;left:2px;width:16px;',
    '  height:16px;border-radius:50%;background:#FFFCF0;transition:left .15s}',
    '.switch.on::after{left:18px}',
    '.linkbox{word-break:break-all;font-size:11px;background:#0b0b10;',
    '  border:1px solid #2a2a35;border-radius:8px;padding:8px;margin-top:8px}',
    '#toast{position:fixed;bottom:96px;left:50%;transform:translateX(-50%);',
    '  background:#0b0b10;color:#FFFCF0;font-size:12.5px;padding:10px 16px;',
    '  border-radius:10px;border:1px solid #0891b2;opacity:0;',
    '  transition:opacity .2s;pointer-events:none;z-index:40}',
    /* Design Mode: selection hover tint, facet editors, token rows */
    '#hover.design{border-color:#f59e0b;background:rgba(245,158,11,.12)}',
    '#hover.design #hovertag{background:#f59e0b;color:#0b0b10}',
    '.sect{font-size:10.5px;font-weight:700;color:#9aa0ab;padding:10px 10px 4px;',
    '  text-transform:uppercase;letter-spacing:.05em}',
    '.idline{font-family:ui-monospace,monospace;font-size:10px;color:#6b7280;',
    '  padding:2px 10px 8px;word-break:break-all}',
    '.facet{display:flex;align-items:center;gap:8px;padding:4px 10px}',
    '.facet label{width:92px;color:#9aa0ab;font-size:11px;flex:none}',
    '.facet input[type=text]{flex:1;padding:5px 8px;font-size:12px}',
    '.facet input[type=color]{width:28px;height:26px;padding:0;flex:none;',
    '  border:1px solid #2a2a35;border-radius:6px;background:#0b0b10}',
    '.facet select{flex:1;background:#0b0b10;color:#FFFCF0;',
    '  border:1px solid #2a2a35;border-radius:8px;padding:5px;font-size:12px}',
    '.draftmeta{font-size:10.5px;color:#6b7280;padding:8px 10px 0}',
    /* Design Mode direct manipulation: resize handles on the selection and
       the inline text-editing cue (locked decision 2). Handles live in the
       shadow root so the design can never restyle them and the selection
       walk never picks them (host children are skipped). */
    '#handles{position:fixed;inset:0;pointer-events:none;z-index:15}',
    '.hnd{position:absolute;width:10px;height:10px;background:#f59e0b;',
    '  border:2px solid #0b0b10;border-radius:2px;pointer-events:auto;',
    '  transform:translate(-50%,-50%);box-shadow:0 1px 4px rgba(0,0,0,.4)}',
    '.hnd[data-d=n]{cursor:n-resize}.hnd[data-d=s]{cursor:s-resize}',
    '.hnd[data-d=e]{cursor:e-resize}.hnd[data-d=w]{cursor:w-resize}',
    '.hnd[data-d=ne]{cursor:ne-resize}.hnd[data-d=sw]{cursor:sw-resize}',
    '.hnd[data-d=nw]{cursor:nw-resize}.hnd[data-d=se]{cursor:se-resize}',
    '[data-arxa-inline-editing]{outline:2px dashed #f59e0b !important;',
    '  cursor:text;caret-color:#f59e0b}',
  ];
  const style = document.createElement('style');
  style.textContent = CSS.join('\n');
  root.appendChild(style);

  // ── tiny DOM helper: text is textContent, always ───────────────────────
  function h(tag, attrs, kids) {
    const el = document.createElement(tag);
    if (attrs) {
      for (const k in attrs) {
        if (k === 'class') el.className = attrs[k];
        else if (k === 'text') el.textContent = attrs[k];
        else el.setAttribute(k, attrs[k]);
      }
    }
    for (const kid of kids || []) {
      if (kid) el.appendChild(kid);
    }
    return el;
  }

  // ── API ────────────────────────────────────────────────────────────────
  function apiUrl(sub) {
    return '/__dial' + sub + (S.token ? '?dial=' + encodeURIComponent(S.token) : '');
  }
  async function api(method, sub, body) {
    // Never throw: a transient network failure must surface as the caller's
    // error path (toast, composer stays open), not as an unhandled rejection
    // that leaves the verb silently stuck (smoke S9a: mint died mid-flight
    // and the button read 'Minting…' forever). Every caller already guards
    // on the fields it needs, so null degrades cleanly everywhere.
    try {
      const res = await fetch(apiUrl(sub), {
        method,
        headers: body ? { 'Content-Type': 'application/json' } : undefined,
        body: body ? JSON.stringify(body) : undefined,
      });
      return await res.json();
    } catch (_) {
      return null;
    }
  }
  // One read in flight at a time: pins SSE frames can land while a previous
  // read is still out, and stacked reads multiply connection pressure for no
  // newer truth (the server broadcasts on mutations only — a read loop here
  // once kept every rung's socket pool busy enough to starve edits).
  let pinsLoading = false;
  async function loadPins() {
    if (pinsLoading) return;
    pinsLoading = true;
    try {
      const r = await api('GET', '/pins');
      if (r && r.pins) {
        S.pins = r.pins;
        renderPins();
        if (S.tray === 'comments') renderTraySlide('comments');
        updateBadge();
      }
    } finally {
      pinsLoading = false;
    }
  }

  // ── layer hosts ────────────────────────────────────────────────────────
  const pinsLayer = h('div', { id: 'pins' });
  const hover = h('div', { id: 'hover' }, [h('span', { id: 'hovertag' })]);
  root.appendChild(pinsLayer);
  root.appendChild(hover);

  // ── the dock (radial, draggable, edge-snapping) ───────────────────────
  const ICONS = {
    dial: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="3" fill="currentColor"/><line x1="12" y1="3" x2="12" y2="7"/><line x1="12" y1="17" x2="12" y2="21"/><line x1="3" y1="12" x2="7" y2="12"/><line x1="17" y1="12" x2="21" y2="12"/></svg>',
    pin: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 21s-7-6.1-7-11a7 7 0 0 1 14 0c0 4.9-7 11-7 11z"/><circle cx="12" cy="10" r="2.5"/></svg>',
    list: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="8" y1="6" x2="21" y2="6"/><line x1="8" y1="12" x2="21" y2="12"/><line x1="8" y1="18" x2="21" y2="18"/><circle cx="4" cy="6" r="1.4" fill="currentColor"/><circle cx="4" cy="12" r="1.4" fill="currentColor"/><circle cx="4" cy="18" r="1.4" fill="currentColor"/></svg>',
    share: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="18" cy="5" r="3"/><circle cx="6" cy="12" r="3"/><circle cx="18" cy="19" r="3"/><line x1="8.6" y1="10.7" x2="15.4" y2="6.3"/><line x1="8.6" y1="13.3" x2="15.4" y2="17.7"/></svg>',
    design: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 4l7 17 2.5-6.5L20 12z"/><path d="M13.5 14.5 19 20"/></svg>',
    comment: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>',
    studio: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="4" y1="21" x2="4" y2="14"/><line x1="4" y1="10" x2="4" y2="3"/><line x1="12" y1="21" x2="12" y2="12"/><line x1="12" y1="8" x2="12" y2="3"/><line x1="20" y1="21" x2="20" y2="16"/><line x1="20" y1="12" x2="20" y2="3"/><line x1="1" y1="14" x2="7" y2="14"/><line x1="9" y1="8" x2="15" y2="8"/><line x1="17" y1="16" x2="23" y2="16"/></svg>',
  };
  function icon(name) {
    const span = document.createElement('span');
    span.innerHTML = ICONS[name];
    return span;
  }

  const dock = h('div', { id: 'dock' });
  // The card's faces (operator, 2026-08-26): rest = the arxa mark +
  // wordmark; a mode face per armed trigger (Edit / Comment). Arming
  // flips the card through data-mode; disarming returns the brand face.
  const restFace = h('div', { class: 'face rest' }, [
    h('span', { class: 'mark', text: 'A' }),
    h('span', { class: 'word', text: 'arxa' }),
  ]);
  const editFace = h('div', { class: 'face mode edit' }, [
    icon('design'),
    h('span', { class: 'mlabel', text: 'Edit' }),
  ]);
  const commentFace = h('div', { class: 'face mode comment' }, [
    icon('comment'),
    h('span', { class: 'mlabel', text: 'Comment' }),
  ]);
  const dockBtn = h(
    'button',
    { id: 'dockbtn', title: 'Design Dial', 'aria-label': 'Design Dial — arxa' },
    [restFace, editFace, commentFace],
  );
  const badge = h('span', { class: 'dot', text: '0' });
  badge.style.display = 'none';
  dockBtn.appendChild(badge);
  dock.appendChild(dockBtn);
  root.appendChild(dock);
  function setDockMode(m) {
    if (m) dockBtn.setAttribute('data-mode', m);
    else dockBtn.removeAttribute('data-mode');
  }

  // Radial triggers (rework 2026-08-24): exactly three — Edit arms
  // selection, Comment arms pin-drop, Studio opens the tray. Guests get
  // Comment + Studio(Comments-only tray); Edit is author-only.
  const VERBS = [
    { id: 'edit', icon: 'design', tip: 'Edit — select & adjust elements', modes: ['author'] },
    { id: 'comment', icon: 'comment', tip: 'Comment — drop a pin', modes: ['author', 'guest'] },
    { id: 'studio', icon: 'studio', tip: 'Studio — open the tray', modes: ['author', 'guest'] },
  ];
  const verbEls = {};
  const verbOrder = [];
  VERBS.forEach((v, i) => {
    if (v.modes.indexOf(S.mode) === -1) return;
    const el = h('button', { class: 'verb', 'data-verb': v.id, title: v.tip }, [
      icon(v.icon),
      h('span', { class: 'tip', text: v.tip }),
    ]);
    el.addEventListener('click', (e) => {
      e.stopPropagation();
      onVerb(v.id, el);
    });
    verbEls[v.id] = el;
    verbOrder.push(el);
    dock.appendChild(el);
  });

  // Boot truth: a URL override already rendered by the server lights the
  // preview badge immediately — no flip needed.
  if (S.axes) updatePreviewMark();
  // The fan biases AWAY from the docked edge: right-docked fans up-left
  // (-175°..-85°), left-docked fans up-right (-95°..-5°) — verbs never clip
  // off-screen. Re-runs on every edge snap.
  function layoutFan() {
    const n = verbOrder.length;
    // SQUARE-ERA GEOMETRY (operator, 2026-08-26, three rounds):
    //   R1 "recalculate the radius": positions were PERCENT of the dock
    //      box (R*100/56 % — /56 hardcoded the round 56px dock; the 64px
    //      card silently stretched R=75 to 86). Offsets are now
    //      PIXEL-exact calc(50% ± Npx) — dock-size-independent.
    //   R2: the chord law ("44px chords exactly") was a CIRCLE law.
    //      R = (BTN+GAP)/(2·sin(spacing/2)) guaranteed center distance,
    //      but squares approach CORNER-TO-CORNER diagonally: at 34° the
    //      Comment↔Studio rect gap measured 0px — touching, the
    //      operator's "studio and comments are too close" report.
    //   R3 (this): the law is now the operator-visible one — the VISIBLE
    //      gap between neighbor bounding boxes must be >= GAP — and R is
    //      SOLVED for it (binary search; no closed form exists for the
    //      piecewise rect distance). Spacing widens 34° -> 38° so the
    //      arc spreads instead of the radius ballooning: solver says
    //      R≈94 gives 8.5px+ gaps for 3 verbs. Kept honest by
    //      lens_dial_card_probe (asserts dists AND rect gaps).
    const BTN = 44; // square verb side (keep in phase with .verb CSS)
    const GAP = 8; // visible clearance required between neighbor squares
    const full = n > 7;
    const spacing = n <= 3 ? 38 : full ? 13.5 : 17;
    const start = S.dockSide === 'right' ? -178 : -2 - (n - 1) * spacing;
    // rect gap between two BTN-square verbs at angles a1,a2 on radius r
    const rectGap = (r, a1, a2) => {
      const x1 = r * Math.cos(a1), y1 = r * Math.sin(a1);
      const x2 = r * Math.cos(a2), y2 = r * Math.sin(a2);
      const dx = Math.max(x1 - BTN / 2 - (x2 + BTN / 2), x2 - BTN / 2 - (x1 + BTN / 2));
      const dy = Math.max(y1 - BTN / 2 - (y2 + BTN / 2), y2 - BTN / 2 - (y1 + BTN / 2));
      return Math.hypot(Math.max(dx, 0), Math.max(dy, 0));
    };
    const worstGap = (r) => {
      let m = Infinity;
      for (let i = 0; i + 1 < n; i++) {
        const a1 = ((start + i * spacing) * Math.PI) / 180;
        const a2 = ((start + (i + 1) * spacing) * Math.PI) / 180;
        m = Math.min(m, rectGap(r, a1, a2));
      }
      return m; // Infinity when n < 2
    };
    var R = 75;
    if (n > 1) {
      let lo = 75, hi = 190; // reach budget: verbs stay near the card
      if (worstGap(lo) < GAP) {
        for (let k = 0; k < 24; k++) { // binary search the minimal R
          const mid = (lo + hi) / 2;
          if (worstGap(mid) < GAP) lo = mid; else hi = mid;
        }
        R = hi;
      }
    }
    if (full) R = Math.max(R, 95); // the 8-verb fan keeps its reach
    verbOrder.forEach((el, i) => {
      const rad = ((start + i * spacing) * Math.PI) / 180;
      el.style.left = 'calc(50% + ' + (Math.cos(rad) * R).toFixed(1) + 'px)';
      el.style.top = 'calc(50% + ' + (Math.sin(rad) * R).toFixed(1) + 'px)';
      // Stagger index: the OPEN state delays each verb by --i * 40ms
      // (MDN transition-delay: the wait between a value change and the
      // transition start). The closed state keeps the base 0s delay so
      // the fan collapses as one, not in sequence.
      el.style.setProperty('--i', String(i));
    });
  }
  layoutFan();

  function updateBadge() {
    const open = S.pins.filter((p) => p.status === 'open').length;
    badge.textContent = String(open);
    badge.style.display = open ? 'flex' : 'none';
  }

  // The dial is NOT draggable (operator law, 2026-08-24): it lives in the
  // bottom-right corner, period. The fan toggles on 'click' - a keyboard or
  // synthetic click (no pointer events at all) must still open it.
  {
    dockBtn.addEventListener('click', () => {
      S.open = !S.open;
      dock.classList.toggle('open', S.open);
      dialPanelChanged(); // fan open: freeze hiding; fan closed: re-arm 30s
    });
  }

  // ── toast ──────────────────────────────────────────────────────────────
  const toast = h('div', { id: 'toast' });
  root.appendChild(toast);
  let toastTimer = null;
  function say(msg) {
    toast.textContent = msg;
    toast.style.opacity = '1';
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => {
      toast.style.opacity = '0';
    }, 2600);
  }

  // ── comments board (tray slide body) ───────────────────────────────────
  function chip(status) {
    return h('span', {
      class: 'chip ' + status.replace('_', ''),
      text: (KANBAN.find((k) => k[0] === status) || ['?', status])[1],
    });
  }

  function renderCommentsBody(body) {
    const route = location.pathname;
    if (S.mode === 'author') ensureGuestShareUI(body, false);
    const here = S.pins.filter((p) => p.route === route);
    const elsewhere = S.pins.filter((p) => p.route !== route);
    if (!S.pins.length) {
      body.appendChild(
        h('div', { class: 'ctl', text: 'No pins yet — tap the Comment trigger and click the design.' }),
      );
      return;
    }
    const section = (title, list) => {
      if (!list.length) return;
      if (title) {
        body.appendChild(
          h('div', {
            class: 'ctl',
            text: title,
            style: 'color:#9aa0ab;font-size:11px;padding:6px 10px 2px',
          }),
        );
      }
      list.forEach((p) => {
        const row = h('div', { class: 'row' + (S.activePin === p.id ? ' active' : '') });
        if (p.anchor && p.anchor.text) row.title = 'Anchored text: ' + p.anchor.text.slice(0, 200);
        const txt = h('span', { class: 'txt', text: p.body });
        const meta = h('div', { class: 'meta' }, [
          chip(p.status),
          h('span', {
            text: p.name
              + (p.guestEmail && S.mode === 'author' ? ' · ' + p.guestEmail : '')
              + ' · ' + p.route,
          }),
        ]);
        if (!p.anchor.el) meta.appendChild(h('span', { class: 'orphan-tag', text: 'surface' }));
        else if (!resolveAnchor(p)) meta.appendChild(h('span', { class: 'orphan-tag', text: 'orphaned' }));
        row.appendChild(txt);
        row.appendChild(meta);
        // Navigate-to-pin: a pin on another route is one tap away — jump
        // there and flash its thread open on arrival.
        row.addEventListener('click', () => {
          if (p.route === route) return openThread(p);
          try { sessionStorage.setItem('arxa-dial-open-pin', p.id); } catch (_) {}
          location.assign(p.route);
        });
        body.appendChild(row);
      });
    };
    section(null, here);
    section('Other routes', elsewhere);
  }
  // Boot continuation: a board navigation asks to open a specific pin.
  function openPinnedOnArrival() {
    let id = null;
    try { id = sessionStorage.getItem('arxa-dial-open-pin'); } catch (_) {}
    if (!id) return;
    try { sessionStorage.removeItem('arxa-dial-open-pin'); } catch (_) {}
    const pin = S.pins.find((p) => p.id === id);
    if (pin) setTimeout(() => openThread(pin), 350); // let the page settle first
  }

  // ── the identity plane: personal client links (arc 2, Comments slide) ──
  // Anonymous tokens are gone from the UI: every minted link belongs to a
  // REGISTERED guest (email keyed), their pins/replies attribute by
  // construction, and revoke deletes the PII while keeping the feedback.
  function guestLabel(g) {
    return (g.name && g.name.trim()) || g.email.split('@')[0];
  }

  async function loadGuests(force) {
    if (S.guests && !force) return S.guests;
    const r = await api('GET', '/guests');
    S.guests = (r && r.guests) || [];
    return S.guests;
  }

  function renderGuestRoster(panel) {
    const list = panel.querySelector('.gstlist');
    if (!list) return;
    list.textContent = '';
    const gs = S.guests || [];
    if (!gs.length) {
      list.appendChild(h('div', {
        class: 'ctl',
        style: 'font-size:11px;color:#9aa0ab',
        text: 'No guests yet — mint a personal link below.',
      }));
      return;
    }
    gs.forEach((g) => {
      const row = h('div', { class: 'row', style: 'cursor:default' });
      row.appendChild(h('span', {
        class: 'txt',
        text: guestLabel(g) + ' · ' + g.email,
        title: g.linksAlive + ' live link(s) · added ' + (g.createdAt || ''),
      }));
      const revoke = h('button', { class: 'btn ghost', text: 'Revoke' });
      revoke.title = 'Delete their links + email; keep the feedback, de-attributed';
      revoke.addEventListener('click', async () => {
        revoke.disabled = true;
        const r = await api('POST', '/guests/revoke', { email: g.email });
        if (r && r.ok) {
          say('Revoked ' + g.email + ' — feedback kept, email scrubbed');
          await loadGuests(true);
          renderGuestRoster(panel);
        } else {
          revoke.disabled = false;
          say((r && r.error) || 'Revoke failed');
        }
      });
      const meta = h('div', { class: 'meta' }, [
        h('span', { text: g.linksAlive + ' link' + (g.linksAlive === 1 ? '' : 's') }),
        revoke,
      ]);
      row.appendChild(meta);
      list.appendChild(row);
    });
  }

  function ensureGuestShareUI(body, focusEmail) {
    let panel = body.querySelector('.gstpanel');
    if (panel) {
      if (focusEmail) {
        const em = panel.querySelector('.gstemail');
        if (em) em.focus();
      }
      return panel;
    }
    panel = h('div', { class: 'gstpanel' });
    panel.appendChild(h('div', {
      class: 'sect',
      text: 'Client access — personal links',
    }));
    panel.appendChild(h('div', {
      class: 'ctl',
      style: 'font-size:11px;color:#9aa0ab',
      text: 'Each link belongs to one registered email: their pins attribute to them, and revoke deletes their email while keeping every comment.',
    }));
    const list = h('div', { class: 'gstlist' });
    panel.appendChild(list);
    const email = h('input', {
      type: 'email',
      class: 'gstemail',
      placeholder: 'client@company.com',
      style: 'margin-top:8px',
    });
    const name = h('input', {
      type: 'text',
      placeholder: 'Display name (optional)',
      style: 'margin-top:6px',
    });
    const mint = h('button', { class: 'btn', text: 'Mint personal link' });
    const out = h('div');
    mint.addEventListener('click', async () => {
      const em = email.value.trim();
      if (!em || em.indexOf('@') < 1) {
        say('Enter the client email first');
        email.focus();
        return;
      }
      mint.disabled = true;
      mint.textContent = 'Minting…';
      const r = await api('POST', '/guests', {
        email: em,
        name: name.value.trim() || undefined,
      });
      mint.disabled = false;
      mint.textContent = 'Mint personal link';
      if (r && r.token) {
        const url = location.origin + location.pathname + '?dial=' + r.token;
        out.textContent = '';
        out.appendChild(h('div', {
          class: 'linkbox',
          text: url,
          title: 'Personal link for ' + r.email,
        }));
        const copy = h('button', { class: 'btn ghost', text: 'Copy link' });
        copy.addEventListener('click', async () => {
          try {
            await navigator.clipboard.writeText(url);
            say('Link copied — send it to ' + r.email);
          } catch (_) {
            say('Copy failed — select the link manually');
          }
        });
        out.appendChild(h('div', { class: 'btnrow' }, [copy]));
        email.value = '';
        name.value = '';
        say('Personal link minted for ' + r.email);
        await loadGuests(true);
        renderGuestRoster(panel);
      } else {
        say((r && r.error) || 'Could not mint a link');
      }
    });
    panel.appendChild(email);
    panel.appendChild(name);
    panel.appendChild(h('div', { class: 'btnrow', style: 'margin-top:8px' }, [mint]));
    panel.appendChild(out);
    body.insertBefore(panel, body.firstChild);
    loadGuests(true).then(() => renderGuestRoster(panel));
    if (focusEmail) email.focus();
    return panel;
  }

  // ── pin anchoring: data-el identity + rect snapshot (decision 6) ──────
  function resolveAnchor(pin) {
    if (!pin.anchor.el) return null;
    const sel = '[data-el="' + pin.anchor.el.replace(/"/g, '') + '"]';
    const el = document.querySelector(sel);
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return { x: r.left + scrollX + r.width / 2, y: r.top + scrollY };
  }

  // Anchor point in PAGE coords: element center when resolvable, else the
  // stored snapshot's center (orphaned pins hold their last known spot).
  function anchorPoint(pin) {
    const live = resolveAnchor(pin);
    if (live) return { p: live, orphan: false };
    const rc = pin.anchor.rect;
    return { p: { x: rc.x + rc.w / 2, y: rc.y + rc.h / 2 }, orphan: !!pin.anchor.el };
  }

  function renderPins() {
    pinsLayer.textContent = '';
    const route = location.pathname;
    S.pins.forEach((pin, i) => {
      if (pin.route !== route) return;
      const pt = anchorPoint(pin);
      const b = h('button', {
        class:
          'pin ' +
          pin.status.replace('_', '') +
          (pt.orphan ? ' orphan' : '') +
            (S.activePin === pin.id ? ' active' : ''),
        text: String(i + 1),
        title: pin.name + ': ' + pin.body,
      });
      b.style.left = pt.p.x - scrollX + 'px';
      b.style.top = pt.p.y - scrollY + 'px';
      b.addEventListener('click', (e) => {
        e.stopPropagation();
        openThread(pin);
      });
      pinsLayer.appendChild(b);
    });
  }

  let rafPending = false;
  function scheduleRepin() {
    if (rafPending) return;
    rafPending = true;
    requestAnimationFrame(() => {
      rafPending = false;
      renderPins();
      renderHandles();
    });
  }
  addEventListener('scroll', scheduleRepin, { passive: true, capture: true });
  addEventListener('resize', scheduleRepin);

  // ── pin placement (the inspect.js walk, trimmed) ───────────────────────
  function targetAt(x, y) {
    const stack = document.elementsFromPoint(x, y);
    for (const el of stack) {
      if (host.contains(el) || el === host) continue;
      let node = el;
      if (node.namespaceURI && node.namespaceURI.indexOf('svg') !== -1 && node.tagName !== 'svg') {
        node = node.closest('svg') || node;
      }
      const hit = node.closest && node.closest('[data-el]');
      if (hit) {
        const r = hit.getBoundingClientRect();
        // The text snapshot rides the pin (Figma design-context practice:
        // a comment bound to content survives copy edits and orphaning).
        // Whitespace-collapsed and capped client-side; the server re-
        // validates the cap.
        const text = (hit.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 600);
        return {
          el: hit.getAttribute('data-el'),
          rect: { x: r.left + scrollX, y: r.top + scrollY, w: r.width, h: r.height },
          screenRect: r,
          text: text || null,
        };
      }
    }
    const r = document.body.getBoundingClientRect();
    return {
      el: null,
      rect: { x: r.left + scrollX, y: r.top + scrollY, w: r.width, h: r.height },
      screenRect: r,
    };
  }

  function onArmMove(e) {
    // Host moves never highlight (same law as onDesignClick): the card
    // and its fan stay usable while the mode is armed.
    if (e.composedPath().indexOf(host) !== -1) { hover.style.display = 'none'; return; }
    const t = targetAt(e.clientX, e.clientY);
    hover.style.display = 'block';
    hover.style.left = t.screenRect.left + 'px';
    hover.style.top = t.screenRect.top + 'px';
    hover.style.width = t.screenRect.width + 'px';
    hover.style.height = t.screenRect.height + 'px';
    hover.firstChild.textContent = t.el || 'surface';
  }

  function onArmClick(e) {
    // Clicks inside the dial host belong to the card/fan — the panel
    // stays usable while the mode is armed (the exact guard onDesignClick
    // has always had; without it, tapping the armed card dropped a pin on
    // whatever sat under the corner and the fan could never reopen).
    if (e.composedPath().indexOf(host) !== -1) return;
    e.preventDefault();
    e.stopPropagation();
    const t = targetAt(e.clientX, e.clientY);
    disarm();
    openComposer(e.clientX, e.clientY, t);
  }

  function arm() {
    if (S.design) designOff();
    S.arming = true;
    setDockMode('comment'); // the card flips to the comment face
    verbEls.comment.classList.add('on');
    document.addEventListener('pointermove', onArmMove, true);
    document.addEventListener('click', onArmClick, true);
  }
  function disarm() {
    S.arming = false;
    setDockMode(''); // the card returns to the arxa face
    verbEls.comment.classList.remove('on');
    hover.style.display = 'none';
    document.removeEventListener('pointermove', onArmMove, true);
    document.removeEventListener('click', onArmClick, true);
  }

  // ── the composer (new pin) ─────────────────────────────────────────────
  const composer = h('div', { id: 'composer' });
  root.appendChild(composer);

  function openComposer(x, y, target) {
    composer.textContent = '';
    composer.style.left = Math.min(x + 12, innerWidth - 300) + 'px';
    composer.style.top = Math.min(y + 12, innerHeight - 260) + 'px';
    composer.appendChild(
      h('div', { class: 'who', style: 'font-size:11px;color:#9aa0ab', text: 'Pin on: ' + (target.el || 'whole surface') }),
    );
    // The anchor's own words ride along (improvement 4): reviewers see
    // WHAT was commented even after the copy changes underneath.
    if (target.text) {
      const t = target.text.length > 120 ? target.text.slice(0, 120) + '…' : target.text;
      composer.appendChild(h('div', { class: 'ctx', text: '“' + t + '”' }));
    }
    const area = h('textarea', { rows: '3', placeholder: 'What should change?' });
    composer.appendChild(area);
    let nameInput = null;
    if (S.guest) {
      composer.appendChild(h('div', {
        class: 'who',
        style: 'font-size:11px;color:#8fa98f;margin-top:6px',
        text: 'Commenting as ' + S.name + ' (' + S.guest.email + ')',
      }));
    }
    if (S.mode === 'guest' && !S.name && !S.guest) {
      nameInput = h('input', { type: 'text', placeholder: 'Your name', style: 'margin-top:8px' });
      composer.appendChild(nameInput);
    }
    const add = h('button', { class: 'btn', text: 'Add pin' });
    const cancel = h('button', { class: 'btn ghost', text: 'Cancel' });
    composer.appendChild(h('div', { class: 'btnrow' }, [cancel, add]));
    composer.classList.add('open');
    area.focus();
    cancel.addEventListener('click', () => composer.classList.remove('open'));
    add.addEventListener('click', async () => {
      const body = area.value.trim();
      if (!body) return;
      if (nameInput) {
        S.name = nameInput.value.trim() || 'guest';
        try {
          localStorage.setItem('arxa-dial-name', S.name);
        } catch (_) {}
      }
      const r = await api('POST', '/pins', {
        route: location.pathname,
        viewport: { w: innerWidth, h: innerHeight },
        anchor: { el: target.el, rect: target.rect, text: target.text || undefined },
        body,
        name: S.name || undefined,
      });
      composer.classList.remove('open');
      if (r && r.pin) {
        say('Pin added');
        await loadPins();
      } else {
        say((r && r.error) || 'Pin failed');
      }
    });
  }

  // ── the thread popover ─────────────────────────────────────────────────
  const thread = h('div', { id: 'thread' });
  root.appendChild(thread);

  // The open thread's pin — set while the popover is open so the float
  // tracker (below, with the card) can re-derive its anchor point.
  let threadPin = null;
  function positionThread() {
    if (!threadPin) return;
    const pt = anchorPoint(threadPin);
    const sx = pt.p.x - scrollX;
    const sy = pt.p.y - scrollY;
    thread.style.left = Math.min(Math.max(sx + 18, 8), innerWidth - 316) + 'px';
    thread.style.top = Math.min(Math.max(sy + 18, 8), innerHeight - 320) + 'px';
  }

  function openThread(pin) {
    S.activePin = pin.id;
    renderPins();
    thread.textContent = '';
    const head = h('div', {
      class: 'who',
      text: pin.name
        + (pin.guestEmail && S.mode === 'author' ? ' · ' + pin.guestEmail : '')
        + ' · ' + pin.route,
    });
    thread.appendChild(head);
    thread.appendChild(h('div', { class: 'body', text: pin.body }));
    const ctx = pin.anchor && pin.anchor.text;
    if (ctx) {
      thread.appendChild(h('div', { class: 'ctx', title: 'Anchored text at pin time', text: '“' + ctx + '”' }));
    }
    const replies = h('div', { class: 'replies' });
    (pin.replies || []).forEach((r) => {
      replies.appendChild(
        h('div', { class: 'reply' }, [
          h('span', { class: 'who', text: r.name + ' (' + r.author + '):' }),
          h('span', { text: r.body }),
        ]),
      );
    });
    thread.appendChild(replies);
    // Kanban row — Author only (locked decision 1).
    if (S.mode === 'author') {
      const row = h('div', { id: 'statusrow' });
      KANBAN.forEach(([st, label]) => {
        const b = h('button', {
          class: 'stbtn' + (pin.status === st ? ' cur' : ''),
          text: label,
        });
        b.addEventListener('click', async () => {
          await api('POST', '/pins/status', { id: pin.id, status: st });
          await loadPins();
          const fresh = S.pins.find((p) => p.id === pin.id);
          if (fresh) openThread(fresh);
        });
        row.appendChild(b);
      });
      thread.appendChild(row);
    }
    const input = h('input', { type: 'text', placeholder: 'Reply…' });
    input.addEventListener('keydown', async (e) => {
      if (e.key !== 'Enter' || !input.value.trim()) return;
      await api('POST', '/pins/reply', {
        id: pin.id,
        body: input.value.trim(),
        name: S.name || undefined,
      });
      input.value = '';
      await loadPins();
      const fresh = S.pins.find((p) => p.id === pin.id);
      if (fresh) openThread(fresh);
    });
    thread.appendChild(input);
    thread.classList.add('open');
    // Position near the pin, clamped into the viewport.
    threadPin = pin;
    positionThread();
  }
  function closeThread() {
    S.activePin = null;
    threadPin = null;
    thread.classList.remove('open');
    renderPins();
  }

  // ── Design Mode (author only; locked decisions 1-5) ────────────────────
  // Selection walks data-arxa-id (the machine identity design patch rides),
  // facet sets are curated per element kind, and every edit applies live,
  // then auto-saves into the server-side Draft Overlay. Artifact source is
  // only ever touched by the studio-socket commit — never from this island.

  const FACET_GROUPS = {
    text: ['color', 'font-size', 'font-weight', 'line-height', 'letter-spacing', 'text-align'],
    action: ['background', 'color', 'font-size', 'font-weight', 'padding', 'border-radius'],
    surface: ['background', 'padding', 'gap', 'width', 'height', 'border-radius', 'border-color'],
    field: ['background', 'color', 'font-size', 'padding', 'border-color', 'border-radius'],
    media: ['width', 'height', 'opacity'],
    generic: ['color', 'background', 'font-size', 'width', 'height', 'padding', 'margin', 'border-radius'],
  };
  // The 15-kind widget vocabulary plus the simple data-el names and tag
  // kinds real artifacts carry; anything unlisted edits as 'generic'.
  const KIND_GROUP = {
    card: 'surface', 'panel-activity': 'surface', modal: 'surface', dialog: 'surface',
    'bottom-sheet': 'surface', 'empty-state': 'surface', toast: 'surface', panel: 'surface',
    'list-row': 'surface', frame: 'surface',
    'cta-link': 'action', chip: 'action', appbar: 'action', tabbar: 'action', tabs: 'action',
    'nav-rail': 'action', action: 'action', button: 'action', link: 'action',
    text: 'text', heading: 'text', label: 'text', title: 'text',
    'form-field': 'field', input: 'field', field: 'field',
    icon: 'media', image: 'media', media: 'media',
  };
  const TAG_KIND = {
    h1: 'heading', h2: 'heading', h3: 'heading', h4: 'heading', h5: 'heading', h6: 'heading',
    p: 'text', span: 'text', label: 'label', a: 'link', button: 'button',
    img: 'image', svg: 'icon', input: 'input', textarea: 'input', select: 'input',
    nav: 'nav-rail', header: 'appbar', li: 'list-row',
  };
  const COLOR_PROPS = { background: 1, color: 1, 'border-color': 1 };
  const SELECT_OPTS = {
    'font-weight': ['300', '400', '500', '600', '700', '800'],
    'text-align': ['left', 'center', 'right', 'start', 'end'],
  };

  function kindOf(el) {
    const de = el.getAttribute('data-el');
    if (de) {
      const k = de.split(':')[0].toLowerCase();
      if (KIND_GROUP[k]) return { kind: k, group: KIND_GROUP[k] };
    }
    const tag = el.tagName.toLowerCase();
    const kind = TAG_KIND[tag] || tag;
    return { kind: kind, group: KIND_GROUP[kind] || 'generic' };
  }

  // The selection walk: data-arxa-id identity, SVG collapse, island skipped.
  function designTargetAt(x, y) {
    const stack = document.elementsFromPoint(x, y);
    for (const el of stack) {
      if (host.contains(el) || el === host) continue;
      let node = el;
      if (node.namespaceURI && node.namespaceURI.indexOf('svg') !== -1 && node.tagName !== 'svg') {
        node = node.closest('svg') || node;
      }
      const hit = node.closest && node.closest('[data-arxa-id]');
      if (hit) {
        const k = kindOf(hit);
        return {
          id: hit.getAttribute('data-arxa-id'),
          el: hit,
          label: (hit.getAttribute('data-el') || hit.tagName.toLowerCase()) + ' · ' + k.kind,
          group: k.group,
          rect: hit.getBoundingClientRect(),
        };
      }
    }
    return null;
  }

  function onDesignMove(e) {
    if (e.composedPath().indexOf(host) !== -1) { hover.style.display = 'none'; return; }
    // Hunt-freeze law (operator, 2026-08-25): once an element is
    // selected the cursor's hunting STOPS — focus belongs to the
    // selected element (amber outline + handles + card); a second
    // highlight chasing the cursor is noise. Hunting is a DISCOVERY
    // affordance, and there is nothing left to discover mid-selection.
    // Deselected (outline cleared / mode re-armed) it resumes by
    // itself — this guard reads S.selected live.
    if (S.selected) { hover.style.display = 'none'; return; }
    const t = designTargetAt(e.clientX, e.clientY);
    if (!t) { hover.style.display = 'none'; return; }
    hover.classList.add('design');
    hover.style.display = 'block';
    hover.style.left = t.rect.left + 'px';
    hover.style.top = t.rect.top + 'px';
    hover.style.width = t.rect.width + 'px';
    hover.style.height = t.rect.height + 'px';
    hover.firstChild.textContent = t.label;
  }

  function onDesignClick(e) {
    if (e.composedPath().indexOf(host) !== -1) return; // the panel stays usable
    // While editing text on-canvas, clicks INSIDE the edited element are
    // cursor placement — the page keeps them. A click anywhere else commits.
    if (S.inlineEditing != null && S.selected) {
      if (S.selected.el.contains(e.target)) return;
      inlineEditEnd(true);
    }
    const t = designTargetAt(e.clientX, e.clientY);
    if (!t) return; // unstamped spot — let the page have the click
    e.preventDefault();
    e.stopPropagation();
    selectEl(t);
  }

  // Which identity a patch binds to (amended 2026-08-24 — authored identity
  // wins on divergence): when one machine id fans out over instances with
  // DIFFERENT authored meanings, keying the patch by machine id would commit
  // the edit over every sibling slot at once (the operator's copyright edit
  // on the shared wordmark id nearly rewrote the statement text too). A
  // divergent selection binds to its data-el; homogeneous loops keep the
  // machine id and its every-row-at-once fan-out.
  function bindingFor(el, id) {
    const inst = [...document.querySelectorAll('[data-arxa-id="' + id + '"]')];
    if (inst.length > 1) {
      const meanings = new Set(inst.map((x) => x.getAttribute('data-el') || ''));
      if (meanings.size > 1) {
        const de = el.getAttribute('data-el');
        if (de) return 'el:' + de;
      }
    }
    return id;
  }

  // ONE-FOCUS LAW (operator, 2026-08-26): "when selected an element in
  // edit mode no other element can be selected." The hunt-freeze law
  // (2026-08-25) stopped the cursor's highlight; this choke closes the
  // bigger hole — a click (or double-click, or a tray jump) on a
  // DIFFERENT element used to switch the selection outright. While an
  // element holds the focus, every such request is absorbed here at the
  // single source; the only doors to a new selection are a full
  // deselect (Esc ×2 / tray close — both clear S.selected) or the
  // element dying in a swap (a stranded selection locks nothing — the
  // handles renderer and trackBack tier-2 already treat it as gone).
  // Re-selecting the SAME element stays legal — the recovery path that
  // re-opens a ×-closed card (the 2026-08-25 law kept the selection on
  // close) — and a request resolving INSIDE the selection's subtree is
  // the SAME element too: stamped children are parts of their wrapper,
  // and a wrapper's visible area is covered by them (intro-line-3's em
  // owns every pixel of its line). Returns whether the selection ended
  // up on the selection's element (requests for others are refused).
  function selectEl(t) {
    if (S.selected && S.selected.el && S.selected.el.isConnected &&
        S.selected.el !== t.el) {
      if (S.selected.el.contains(t.el)) {
        // inside the selection: re-target to the SELECTION itself —
        // the card re-opens on it, the child never takes the focus.
        t = { id: S.selected.id, el: S.selected.el, label: S.selected.label, group: S.selected.group };
      } else {
        // outside (or an ancestor wrapper): absorbed. Ancestors are NOT
        // the selection — their padding is a different element's ground.
        say('Focus locked on the selected element — Esc to pick another');
        return false;
      }
    }
    if (S.inlineEditing != null) inlineEditEnd(true); // commit before switching
    clearSelOutline();
    hover.style.display = 'none'; // the hunt-freeze law starts clean: no stale box under the new selection
    const key = bindingFor(t.el, t.id);
    const insts = targetsForKey(key);
    S.selected = { id: t.id, key: key, el: t.el, label: t.label, group: t.group,
      // track-back provenance (2026-08-26): the route the element
      // lives on and WHICH instance it is — the button's cross-page
      // tier restores by exactly this pair.
      route: location.pathname, nth: Math.max(0, insts.indexOf(t.el)) };
    // the track-back stash is the LIVE selection (2026-08-26): whoever
    // navigates away and comes back to this route lands on the element
    // again — restored once, then the intent is spent until the next
    // selection rewrites it.
    try {
      sessionStorage.setItem('arxa-dial-trackback', JSON.stringify({
        key: key, nth: S.selected.nth, route: S.selected.route,
      }));
    } catch (_) {}
    S.selOutline = t.el.style.outline;
    t.el.style.outline = '2px solid #f59e0b';
    renderHandles();
    trackHandles();
    openCard();
    return true;
  }
  function clearSelOutline() {
    if (S.inlineEditing != null) inlineEditEnd(true);
    if (S.selected) S.selected.el.style.outline = S.selOutline || '';
    S.selected = null;
    handlesLayer.textContent = '';
  }

  // ── direct manipulation: resize handles + on-canvas text editing ─────
  // Locked decision 2 ("direct manipulation + studio socket") read literally:
  // the Author drags the selection's amber handles to resize it and
  // double-clicks pure-text elements to type in place. Every change still
  // flows through the SAME patch functions (setStyleProp / setTextContent),
  // so live-apply, Draft Overlay auto-save, and the commit socket are
  // identical to panel edits — the handles are a gesture, not a write path.
  const handlesLayer = h('div', { id: 'handles' });
  root.appendChild(handlesLayer);
  const DIRS = ['nw', 'n', 'ne', 'e', 'se', 's', 'sw', 'w'];
  function renderHandles() {
    handlesLayer.textContent = '';
    if (!S.selected || !S.design) return;
    if (!document.contains(S.selected.el)) return; // hot-reload swapped the DOM
    const r = S.selected.el.getBoundingClientRect();
    if (r.width < 4 || r.height < 4) return;
    const pts = {
      nw: [r.left, r.top], n: [r.left + r.width / 2, r.top], ne: [r.right, r.top],
      e: [r.right, r.top + r.height / 2], se: [r.right, r.bottom],
      s: [r.left + r.width / 2, r.bottom], sw: [r.left, r.bottom],
      w: [r.left, r.top + r.height / 2],
    };
    for (const d of DIRS) {
      const hd = h('div', { class: 'hnd', 'data-d': d });
      hd.style.left = pts[d][0] + 'px';
      hd.style.top = pts[d][1] + 'px';
      hd.addEventListener('pointerdown', (e) => startHandleDrag(e, d));
      handlesLayer.appendChild(hd);
    }
  }
  // Handles must TRACK the selection, not snapshot it: artifacts animate
  // their own elements (this one's intro flies the wordmark in), and a
  // render-at-click-time handle set freezes where the element WAS. A rAF
  // loop repositions the existing handles every frame while a selection is
  // live; it parks itself when the selection clears.
  let handleRaf = 0;
  function positionHandles() {
    const kids = handlesLayer.children;
    if (!S.selected || kids.length !== 8) return;
    if (!document.contains(S.selected.el)) return;
    const r = S.selected.el.getBoundingClientRect();
    const pts = {
      nw: [r.left, r.top], n: [r.left + r.width / 2, r.top], ne: [r.right, r.top],
      e: [r.right, r.top + r.height / 2], se: [r.right, r.bottom],
      s: [r.left + r.width / 2, r.bottom], sw: [r.left, r.bottom],
      w: [r.left, r.top + r.height / 2],
    };
    for (let i = 0; i < DIRS.length; i++) {
      kids[i].style.left = pts[DIRS[i]][0] + 'px';
      kids[i].style.top = pts[DIRS[i]][1] + 'px';
    }
  }
  function trackHandles() {
    cancelAnimationFrame(handleRaf);
    const tick = () => {
      if (!S.selected || !S.design) return;
      positionHandles();
      handleRaf = requestAnimationFrame(tick);
    };
    handleRaf = requestAnimationFrame(tick);
  }
  function startHandleDrag(e, dir) {
    e.preventDefault();
    e.stopPropagation();
    const sel = S.selected;
    if (!sel) return;
    const r0 = sel.el.getBoundingClientRect();
    const x0 = e.clientX, y0 = e.clientY;
    const w0 = r0.width, h0 = r0.height;
    const move = (ev) => {
      const dx = ev.clientX - x0, dy = ev.clientY - y0;
      if (dir.indexOf('e') !== -1) setStyleProp(sel.key, 'width', Math.max(10, Math.round(w0 + dx)) + 'px');
      if (dir.indexOf('w') !== -1) setStyleProp(sel.key, 'width', Math.max(10, Math.round(w0 - dx)) + 'px');
      if (dir.indexOf('s') !== -1) setStyleProp(sel.key, 'height', Math.max(10, Math.round(h0 + dy)) + 'px');
      if (dir.indexOf('n') !== -1) setStyleProp(sel.key, 'height', Math.max(10, Math.round(h0 - dy)) + 'px');
      renderHandles();
    };
    const up = () => {
      document.removeEventListener('pointermove', move, true);
      document.removeEventListener('pointerup', up, true);
      renderCardAgain(); // the facet inputs catch up with the dragged values
    };
    document.addEventListener('pointermove', move, true);
    document.addEventListener('pointerup', up, true);
  }

  // Text-editable means: no STAMPED descendant. Runtime line/word splitters
  // (the artifact's own intro animator wraps "SUCZKA" in unstamped .line
  // divs) nest markup the source never had — the text is still one authored
  // string, the patch applies to source, and the animator re-splits the new
  // text on next serve. Genuine composites carry stamped children and stay
  // refused, the same refusal the patch grammar enforces on --text.
  function isTextEditable(el) {
    return (el.textContent || '').trim().length > 0 &&
      !el.querySelector('[data-arxa-id], [data-el]');
  }
  function inlineEditStart() {
    const sel = S.selected;
    if (!sel || S.inlineEditing != null) return;
    if (!isTextEditable(sel.el)) {
      say('Composite element — edit its parts, not its text');
      return;
    }
    S.inlineEditing = sel.el.textContent;
    sel.el.setAttribute('contenteditable', 'true');
    sel.el.setAttribute('data-arxa-inline-editing', '1');
    sel.el.focus();
    const range = document.createRange();
    range.selectNodeContents(sel.el);
    const s = getSelection();
    s.removeAllRanges();
    s.addRange(range);
    sel.el.addEventListener('focusout', onInlineFocusOut);
  }
  function onInlineFocusOut(e) {
    // relatedTarget null means focus left the DOCUMENT (OS focus change,
    // DevTools, headless quirk) — not the author clicking the design. Page
    // clicks already commit via onDesignClick; a blur-to-nowhere must not
    // slam the editor shut the moment it opens.
    if (e && e.relatedTarget == null) return;
    if (S.inlineEditing != null) inlineEditEnd(true);
  }
  function inlineEditEnd(commit) {
    const sel = S.selected;
    if (!sel || S.inlineEditing == null) return;
    const original = S.inlineEditing;
    S.inlineEditing = null;
    const el = sel.el;
    el.removeEventListener('focusout', onInlineFocusOut);
    el.removeAttribute('contenteditable');
    el.removeAttribute('data-arxa-inline-editing');
    if (commit) {
      // setTextContent normalizes whatever markup contenteditable produced,
      // patches the draft, and schedules the auto-save.
      setTextContent(sel.key, el.textContent, el);
    } else {
      el.textContent = original;
    }
    renderCardAgain();
  }
  function onDesignDblClick(e) {
    if (e.composedPath().indexOf(host) !== -1) return;
    const t = designTargetAt(e.clientX, e.clientY);
    if (!t) return;
    e.preventDefault();
    e.stopPropagation();
    if (!S.selected || S.selected.el !== t.el) selectEl(t);
    // one-focus law: on-canvas typing belongs to the SELECTED element —
    // a double-click on another element is absorbed whole (the choke
    // refused the reselect; starting an edit anyway would hand the
    // keyboard to an element the card is not even open on).
    if (!S.selected || S.selected.el !== t.el) return;
    inlineEditStart();
  }

  function designOn() {
    if (S.arming) disarm();
    S.design = true;
    setDockMode('edit'); // the card flips to the edit face
    verbEls.edit.classList.add('on');
    document.addEventListener('pointermove', onDesignMove, true);
    document.addEventListener('click', onDesignClick, true);
    document.addEventListener('dblclick', onDesignDblClick, true);
    say('Edit Mode — click any element to open its card; double-click text to type in place');
  }
  function designOff() {
    S.design = false;
    setDockMode(''); // the card returns to the arxa face
    closeCard();
    if (verbEls.edit) verbEls.edit.classList.remove('on');
    hover.style.display = 'none';
    hover.classList.remove('design');
    clearSelOutline();
    document.removeEventListener('pointermove', onDesignMove, true);
    document.removeEventListener('click', onDesignClick, true);
    document.removeEventListener('dblclick', onDesignDblClick, true);
  }

  // ── the Draft Overlay: live apply + debounced auto-save ────────────────
  function patchFor(id) {
    let p = S.draft.patches[id];
    if (!p) { p = { style: {}, attrs: {} }; S.draft.patches[id] = p; }
    if (!p.style) p.style = {};
    if (!p.attrs) p.attrs = {};
    return p;
  }

  let saveTimer = null;
  function scheduleSave() {
    S.draftDirty = true;
    clearTimeout(saveTimer);
    saveTimer = setTimeout(saveDraft, 700);
    renderDraftMeta();
  }
  // The text patches' current signature — used to tell "this save changed
  // text" apart from style-only saves, because only text changes need the
  // reload converge (animator-owned nodes; see syncRemoteDraft).
  function textSig(d) {
    const parts = [];
    for (const k of Object.keys(d.patches).sort()) {
      const t = (d.patches[k] || {}).text;
      if (t != null) parts.push(k + '=' + t);
    }
    return parts.join('|');
  }
  let lastTextSig = null;
  let textReloadTimer = null;

  async function saveDraft() {
    if (!S.draftDirty) return;
    S.draftDirty = false;
    S.ownSave = Date.now();
    const r = await api('PUT', '/draft', { tokens: S.draft.tokens, patches: S.draft.patches });
    if (r && r.ok) {
      S.draftMeta = r;
      S.draftWarnings = r.warnings || [];
      renderDraftMeta();
    }
    else say(r && r.error ? 'Draft refused: ' + r.error : 'Draft save failed');
    // A text edit the author just committed will be fought by the artifact's
    // own animator (it re-renders split text from its boot capture — the
    // edit looks like it "did nothing" or duplicates). Once typing pauses,
    // reload so the author sees the animator rendering the NEW text — the
    // same converge the sibling rungs do. Style-only saves never reload.
    const sig = textSig(S.draft);
    if (r && r.ok && lastTextSig != null && sig !== lastTextSig) {
      lastTextSig = sig;
      clearTimeout(textReloadTimer);
      textReloadTimer = setTimeout(resumeReload, 1400);
    } else {
      lastTextSig = sig;
    }
  }

  // The editing rung's text-converge reload must not cost the author his
  // place: stash the design session, reload, and resumeAfterReload (boot)
  // re-arms and re-selects — the reload reads as a flicker, not a reset.
  function resumeReload() {
    try {
      sessionStorage.setItem('arxa-dial-resume', JSON.stringify({
        design: S.design,
        key: S.selected ? S.selected.key : null,
      }));
    } catch (_) {}
    location.reload();
  }
  function resumeAfterReload() {
    let r = null;
    try { r = JSON.parse(sessionStorage.getItem('arxa-dial-resume') || 'null'); } catch (_) {}
    try { sessionStorage.removeItem('arxa-dial-resume'); } catch (_) {}
    if (!r || S.mode !== 'author') return;
    if (r.design) designOn();
    if (r.key) {
      const el = targetsForKey(r.key)[0];
      const id = el && el.getAttribute('data-arxa-id');
      if (el && id) {
        const k = kindOf(el);
        selectEl({
          id: id, el: el,
          label: (el.getAttribute('data-el') || el.tagName.toLowerCase()) + ' · ' + k.kind,
          group: k.group,
        });
      }
    }
  }
  // The track-back button's cross-page half. Two triggers: a fresh
  // boot AND an htmx afterSwap — boosted navigation swaps the body
  // without ever re-running this script, so the swap moment is the
  // "boot" the restore rides. The stash is KEPT while the route
  // doesn't match (the author roams other pages; nothing chases him)
  // and SPENT the moment his own page restores the selection — once,
  // never insisting again until a new selection rewrites it.
  function maybeRestoreTrackback() {
    let t = null;
    try { t = JSON.parse(sessionStorage.getItem('arxa-dial-trackback') || 'null'); } catch (_) {}
    if (!t || !t.key || !t.route || t.route !== location.pathname) return;
    if (S.mode !== 'author') return;
    if (S.selected && S.selected.key === t.key && S.card) return; // already there
    const insts = targetsForKey(t.key);
    if (!insts.length) return;
    const el = insts[Math.min(t.nth || 0, insts.length - 1)];
    if (!el || !el.isConnected) return;
    if (!S.design) designOn();
    centerElement(el);
    const k = kindOf(el);
    selectEl({
      id: el.getAttribute('data-arxa-id'), el: el,
      label: (el.getAttribute('data-el') || el.tagName.toLowerCase()) + ' · ' + k.kind,
      group: k.group,
    });
    try { sessionStorage.removeItem('arxa-dial-trackback'); } catch (_) {}
  }
  document.body.addEventListener('htmx:afterSwap', () => maybeRestoreTrackback());

  async function loadDraft() {
    if (S.mode !== 'author') return false;
    const r = await probeCapable('/draft');
    // Capability, not content: {"draft":null} is a REAL author answer (no
    // draft saved yet) and must boot the dock. Only the server's quiet
    // mirror marker or a dead network means this context has no dial.
    if (r == null || r.mirror === true) return false;
    S.draftWarnings = r.warnings || []; // parity: computed server-side on every draft read
    if (r.draft) {
      S.draft.tokens = r.draft.tokens || {};
      S.draft.patches = r.draft.patches || {};
      lastTextSig = textSig(S.draft); // boot truth — only CHANGES reload
    }
    return true;
  }

  // Apply the CURRENT draft patch set to this document. The serve-time
  // overlay does this for page loads; this is the live path for frames that
  // are already open (the other rungs of the ladder, another author tab).
  function applyPatchesLive() {
    for (const key of Object.keys(S.draft.patches)) {
      const p = S.draft.patches[key] || {};
      const insts = targetsForKey(key);
      for (const el of insts) {
        if (p.style) {
          for (const prop of Object.keys(p.style)) {
            const v = p.style[prop];
            if (v == null) el.style.removeProperty(prop);
            else el.style.setProperty(prop, v);
          }
        }
        // Text lands only on text-editable targets; composite instances are
        // the serve-time overlay's job (it refuses them loudly, by design).
        if (p.text != null && isTextEditable(el)) el.textContent = p.text;
        if (p.attrs) {
          for (const name of Object.keys(p.attrs)) {
            const v = p.attrs[name];
            // instance-scoped attrs (see setAttrProp) touch ONLY their
            // occurrence — the live twin of the overlay's onlyNth path.
            if (p.attrsNth && Object.prototype.hasOwnProperty.call(p.attrsNth, name)) {
              if (el === insts[p.attrsNth[name]]) {
                if (v == null) el.removeAttribute(name);
                else el.setAttribute(name, v);
              }
              continue;
            }
            if (v == null) el.removeAttribute(name);
            else el.setAttribute(name, v);
          }
        }
      }
    }
  }

  // Another author context saved its draft (a sibling rung of the viewport
  // ladder, a second tab): pull it and apply — the operator's law is that
  // every platform the design was authored at shows the same thing LIVE
  // (amended 2026-08-24). Removals can't be un-applied from a live DOM we
  // never snapshotted, so a shrinking draft converges by reload — the same
  // thing the resetting rung itself does.
  let syncing = false;
  // Per-PATCH prop count. renderLedger counts ONE patch entry; the
  // 2026-08-26 sheet bug passed a patch to patchPropCount — which wants a
  // whole draft — and Object.keys(undefined) threw, killing the render of
  // every slide after Edit (Comments/Settings/Tweak/Ship stayed blank
  // whenever a draft edit existed).
  function patchProps(p) {
    p = p || {};
    return (p.style ? Object.keys(p.style).length : 0) +
      (p.attrs ? Object.keys(p.attrs).length : 0) + (p.text != null ? 1 : 0);
  }
  function patchPropCount(d) {
    let n = 0;
    for (const k of Object.keys((d && d.patches) || {})) {
      n += patchProps(d.patches[k]);
    }
    return n;
  }
  async function syncRemoteDraft() {
    if (syncing || S.mode !== 'author') return;
    syncing = true;
    try {
      const r = await api('GET', '/draft');
      if (!r || !r.draft) return;
      const next = { tokens: r.draft.tokens || {}, patches: r.draft.patches || {} };
      const had = Object.keys(S.draft.patches).length + Object.keys(S.draft.tokens).length;
      const has = Object.keys(next.patches).length + Object.keys(next.tokens).length;
      const shrink = has < had || patchPropCount(next) < patchPropCount(S.draft);
      // Text patches converge ONLY by reload: artifact animators own their
      // text nodes (this one's intro re-splits the wordmark every pass from
      // its boot capture — a live textContent write is reverted, duplicated,
      // or collapsed within seconds, worst on wide rungs). A reload re-serves
      // with the overlay applied and the animator boots on the NEW text.
      // Style/token patches have no such owner — they stay live.
      //
      // Reload only when the incoming TEXT SIGNATURE differs from the one
      // this document rendered with (lastTextSig — set at boot and after own
      // saves). The earlier "any text patch exists" test reloaded every rung
      // on every frame — duplicate frames and style-only saves included —
      // yet could still leave a rung that had MISSED frames stale forever,
      // because nothing re-checked divergence. The signature check both
      // spares the pointless reloads and catches the missed-frame rung.
      if (shrink || textSig(next) !== lastTextSig) { location.reload(); return; }
      S.draft.tokens = next.tokens;
      S.draft.patches = next.patches;
      applyTokensLive();
      applyPatchesLive();
      refreshOpenCard();
      if (S.tray === 'edit') renderTraySlide('edit');
      if (S.tray === 'tweak') renderTraySlide('tweak');
    } finally {
      syncing = false;
    }
  }

  function renderDraftMeta() {
    const els = root.querySelectorAll('.draftmeta');
    if (!els.length) return;
    const np = Object.keys(S.draft.patches).length;
    const nt = Object.keys(S.draft.tokens).length;
    const nw = (S.draftWarnings || []).filter(w =>
      Object.keys(S.draft.patches).indexOf('el:' + w.el) >= 0).length;
    let txt = S.draftDirty
      ? 'unsaved changes…'
      : np + ' patches · ' + nt + ' tokens' + (S.draftMeta ? ' · saved' : '');
    let detail = '';
    if (nw > 0) {
      detail = S.draftWarnings
        .map(w => w.el + ': ' + w.sites + ' name= sites (' + w.problem + ')')
        .join('; ');
      txt += ' · ⚠ ' + nw + ' uncommittable';
    }
    els.forEach((el) => {
      el.textContent = txt;
      if (detail) el.title = 'These el: edits cannot commit - ' + detail;
      else el.removeAttribute('title');
    });
    updateTrayCta();
  }

  // Every instance a patch key governs. el:-keys fan out over their data-el
  // (homogeneous rows share one authored meaning); machine ids fan out over
  // every instance of the id — live apply must match what the serve-time
  // overlay will do, or the design changes personality on reload.
  function targetsForKey(key) {
    if (key.indexOf('el:') === 0) {
      return [...document.querySelectorAll('[data-el="' + key.slice(3) + '"]')];
    }
    return [...document.querySelectorAll('[data-arxa-id="' + key + '"]')];
  }

  // Attr edits carry the text law's instance provenance (2026-08-26):
  // an anchor whose instances DIVERGE on the edited attr is not a
  // homogeneous row — every image sharing data-el="media-source" has its
  // OWN src, and an every-row apply rewrote all 22 at once (live report:
  // "changed the image of one element and it changed most of the
  // images"). Divergent instances get per-instance scoping: nth is
  // recorded on the patch (attrsNth[name]) and both live apply and the
  // serve-time overlay touch ONLY that occurrence. Homogeneous repeats
  // (same value everywhere) keep every-row semantics, exactly as text
  // does. [origin] is the tapped instance the edit is about.
  function setAttrProp(key, name, value, origin) {
    const p = patchFor(key);
    p.attrs[name] = value || null; // empty clears the attribute
    const insts = targetsForKey(key);
    let targets = insts;
    const vals = new Set(insts.map((el) => el.getAttribute(name)));
    if (insts.length > 1 && vals.size > 1) {
      // instances disagree on this attr — scope to the edited one
      const idx = origin && insts.indexOf(origin) >= 0
        ? insts.indexOf(origin) : 0;
      p.attrsNth = p.attrsNth || {};
      p.attrsNth[name] = idx;
      targets = [insts[idx]];
    } else if (p.attrsNth && Object.prototype.hasOwnProperty.call(p.attrsNth, name)) {
      // the instances became homogeneous again — drop the scoping
      delete p.attrsNth[name];
      if (!Object.keys(p.attrsNth).length) delete p.attrsNth;
    }
    for (const el of targets) {
      if (value) el.setAttribute(name, value);
      else el.removeAttribute(name);
    }
    scheduleSave();
  }
  function setStyleProp(key, prop, value) {
    const p = patchFor(key);
    p.style[prop] = value || null; // empty clears the property (removal)
    for (const el of targetsForKey(key)) {
      if (value) el.style.setProperty(prop, value);
      else el.style.removeProperty(prop);
    }
    scheduleSave();
  }
  function setTextContent(key, value, origin) {
    const p = patchFor(key);
    const insts = targetsForKey(key);
    if (p.text == null && insts.length) {
      // First text edit captures seed-route provenance: was = this
      // instance's pre-edit text (the commit-time value anchor); nth =
      // its occurrence index, recorded ONLY when instances diverge —
      // data-backed rows get per-instance commits and per-instance live
      // apply, homogeneous repeats keep every-row semantics; page rides
      // for slug correlation.
      const o = origin && insts.indexOf(origin) >= 0 ? origin : insts[0];
      p.was = o.textContent;
      if (origin && insts.some((el) => el.textContent !== insts[0].textContent)) {
        p.nth = Math.max(0, insts.indexOf(origin));
      }
      p.page = location.pathname;
      // Locale targeting (2026-08-24): the commit writes ONLY the locale
      // being edited — <html lang> first, else the leading /xx/ pathname
      // segment. Absent both, the commit updates every locale (old law).
      const hl = (document.documentElement.lang || '').toLowerCase().slice(0, 2);
      if (/^[a-z]{2}$/.test(hl)) p.locale = hl;
      else {
        const seg = location.pathname.split('/')[1] || '';
        if (/^[a-z]{2}$/.test(seg)) p.locale = seg;
      }
    }
    p.text = value;
    const scoped = p.nth != null && insts[p.nth] ? [insts[p.nth]] : insts;
    for (const el of scoped) {
      if (isTextEditable(el)) el.textContent = value;
    }
    scheduleSave();
  }

  // Normalize-on-write (input[type=color] contract, MDN): the color
  // input only accepts a simple lowercase #rrggbb and renders ANY
  // other value as #000000 — its documented invalid-value default.
  // So the chip is a display and this function is the translator:
  // whatever the model holds (picked hex, typed 3/6-digit hex,
  // computed rgb()/rgba() in comma OR space syntax, even buried in a
  // computed shorthand) becomes canonical 7-char hex or null. Feeding
  // the chip anything else is indistinguishable from black (the
  // 2026-08-25 23:21 bug: a picked #ff0000 re-rendered through
  // rgb-only parsing → black chip, red field).
  function toHex6(v) {
    const s = String(v == null ? '' : v).trim().toLowerCase();
    let m = /^#([0-9a-f]{6})$/.exec(s);
    if (m) return '#' + m[1];
    m = /^#([0-9a-f]{3})$/.exec(s);
    if (m) return '#' + m[1].split('').map((c) => c + c).join('');
    m = /rgba?\(\s*(\d+)\s*[, ]\s*(\d+)\s*[, ]\s*(\d+)/.exec(s);
    if (m) {
      const to = (n) => ('0' + Math.min(255, Number(n)).toString(16)).slice(-2);
      return '#' + to(m[1]) + to(m[2]) + to(m[3]);
    }
    return null;
  }
  // The escape hatch parses declarations into STRUCTURED style patches —
  // the grammar underneath stays the only write path.
  function parseCss(text) {
    const out = {};
    text.split(';').forEach((decl) => {
      const i = decl.indexOf(':');
      if (i < 1) return;
      const k = decl.slice(0, i).trim();
      const v = decl.slice(i + 1).trim();
      if (/^[a-zA-Z-]+$/.test(k) && v) out[k] = v;
    });
    return out;
  }

  function requestCommit() {
    return (async () => {
      await saveDraft();
      const r = await api('POST', '/commit', {});
      if (r && r.ok) say('Commit requested — ' + r.ops.length + ' ops handed to the studio agent');
      else say(r && r.error ? r.error : 'Commit request failed');
    })();
  }
  // The Edit slide's ledger: one row per draft key with per-key revert, the
  // parity line, and reset-all (the tray CTA reuses requestCommit — one
  // action, one home, promoted to the bar).
  function renderLedger(body) {
    body.appendChild(h('div', { class: 'sect', text: 'Draft ledger' }));
    body.appendChild(h('div', { class: 'draftmeta' }));
    const keys = Object.keys(S.draft.patches);
    if (!keys.length && !Object.keys(S.draft.tokens).length) {
      body.appendChild(h('div', { class: 'ctl', style: 'font-size:12px;color:#9aa0ab', text: 'No pending edits — every change you make in a card lands here first.' }));
    }
    keys.forEach((key) => {
      const d = S.draft.patches[key];
      const n = patchProps(d);
      const row = h('div', { class: 'row' });
      const txt = h('span', { class: 'txt', text: key });
      const meta = h('div', { class: 'meta' }, [
        h('span', { text: (d.text != null ? 'text + ' : '') + n + ' style props' }),
      ]);
      const x = h('button', { class: 'stbtn', text: 'revert', title: 'Drop this element pending edits' });
      x.addEventListener('click', async (e) => {
        e.stopPropagation();
        delete S.draft.patches[key];
        S.draftDirty = true;
        await saveDraft();
        location.reload(); // re-served without this patch — source state
      });
      meta.appendChild(x);
      row.appendChild(txt);
      row.appendChild(meta);
      row.addEventListener('click', () => {
        const el = targetsForKey(key)[0];
        if (!el) return;
        const id = el.getAttribute('data-arxa-id');
        if (!id) return;
        if (!S.design) designOn();
        const k = kindOf(el);
        // one-focus law: the jump is a selection request like any other
        // — absorbed while another element holds the focus (the toast
        // says why); the scroll rides WITH a selection, never alone.
        if (!selectEl({ id: id, el: el, label: (el.getAttribute('data-el') || el.tagName.toLowerCase()) + ' · ' + k.kind, group: k.group })) return;
        el.scrollIntoView({ block: 'center', behavior: 'smooth' });
      });
      body.appendChild(row);
    });
    const reset = h('button', { class: 'btn ghost', text: 'Reset all' });
    reset.addEventListener('click', async () => {
      await api('DELETE', '/draft');
      S.draft.tokens = {};
      S.draft.patches = {};
      location.reload();
    });
    body.appendChild(h('div', { class: 'btnrow' }, [reset]));
    renderDraftMeta();
  }

  function renderCardBody(body) {
    const sel = S.selected;
    if (!sel) return;
    const draft = S.draft.patches[sel.key] || {};

    // Content facet — text-bearing elements with no stamped descendants
    // (see isTextEditable: runtime splitter wrappers are not authored
    // structure; genuine composites are refused like the grammar's --text).
    if (isTextEditable(sel.el)) {
      body.appendChild(h('div', { class: 'sect', text: 'Content' }));
      const ta = h('textarea', { rows: '2' });
      ta.value = draft.text != null ? draft.text : sel.el.textContent;
      ta.addEventListener('input', () => setTextContent(sel.key, ta.value, sel.el));
      body.appendChild(h('div', { class: 'facet' }, [ta]));
    }

    body.appendChild(h('div', { class: 'sect', text: 'Facets · ' + sel.group }));
    const cs = getComputedStyle(sel.el);
    const facets = FACET_GROUPS[sel.group] || FACET_GROUPS.generic;
    for (const prop of facets) {
      const has = draft.style && Object.prototype.hasOwnProperty.call(draft.style, prop);
      const cur = has ? draft.style[prop] : null;
      const row = h('div', { class: 'facet' }, [h('label', { text: prop })]);
      let input;
      if (SELECT_OPTS[prop]) {
        input = h('select');
        input.appendChild(h('option', { value: '', text: '—' }));
        for (const o of SELECT_OPTS[prop]) input.appendChild(h('option', { value: o, text: o }));
        input.value = cur || '';
      } else {
        input = h('input', { type: 'text', placeholder: cs.getPropertyValue(prop) || 'unset' });
        input.value = cur || '';
      }
      input.addEventListener('input', () => setStyleProp(sel.key, prop, input.value.trim()));
      if (COLOR_PROPS[prop]) {
        const sw = h('input', { type: 'color', title: 'pick ' + prop });
        sw.value = toHex6(cur) || toHex6(cs.getPropertyValue(prop)) || '#000000';
        sw.addEventListener('input', () => {
          input.value = sw.value;
          setStyleProp(sel.key, prop, sw.value);
        });
        row.appendChild(sw);
        // Chip-follows-field law (operator, 2026-08-25): a color TYPED
        // in the hex field is the same edit as one picked in the chip —
        // the chip must follow the field live, not freeze at its
        // open-time value (report: green typed, page turned green, the
        // chip stayed black through every later frame).
        input.addEventListener('input', () => {
          const hex = toHex6(input.value.trim());
          if (hex) sw.value = hex;
        });
      }
      row.appendChild(input);
      body.appendChild(row);
    }

    // Media section (slice 4): img/video elements search Unsplash/Pexels
    // server-side (keys never reach the browser) and pick swaps the src
    // live — the committed op is an attrs src write through patchFor.
    if (sel.group === 'media' || sel.el.tagName === 'IMG' || sel.el.tagName === 'VIDEO') {
      body.appendChild(h('div', { class: 'sect', text: 'Media' }));
      const isVideo = sel.el.tagName === 'VIDEO';
      const mrow = h('div', { class: 'facet' });
      const q = h('input', { type: 'text', placeholder: isVideo ? 'search Pexels video…' : 'search Unsplash + Pexels…' });
      const go = h('button', { class: 'btn', text: 'Find' });
      mrow.appendChild(q);
      mrow.appendChild(go);
      body.appendChild(mrow);
      const grid = h('div', { style: 'display:flex;flex-wrap:wrap;gap:6px;padding:6px 10px' });
      body.appendChild(grid);
      const creditLine = h('div', { class: 'idline' });
      body.appendChild(creditLine);
      go.addEventListener('click', async () => {
        grid.textContent = '';
        creditLine.textContent = 'searching…';
        const r = await api('POST', '/media/search', { q: q.value.trim(), kind: isVideo ? 'video' : 'photo' });
        grid.textContent = '';
        if (!r || !r.results) { creditLine.textContent = (r && r.error) || 'search failed'; return; }
        if (!r.results.length) { creditLine.textContent = 'no results'; return; }
        r.results.forEach((hit) => {
          const b = h('button', {
            title: hit.credit + ' · ' + hit.provider,
            style: 'width:64px;height:64px;border-radius:8px;overflow:hidden;padding:0;border:1px solid #2a2a35;flex:none',
          });
          const im = h('img', { src: hit.thumb, alt: hit.credit, style: 'width:100%;height:100%;object-fit:cover;display:block' });
          b.appendChild(im);
          b.addEventListener('click', async () => {
            creditLine.textContent = 'copying…';
            const c = await api('POST', '/media/copy', {
              url: hit.full, name: hit.provider + '-' + hit.id + (isVideo ? '.mp4' : '.jpg'),
              credit: hit.credit, provider: hit.provider,
            });
            if (!c || !c.path) { creditLine.textContent = (c && c.error) || 'copy failed'; return; }
            setAttrProp(sel.key, 'src', c.path, sel.el);
            if (isVideo && hit.poster) setAttrProp(sel.key, 'poster', hit.poster, sel.el);
            creditLine.textContent = '✓ ' + c.path + ' — ' + hit.credit;
          });
          grid.appendChild(b);
        });
        creditLine.textContent = r.results.length + ' results — tap to swap in';
      });
      // From assets: what the artifact already holds, one tap to reuse.
      const assetsRow = h('div', { class: 'facet' });
      const loadAssets = h('button', { class: 'btn ghost', text: 'From assets' });
      loadAssets.addEventListener('click', async () => {
        const r = await api('GET', '/media/assets');
        grid.textContent = '';
        if (!r || !r.assets) { creditLine.textContent = (r && r.error) || 'asset list failed'; return; }
        if (!r.assets.length) { creditLine.textContent = 'no local assets yet'; return; }
        r.assets.forEach((path) => {
          const b = h('button', { title: path, text: path.split('/').pop(), style: 'font-size:10px;padding:4px 6px;border-radius:6px;border:1px solid #2a2a35;flex:none' });
          b.addEventListener('click', () => { setAttrProp(sel.key, 'src', path, sel.el); creditLine.textContent = '✓ ' + path; });
          grid.appendChild(b);
        });
      });
      assetsRow.appendChild(loadAssets);
      body.appendChild(assetsRow);
    }
    body.appendChild(h('div', { class: 'sect', text: 'CSS escape hatch' }));
    const css = h('textarea', { rows: '3' });
    css.placeholder = 'prop: value; prop: value;';
    if (draft.style) {
      css.value = Object.keys(draft.style)
        .map((k) => k + ': ' + (draft.style[k] == null ? '' : draft.style[k]))
        .join('; ');
    }
    cssEscapeEl = css; // the footer's Apply CSS reads this live
    body.appendChild(h('div', { class: 'facet' }, [css]));
  }
  // the live CSS-escape textarea (owned by the body, read by the
  // footer's Apply CSS button — the CTA bar is per-tab, not per-body)
  let cssEscapeEl = null;

  // ── the floating card's bottom CTA bar (operator, 2026-08-26) ────────
  function renderCardFooter() {
    cfoot.textContent = '';
    if (!S.card || !S.selected) return;
    if (S.cardTab === 'customise') {
      const apply = h('button', { class: 'btn', text: 'Apply CSS' });
      apply.addEventListener('click', () => {
        if (!cssEscapeEl || !S.selected) return;
        const parsed = parseCss(cssEscapeEl.value);
        const keys = Object.keys(parsed);
        if (!keys.length) { say('No valid declarations parsed'); return; }
        for (const k of keys) setStyleProp(S.selected.key, k, parsed[k]);
        say(keys.length + (keys.length === 1 ? ' property' : ' properties') + ' applied');
        renderCardAgain();
      });
      cfoot.appendChild(apply);
      return;
    }
    const a = S.arxa[S.selected.key];
    if (!a || !a.id) {
      const send = h('button', { class: 'btn', text: 'Send to arxa studio' });
      send.addEventListener('click', () => sendArxa());
      cfoot.appendChild(send);
      return;
    }
    const comp = h('button', { class: 'btn', text: '→ composer' });
    comp.addEventListener('click', () => composeArxa());
    cfoot.appendChild(comp);
    const copy = h('button', { class: 'btn ghost', text: 'copy line' });
    copy.addEventListener('click', () => copyPointerLine());
    cfoot.appendChild(copy);
    const again = h('button', { class: 'btn ghost', text: 'send again' });
    again.addEventListener('click', () => sendArxa());
    cfoot.appendChild(again);
  }

  // ── the Arxa tab (operator, 2026-08-26): the studio handoff lives in
  //    the floating card now — the panel's green card retired. The pane
  //    shows everything the old card showed; the CTAs live in the
  //    footer. No auto-send: viewing the tab sends nothing.
  function renderArxaPane() {
    paneArxa.textContent = '';
    if (!S.selected) return;
    const sel = S.selected;
    const a = S.arxa[sel.key];
    if (!a || !a.id) {
      paneArxa.appendChild(h('div', { class: 'sect', text: 'arxa studio' }));
      paneArxa.appendChild(h('div', { class: 'arxaline',
        text: 'Send this element to the arxa studio composer. The agent receives an organized context — identity, computed styles, a snapshot — and edits ONLY this element via the design patch contract.' }));
      return;
    }
    paneArxa.appendChild(h('div', { class: 'sect', text: 'arxa studio' }));
    paneArxa.appendChild(h('div', { class: 'arxaid', text: '✨ design selection ' + a.id }));
    const chips = h('div', { style: 'display:flex;gap:4px;flex-wrap:wrap;padding:4px 10px' });
    chips.appendChild(h('span', { class: 'kchip', text: a.label || 'element' }));
    chips.appendChild(h('span', { class: 'kchip', text: (a.kind || '') + ' · ' + (a.group || '') }));
    chips.appendChild(h('span', { class: 'kchip', text: a.route || '/' }));
    paneArxa.appendChild(chips);
    if (a.png) paneArxa.appendChild(h('div', { class: 'arxaline',
      text: '📸 snapshot captured — “→ composer” attaches it to the draft' }));
    if (a.text) paneArxa.appendChild(h('div', { class: 'arxaline',
      style: 'white-space:nowrap;overflow:hidden;text-overflow:ellipsis',
      text: '“' + a.text.slice(0, 90) + '”' }));
    paneArxa.appendChild(h('div', { class: 'arxaline',
      text: 'the agent fetches the organized context (styles · law · screenshot) from the design server and edits ONLY this element' }));
    if (a.status) {
      const st = h('div', { class: 'arxastatus' + (a.statusOk ? ' ok' : ''), text: a.status });
      paneArxa.appendChild(st);
    }
  }

  // sendArxa = the old askArxa, relocated into the tab flow: capture +
  // POST, then remember the handoff per element (in-session) so the
  // pane keeps its sent state through card close/reopen.
  async function sendArxa() {
    const sel = S.selected;
    if (!sel) return;
    const a = S.arxa[sel.key] || (S.arxa[sel.key] = {});
    a.status = 'capturing…'; a.statusOk = false;
    renderArxaPane(); renderCardFooter();
    const cs = getComputedStyle(sel.el);
    const digest = {};
    ['font-size', 'font-weight', 'line-height', 'color', 'background-color',
      'padding', 'gap', 'border-radius'].forEach((p) => {
      const v = cs.getPropertyValue(p);
      if (v) digest[p] = v.trim();
    });
    say('Capturing selection…');
    const png = await captureElement(sel.el);
    const r = await api('POST', '/selection', {
      // Protocol v2 (2026-08-26): the tabbed card's Send STORES the
      // selection; only → composer inserts it (no auto-send law). The
      // marker rides the broadcast frame so a v2-aware panel can tell
      // this apart from a stale pre-tabs island whose ask WAS the whole
      // flow — v-less frames still deliver straight to the composer.
      v: 2,
      key: sel.key,
      label: sel.label,
      kind: sel.el.tagName.toLowerCase(),
      group: sel.group,
      route: location.pathname,
      text: sel.el.textContent.trim().slice(0, 400) || undefined,
      styles: digest,
      png: png || undefined,
    });
    if (r && r.id) {
      a.id = r.id;
      a.fetch = r.fetch;
      a.label = sel.label.split(' · ')[0];
      a.kind = sel.el.tagName.toLowerCase();
      a.group = sel.group;
      a.route = location.pathname;
      a.png = !!png;
      a.text = sel.el.textContent.trim().slice(0, 90);
      a.status = ''; a.statusOk = false;
      say('Sent to arxa studio — design selection ' + r.id);
    } else {
      a.status = (r && r.error) || 'send failed'; a.statusOk = false;
      say((r && r.error) || 'handoff failed');
    }
    renderArxaPane(); renderCardFooter();
  }

  // → composer: POST /compose; the panel (always-on SSE) inserts the
  // pointer line + snapshot into the composer and acks; the ack rides
  // the same dial event stream back here. The button never fakes a ✓ —
  // the status line waits for the REAL ack (4s budget).
  let composeWaiter = null;
  async function composeArxa() {
    const sel = S.selected;
    const a = sel && S.arxa[sel.key];
    if (!a || !a.id) return;
    a.status = 'sending to composer…'; a.statusOk = false; a.ackFalse = false;
    renderArxaPane(); renderCardFooter();
    // api() never throws and returns the parsed body — an error body
    // carries {error}, a success carries {id}.
    const r = await api('POST', '/compose', { id: a.id });
    if (!r || !r.id) {
      a.status = (r && r.error) || 'compose failed'; a.statusOk = false;
      renderArxaPane(); renderCardFooter();
      return;
    }
    if (composeWaiter) clearTimeout(composeWaiter);
    composeWaiter = setTimeout(() => {
      composeWaiter = null;
      const cur = S.selected && S.arxa[S.selected.key];
      if (cur && cur.id === a.id && cur.status === 'sending to composer…') {
        cur.status = cur.ackFalse
          ? 'studio found no open composer — click into a session, '
            + 'then → composer again'
          : 'no studio answered — is arxa studio open AND reloaded?';
        cur.ackFalse = false;
        cur.statusOk = false;
        if (S.card) { renderArxaPane(); }
      }
    }, 4000);
  }

  function pointerLineFor(a) {
    return 'design selection #' + (a.id || '') + ' · ' + (a.label || 'element') +
      ' · ' + (a.route || '/') +
      ' · fetch ' + location.origin + (a.fetch || '/__dial/selection/' + (a.id || '')) +
      ' — edit ONLY this element via the design patch contract; structure is locked.';
  }
  async function copyPointerLine() {
    const sel = S.selected;
    const a = sel && S.arxa[sel.key];
    if (!a || !a.id) return;
    const line = pointerLineFor(a);
    try {
      await navigator.clipboard.writeText(line);
      say('Pointer line copied');
      return;
    } catch (_) {}
    // clipboard API refused (iframe without clipboard-write, insecure
    // context): deprecated-but-universal fallback, then honest failure.
    try {
      const ta = h('textarea', { style: 'position:fixed;left:-9999px' });
      ta.value = line;
      root.appendChild(ta);
      ta.select();
      document.execCommand('copy');
      ta.remove();
      say('Pointer line copied');
    } catch (_) {
      say('Copy blocked — line: ' + line);
    }
  }

  // ── the token tier (global design tokens, decision 3) ──────────────────
  function pageTokenNames() {
    const names = [];
    for (const sheet of document.styleSheets) {
      let rules;
      try { rules = sheet.cssRules; } catch (_) { continue; } // cross-origin sheet
      for (const r of rules) {
        if (r.selectorText && (r.selectorText === ':root' || r.selectorText === 'html')) {
          for (const p of r.style) {
            if (p.indexOf('--') === 0 && names.indexOf(p) === -1) names.push(p);
          }
        }
      }
    }
    for (const k of Object.keys(S.draft.tokens)) if (names.indexOf(k) === -1) names.push(k);
    return names.sort();
  }

  let tokenStyleEl = null;
  function applyTokensLive() {
    if (!tokenStyleEl) {
      tokenStyleEl = document.createElement('style');
      tokenStyleEl.id = 'arxa-draft-tokens-live';
      document.head.appendChild(tokenStyleEl); // page-level: shadow styles cannot reach the design
    }
    const decls = Object.keys(S.draft.tokens).map((k) => k + ': ' + S.draft.tokens[k]).join('; ');
    tokenStyleEl.textContent = ':root{' + decls + '}';
  }

  function renderTokensBody(body) {
    body.appendChild(h('div', { class: 'ctl', style: 'font-size:12px;color:#9aa0ab', text: 'The design tokens this page declares (:root custom properties). Edits override live and auto-save to the Draft Overlay.' }));
    const rootCs = getComputedStyle(document.documentElement);
    const names = pageTokenNames();
    if (!names.length) {
      body.appendChild(h('div', { class: 'ctl', style: 'font-size:12px', text: 'No :root custom properties found — add an override below.' }));
    }
    for (const name of names) {
      const row = h('div', { class: 'facet' }, [h('label', { text: name, title: name })]);
      const input = h('input', { type: 'text', placeholder: rootCs.getPropertyValue(name).trim() || 'unset' });
      input.value = S.draft.tokens[name] || '';
      input.addEventListener('input', () => {
        const v = input.value.trim();
        if (v) S.draft.tokens[name] = v;
        else delete S.draft.tokens[name];
        applyTokensLive();
        scheduleSave();
      });
      row.appendChild(input);
      body.appendChild(row);
    }
    body.appendChild(h('div', { class: 'sect', text: 'New token override' }));
    const nameIn = h('input', { type: 'text', placeholder: '--token-name' });
    const valIn = h('input', { type: 'text', placeholder: 'value' });
    const add = h('button', { class: 'btn', text: 'Add' });
    add.addEventListener('click', () => {
      const n = nameIn.value.trim();
      const v = valIn.value.trim();
      if (!/^--[a-zA-Z0-9-]+$/.test(n) || !v) { say('A token needs a --name and a value'); return; }
      S.draft.tokens[n] = v;
      applyTokensLive();
      scheduleSave();
      renderTraySlide('tweak');
    });
    body.appendChild(h('div', { class: 'facet' }, [nameIn]));
    body.appendChild(h('div', { class: 'facet' }, [valIn]));
    body.appendChild(h('div', { class: 'btnrow' }, [add]));
  }


  // ── element capture (Ask arxa, slice 7): best-effort PNG of the
  // selection for the composer's image rail. foreignObject rasterization
  // with computed styles inlined and <img> swapped to same-origin data
  // URLs; ANY failure returns null — the handoff proceeds without the
  // image (the server context still carries text + styles).
  async function captureElement(el) {
    try {
      const r = el.getBoundingClientRect();
      const w = Math.min(480, Math.max(2, Math.round(r.width)));
      const h = Math.max(2, Math.round(r.height * (w / r.width)));
      const clone = el.cloneNode(true);
      const cs = getComputedStyle(el);
      const pick = ['font', 'color', 'background', 'padding', 'margin',
        'display', 'flex-direction', 'gap', 'align-items', 'justify-content',
        'border', 'border-radius', 'width', 'height', 'overflow'];
      // Computed font families arrive double-quoted ("Inter") — inside the
      // double-quoted style="..." XML attribute they would break the SVG
      // parse and the raster load dies with onerror (measured). Single-
      // quote them; CSS treats both as identical.
      const decls = pick
        .filter((p) => cs.getPropertyValue(p))
        .map((p) => p + ':' + cs.getPropertyValue(p))
        .join(';')
        .replace(/"/g, "'");
      // Same-origin imgs → data URLs or drop them (a tainted canvas would
      // kill the whole export).
      const imgs = [...clone.querySelectorAll('img')];
      imgs.forEach((im) => {
        try {
          const c = document.createElement('canvas');
          c.width = im.naturalWidth || 100; c.height = im.naturalHeight || 100;
          c.getContext('2d').drawImage(im, 0, 0);
          if (c.width && c.height) im.src = c.toDataURL('image/png');
        } catch (_) { im.remove(); }
      });
      const svg = '<svg xmlns="http://www.w3.org/2000/svg" width="' + w + '" height="' + h + '">' +
        '<foreignObject width="100%" height="100%">' +
        '<div xmlns="http://www.w3.org/1999/xhtml" style="' + decls + '">' +
        new XMLSerializer().serializeToString(clone) + '</div></foreignObject></svg>';
      const url = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg);
      const img = new Image();
      img.src = url;
      // SVG data URLs decode asynchronously — drawing before load yields
      // a blank raster. Wait it out; a decode failure is a null capture.
      await new Promise((res, rej) => {
        img.onload = res;
        img.onerror = rej;
        setTimeout(rej, 2500);
      });
      const canvas = document.createElement('canvas');
      canvas.width = w; canvas.height = h;
      const ctx = canvas.getContext('2d');
      ctx.drawImage(img, 0, 0);
      return canvas.toDataURL('image/png');
    } catch (_) {
      return null;
    }
  }

  // ── the floating smart card (Edit Mode's inspector) ───────────────────
  // Dropdown-style smart anchor: prefer the element's right, flip left on
  // clip, clamp on both axes, vertical flip when the bottom would clip.
  const card = h('div', { id: 'card' });
  const chead = h('div', { id: 'chead' });
  const cidrow = h('div', { id: 'cidrow' });
  const cbodyEl = h('div', { class: 'cbody' });
  const cfoot = h('div', { id: 'cfoot' });
  card.appendChild(chead);
  card.appendChild(cidrow);
  card.appendChild(cbodyEl);
  card.appendChild(cfoot);
  root.appendChild(card);
  // the two tab panes live inside the scrolling body; the identity row
  // and both bars stay fixed. Toggling is display-only — a switch never
  // re-renders inputs, so facet values and focus survive.
  const paneCustomise = h('div', { class: 'tabpane' });
  const paneArxa = h('div', { class: 'tabpane' });
  cbodyEl.appendChild(paneCustomise);
  cbodyEl.appendChild(paneArxa);

  // CARD DRAG (operator, 2026-08-26): the card is anchored by default
  // (dropdown anchor + float tracking) but the header is a grab handle —
  // a manual drag OVERRIDES the anchor law. The drop point becomes a
  // pin: positionCard honors it (clamped to the viewport) instead of
  // re-deriving from the element, so a dragged card stays where it was
  // dropped through scrolls and resizes. Opening the card again on a
  // fresh selection clears the pin and re-anchors.
  let cardPin = null;
  chead.addEventListener('pointerdown', (e) => {
    if (e.pointerType === 'mouse' && e.button !== 0) return;
    if (e.target.closest('button')) return;
    const grab = card.getBoundingClientRect();
    const ox = e.clientX - grab.left, oy = e.clientY - grab.top;
    const place = (cx, cy) => {
      const x = Math.min(Math.max(8, cx - ox),
        Math.max(8, innerWidth - grab.width - 8));
      const y = Math.min(Math.max(8, cy - oy),
        Math.max(8, innerHeight - grab.height - 8));
      card.style.left = x + 'px';
      card.style.top = y + 'px';
      cardPin = { x, y };
    };
    const move = (ev) => place(ev.clientX, ev.clientY);
    const done = () => {
      chead.removeEventListener('pointermove', move);
      chead.removeEventListener('pointerup', done);
      chead.removeEventListener('pointercancel', done);
    };
    // Pointer capture keeps the drag alive when the cursor leaves the
    // card and makes the post-drag click land on the header (never on
    // a row the card happens to pass over).
    try { chead.setPointerCapture(e.pointerId); } catch (_) {}
    chead.addEventListener('pointermove', move);
    chead.addEventListener('pointerup', done);
    chead.addEventListener('pointercancel', done);
    e.preventDefault();
  });

  function positionCard() {
    if (!S.selected) return;
    const W = 300, GAP = 12;
    if (cardPin) { // manual drop wins over the anchor law
      const ch = card.offsetHeight || 240;
      const x = Math.min(Math.max(8, cardPin.x), Math.max(8, innerWidth - W - 8));
      const y = Math.min(Math.max(8, cardPin.y), Math.max(8, innerHeight - ch - 8));
      card.style.left = x + 'px';
      card.style.top = y + 'px';
      return;
    }
    const r = S.selected.el.getBoundingClientRect();
    let x = r.right + GAP;
    if (x + W > innerWidth - 8) x = r.left - W - GAP;
    if (x < 8) x = Math.min(Math.max(8, r.left), Math.max(8, innerWidth - W - 8));
    const ch = card.offsetHeight || 240;
    let y = r.top;
    if (y + ch > innerHeight - 8) y = r.top + r.height - ch;
    y = Math.min(Math.max(8, y), Math.max(8, innerHeight - ch - 8));
    card.style.left = x + 'px';
    card.style.top = y + 'px';
  }
  function renderCardAgain() {
    if (!S.card) return;
    paneCustomise.textContent = '';
    renderCardBody(paneCustomise);
    positionCard();
  }
  // Reactivity law (operator, 2026-08-26): an OPEN card documents its
  // element LIVE — every external restyle (a draft sync, an axes
  // publish or preview pick) re-renders the facets so the swatch never
  // lies about the page. Two guards: while the author is mid-edit
  // inside the card a re-render would drop their cursor, so that beat
  // is skipped (the next one catches up); and the CSS escape hatch is
  // deferred-until-Apply by design, so its unapplied text survives
  // every re-render instead of silently disappearing.
  let cardRefreshPending = false;
  function refreshOpenCard() {
    if (!S.card || !S.selected) return;
    // Shadow-retargeting law: document.activeElement returns the HOST
    // when the focused element lives inside this shadow root, so the
    // guard must ask the ROOT (ShadowRoot.activeElement is not
    // retargeted) or every mid-edit frame would slip past the skip and
    // re-render under the author's cursor.
    const a = (root.activeElement || document.activeElement);
    if (a && card.contains(a) &&
        (a.tagName === 'INPUT' || a.tagName === 'TEXTAREA' ||
         a.tagName === 'SELECT')) {
      // The beat is DEFERRED, not dropped: when focus later leaves the
      // card the deferred refresh runs (the focusout hook below). A
      // dropped beat left the card stale forever — the report's chip
      // stayed black through every frame after one guard fired.
      cardRefreshPending = true;
      return;
    }
    const unapplied = cssEscapeEl ? cssEscapeEl.value : '';
    renderCardAgain();
    if (cssEscapeEl && unapplied.trim()) cssEscapeEl.value = unapplied;
    cardRefreshPending = false;
  }
  // Catch-up half of the reactivity law: focusout bubbles out of every
  // card field; a tick later (focus has settled) a deferred refresh
  // runs — unless focus moved to ANOTHER field inside the card (that
  // field's own guard re-defers on its frames, and re-rendering under
  // a fresh cursor is exactly what the guard exists to prevent).
  card.addEventListener('focusout', () => {
    setTimeout(() => {
      if (!cardRefreshPending || !S.card) return;
      const a = (root.activeElement || document.activeElement);
      if (a && card.contains(a)) return;
      refreshOpenCard();
    }, 0);
  });
  function openCard() {
    if (!S.selected) return;
    S.card = S.selected.key;
    cardPin = null; // a fresh open re-anchors (drag law above)
    // TAB LAW (operator, 2026-08-26): Customise is the default; a
    // different element never inherits the last tab; the SAME element
    // restores the tab it had when the card closed.
    S.cardTab = S.cardTabs[S.selected.key] === 'arxa' ? 'arxa' : 'customise';
    chead.textContent = '';
    for (const [tid, tlabel] of [['customise', 'Customise'], ['arxa', 'Arxa']]) {
      const tb = h('button', { class: 'tab', 'data-tab': tid, text: tlabel });
      tb.addEventListener('click', (e) => { e.stopPropagation(); setCardTab(tid); });
      chead.appendChild(tb);
    }
    const go = h('button', {
      class: 'cgo', title: 'Track back to the selected element',
      'aria-label': 'Track back to the selected element',
    });
    go.innerHTML = ICONS.dial; // the crosshair
    go.addEventListener('click', (e) => { e.stopPropagation(); trackBack(); });
    chead.appendChild(go);
    const x = h('button', { class: 'cclose', title: 'Close card', 'aria-label': 'Close card', text: '×' });
    x.addEventListener('click', (e) => { e.stopPropagation(); closeCard(); });
    chead.appendChild(x);
    cidrow.textContent = '';
    cidrow.appendChild(h('span', { text: S.selected.label.split(' · ')[0] }));
    cidrow.appendChild(h('span', { class: 'kchip', text: S.selected.group }));
    cidrow.appendChild(h('div', { class: 'idline', text: S.selected.key === S.selected.id ? S.selected.id : S.selected.id + ' → ' + S.selected.key }));
    card.classList.add('open');
    paneCustomise.textContent = '';
    renderCardBody(paneCustomise);
    renderArxaPane();
    setCardTab(S.cardTab);
    positionCard();
    dialPanelChanged();
  }
  function setCardTab(t) {
    S.cardTab = t;
    if (S.selected) S.cardTabs[S.selected.key] = t;
    paneCustomise.classList.toggle('on', t === 'customise');
    paneArxa.classList.toggle('on', t === 'arxa');
    [...chead.querySelectorAll('.tab')].forEach((b) =>
      b.classList.toggle('on', b.getAttribute('data-tab') === t));
    renderCardFooter();
  }
  function closeCard() {
    S.card = null;
    cardPin = null;
    card.classList.remove('open');
    dialPanelChanged();
  }
  // TRACK-BACK (operator, 2026-08-26): "i want to get back to the
  // selected element from the floating card ... even if scrolled or
  // navigated between pages". Three tiers, one button: the element is
  // still in this document → center it (BOTH axes — this design
  // scrolls horizontally); a same-page swap killed the node but the
  // identity lives here → rebind and center; the element lived on
  // ANOTHER route (hx-boost wipes body children while the island,
  // off-body, floats on) → stash {key, nth, route} and navigate home;
  // the fresh boot's restoreTrackback rebuilds the selection centered.
  // SMOOTH-SCROLL LAW: this artifact owns the wheel (a Lenis-style
  // lerp on the GSAP ticker — window.NIBSmoothScroll). It resyncs on
  // scrolls it did not drive, so scrollIntoView survives, but the
  // page's own scrollTo is the first-class path: element at top +
  // offset centers it, animated at the site's own easing.
  function centerElement(el) {
    try {
      const lib = window.NIBSmoothScroll;
      if (lib && typeof lib.scrollTo === 'function') {
        const r = el.getBoundingClientRect();
        lib.scrollTo(el, {
          offset: -Math.max(0, (window.innerHeight - r.height) / 2),
        });
        return;
      }
    } catch (_) {}
    el.scrollIntoView({ block: 'center', inline: 'center' });
  }
  function trackBack() {
    if (!S.selected) return;
    const sel = S.selected;
    if (sel.el && sel.el.isConnected) {
      centerElement(sel.el);
      return;
    }
    const insts = targetsForKey(sel.key).filter((x) => x.isConnected);
    if (insts.length && sel.route === location.pathname) {
      const el = insts[Math.min(sel.nth || 0, insts.length - 1)];
      const k = kindOf(el);
      selectEl({
        id: el.getAttribute('data-arxa-id'), el: el,
        label: (el.getAttribute('data-el') || el.tagName.toLowerCase()) + ' · ' + k.kind,
        group: k.group,
      });
      centerElement(el);
      return;
    }
    try {
      sessionStorage.setItem('arxa-dial-trackback', JSON.stringify({
        key: sel.key, nth: sel.nth || 0, route: sel.route || '/',
      }));
    } catch (_) {}
    location.assign(sel.route || '/');
  }
  // FLOAT TRACKING (improvement 2, floating-ui autoUpdate practice,
  // 2026-08-25): an anchored panel re-derives its position on every
  // frame-worthy signal — capture-phase scroll (scroll does not bubble,
  // capture still sees nested scroll containers), window resize, and one
  // rAF to coalesce bursts so a fast wheel never thrashes layout reads.
  // Before this the card clamped ONCE at open and then sat still while
  // its anchor scrolled out from under it.
  let floatTrackRaf = false;
  function trackFloats() {
    if (floatTrackRaf) return;
    floatTrackRaf = true;
    requestAnimationFrame(() => {
      floatTrackRaf = false;
      if (S.card) positionCard();
      if (threadPin) positionThread();
    });
  }
  addEventListener('scroll', trackFloats, { passive: true, capture: true });
  addEventListener('resize', trackFloats);

  // ── tweaks (Tweak slide prefs; persisted per browser) ─────────────────
  const TWEAK = {
    motion: true, dur: 0.5, zeta: 0.86,
    tint: 0.82, blur: 16, glow: 0.22, rad: 16, always: false,
  };
  function loadTweakPrefs() {
    try {
      const j = JSON.parse(localStorage.getItem('arxa-dial-tweak') || 'null');
      if (j) for (const k of Object.keys(TWEAK)) if (j[k] !== undefined) TWEAK[k] = j[k];
    } catch (_) {}
  }
  function saveTweakPrefs() {
    try { localStorage.setItem('arxa-dial-tweak', JSON.stringify(TWEAK)); } catch (_) {}
  }
  function applyTweakPrefs() {
    loadTweakPrefs();
    REVEAL.dur = TWEAK.dur;
    REVEAL.zeta = TWEAK.zeta;
    host.style.setProperty('--tint', String(TWEAK.tint));
    host.style.setProperty('--tblur', TWEAK.blur + 'px');
    host.style.setProperty('--glow', String(TWEAK.glow));
    host.style.setProperty('--trayrad', TWEAK.rad + 'px');
    host.classList.toggle('nomotion', !TWEAK.motion);
  }

  // ── the axes plane (arc 1, 2026-08-25): style/theme, dial-owned ────────
  // The server already rendered the active pick into the page; these flip
  // it live in THIS document (link.disabled + the html data-theme attr) and
  // keep the URL honest — the URL is the receipt (the Storybook-globals
  // pattern). Authors publish via POST /__dial/axes; guests only ride the
  // URL, and a persistent badge marks on-screen ≠ published.
  function axesPreviewing() {
    return !!S.axes && (S.axes.current.style !== S.axes.published.style ||
      S.axes.current.theme !== S.axes.published.theme);
  }
  function applyAxes(style, theme) {
    document.querySelectorAll('link[data-axes-style]').forEach((link) => {
      link.disabled = link.getAttribute('data-axes-style') !== style;
    });
    if (!theme || theme === 'system') {
      document.documentElement.removeAttribute('data-theme');
    } else {
      document.documentElement.setAttribute('data-theme', theme);
    }
    S.axes.current = { style: style, theme: theme || 'system' };
    syncAxesUrl();
    updatePreviewMark();
    // An axes flip restyles every element at stylesheet level — an
    // open card's facets must follow or its swatches go stale against
    // the page (the reactivity law above; same guard applies).
    refreshOpenCard();
    if (S.tray === 'style') renderTraySlide('style');
  }
  function syncAxesUrl() {
    try {
      const url = new URL(location.href);
      const current = S.axes.current, published = S.axes.published;
      if (current.style === published.style &&
          current.theme === published.theme) {
        url.searchParams.delete('style');
        url.searchParams.delete('theme');
      } else {
        url.searchParams.set('style', current.style);
        url.searchParams.set('theme', current.theme);
      }
      history.replaceState(null, '', url);
    } catch (_) { /* an unwritable URL just keeps its params */ }
  }
  function updatePreviewMark() {
    dock.classList.toggle('previewing', axesPreviewing());
    dockBtn.title = axesPreviewing()
      ? 'Design Dial — previewing unpublished style/theme'
      : 'Design Dial — arxa';
  }
  async function flipAxes(patch) {
    if (!S.axes) return;
    const next = {
      style: patch.style || S.axes.current.style,
      theme: patch.theme || S.axes.current.theme,
    };
    applyAxes(next.style, next.theme);
    if (S.mode !== 'author') return; // guests ride the URL, never the store
    const res = await api('POST', '/axes', next);
    if (res && res.ok && res.axes) {
      S.axes.published = { style: res.axes.style, theme: res.axes.theme };
      syncAxesUrl();
      updatePreviewMark();
    } else {
      say('Could not publish — the axes store refused');
    }
  }
  function renderStyleBody(body) {
    if (!S.axes) return;
    body.appendChild(h('div', { class: 'sect', text: 'Style' }));
    const seg = h('div', { class: 'seg' });
    S.axes.styles.forEach((id) => {
      const btn = h('button', {
        class: S.axes.current.style === id ? 'on' : '',
        text: id,
      });
      btn.addEventListener('click', () => flipAxes({ style: id }));
      seg.appendChild(btn);
    });
    body.appendChild(seg);
    if (S.axes.themes.length) {
      body.appendChild(h('div', { class: 'sect', text: 'Theme' }));
      const themeSeg = h('div', { class: 'seg' });
      S.axes.themes.forEach((id) => {
        const btn = h('button', {
          class: S.axes.current.theme === id ? 'on' : '',
          text: id,
        });
        btn.addEventListener('click', () => flipAxes({ theme: id }));
        themeSeg.appendChild(btn);
      });
      body.appendChild(themeSeg);
    }
    body.appendChild(h('div', {
      class: 'ctl', style: 'font-size:11px;color:#9aa0ab',
      text: S.mode === 'author'
        ? 'Your pick publishes for everyone viewing this design.'
        : 'Preview applies to your view only — the URL carries it.',
    }));
    if (S.store === 'memory') {
      body.appendChild(h('div', {
        class: 'ctl', style: 'font-size:11px;color:#9aa0ab',
        text: 'local process store — picks reset when the server restarts',
      }));
    }
    if (axesPreviewing()) {
      const note = h('div', { class: 'pvnote' }, [
        h('span', { text: 'Previewing — not the published look' }),
      ]);
      const reset = h('button', { text: 'Reset to published' });
      reset.addEventListener('click', () => {
        applyAxes(S.axes.published.style, S.axes.published.theme);
      });
      note.appendChild(reset);
      body.appendChild(note);
    }
  }

  // ── the tray (Studio): glass bottom sheet, 5-slide snap carousel ──────
  const SLIDES = [
    ['edit', 'Edit'], ['comments', 'Comments'], ['settings', 'Settings'],
    ['tweak', 'Tweak'], ['style', 'Style'], ['ship', 'Ship'],
  ];
  function traySlideList() {
    // Style rides the axes plane (arc 1): present only when the server
    // declared axes for this artifact — and for guests too, whose flips
    // ride the URL override and never touch the store.
    return SLIDES.filter(([id]) =>
      (id !== 'style' || !!S.axes) &&
      (S.mode !== 'guest' || id === 'comments' || id === 'style'));
  }
  const tray = h('div', { id: 'tray' });
  const grabber = h('div', { id: 'grabber' }, [h('div', { class: 'gbar' })]);
  const tbar = h('div', { id: 'tbar' });
  const ttitle = h('span', { id: 'ttitle', text: 'Studio' });
  const dots = h('div', { id: 'dots' });
  const ctaBtn = h('button', { id: 'cta' });
  const closeBtn = h('button', { id: 'tclose', title: 'Close tray', 'aria-label': 'Close tray', text: '×' });
  // tabindex=0 is the keyboard escape hatch (WAI carousel practice): the
  // snap track has no visible scrollbar and its slides hold focusable
  // controls only sometimes — a focusable, labelled region makes the
  // arrows below reachable at all.
  const track = h('div', {
    id: 'track', tabindex: '0', role: 'region',
    'aria-label': 'Studio slides — arrow keys move between slides',
  });
  tbar.appendChild(ttitle);
  tbar.appendChild(dots);
  tbar.appendChild(ctaBtn);
  tbar.appendChild(closeBtn);
  tray.appendChild(grabber);
  tray.appendChild(tbar);
  tray.appendChild(track);
  root.appendChild(tray);
  const slideBodies = {};
  let trayBuiltFor = null;

  closeBtn.addEventListener('click', () => closeTray());
  grabber.addEventListener('click', () => closeTray());

  function buildTraySlides() {
    const list = traySlideList();
    const key = list.map((s) => s[0]).join('|');
    if (trayBuiltFor === key) return;
    trayBuiltFor = key;
    track.textContent = '';
    dots.textContent = '';
    slideBodies.bodies = {};
    list.forEach(([id, label], i) => {
      const body = h('div', { class: 'slidebody' });
      const slide = h('div', {
        class: 'slide', 'data-slide': id,
        role: 'group', 'aria-roledescription': 'slide',
        'aria-label': (i + 1) + ' of ' + list.length + ': ' + label,
      }, [body]);
      slideBodies[id] = body;
      track.appendChild(slide);
      const d = h('button', {
        class: 'dotbtn', 'data-i': String(i),
        'aria-label': 'Go to ' + label + ' slide', 'aria-controls': 'track',
      });
      d.addEventListener('click', () => goToSlide(i));
      dots.appendChild(d);
    });
  }
  // Deterministic slide navigation (improvement 3): offsetLeft, NOT
  // index*width — desktop slides are calc(100% - 96px) with the edge
  // peek, so width math lands between snap points (trayIndex's comment
  // documents the same trap).
  function goToSlide(i) {
    const kids = [...track.children];
    if (!kids.length) return;
    i = Math.max(0, Math.min(kids.length - 1, i));
    track.scrollTo({ left: kids[i].offsetLeft, behavior: TWEAK.motion ? 'smooth' : 'auto' });
  }
  // Dots: roving arrows (WAI carousel) — Arrow/Home/End move focus AND
  // the slide together; Tab still leaves the group.
  dots.addEventListener('keydown', (e) => {
    const btns = [...dots.querySelectorAll('.dotbtn')];
    if (!btns.length) return;
    let i = trayIndex();
    if (e.key === 'ArrowRight') i++;
    else if (e.key === 'ArrowLeft') i--;
    else if (e.key === 'Home') i = 0;
    else if (e.key === 'End') i = btns.length - 1;
    else return;
    e.preventDefault();
    i = Math.max(0, Math.min(btns.length - 1, i));
    btns[i].focus();
    goToSlide(i);
  });
  // Track: arrows on the focused region itself. e.target guard — arrows
  // from controls INSIDE a slide (text inputs, selects) must keep their
  // native meaning and never bubble into a slide flip.
  track.addEventListener('keydown', (e) => {
    if (e.target !== track) return;
    const n = track.children.length;
    if (!n) return;
    const i = trayIndex();
    if (e.key === 'ArrowRight' || e.key === 'PageDown') { e.preventDefault(); goToSlide(i + 1); }
    else if (e.key === 'ArrowLeft' || e.key === 'PageUp') { e.preventDefault(); goToSlide(i - 1); }
    else if (e.key === 'Home') { e.preventDefault(); goToSlide(0); }
    else if (e.key === 'End') { e.preventDefault(); goToSlide(n - 1); }
  });
  function trayIndex() {
    // Nearest-slide, not width math: desktop slides are calc(100% - 96px)
    // (the edge peek), so scrollLeft/clientWidth lies there. offsetLeft of
    // each slide is the truth the snap points actually use.
    const kids = [...track.children];
    let best = 0, bd = Infinity;
    kids.forEach((s, i) => {
      const d = Math.abs(s.offsetLeft - track.scrollLeft);
      if (d < bd) { bd = d; best = i; }
    });
    return best;
  }
  function currentSlideId() {
    const list = traySlideList();
    return list.length ? list[trayIndex()][0] : null;
  }
  function syncTrayChrome() {
    const list = traySlideList();
    const i = trayIndex();
    ttitle.textContent = list[i] ? list[i][1] : 'Studio';
    dots.querySelectorAll('.dotbtn').forEach((d, j) => {
      d.classList.toggle('cur', j === i);
      // Roving tabindex (WAI carousel): one tab stop for the whole dot
      // group; arrows (handler above) move within it.
      d.tabIndex = j === i ? 0 : -1;
      if (j === i) d.setAttribute('aria-current', 'true');
      else d.removeAttribute('aria-current');
    });
    updateTrayCta();
  }
  function updateTrayCta() {
    if (!S.tray) return;
    const id = currentSlideId();
    ctaBtn.className = '';
    ctaBtn.disabled = false;
    ctaBtn.title = '';
    if (id === 'edit') {
      const n = Object.keys(S.draft.patches).length + Object.keys(S.draft.tokens).length;
      ctaBtn.textContent = 'Commit · ' + n;
      ctaBtn.disabled = n === 0;
      ctaBtn.title = n === 0 ? 'Nothing to commit yet' : 'Hand the draft to the studio agent';
    } else if (id === 'comments') {
      ctaBtn.textContent = 'Share';
      ctaBtn.title = 'Mint a personal client link (view + comment, 30 days)';
    } else if (id === 'ship') {
      ctaBtn.textContent = 'Deploy';
      // Enabled only when the pipeline allows AND the server's deploy
      // gates are satisfied (wrangler present, CF env, eject dir). The
      // blockers render in the Ship slide.
      const allowed = !shipSt?.pr && shipSt?.branch === 'main' && shipSt?.dirty === 0;
      ctaBtn.disabled = !(allowed && S.deployReady);
      ctaBtn.title = ctaBtn.disabled
        ? 'Enabled when the tree is clean on main with no open PR and the deploy gates pass (see Ship slide)'
        : 'wrangler → Cloudflare Pages — your tap is the approval';
    } else {
      ctaBtn.className = 'off';
    }
  }
  ctaBtn.addEventListener('click', () => {
    const id = currentSlideId();
    if (id === 'edit') return requestCommit();
    if (id === 'comments') {
      const body = slideBodies.comments;
      if (body) ensureGuestShareUI(body, true);
      return;
    }
    if (id === 'ship') return shipVerb('/ship/deploy');
  });
  track.addEventListener('scroll', () => {
    if (!S.tray) return;
    S.tray = currentSlideId();
    syncTrayChrome();
    // Landing on Ship by swipe/dot needs the live pipeline read too —
    // only openTray's direct-open path covered it before.
    if (S.tray === 'ship') refreshShip();
  }, { passive: true });

  function renderTraySlide(id) {
    const body = slideBodies[id];
    if (!body) return;
    body.textContent = '';
    if (id === 'edit') return renderEditBody(body);
    if (id === 'comments') return renderCommentsBody(body);
    if (id === 'settings') return renderSettingsBody(body);
    if (id === 'tweak') return renderTweakBody(body);
    if (id === 'style') return renderStyleBody(body);
    if (id === 'ship') return renderShipBody(body);
  }
  function openTray(id) {
    buildTraySlides();
    const list = traySlideList();
    const want = list.find((s) => s[0] === id);
    S.tray = want ? want[0] : list[0][0];
    tray.classList.add('open');
    // Tray swap law: park the dial outright; the timer suspends.
    dock.classList.remove('open');
    S.open = false;
    dialPark();
    list.forEach(([sid]) => renderTraySlide(sid));
    if (S.tray === 'ship') refreshShip();
    const idx = list.findIndex((s) => s[0] === S.tray);
    requestAnimationFrame(() => {
      track.scrollLeft = idx * track.clientWidth;
      syncTrayChrome();
    });
  }
  function closeTray() {
    S.tray = null;
    tray.classList.remove('open');
    // SHEET-CHILDREN LAW (operator, 2026-08-26): whatever the sheet held
    // open closes WITH it — the floating smart card (plus its selection:
    // outline, handles, and the Edit Mode arming its outline rows imply),
    // the pin thread popover, and the comment composer. The island returns
    // to its resting state: dial in, nothing else floating.
    if (S.arming) disarm();
    if (S.design) designOff(); // closes the card, clears the selection
    else if (S.card || S.selected) { closeCard(); clearSelOutline(); }
    if (S.activePin) closeThread();
    composer.classList.remove('open');
    dialUnpark(); // spring back in + re-arm the 30s tuck-away fresh
  }

  // Edit slide: the locked outline (navigation only) + the draft ledger.
  function renderEditBody(body) {
    body.appendChild(h('div', { class: 'sect', text: 'Outline' }));
    body.appendChild(h('div', { class: 'ctl', style: 'font-size:11px;color:#9aa0ab', text: 'The locked structure, navigable. Tap an entry to select it and open its card.' }));
    const els = document.querySelectorAll('[data-el]');
    els.forEach((el) => {
      let depth = 0, p = el.parentElement;
      while (p) { if (p.getAttribute && p.getAttribute('data-el')) depth++; p = p.parentElement; }
      const name = el.getAttribute('data-el');
      const row = h('div', { class: 'row', style: 'margin-left:' + Math.min(depth, 6) * 14 + 'px' });
      row.appendChild(h('span', { class: 'txt', text: name }));
      const k = kindOf(el);
      row.appendChild(h('div', { class: 'meta' }, [h('span', { text: k.kind })]));
      row.addEventListener('click', () => {
        const id = el.getAttribute('data-arxa-id');
        if (!id) { say('This element has no patch identity (data-arxa-id)'); return; }
        if (!S.design) designOn();
        selectEl({ id: id, el: el, label: name + ' · ' + k.kind, group: k.group });
        el.scrollIntoView({ block: 'center', behavior: TWEAK.motion ? 'smooth' : 'auto' });
      });
      body.appendChild(row);
    });
    if (!els.length) {
      body.appendChild(h('div', { class: 'ctl', style: 'font-size:12px', text: 'No data-el identity on this page.' }));
    }
    renderLedger(body);
  }

  // Settings slide: environment & session — describes, writes nothing.
  function renderSettingsBody(body) {
    body.appendChild(h('div', { class: 'sect', text: 'Session' }));
    const row = h('div', { class: 'facet' }, [h('label', { text: 'Name' })]);
    const nameIn = h('input', { type: 'text', placeholder: 'your name' });
    nameIn.value = S.name;
    nameIn.addEventListener('input', () => {
      S.name = nameIn.value.trim();
      try { localStorage.setItem('arxa-dial-name', S.name); } catch (_) {}
    });
    row.appendChild(nameIn);
    body.appendChild(row);
    body.appendChild(h('div', { class: 'sect', text: 'Environment' }));
    const fact = (k, v) => body.appendChild(h('div', { class: 'facet' }, [
      h('label', { text: k }), h('span', { style: 'font-size:11.5px;color:#c8ccd4;word-break:break-all', text: v }),
    ]));
    fact('Mode', S.mode === 'author' ? 'author (this browser)' : S.mode);
    fact('Store', S.store === 'memory' ? 'local — pins die with this server' : S.store);
    fact('Artifact', String(cfg.artifact || '—'));
    fact('Server', location.origin);
    fact('Route', location.pathname);
    fact('Open pins', String(S.pins.filter((p) => p.status === 'open').length));
    const reset = h('button', { class: 'btn ghost', text: 'Reset tweaks' });
    reset.addEventListener('click', () => {
      try { localStorage.removeItem('arxa-dial-tweak'); } catch (_) {}
      applyTweakPrefs();
      renderTraySlide('settings');
      say('Tweaks reset');
    });
    body.appendChild(h('div', { class: 'btnrow' }, [reset]));
  }

  // Tweak slide: Theme (token channel) · Motion · Surface — all live-write.
  function renderTweakBody(body) {
    body.appendChild(h('div', { class: 'sect', text: 'Theme' }));
    renderTokensBody(body);
    body.appendChild(h('div', { class: 'sect', text: 'Motion' }));
    const swRow = h('div', { class: 'ctl' });
    swRow.appendChild(h('span', { text: 'Animations' }));
    const sw = h('button', { class: 'switch' + (TWEAK.motion ? ' on' : ''), 'aria-label': 'toggle animations' });
    sw.addEventListener('click', () => {
      TWEAK.motion = !TWEAK.motion;
      sw.classList.toggle('on', TWEAK.motion);
      host.classList.toggle('nomotion', !TWEAK.motion);
      saveTweakPrefs();
    });
    swRow.appendChild(sw);
    body.appendChild(swRow);
    const slider = (label, min, max, step, val, oninput, fmt) => {
      const row = h('div', { class: 'ctl' });
      row.appendChild(h('span', { style: 'flex:none;width:110px;font-size:11.5px', text: label }));
      const s = h('input', { type: 'range', min: String(min), max: String(max), step: String(step) });
      s.value = String(val);
      const out = h('span', { style: 'flex:none;width:44px;font-size:11px;color:#9aa0ab;text-align:right', text: fmt(val) });
      s.addEventListener('input', () => {
        oninput(parseFloat(s.value));
        out.textContent = fmt(parseFloat(s.value));
      });
      row.appendChild(s);
      row.appendChild(out);
      body.appendChild(row);
    };
    slider('Dial reveal · s', 0.2, 0.8, 0.02, TWEAK.dur, (v) => { TWEAK.dur = v; REVEAL.dur = v; saveTweakPrefs(); }, (v) => v.toFixed(2));
    slider('Dial damping · ζ', 0.5, 1.1, 0.02, TWEAK.zeta, (v) => { TWEAK.zeta = v; REVEAL.zeta = v; saveTweakPrefs(); }, (v) => v.toFixed(2));
    body.appendChild(h('div', { class: 'sect', text: 'Surface' }));
    slider('Tint', 0.6, 1, 0.02, TWEAK.tint, (v) => { TWEAK.tint = v; host.style.setProperty('--tint', String(v)); saveTweakPrefs(); }, (v) => v.toFixed(2));
    slider('Blur · px', 0, 24, 1, TWEAK.blur, (v) => { TWEAK.blur = v; host.style.setProperty('--tblur', v + 'px'); saveTweakPrefs(); }, (v) => String(v));
    slider('Glow', 0, 0.5, 0.02, TWEAK.glow, (v) => { TWEAK.glow = v; host.style.setProperty('--glow', String(v)); saveTweakPrefs(); }, (v) => v.toFixed(2));
    slider('Radius · px', 0, 24, 1, TWEAK.rad, (v) => { TWEAK.rad = v; host.style.setProperty('--trayrad', v + 'px'); saveTweakPrefs(); }, (v) => String(v));
    const alRow = h('div', { class: 'ctl' });
    alRow.appendChild(h('span', { text: 'Dial always on' }));
    const al = h('button', { class: 'switch' + (TWEAK.always ? ' on' : ''), 'aria-label': 'toggle dial always on' });
    al.addEventListener('click', () => {
      TWEAK.always = !TWEAK.always;
      al.classList.toggle('on', TWEAK.always);
      saveTweakPrefs();
      if (TWEAK.always) dialShow();
    });
    alRow.appendChild(al);
    body.appendChild(alRow);
  }

  // Ship slide (slice 5, 2026-08-24): automation up to the button. The
  // status is live from the confined git+gh channel; Branch+PR is the
  // automated prefix; Merge / Close / Pull & rebase are the one-tap
  // irreversible verbs — the server re-enforces green before any merge.
  let shipBusy = false;
  let shipSt = null; // last /ship/status answer (drives the Deploy CTA)
  async function shipVerb(sub, body) {
    if (shipBusy) return;
    shipBusy = true;
    say('Ship: ' + sub + '…');
    const r = await api('POST', sub, body || {});
    shipBusy = false;
    if (r && (r.error === undefined)) {
      say(sub.replace('/ship/', '') + ' ✓');
    } else {
      say((r && r.error) || (sub + ' failed'));
    }
    await refreshShip();
    return r;
  }
  async function refreshShip() {
    const body = slideBodies.ship;
    if (!body || !S.tray) return;
    const r = await api('GET', '/ship/status');
    shipSt = r;
    const rd = await api('GET', '/ship/deploy/ready');
    S.deployReady = !!(rd && rd.blockers && rd.blockers.length === 0);
    S.deployBlockers = (rd && rd.blockers) || ['deploy gates unreadable'];
    renderShipBody(body, r);
    updateTrayCta();
  }
  function renderShipBody(body, st) {
    body.textContent = '';
    if (!st) {
      body.appendChild(h('div', { class: 'ctl', text: 'reading pipeline state…' }));
      return;
    }
    if (st.error) {
      body.appendChild(h('div', { class: 'ctl', style: 'color:#f59e0b', text: st.error }));
      return;
    }
    body.appendChild(h('div', { class: 'sect', text: 'Pipeline' }));
    const fact = (k, v) => body.appendChild(h('div', { class: 'facet' }, [
      h('label', { text: k }),
      h('span', { style: 'font-size:11.5px;color:#c8ccd4;word-break:break-all', text: String(v == null ? '—' : v) }),
    ]));
    fact('Repo', st.repo);
    fact('Branch', st.branch);
    fact('Dirty paths', st.dirty);
    (st.log || []).slice(0, 3).forEach((l, i) => fact(i === 0 ? 'Latest' : ' ', l));
    const pr = st.pr;
    if (pr) {
      body.appendChild(h('div', { class: 'sect', text: 'PR #' + pr.number + ' · ' + String(pr.state).toUpperCase() }));
      fact('Title', pr.title);
      fact('Branch', pr.head);
      const checksTxt = !((pr.checks || []).length)
        ? 'no checks reported'
        : (pr.failing ? pr.failing + ' failing · ' : '') +
          (pr.pending ? pr.pending + ' pending · ' : '') +
          ((pr.checks || []).length - (pr.failing || 0) - (pr.pending || 0)) + ' passed';
      fact('Checks', checksTxt);
      const link = h('button', { class: 'stbtn', text: 'open on github ↗', title: pr.url });
      link.addEventListener('click', () => { try { window.open(pr.url, '_blank'); } catch (_) {} });
      body.appendChild(h('div', { class: 'facet' }, [link]));
    }
    const onMain = st.branch === 'main';
    const canPr = onMain && !pr && st.dirty > 0;
    const canMerge = !!(pr && pr.state === 'OPEN' && pr.mergeable && pr.green);
    const canSync = !onMain || true; // sync also fast-forwards main after a merge
    const mk = (label, enabled, fn, ghost, title) => {
      const b = h('button', { class: 'btn' + (ghost ? ' ghost' : ''), text: label, title: title || '' });
      if (!enabled) b.disabled = true;
      else b.addEventListener('click', fn);
      return b;
    };
    const row = h('div', { class: 'btnrow', style: 'flex-wrap:wrap;gap:6px' });
    row.appendChild(mk(canPr ? 'Branch + PR (' + st.dirty + ' dirty)' : 'Branch + PR', canPr, async () => {
      const title = 'design(dial): live edit batch';
      const bodyTxt = 'Committed from the Design Dial (Ship slide). ' +
        Object.keys(S.draft.patches).length + ' element patch keys pending in the draft overlay; ' +
        'run the commit ops via the Edit slide CTA first if the draft is still uncommitted.';
      await shipVerb('/ship/pr', { title, body: bodyTxt });
    }, false, canPr ? '' : onMain ? (pr ? 'a PR is already open' : 'nothing dirty to ship') : 'not on main — merge or close first'));
    row.appendChild(mk('Pull & rebase', canSync, () => shipVerb('/ship/sync'), true));
    row.appendChild(mk('Merge · squash', canMerge, () => shipVerb('/ship/merge'), false,
      canMerge ? 'green + mergeable — your tap merges' : 'enabled when checks are green and the PR is mergeable'));
    row.appendChild(mk('Close PR', !!pr, () => shipVerb('/ship/close'), true));
    body.appendChild(row);
    if (S.deployBlockers && S.deployBlockers.length) {
      body.appendChild(h('div', { class: 'sect', text: 'Deploy gates' }));
      S.deployBlockers.forEach((b) => {
        body.appendChild(h('div', { class: 'ctl', style: 'font-size:11px;color:#f59e0b;padding:4px 10px', text: '• ' + b }));
      });
    }
    body.appendChild(h('div', { class: 'ctl', style: 'font-size:11px;color:#9aa0ab', text: 'Automation up to the button: branch, PR and gate-watching are automatic; merge, close and deploy wait for your finger. Conflicts are never auto-resolved.' }));
  }
  // ── verbs ──────────────────────────────────────────────────────────────
  function onVerb(id, el) {
    // A trigger tap closes the fan first — the mode or the tray takes the
    // screen (rework law: the fan is a launcher, never a staying surface).
    dock.classList.remove('open');
    S.open = false;
    dialPanelChanged();
    if (id === 'edit') {
      if (S.design) designOff();
      else designOn();
      return;
    }
    if (id === 'comment') {
      if (S.arming) disarm();
      else {
        arm();
        say('Click the design to drop a pin');
      }
      return;
    }
    if (id === 'studio') return openTray(S.tray || (S.mode === 'guest' ? 'comments' : 'edit'));
  }

  // Outside click closes the thread; Escape disarms everything. "Outside"
  // means outside THE DIAL, not outside the thread popover: the thread is a
  // sibling of the panel, so a click on a feedback ROW (which opens the
  // thread) is never inside it, and shadow retargeting hides every dial
  // element behind the host for document-level listeners anyway. Guarding on
  // the composed path's HOST covers both at once (smoke S5a).
  document.addEventListener('click', (e) => {
    if (!S.arming && S.activePin && e.composedPath().indexOf(host) === -1) {
      closeThread();
    }
  });
  document.addEventListener('keydown', (e) => {
    // On-canvas text editing owns Enter (commit — a newline would inject
    // markup the --text grammar refuses) and Escape (revert, keep editing
    // mode armed).
    if (S.inlineEditing != null) {
      if (e.key === 'Enter') {
        e.preventDefault();
        inlineEditEnd(true);
      } else if (e.key === 'Escape') {
        e.preventDefault();
        inlineEditEnd(false);
      }
      return;
    }
    if (e.key === 'Escape') {
      if (S.arming) disarm();
      if (S.card) { closeCard(); return; }
      if (S.tray) { closeTray(); return; }
      if (S.design) designOff();
      closeThread();
      composer.classList.remove('open');
    }
  });

  // ── realtime: the server's own writes arrive over SSE ─────────────────
  // Subscribe only after a pins read SUCCEEDED. Inside a sandboxed frame
  // (opaque origin — a gen_ui RungLadder pointing at this server) every
  // guarded /__dial/* call is refused by design, and a bare EventSource
  // would retry the 403 forever: a refusal storm per frame, forever. No
  // pins answer → this frame cannot use the dial API at all → stay quiet.
  // SOCKET-POOL LAW (2026-08-25 — the "loads for no reason" tab freeze):
  // HTTP/1.1 caps one origin at 6 browser sockets, and this stream is held
  // open by design — so N live tabs hold N sockets hostage from every
  // navigation's budget; at 6 the next request queues for seconds to
  // minutes while the tab spinner spins over a dead page (proved live: a
  // frozen fetch completed within 20ms of closing ONE background tab). A
  // hidden tab has no audience for realtime — never open (a tab may boot
  // already hidden; visibilitychange will not fire for it), close on hide,
  // reopen and resync on show. A fresh EventSource sends no Last-Event-ID,
  // so the resync READS (not replay) carry the truth across the gap; both
  // are reads, and reads never broadcast.
  let liveEs = null;
  let swallowTimer = null; // a frame held back by the own-save window, re-checked once it closes
  let eventsAllowed = false; // capability proven at boot; mirrors never subscribe
  function subscribeEvents() {
    if (liveEs || !eventsAllowed || document.hidden) return;
    try {
      const es = new EventSource(apiUrl('/events'));
      liveEs = es;
    // A RECONNECT is the certain sign frames were missed (socket-pool
    // starvation, a server restart, laptop sleep) — resync instead of
    // trusting the stream. The first open is boot truth: loadDraft already
    // read it, and the signature check makes a no-divergence resync a
    // no-op, so a flapping connection never reload-loops.
    let esOpened = false;
    es.addEventListener('open', () => {
      // A reconnect also refetches pins: the server replays what it logged
      // (Last-Event-ID), but a restart's log is empty — without this the
      // board stays stale until someone else acts. loadPins is a read;
      // reads never broadcast, so this cannot loop.
      if (esOpened) { syncRemoteDraft(); loadPins(); }
      esOpened = true;
    });
    es.addEventListener('dial', (ev) => {
      let d = null;
      try { d = JSON.parse(ev.data); } catch (_) {}
      if (!d || d.kind === 'pins') return loadPins();
      // Another author context saved its draft — sync it INTO this
      // document, unless the frame was this document's own save. The
      // own-save suppression is DEFERRED, never dropped (the reactivity
      // law's sibling, 2026-08-25): a frame landing inside the 1500ms
      // window is re-checked once the window closes. Before this, an
      // external change arriving ~1s after our own save vanished from
      // this page until some later frame — and a shrinking external
      // cleanup never converged by reload (probe-proved: the next beat
      // armed a dead surface on a page that silently skipped its
      // reload). Our own echo re-checks too, but the resync is a read:
      // store == S.draft after our save, so it no-ops (no refetch
      // loop). Coalesced — a burst inside the window arms ONE recheck.
      if (d.kind === 'draft') {
        const since = Date.now() - S.ownSave;
        if (since > 1500) syncRemoteDraft();
        else {
          clearTimeout(swallowTimer);
          swallowTimer = setTimeout(syncRemoteDraft, 1600 - since);
        }
      }
      // The published axes changed (our own POST echoes here too — applying
      // the same pick is idempotent and settles the URL to published).
      if (d.kind === 'axes' && d.data && S.axes) {
        S.axes.published = { style: d.data.style, theme: d.data.theme };
        applyAxes(d.data.style, d.data.theme);
      }
      // The identity plane: someone minted or revoked — an author holding
      // the comments slide refetches the roster (read; reads never
      // broadcast, so no loop).
      if (d.kind === 'guests' && S.mode === 'author' && slideBodies.comments) {
        loadGuests(true).then(() => {
          const panel = slideBodies.comments.querySelector('.gstpanel');
          if (panel) renderGuestRoster(panel);
        });
      }
      // 'commit' frames feed the studio agent — the requester already
      // heard its toast, there is nothing for this page to do.
      // 'compose-ack' (2026-08-26): the studio panel inserted the
      // pointer line + snapshot and acked. The Arxa tab's status line
      // shows a VERIFIED ✓ only from here — the button never fakes it.
      if (d.kind === 'compose-ack' && d.data && d.data.id) {
        // Multi-page ack truth (2026-08-26): EVERY connected studio page
        // acks its own result. The ✓ means AT LEAST ONE page took the
        // insert — a true ack wins at once; a false ack (that page had
        // no open composer) is noted and the window runs out, so a true
        // ack from another page can still arrive. Only an all-false or
        // silent window becomes the honest failure (timeout branch).
        for (const k of Object.keys(S.arxa)) {
          const a = S.arxa[k];
          if (a.id === d.data.id && a.status === 'sending to composer…') {
            if (d.data.inserted === false) {
              a.ackFalse = true;
            } else {
              if (composeWaiter) { clearTimeout(composeWaiter); composeWaiter = null; }
              a.ackFalse = false;
              a.status = '✓ inserted into the composer'; a.statusOk = true;
              if (S.card && S.cardTab === 'arxa') renderArxaPane();
            }
          }
        }
      }
    });
    } catch (_) {}
  }
  // The visibility half of the socket-pool law: release this tab's socket
  // the moment it hides, take it back (and catch up) the moment it shows.
  document.addEventListener('visibilitychange', () => {
    if (!eventsAllowed) return;
    if (document.hidden) {
      if (liveEs) { liveEs.close(); liveEs = null; }
    } else {
      syncRemoteDraft();
      loadPins();
      subscribeEvents();
    }
  });

  // ── boot ───────────────────────────────────────────────────────────────
  // CAPABILITY-GATED BOOT. Sandboxed mirror frames must stay out of the
  // DOM, but origin-string heuristics cannot detect them: Brave reports a
  // REAL location.origin inside frames whose network requests are still
  // refused as null-origin (measured 2026-08-24; Chromium says 'null',
  // Brave doesn't). So ask the API instead: an author page proves itself
  // with the draft read (file-backed — no pins store needed), a guest with
  // the pins read. Any context where the proof cannot come back —
  // sandboxed mirror, hard refusal, server down — stays a silent
  // view-only mirror; the server answers those reads with a quiet
  // CORS-clean 200 so not even a console line escapes.
  function mirrorNote() {
    try {
      console.info('[arxa dial] unavailable in this context — view-only mirror');
    } catch (_) {}
  }
  // A boot can collide with a design-server restart or a stalled renderer,
  // and one failed probe used to mute the rung FOREVER while the server sat
  // perfectly healthy ("unavailable although available"). Retry with
  // backoff across ~25s before concluding mirror; the server answers
  // refused reads instantly, so genuine mirrors just burn a few quiet GETs.
  const CAP_RETRY_WAITS = [250, 500, 1000, 2000, 4000, 8000, 8000];
  function probeCapable(sub) {
    let step = -1;
    const attempt = () => {
      step++;
      return api('GET', sub).then((r) => {
        if ((r != null && r.mirror !== true) || step >= CAP_RETRY_WAITS.length) return r;
        return new Promise((res) => setTimeout(res, CAP_RETRY_WAITS[step]))
            .then(attempt);
      });
    };
    return attempt();
  }
  // ── corner reveal (operator request, 2026-08-24) ─────────────────────
  // The dial is ALWAYS mounted but parked off-screen; moving the cursor
  // into a 100x100px square in the bottom-right corner springs it in.
  //
  // Physics contract from Apple's own documentation (UIViewPropertyAnimator
  // init(duration:dampingRatio:animations:), developer.apple.com): the
  // animated value accelerates toward its target and oscillates to rest;
  // dampingRatio 1 decelerates smoothly with no oscillation, values nearer
  // 0 oscillate more. Reveal is underdamped (a small overshoot that
  // settles, the macOS sheet/sidebar feel); hide is shorter and
  // critically damped. Integrated every frame so re-triggering mid-flight
  // keeps velocity - the interruptible quality native animation has that
  // CSS curves cannot give.
  const HOT_CORNER = 50;    // px square in the bottom-right corner
  const PARK_PX = 168;      // how far off-screen the parked dial sits
  let sp = null;            // spring state { p, v, raf, target }
  let dialLastWant = false; // cursor's latest inside-zone-or-dock verdict
  let dialHideAt = 0;       // 30s auto-hide backstop timer
  // 2026-08-26 scope fix: the park pose belongs to the DIAL (#dock),
  // never the host. The host also carries the tray, card, thread, composer
  // and pins - a host-wide visibility:hidden took the just-opened sheet
  // with it (the "dial and sheet both vanish" report), and every 30s
  // tuck-away used to blink out the pins too. lens_dial_tray_park_probe.
  function dialApplyPose() {
    const e = Math.max(-0.18, Math.min(1.14, sp.p)); // room for overshoot
    const off = (1 - e) * PARK_PX;
    dock.style.transform =
      'translate3d(' + off.toFixed(1) + 'px,' + off.toFixed(1) + 'px,0)';
    dock.style.opacity = Math.max(0, Math.min(1, e * 1.25)).toFixed(3);
    const parked = sp.p <= 0.001 && Math.abs(sp.v) < 0.02;
    dock.style.visibility = parked ? 'hidden' : 'visible';
  }
  function dialSpringTo(target, durationSec, dampingRatio) {
    if (!sp) sp = { p: 0, v: 0, raf: 0, target };
    sp.target = target;
    if (matchMedia('(prefers-reduced-motion: reduce)').matches) {
      cancelAnimationFrame(sp.raf);
      sp.p = target; sp.v = 0; dialApplyPose(); return;
    }
    const wn = 4.6 / (dampingRatio * durationSec); // ~1% envelope at duration
    const c = 2 * dampingRatio * wn, k = wn * wn;
    cancelAnimationFrame(sp.raf);
    let last = performance.now();
    const tick = (now) => {
      const dt = Math.min((now - last) / 1000, 1 / 30); last = now;
      const a = k * (target - sp.p) - c * sp.v;
      sp.v += a * dt; sp.p += sp.v * dt;
      dialApplyPose();
      if (Math.abs(sp.v) < 0.004 && Math.abs(target - sp.p) < 0.004) {
        sp.p = target; sp.v = 0; dialApplyPose(); sp.raf = 0; return;
      }
      sp.raf = requestAnimationFrame(tick);
    };
    sp.raf = requestAnimationFrame(tick);
  }
  const REVEAL = { dur: 0.5, zeta: 0.86 }; // Tweak > Motion owns these live
  function dialShow() {
    dialSpringTo(1, REVEAL.dur, REVEAL.zeta);
    dialArmAutoHide();
  }
  // TRAY SWAP LAW (operator, 2026-08-24): tray open parks the dial outright
  // (the timer suspends — nothing to time); tray close springs it back in
  // and re-arms the 30s tuck-away fresh.
  function dialPark() {
    clearTimeout(dialHideAt);
    dialSpringTo(0, 0.34, 1.0);
  }
  function dialUnpark() {
    dialSpringTo(1, REVEAL.dur, REVEAL.zeta);
    dialArmAutoHide();
  }
  // Open mode = a panel OR the expanded dock fan is on screen. The dial
  // cannot hide at all in either state - not by timer, not by anything.
  function dialOpenMode() {
    // Never-hide law (operator 2026-08-24): fan open, Edit Mode armed,
    // pin-drop armed, the smart card up, or inline text editing active.
    // The TRAY is deliberately absent — it swaps the dial out entirely.
    return !!(S.open || S.design || S.arming || S.card || S.inlineEditing != null);
  }
  function dialHide() {
    clearTimeout(dialHideAt);
    if (TWEAK.always) return; // Tweak > Surface: dial always on
    if (dialOpenMode()) return; // open mode law
    dialSpringTo(0, 0.34, 1.0);
  }
  // Thirty seconds of visibility ends in a tuck-away - unless a panel is
  // open (never hides) or the cursor still sits in the zone or on the dock
  // (that is intent: re-arm instead of fighting the hand).
  function dialArmAutoHide() {
    clearTimeout(dialHideAt);
    if (!(sp && sp.target === 1)) return;
    dialHideAt = setTimeout(() => {
      if (dialOpenMode() || dialLastWant) dialArmAutoHide();
      else dialHide();
    }, 30000);
  }
  function dialPanelChanged() {
    if (dialOpenMode()) { clearTimeout(dialHideAt); return; }
    dialArmAutoHide();
  }
  function mountHost() {
    if (!sp) sp = { p: 0, v: 0, raf: 0, target: 0 };
    dialApplyPose();                            // parked BEFORE first paint
    document.documentElement.appendChild(host); // off-body: hx-boost swaps wipe body children
    dialInstallCornerReveal();
  }
  let dialCornerArmed = false;
  function dialInstallCornerReveal() {
    if (dialCornerArmed) return;
    dialCornerArmed = true;
    const inCorner = (x, y) =>
      x >= innerWidth - HOT_CORNER && y >= innerHeight - HOT_CORNER;
    const overDock = (ev) => ev.composedPath().includes(host);
    addEventListener('pointermove', (ev) => {
      // Tray open: the swap law keeps the dial parked. Hover inside the
      // sheet counts as overDock (same host) and must NOT spring the dial
      // back in over the open sheet.
      if (S.tray) { dialLastWant = false; return; }
      const want = inCorner(ev.clientX, ev.clientY) || overDock(ev);
      dialLastWant = want;
      // Leaving does NOT hide - the 30s timer owns the tuck-away (proved
      // unreachable otherwise: lens probe showed instant-leave-hide starved
      // it, and holding the corner re-armed it forever).
      if (sp.target !== 1) {
        if (want) dialShow();
      } else if (want) {
        dialArmAutoHide(); // active use refreshes the visibility window
      }
    }, { passive: true });
    // touch has no hover: a tap in the zone reveals too
    addEventListener('pointerdown', (ev) => {
      if (S.tray) return; // the sheet is the surface; the dial returns on close
      if (inCorner(ev.clientX, ev.clientY) && sp.target !== 1) dialShow();
    }, { passive: true });
  }
  function finishBoot() {
    mountHost();
    applyTweakPrefs();
    openPinnedOnArrival();
    resumeAfterReload(); // no-op unless the last text edit converged by reload
  maybeRestoreTrackback(); // no-op unless the last selection lived on this route
  }
  if (S.mode === 'invalid') {
    mountHost();
    applyTweakPrefs();
    openPinnedOnArrival();
    say('This share link is expired or invalid');
    return;
  }
  if (S.mode === 'guest') {
    probeCapable('/pins').then((r) => {
      if (!(r && r.pins)) { mirrorNote(); return; }
      S.pins = r.pins;
      finishBoot();
      renderPins();
      updateBadge();
      eventsAllowed = true;
      subscribeEvents();
    });
    return;
  }
  loadDraft().then((ok) => {
    if (!ok) { mirrorNote(); return; }
    finishBoot();
    api('GET', '/pins').then((r) => {
      if (r && r.pins) { S.pins = r.pins; renderPins(); updateBadge(); }
      eventsAllowed = true;
      subscribeEvents();
    });
  });
})();
