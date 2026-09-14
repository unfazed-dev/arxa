/* dial_island.js — the Arxa Dial island (first-party, ADR-0002 form;
   locked amendment 2026-08-23: 'the feedback dial becomes the Arxa Dial').

   WHY THIS EXISTS. Every arxa artifact carries one floating control so the
   Author can adjust the design live and clients can leave feedback on the
   shared design. REWORK LOCKED 2026-08-24 (19 decisions, grilled): the dial
   does exactly three things — a 3-trigger radial fan (Edit / Comment /
   Studio); per-element editing happens in a floating smart CARD anchored to
   the clicked element (dropdown-style flip/clamp, capability matrix per
   element kind, live apply, draft auto-save); Studio opens the TRAY, a
   glass bottom sheet (translucent, blurred, moss accent glow, close button
   top-right, drag grabber + hairline divider + top bar) holding a native
   scroll-snap carousel of exactly TWO slides (locked trim, grilled): Theme
   (the palette plane — plus the style/theme pickers for app designs) and
   Incoming (a placeholder for what ships next). The retired slides (Edit,
   Comments, Settings, Tweak, Style, Ship) lost only their tray UI — their
   client functions stay callable for the ongoing dial rewrite. Pins keep
   W7 data-el identity, rect snapshots, orphan survival, threaded replies.
   The 6 displaced verbs
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
   trigger and the same two-slide tray; no Edit Mode. 'invalid' (a dead
   token): the dock boots to say so, nothing
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

   EDIT MODE (author only; redesigned 2026-09-11, nine grilled decisions —
   the over-built inspector died). Editing is TEXT + IMAGE SWAP, nothing
   else: hover outlines editable elements, click selects (amber outline +
   a small chip), double-click text types in place (contenteditable). Every
   edit lands in the LIVE OVERLAY — one Supabase row per design
   (arxa_dial_overlays: patches jsonb + rev) — debounced-saved through the
   save_overlay RPC (author-token or service-role validated; guests are
   read-only) and streamed to EVERY open dial (local SSE 'overlay' frame,
   static postgres_changes channel) so clients watch the author work in
   real time (decision 5 of 2026-08-23 overturned). Undo/redo is a
   session-local inverse stack (Cmd+Z / Shift+Cmd+Z, depth ~50 — decision
   3); Revert-to-published empties the row and everyone snaps back. Source
   is only ever touched by the EJECT BAKE (decision 7): the next eject
   fetches the overlay, applies the patches through the design-patch
   machinery, and clears the row. The dead machinery — facet rows, CSS
   escape hatch, resize handles, the arxa-studio tab, the draft ledger,
   the server-side journal, /draft /commit /undo /redo routes — is deleted,
   not parked. Editing requires the Supabase store: a memory-store design
   shows no Edit verb (decision 4).

   PALETTE EDITOR (universal palette plane, Q4 — locked 2026-09-10). Every
   Theme-slide card carries an author-only edit affordance: a NON-default
   palette edits IN PLACE (stable id; swatch/sheet/tokens re-derived
   server-side, published picks and ?palette= links never break); editing
   the DEFAULT palette FORKS into the one custom slot (the base corpus
   stays hand-owned), replacing the previous custom, and the fork previews
   locally — publishing stays the author's explicit click. Deployed
   static mode hides the affordance exactly like the paste row: there is
   no server to derive against. */
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
    // Deployed static mode (VERIFY ADDENDUM 17, locked Q8): when the worker
    // bakes this block the artifact has NO /__dial/* server — the store is
    // Supabase directly (PostgREST + RPC + Realtime over the anon key).
    static: cfg.static || null, // {url, anonKey, designId} | null
    // Palette-only axes (sites) omit style/theme entirely — normalize to
    // '' / 'system' so the preview compare and the URL receipt never see
    // undefined (probe-proved: ?style=undefined and a badge that would not
    // clear after Reset to published).
    axes: cfg.axes // the style/theme/palette/font plane: null = undeclared or kind-gated off
      ? {
          styles: cfg.axes.styles,
          themes: cfg.axes.themes || [],
          palettes: cfg.axes.palettes || [],
          // The font plane (grilled 2026-09-13): {default, roles} when the
          // artifact declares fonts.json; current/published font are
          // role -> choice-id objects (independent per-role picks).
          fonts: cfg.axes.fonts || null,
          published: {
            style: (cfg.axes.published || {}).style || '',
            theme: (cfg.axes.published || {}).theme || 'system',
            palette: (cfg.axes.published || {}).palette || '',
            font: (cfg.axes.published || {}).font || {},
          },
          current: {
            style: (cfg.axes.active || {}).style || '',
            theme: (cfg.axes.active || {}).theme || 'system',
            palette: (cfg.axes.active || {}).palette || '',
            font: (cfg.axes.active || {}).font || {},
          },
        }
      : null,
    token: cfg.token || null,
    guest: cfg.guest || null, // arc 2: personal-link identity {email, name} — attribution by construction
    guests: null, // arc 2: author's roster cache (null = not loaded)
    pins: [],
    open: false, // radial fan expanded
    tray: null, // null | 'theme' | 'access' (author-local) | 'incoming' (retired)
    arming: false, // pin-placement armed
    activePin: null, // id whose thread popover is open
    name: '',
    dockSide: 'right',
    deployReady: false, // /ship/deploy/ready answer
    deployBlockers: [],
    design: false, // Edit Mode armed (author only)
    selected: null, // { id, el, key, label, group, route, nth } — the selected element
    selOutline: '', // inline outline the selection highlight borrowed
    // The Live Overlay (2026-09-11 redesign): one Supabase row per design,
    // applied client-side at boot and on every realtime frame. rev is the
    // stale-guard AND the own-echo suppressor — a frame with rev <= ours is
    // ours (or older) and never re-applies.
    overlay: { patches: {}, rev: 0 },
    overlayReady: false, // boot read came back (author probe + guest apply)
    ownSave: 0, // suppress refetch loops on our own PUT's broadcast
    inlineEditing: null, // original text of the element being edited on-canvas
    chipOpen: false, // the selection chip (the smart card's tiny successor)
    undoStack: [], // session-local inverse ops (decision 3) — dies on reload
    redoStack: [],
    palEdit: null, // the palette editor session (Q4): null | {id, hexes,
    //   name, error, busy} — kept in S so a slide re-render (an axes echo,
    //   a live frame) never kills an in-flight edit
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
  // Lenis escape hatch (operator, 2026-09-13): artifacts ship Lenis 1.3
  // smooth scroll, whose page-level wheel listener preventDefaults every
  // composed wheel it sees — including wheels over the dial's shadow
  // scrollers (the fonts dropdown rows, tall tray slides) — unless the
  // composedPath walk finds data-lenis-prevent below the root scroller.
  // The dial is chrome, not content: native scroll inside it, always.
  host.setAttribute('data-lenis-prevent', '');
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
    /* cursor law (operator, 2026-09-09): the site's custom cursor hides the
       native cursor page-wide (html.arxa-cursor-on * — inherited through the
       host into this shadow tree) while its dot/ring ride z 99998, UNDER the
       dial host (z 2147483000) — without this rule the pointer VANISHES over
       the open tray/card. Dial chrome always shows the native cursor;
       elements with explicit cursors (pointer/copy/grab/text) keep theirs. */
    '#dock,#tray,#card,#thread,#composer{cursor:auto}',
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
    '  background:#14141c;backdrop-filter:none;-webkit-backdrop-filter:none}}',
    '@media (prefers-reduced-motion:reduce){#track{scroll-behavior:auto}}',
    /* the selection chip (2026-09-11 redesign): the floating smart
       card's tiny successor. Text editing happens ON THE CANVAS; the
       chip only says what the selection is, offers the rare actions
       (swap image, revert element), and stays out of the way. Moss
       gradient like the dock card, no drag, no tabs, no scrolling. */
    '#echip{position:fixed;z-index:26;display:none;pointer-events:auto;',
    '  color:rgb(243,246,238);background:linear-gradient(135deg,',
    '  rgb(139,165,101) 0%,rgb(106,133,74) 55%,rgb(64,80,44) 100%);',
    '  border:1px solid rgba(227,238,222,.4);border-radius:10px;',
    '  padding:6px 8px;box-shadow:0 8px 24px rgba(0,0,0,.45),',
    '    0 0 18px rgba(110,136,76,var(--glow,.22));',
    '  max-width:280px;font-size:11.5px}',
    '#echip.open{display:flex;align-items:center;gap:6px;flex-wrap:wrap}',
    '#echip .elabel{font-weight:700;max-width:150px;overflow:hidden;',
    '  text-overflow:ellipsis;white-space:nowrap}',
    '#echip .hint{color:rgba(243,246,238,.78);font-size:10.5px}',
    '#echip button{cursor:pointer;font-size:10.5px;font-weight:700;',
    '  padding:4px 8px;border-radius:7px;border:1px solid transparent;',
    '  background:rgba(243,246,238,.16);color:rgb(243,246,238)}',
    '#echip button:hover{background:rgba(243,246,238,.3)}',
    '#echip button.xbtn{padding:4px 6px;background:transparent;',
    '  color:rgba(243,246,238,.72)}',
    /* the swap panel: the chip's one popover (image swap: paste URL on
       the deployed site, search + from-assets on the local designer). */
    '#epanel{position:fixed;z-index:27;display:none;pointer-events:auto;',
    '  width:280px;background:#14141c;color:#FFFCF0;border-radius:10px;',
    '  border:1px solid #2a2a35;box-shadow:0 12px 40px rgba(0,0,0,.55);',
    '  padding:10px}',
    '#epanel.open{display:block}',
    '#epanel .prow{display:flex;gap:6px;align-items:center;margin-bottom:6px}',
    '#epanel .pgrid{display:flex;flex-wrap:wrap;gap:6px;margin:6px 0;',
    '  max-height:180px;overflow-y:auto}',
    '#epanel .pgrid button{border-radius:8px;overflow:hidden;padding:0;',
    '  border:1px solid #2a2a35;flex:none;cursor:pointer;background:none}',
    '#epanel .pnote{font-size:10.5px;color:#9aa0ab}',
    /* the edit bar (2026-09-11): one small row above the dock while
       Edit Mode is armed — session undo/redo (decision 3) + Revert to
       published (decision 2). Nothing else floats. */
    '#editbar{position:fixed;right:16px;bottom:96px;z-index:12;display:none;',
    '  gap:6px;align-items:center}',
    '#editbar.open{display:flex}',
    '#editbar button{cursor:pointer;font-size:11px;font-weight:700;',
    '  padding:5px 10px;border-radius:8px;background:rgba(20,20,28,.9);',
    '  color:#FFFCF0;border:1px solid #2a2a35}',
    '#editbar button:hover:not(:disabled){border-color:#8fb35a}',
    '#editbar button:disabled{opacity:.4;cursor:default}',
    /* the live chip (decision 9): a client watching the author work sees
       the page change under them — the transient "● live" note says why,
       then fades. Never a toast per frame (typing would spam). */
    '#livechip{position:fixed;bottom:96px;left:50%;transform:translateX(-50%);',
    '  z-index:15;display:none;align-items:center;gap:6px;font-size:11px;',
    '  font-weight:700;color:#FFFCF0;background:rgba(20,20,28,.92);',
    '  border:1px solid #8fb35a;border-radius:10px;padding:6px 12px;',
    '  pointer-events:none}',
    '#livechip .dot{width:6px;height:6px;border-radius:50%;background:#8fb35a;',
    '  animation:arxalive 1.6s ease-in-out infinite}',
    '@keyframes arxalive{0%,100%{opacity:.35}50%{opacity:1}}',
    '.row{padding:8px 10px;border-radius:8px;cursor:pointer;',
    '  border:1px solid transparent;margin-bottom:4px}',
    '.row:hover{background:#1d1d27}',
    '.row.active{border-color:#0891b2;background:#1d1d27}',
    '.row .txt{font-size:12.5px;line-height:1.35;display:block}',
    '.row .meta{display:flex;gap:6px;align-items:center;margin-top:5px;',
    '  font-size:10.5px;color:#9aa0ab}',
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
    /* the Theme slide's palette cards (operator, 2026-09-02): Coolors-style
       5-stripe cards on a centered flex grid — the strip IS the card, name +
       chips below. Card hover lifts; a stripe hover grows the stripe and
       reveals its hex (stripe click copies, never applies); the card body
       applies the palette. Moss ring + Active chip mark the pick; the
       author's × deletes the one custom slot. */
    '.palgrid{display:flex;flex-wrap:wrap;gap:14px;justify-content:center;',
    '  margin:8px 0 4px}',
    '.palcard{position:relative;display:block;flex:0 1 200px;min-width:170px;',
    '  text-align:left;padding:0;background:transparent;border-radius:12px;',
    '  border:1px solid transparent;cursor:pointer;transition:transform .18s}',
    '.palcard:hover{transform:translateY(-2px)}',
    '.palcard:focus-visible{outline:2px solid #8fb35a;outline-offset:3px}',
    '.palcard .palstrip{display:flex;width:100%;aspect-ratio:16/5;',
    '  border-radius:10px;overflow:hidden;',
    '  box-shadow:0 1px 4px rgba(0,0,0,.35);transition:box-shadow .18s}',
    '.palcard:hover .palstrip{box-shadow:0 8px 20px rgba(0,0,0,.5)}',
    '.palcard.on .palstrip{outline:2px solid rgba(143,179,90,.95);',
    '  outline-offset:2px}',
    '.palstripe{position:relative;flex:1 1 0;min-width:0;cursor:copy;',
    '  transition:flex .22s ease}',
    '.palstripe:hover{flex:1.9 1 0}',
    '.palstripe i{position:absolute;inset:0;display:flex;align-items:center;',
    '  justify-content:center;font:600 9px ui-monospace,monospace;',
    '  font-style:normal;letter-spacing:.02em;text-transform:uppercase;',
    '  opacity:0;transition:opacity .15s;pointer-events:none;',
    '  writing-mode:vertical-rl}',
    '.palstripe:hover i{opacity:1}',
    '.palmeta{display:flex;align-items:center;gap:6px;padding:7px 2px 0}',
    '.palcard .palname{flex:1;font-size:12px;font-weight:600;color:#e8ebf0;',
    '  overflow:hidden;text-overflow:ellipsis;white-space:nowrap}',
    '.palchip{display:none;font-size:9px;font-weight:700;letter-spacing:.08em;',
    '  text-transform:uppercase;padding:2px 7px;border-radius:999px}',
    '.palcard.on .palchip.onchip{display:block;',
    '  background:rgba(143,179,90,.25);color:#b8d49a}',
    '.palchip.cchip{display:block;background:rgba(255,255,255,.08);',
    '  color:#9aa0ab}',
    '.palcard .paldel{position:absolute;top:-6px;right:-6px;z-index:2;',
    '  width:20px;height:20px;border-radius:50%;background:#2a2a35;',
    '  border:1px solid rgba(255,255,255,.18);color:#9aa0ab;font-size:12px;',
    '  line-height:1;display:flex;align-items:center;justify-content:center;',
    '  opacity:.65;transition:opacity .15s}',
    '.palcard .paldel:hover{opacity:1;color:#FFFCF0}',
    /* the Fonts slide (grilled 2026-09-13): font cards reuse the palette
       card geometry; the specimen strip is the font's own voice — live
       css2 preview, not a swatch. The dropdown rows are compact list
       rows with the same specimen law. */
    '.fontcard{position:relative;display:block;flex:0 1 220px;min-width:180px;',
    '  text-align:left;background:rgba(255,255,255,.05);',
    '  border:1px solid rgba(255,255,255,.1);border-radius:10px;',
    '  padding:10px 12px;cursor:pointer;transition:transform .15s}',
    '.fontcard:hover{transform:translateY(-2px)}',
    '.fontcard:focus-visible{outline:2px solid #8fb35a;outline-offset:3px}',
    '.fontcard.on{outline:2px solid rgba(143,179,90,.95)}',
    '.fontcard .fontspec{display:block;min-height:34px;font-size:17px;',
    '  line-height:1.25;color:#FFFCF0;overflow:hidden;',
    '  text-overflow:ellipsis;white-space:nowrap}',
    '.fontcard .fontcat{font-size:9px;font-weight:700;letter-spacing:.08em;',
    '  text-transform:uppercase;color:#9aa0ab;margin-right:6px}',
    '.fontsearch{width:100%;box-sizing:border-box;background:rgba(255,255,255,.07);',
    '  border:1px solid rgba(255,255,255,.14);border-radius:8px;',
    '  color:#FFFCF0;font-size:13px;padding:8px 10px;margin-top:4px}',
    '.fontrows{display:flex;flex-direction:column;gap:2px;margin-top:8px;',
    '  max-height:220px;overflow-y:auto;scrollbar-width:thin}',
    '.fontrow{display:flex;align-items:baseline;gap:8px;width:100%;',
    '  text-align:left;background:transparent;border:0;',
    '  border-radius:8px;padding:7px 9px;cursor:pointer;color:#e8ebf0}',
    '.fontrow:hover{background:rgba(255,255,255,.08)}',
    '.fontrow .rspec{flex:1;font-size:15px;color:#FFFCF0;overflow:hidden;',
    '  text-overflow:ellipsis;white-space:nowrap}',
    /* the palette editor (Q4, palette-plane-universal): the card's edit
       affordance mirrors the × — top-left to its top-right, same hover
       law, and like the × it must never fire the card's pick. The panel
       is tray chrome: dark glass, moss accents, amber for the fork banner
       and errors — hardcoded studio colors, NEVER the site's palette
       (this dial does not ride the plane it edits). Everything lives
       inside #tray, so the cursor:auto law above already owns the new
       chrome; explicit cursors (pointer on buttons, text in inputs)
       keep theirs. */
    '.palcard .paledbtn{position:absolute;top:-6px;left:-6px;z-index:2;',
    '  width:20px;height:20px;border-radius:50%;background:#2a2a35;',
    '  border:1px solid rgba(255,255,255,.18);color:#9aa0ab;font-size:11px;',
    '  line-height:1;display:flex;align-items:center;justify-content:center;',
    '  opacity:.65;transition:opacity .15s}',
    '.palcard .paledbtn:hover{opacity:1;color:#FFFCF0}',
    '.paledit{margin:10px 0 4px;padding:10px 12px;border-radius:10px;',
    '  border:1px solid rgba(110,136,76,.45);background:rgba(255,255,255,.04)}',
    '.paledit .edbanner{font-size:11.5px;line-height:1.45;color:#e8c98a;',
    '  background:rgba(243,180,76,.12);border:1px solid rgba(243,180,76,.4);',
    '  border-radius:8px;padding:6px 10px;margin-bottom:8px}',
    '.paledit .edrow{display:flex;align-items:center;gap:8px;',
    '  margin-bottom:6px}',
    '.paledit .edrow input[type=color]{width:30px;height:28px;padding:0;',
    '  flex:none;border:1px solid #2a2a35;border-radius:6px;background:#0b0b10}',
    '.paledit .edrow input[type=text]{flex:1;padding:5px 8px;font-size:12px;',
    '  font-family:ui-monospace,monospace}',
    '.paledit input[type=text].bad{border-color:rgba(243,180,76,.75)}',
    '.paledit .edrem{width:22px;height:22px;border-radius:50%;flex:none;',
    '  background:#2a2a35;color:#9aa0ab;font-size:12px;line-height:1;',
    '  display:flex;align-items:center;justify-content:center}',
    '.paledit .edrem:hover{color:#FFFCF0}',
    '.paledit .edrem:disabled,.paledit .edadd:disabled{opacity:.35;',
    '  cursor:not-allowed}',
    '.paledit .edadd{font-size:11.5px;font-weight:700;color:#b8d49a;',
    '  padding:5px 10px;border-radius:8px;background:rgba(143,179,90,.12);',
    '  border:1px solid rgba(143,179,90,.4)}',
    '.paledit .edname{margin-top:8px}',
    '.paledit .edname input[type=text]{padding:5px 8px;font-size:12px}',
    '.paledit .ederr{font-size:11.5px;line-height:1.45;color:#e8c98a;',
    '  margin-top:8px}',
    /* the Incoming slide: one centered placeholder block */
    '.incoming{display:flex;flex-direction:column;align-items:center;',
    '  justify-content:center;gap:8px;min-height:180px;height:100%;',
    '  text-align:center}',
    '.incoming .eye{font-size:10.5px;font-weight:700;letter-spacing:.14em;',
    '  color:#8fb35a}',
    '.incoming .sub{font-size:12.5px;color:#9aa0ab}',
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
  ];
  const style = document.createElement('style');
  style.textContent = CSS.join('\n');
  root.appendChild(style);
  /* Design Mode: the inline text-editing cue lives at DOCUMENT level —
     shadow styles never reach site elements (the old amber caret/outline
     rule was dead code and the caret rode bare currentColor, invisible
     wherever an uncontracted pair was low-contrast). The base rule rides
     currentColor (contract-guaranteed against the surface); at edit-entry
     pickCaretColor() refines it inline to clear BOTH the surface AND the
     text glyphs — see the caret law v2 note at compositeJs. */
  const pageStyle = document.createElement('style');
  pageStyle.textContent =
    '[data-arxa-inline-editing]{outline:2px dashed currentColor !important;' +
    'outline-offset:2px;cursor:text;caret-color:currentColor}';
  document.head.appendChild(pageStyle);

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
    if (S.static) return staticApi(method, sub, body);
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

  // ── the deployed static store driver (VERIFY ADDENDUM 17, locked Q8) ───
  // The deployed artifact talks Supabase directly: PostgREST for reads and
  // comment writes, the security-definer RPCs for identity + the palette
  // publish + the overlay save, Realtime for live frames (subscribeRealtime
  // below). Request fields and response shapes mirror SupabaseDialStore +
  // DialApi EXACTLY — the UI above cannot tell which store answered. RLS
  // law (anon role): SELECT + INSERT only — no update, no delete. The
  // overlay writes ride save_overlay (author-token validated in SQL — the
  // author's raw token rides cfg.token, worker-side verified). Everything
  // else design-time (status writes, guests + mint/revoke, media search,
  // ship, palette CRUD) answers a LOCAL clean refusal: NO network, and the
  // caller's existing error path takes it.
  let sb = null; // the supabase-js client (the UMD loads before the dial)
  function sbClient() {
    if (!sb) sb = window.supabase.createClient(S.static.url, S.static.anonKey);
    return sb;
  }
  function dialNewId() {
    // Client-minted UUIDv4, the same shape the server's dialNewId returns —
    // in static mode pin/reply ids are born here.
    const b = crypto.getRandomValues(new Uint8Array(16));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    const hex = [...b].map((x) => x.toString(16).padStart(2, '0')).join('');
    return hex.slice(0, 8) + '-' + hex.slice(8, 12) + '-' + hex.slice(12, 16) +
      '-' + hex.slice(16, 20) + '-' + hex.slice(20);
  }
  const STATIC_REFUSAL = { ok: false, error: 'design-time only' };
  // Identity for writes: a static guest's attribution comes from
  // resolve_guest_link at boot (the registry, never a typed name); the
  // static author has no local identity file — 'Author' by locked decision.
  function staticAuthor() {
    if (S.mode === 'guest' && S.guest) {
      return {
        kind: 'guest',
        name: S.guest.name || (S.guest.email.split('@')[0] || 'guest'),
        guestId: S.guest.id,
        guestEmail: S.guest.email,
      };
    }
    return { kind: 'author', name: 'Author' };
  }
  // A DB row → the DialPin JSON shape (DialApi's toJson): the island
  // renders THIS shape, whichever store answered. The embedded drawings
  // row is an object when PostgREST detects the unique FK, a list when it
  // doesn't, null when the pin carries no drawing.
  function staticPinFromRow(r) {
    const dw = r.arxa_dial_drawings;
    const drawing = dw && !Array.isArray(dw) ? dw.strokes
      : Array.isArray(dw) && dw.length ? dw[0].strokes : null;
    const anchor = { el: r.anchor_el || null, rect: r.rect };
    if (r.context_text) anchor.text = r.context_text;
    const pin = {
      id: r.id,
      artifact: r.artifact,
      route: r.route,
      viewport: { w: r.viewport_w, h: r.viewport_h },
      anchor: anchor,
      status: r.status,
      author: r.author_kind,
      name: r.author_name,
      body: r.body,
      createdAt: r.created_at,
      updatedAt: r.updated_at,
      replies: (r.arxa_dial_replies || []).map((rr) => {
        const reply = {
          id: rr.id,
          author: rr.author_kind,
          name: rr.author_name,
          body: rr.body,
          createdAt: rr.created_at,
        };
        if (rr.guest_email) reply.guestEmail = rr.guest_email;
        return reply;
      }),
    };
    if (r.guest_email) pin.guestEmail = r.guest_email;
    if (drawing) pin.drawing = drawing;
    return pin;
  }
  async function staticListPins() {
    const r = await sbClient()
      .from('arxa_dial_pins')
      .select('*,arxa_dial_replies(*),arxa_dial_drawings(strokes)')
      .eq('design_id', S.static.designId)
      .order('created_at', { ascending: true });
    if (r.error) return null;
    return { store: 'supabase', pins: (r.data || []).map(staticPinFromRow) };
  }
  async function staticCreatePin(body) {
    const a = staticAuthor();
    const now = new Date().toISOString();
    const anchor = body.anchor || {};
    const row = {
      id: dialNewId(),
      artifact: S.artifact,
      design_id: S.static.designId,
      route: String(body.route || '/'),
      viewport_w: (body.viewport && body.viewport.w) | 0,
      viewport_h: (body.viewport && body.viewport.h) | 0,
      anchor_el: anchor.el || null,
      rect: anchor.rect || { x: 0, y: 0, w: 0, h: 0 },
      context_text: anchor.text || null,
      status: 'open',
      author_kind: a.kind,
      author_name: a.name,
      body: String(body.body || ''),
      created_at: now,
      updated_at: now,
    };
    if (a.guestId) row.guest_id = a.guestId;
    if (a.guestEmail) row.guest_email = a.guestEmail;
    const r = await sbClient().from('arxa_dial_pins').insert(row);
    if (r.error) return { ok: false, error: r.error.message || 'pin refused' };
    // The island never draws, but the shape parity costs one branch: a
    // caller that sent strokes gets the 1:1 drawings row the server would
    // have written.
    if (body.drawing) {
      await sbClient().from('arxa_dial_drawings')
        .insert({ pin_id: row.id, strokes: body.drawing });
    }
    return {
      pin: staticPinFromRow(Object.assign({}, row, {
        arxa_dial_replies: [], arxa_dial_drawings: null,
      })),
    };
  }
  async function staticReply(body) {
    const a = staticAuthor();
    const row = {
      id: dialNewId(),
      pin_id: String(body.id || ''),
      author_kind: a.kind,
      author_name: a.name,
      body: String(body.body || ''),
      created_at: new Date().toISOString(),
      design_id: S.static.designId,
    };
    if (a.guestId) row.guest_id = a.guestId;
    if (a.guestEmail) row.guest_email = a.guestEmail;
    const r = await sbClient().from('arxa_dial_replies').insert(row);
    if (r.error) return { ok: false, error: r.error.message || 'reply refused' };
    return {
      reply: {
        id: row.id, author: row.author_kind, name: row.author_name,
        body: row.body, createdAt: row.created_at,
      },
    };
  }
  async function staticPublishAxes(body) {
    // Palette and font are THE static axes: style/theme flips re-render
    // source, which only the design-time pipeline can do — a palette id
    // and the per-role font picks are what the deployed store can take,
    // and each RPC validates the link token (share link OR author token)
    // before upserting the shared row.
    const palette = body && body.palette;
    const font = body && body.font;
    if (!palette && !font) return STATIC_REFUSAL;
    const out = { style: 'site', theme: 'system' };
    if (palette) {
      const r = await sbClient().rpc('publish_palette', {
        link_token: S.token, palette_id: palette,
      });
      if (r.error) return null; // transient — the caller's refusal toast owns it
      if (!(r.data && r.data.ok)) {
        return { ok: false, error: (r.data && r.data.error) || 'the axes store refused' };
      }
      out.palette = r.data.palette || palette;
    }
    if (font) {
      // publish_font merges per-role over the stored cell — the grilled
      // independent-dropdowns law, enforced in SQL.
      const r = await sbClient().rpc('publish_font', {
        p_design_id: S.static.designId, p_link_token: S.token, p_font: font,
      });
      if (r.error) return null;
      if (!(r.data && r.data.ok)) {
        return { ok: false, error: (r.data && r.data.error) || 'the font store refused' };
      }
      out.font = r.data.font || font;
    }
    // The same shape the local POST answers (its echo carries the site's
    // 'site'/'system' pair); the Realtime frame settles published ==
    // current exactly like the local SSE echo does.
    return { ok: true, axes: out };
  }
  async function staticResolveGuest() {
    // Boot validation (local parity: dead links boot 'invalid'): the RPC
    // validates the raw token against the live-link hashes and answers WHO
    // this guest is — the guests table itself is closed to anon.
    try {
      const r = await sbClient().rpc('resolve_guest_link', { link_token: S.token });
      if (r.error || !r.data || !r.data.ok) return null;
      return r.data;
    } catch (_) { return null; }
  }
  async function staticSyncAxes() {
    // The axes plane's resync READ (the SSE law's static half): realtime
    // frames missed while the tab was hidden never replay, so on show the
    // published row is read and treated as a frame — the truth, re-applied
    // whole by the one dispatcher.
    try {
      const r = await sbClient().from('arxa_dial_axes')
        .select('style,theme,palette,font')
        .eq('design_id', S.static.designId)
        .limit(1);
      const row = r.data && r.data[0];
      if (row && S.axes) onLiveFrame({ kind: 'axes', data: row });
    } catch (_) {}
  }
  // The overlay write (2026-09-11): save_overlay validates the AUTHOR
  // token hash in SQL — a guest ?dial= link is rejected there, so clients
  // can never write text or media. Empty patches = revert (row deleted).
  async function staticSaveOverlay(patches, baseRev) {
    try {
      const r = await sbClient().rpc('save_overlay', {
        p_design_id: S.static.designId,
        p_link_token: S.token,
        p_base_rev: baseRev,
        p_patches: patches,
      });
      if (r.error) return null; // transient — the caller's toast owns it
      return r.data || { ok: false, error: 'the overlay RPC refused' };
    } catch (_) {
      return null;
    }
  }

  async function staticApi(method, sub, body) {
    // The same never-throw contract as api(): null degrades cleanly
    // everywhere. Unmapped subs are design-time by construction.
    try {
      if (sub === '/pins' && method === 'GET') return await staticListPins();
      if (sub === '/pins' && method === 'POST') return await staticCreatePin(body || {});
      if (sub === '/pins/reply' && method === 'POST') return await staticReply(body || {});
      if (sub === '/axes' && method === 'POST') return await staticPublishAxes(body || {});
      return STATIC_REFUSAL;
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
    { id: 'dockbtn', title: 'Arxa Dial', 'aria-label': 'Arxa Dial — arxa' },
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
    { id: 'edit', icon: 'design', tip: 'Edit — fix words & images live', modes: ['author'] },
    { id: 'comment', icon: 'comment', tip: 'Comment — drop a pin', modes: ['author', 'guest'] },
    { id: 'studio', icon: 'studio', tip: 'Studio — open the tray', modes: ['author', 'guest'] },
  ];
  // Edit needs the Supabase store (2026-09-11 decision 4): the overlay is
  // a Supabase row. Deployed static mode HAS it (the author token writes
  // through save_overlay directly); the local designer has it when the
  // store is supabase. A memory-store design shows no Edit verb — there
  // is no overlay backend and none will be built.
  const editCapable = S.mode === 'author' && (S.static || S.store === 'supabase');
  const verbEls = {};
  const verbOrder = [];
  VERBS.forEach((v, i) => {
    if (v.modes.indexOf(S.mode) === -1) return;
    if (v.id === 'edit' && !editCapable) return;
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

  // ── comments board (retired tray slide body — kept callable) ──────────
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

  // ── the identity plane: personal client links (arc 2, was Comments slide)
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
    // Kanban row — Author only (locked decision 1). Hidden in static mode:
    // status writes are design-time (anon RLS grants no UPDATE).
    if (S.mode === 'author' && !S.static) {
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

  // ── Design Mode (author only; redesigned 2026-09-11) ────────────────────
  // Selection walks data-arxa-id (the machine identity the overlay rides).
  // The editor's vocabulary is text + images (decision 1); the kind table
  // below only feeds selection labels — the curated facet sets, color
  // chips, and CSS escape hatch died with the inspector.

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

  // The selection walk: NEAREST STAMP of either vocabulary, SVG collapse,
  // island skipped. Artifacts differ in how they stamp authored text: some
  // carry data-arxa-id on the text element itself, others (the live
  // arxa-site artifact) stamp text carriers data-el-only under data-arxa-id
  // composites. A data-arxa-id-only walk resolved every click to the
  // composite wrapper — which the 2026-09-11 scope law then refuses — and
  // left the whole page uneditable. The walk now binds to whichever stamp
  // is nearest; a data-el hit carries the 'el:' identity bindingFor and
  // targetsForKey already speak (live apply and the eject bake resolve the
  // same key), a data-arxa-id hit keeps the machine-id fan-out.
  function designTargetAt(x, y) {
    const stack = document.elementsFromPoint(x, y);
    for (const el of stack) {
      if (host.contains(el) || el === host) continue;
      let node = el;
      if (node.namespaceURI && node.namespaceURI.indexOf('svg') !== -1 && node.tagName !== 'svg') {
        node = node.closest('svg') || node;
      }
      const hit = node.closest && node.closest('[data-arxa-id],[data-el]');
      if (hit) {
        const k = kindOf(hit);
        const mid = hit.getAttribute('data-arxa-id');
        return {
          id: mid || ('el:' + (hit.getAttribute('data-el') || '')),
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
    // selected element (amber outline + chip); a second
    // highlight chasing the cursor is noise. Hunting is a DISCOVERY
    // affordance, and there is nothing left to discover mid-selection.
    // Deselected (outline cleared / mode re-armed) it resumes by
    // itself — this guard reads S.selected live.
    if (S.selected) { hover.style.display = 'none'; return; }
    const t = designTargetAt(e.clientX, e.clientY);
    // The 2026-09-11 scope law: only EDITABLE elements highlight —
    // text-editable elements and images/videos. Everything else is not
    // editable anymore, and outlining it would promise an interaction
    // the editor no longer has.
    if (t && !isEditableTarget(t.el)) { hover.style.display = 'none'; return; }
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
    // The 2026-09-11 scope law: a click on a non-editable element is the
    // page's click — selecting it would open a chip with nothing to do.
    if (!isEditableTarget(t.el)) return;
    e.preventDefault();
    e.stopPropagation();
    selectEl(t);
  }

  // The editor's whole target vocabulary (decision 1): text-bearing
  // elements with no stamped descendants (isTextEditable below) and
  // images/videos (the swap surface). Everything else is scenery. The media
  // arm covers BOTH shapes artifacts stamp: the media element itself, and a
  // stamped wrapper whose img/video it carries (the live artifact stamps
  // wrappers only — an img-only law left every image unreachable).
  function isEditableTarget(el) {
    return isTextEditable(el) || el.tagName === 'IMG' || el.tagName === 'VIDEO'
      || !!el.querySelector('img,video');
  }
  // The element a media attr actually lands on: the media inside a stamped
  // wrapper. Live apply, the chip's swap, and the eject bake all resolve
  // through this ONE descent so they can never disagree.
  const MEDIA_ATTRS = ['src', 'srcset', 'poster'];
  function mediaOf(el) {
    if (!el) return null;
    if (el.tagName === 'IMG' || el.tagName === 'VIDEO') return el;
    return el.querySelector('img,video');
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
    openChip();
    return true;
  }
  function clearSelOutline() {
    if (S.inlineEditing != null) inlineEditEnd(true);
    if (S.selected) S.selected.el.style.outline = S.selOutline || '';
    S.selected = null;
    closeChip();
  }

  // ── on-canvas text editing (decision 1 — the primary edit gesture) ───
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
    var caret = pickCaretColor(sel.el);
    if (caret) {
      var caretCss = 'rgb(' + caret[0] + ',' + caret[1] + ',' + caret[2] + ')';
      sel.el.style.caretColor = caretCss;
      sel.el.style.outlineColor = caretCss;
    }
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
    el.style.caretColor = '';
    el.style.outlineColor = '';
    if (commit) {
      // setTextContent normalizes whatever markup contenteditable produced,
      // patches the overlay, records the undo step, and schedules the save.
      setTextContent(sel.key, el.textContent, el);
    } else {
      el.textContent = original;
    }
  }
  function onDesignDblClick(e) {
    if (e.composedPath().indexOf(host) !== -1) return;
    const t = designTargetAt(e.clientX, e.clientY);
    if (!t) return;
    // The scope law again: double-click types TEXT; a non-text-editable
    // target is the page's double-click, not an edit session.
    if (!isTextEditable(t.el)) return;
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
    setDockMode('edit'); // the dock flips to the edit face
    verbEls.edit.classList.add('on');
    document.addEventListener('pointermove', onDesignMove, true);
    document.addEventListener('click', onDesignClick, true);
    document.addEventListener('dblclick', onDesignDblClick, true);
    updateEditBar();
    say('Edit Mode — double-click text to type; click an image to swap it');
  }
  function designOff() {
    S.design = false;
    setDockMode(''); // the dock returns to the arxa face
    closePanel();
    clearSelOutline();
    if (verbEls.edit) verbEls.edit.classList.remove('on');
    hover.style.display = 'none';
    hover.classList.remove('design');
    updateEditBar();
    document.removeEventListener('pointermove', onDesignMove, true);
    document.removeEventListener('click', onDesignClick, true);
    document.removeEventListener('dblclick', onDesignDblClick, true);
  }

  // ── the Live Overlay: patch model + debounced save + session undo ────
  function patchFor(id) {
    let p = S.overlay.patches[id];
    if (!p) { p = { attrs: {} }; S.overlay.patches[id] = p; }
    if (!p.attrs) p.attrs = {};
    return p;
  }
  function dropPatchIfEmpty(key) {
    const p = S.overlay.patches[key];
    if (p && p.text == null && !Object.keys(p.attrs || {}).length) {
      delete S.overlay.patches[key];
    }
  }

  // Session-local undo/redo (decision 3, grilled 2026-09-11): an inverse
  // stack in THIS tab, depth ~50, no server journal. Undo exists to fix
  // the thing you just did — older than that is editing the text back or
  // Revert-to-published, both of which already exist. "Session-local"
  // means the TAB: the stack rides sessionStorage so the animator-converge
  // reload (every text save triggers one ~1.4s later) does not silently
  // erase the author's history — closing the tab still kills it, by design.
  const UNDO_CAP = 50;
  const UNDO_KEY = 'arxa-dial-undo';
  function saveUndoState() {
    try {
      sessionStorage.setItem(UNDO_KEY, JSON.stringify({
        u: S.undoStack, r: S.redoStack,
      }));
    } catch (_) {}
  }
  function restoreUndoState() {
    try {
      const d = JSON.parse(sessionStorage.getItem(UNDO_KEY) || 'null');
      if (d && Array.isArray(d.u)) S.undoStack = d.u.slice(-UNDO_CAP);
      if (d && Array.isArray(d.r)) S.redoStack = d.r.slice(-UNDO_CAP);
    } catch (_) {}
  }
  function pushUndo(entry) {
    S.undoStack.push(entry);
    if (S.undoStack.length > UNDO_CAP) S.undoStack.shift();
    S.redoStack.length = 0; // a new edit forks history
    saveUndoState();
    updateEditBar();
  }
  function doUndo() {
    const e = S.undoStack.pop();
    if (!e) return;
    applyInverse(e, true);
    S.redoStack.push(e);
    saveUndoState();
    updateEditBar();
    refreshChipSafe();
    scheduleSave();
  }
  function doRedo() {
    const e = S.redoStack.pop();
    if (!e) return;
    applyInverse(e, false);
    S.undoStack.push(e);
    saveUndoState();
    updateEditBar();
    refreshChipSafe();
    scheduleSave();
  }
  // Re-render the open chip (its Revert affordance depends on the patch
  // set) — but never while the swap panel holds focus in its inputs.
  function refreshChipSafe() {
    if (S.chipOpen && !ePanelOpen()) renderChipBody();
  }
  // An inverse record is symmetric: {kind:'text', key, from, to} or
  // {kind:'attr', key, attr, from, to} — undo applies from, redo applies
  // to. from/to null on attrs means "attribute absent". A text record with
  // from == null means the element had NO patch before the edit: undo
  // removes the patch and restores the captured pre-edit text.
  function applyInverse(e, undo) {
    const v = undo ? e.from : e.to;
    if (e.kind === 'text') {
      if (v == null) {
        const p = S.overlay.patches[e.key];
        const was = p && p.was != null ? p.was : null;
        delete S.overlay.patches[e.key];
        for (const el of targetsForKey(e.key)) {
          if (was != null && isTextEditable(el)) el.textContent = was;
        }
      } else {
        setTextContent(e.key, v, null, { noUndo: true });
      }
    } else if (e.kind === 'attr') {
      setAttrProp(e.key, e.attr, v, null, { noUndo: true });
    }
    dropPatchIfEmpty(e.key);
  }

  let saveTimer = null;
  function scheduleSave() {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(saveOverlay, 700);
  }
  let saveInFlight = false;
  async function saveOverlay() {
    if (S.mode !== 'author') return;
    if (saveInFlight) { scheduleSave(); return; } // retry after the round trip
    saveInFlight = true;
    S.ownSave = Date.now();
    try {
      const baseRev = S.overlay.rev;
      const r = S.static
        ? await staticSaveOverlay(S.overlay.patches, baseRev)
        : await api('PUT', '/overlay', { patches: S.overlay.patches, baseRev: baseRev });
      if (!r || !r.ok) {
        if (r && r.error === 'stale') {
          // Decision 5's stale-guard: another surface is ahead — adopt its
          // doc whole instead of clobbering it. Our un-saved edit is lost;
          // the toast says so honestly.
          adoptOverlayDoc({ patches: r.patches || {}, rev: r.rev || 0 });
          say('Newer edits exist from another surface — resynced; your last change was not saved');
        } else {
          say(r && r.error ? 'Save refused: ' + r.error : 'Save failed — retrying on the next edit');
        }
        return;
      }
      S.overlay.rev = r.rev || 0;
      if (!Object.keys(S.overlay.patches).length) {
        // Revert-to-published landed: the row is gone, everyone snaps back.
        S.overlay.rev = 0;
        S.undoStack.length = 0;
        S.redoStack.length = 0;
        saveUndoState(); // the cleared history must survive the reload too
        updateEditBar();
        resumeReload(); // the clean way to un-apply attrs we cannot restore
      } else {
        convergeAfterText();
      }
    } finally {
      saveInFlight = false;
    }
  }

  // Revert-to-published (decision 2): empty patches = the row dies. One
  // action, one home — the edit bar's button.
  async function revertPublished() {
    S.overlay.patches = {};
    await saveOverlay();
  }
  // Per-element revert: drop the element's patch; text restores live from
  // its captured `was`, an attr change converges by reload.
  async function revertElement(key) {
    const p = S.overlay.patches[key];
    if (!p) return;
    if (p.text != null && p.was != null && !Object.keys(p.attrs || {}).length) {
      const insts = targetsForKey(key);
      const scoped = p.nth != null && insts[p.nth] ? [insts[p.nth]] : insts;
      for (const el of scoped) { if (isTextEditable(el)) el.textContent = p.was; }
      delete S.overlay.patches[key];
      scheduleSave();
    } else {
      delete S.overlay.patches[key];
      await saveOverlay();
      resumeReload();
    }
    updateEditBar();
    refreshChipSafe();
  }

  // The animator-converge law (2026-08-26, kept): artifact animators
  // re-split their text from a boot capture and will fight a live
  // textContent write within seconds. When the just-saved doc carries
  // text patches, reload once typing pauses so everyone — author and
  // watching clients — sees the animator render the NEW text.
  let lastTextSig = null;
  let textReloadTimer = null;
  function overlayTextSig(patches) {
    const parts = [];
    for (const k of Object.keys(patches).sort()) {
      const t = (patches[k] || {}).text;
      if (t != null) parts.push(k + '=' + t);
    }
    return parts.join('|');
  }
  function noteOverlaySig() {
    lastTextSig = overlayTextSig(S.overlay.patches);
  }
  function convergeAfterText() {
    const sig = overlayTextSig(S.overlay.patches);
    if (sig !== lastTextSig) {
      noteOverlaySig();
      clearTimeout(textReloadTimer);
      textReloadTimer = setTimeout(resumeReload, 1400);
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
    if (S.selected && S.selected.key === t.key && S.chipOpen) return; // already there
    const insts = targetsForKey(t.key);
    if (!insts.length) return;
    const el = insts[Math.min(t.nth || 0, insts.length - 1)];
    if (!el || !el.isConnected) return;
    if (!S.design) designOn();
    centerElement(el);
    const k = kindOf(el);
    // the same identity derivation as designTargetAt — a data-el-only
    // carrier has no machine id, and a null id would crash targetsForKey.
    selectEl({
      id: el.getAttribute('data-arxa-id')
        || (el.getAttribute('data-el') ? 'el:' + el.getAttribute('data-el') : null),
      el: el,
      label: (el.getAttribute('data-el') || el.tagName.toLowerCase()) + ' · ' + k.kind,
      group: k.group,
    });
    try { sessionStorage.removeItem('arxa-dial-trackback'); } catch (_) {}
  }
  document.body.addEventListener('htmx:afterSwap', () => {
    maybeRestoreTrackback();
    // A boosted navigation swapped the body — the live overlay's patches
    // died with the old DOM. Re-apply the whole doc to the fresh one (the
    // local author used to get this from serve-time injection; the
    // overlay is client-side everywhere now).
    if (S.overlayReady) applyOverlayToDom(S.overlay.patches);
  });

  // Boot read (author AND guest — decision 2: clients see the overlay).
  // Local: GET /__dial/overlay (also the author's capability probe — a
  // quiet mirror marker or dead network means no dial here). Static: one
  // PostgREST select on the row. The read is the LAST truth before the
  // realtime frames take over.
  async function loadOverlay() {
    let doc = null;
    if (S.static) {
      try {
        const r = await sbClient().from('arxa_dial_overlays')
          .select('patches,rev').eq('design_id', S.static.designId).limit(1);
        if (!r.error && r.data && r.data[0]) {
          doc = { patches: r.data[0].patches || {}, rev: r.data[0].rev || 0 };
        }
      } catch (_) { return false; }
    } else {
      const r = await probeCapable('/overlay');
      if (r == null || r.mirror === true) return false;
      if (r && r.overlay) doc = { patches: r.overlay.patches || {}, rev: r.overlay.rev || 0 };
    }
    if (doc) {
      S.overlay = doc;
      applyOverlayToDom(doc.patches);
    }
    S.overlayReady = true;
    noteOverlaySig();
    return true;
  }

  // Apply a whole overlay doc to THIS document (boot, realtime frame,
  // afterSwap re-apply). Text lands only on text-editable targets —
  // composite instances are the eject bake's problem, loudly, by design.
  function applyOverlayToDom(patches) {
    for (const key of Object.keys(patches)) {
      const p = patches[key] || {};
      const insts = targetsForKey(key);
      for (const el of insts) {
        if (p.text != null && isTextEditable(el)) el.textContent = p.text;
        if (p.attrs) {
          // media attrs land on the img/video inside (the one descent —
          // setAttrProp records nth over the same mapped list, so the
          // scoping comparison stays apples-to-apples)
          const mediaNames = Object.keys(p.attrs).filter((n) => MEDIA_ATTRS.indexOf(n) >= 0);
          const applyEl = mediaNames.length ? (mediaOf(el) || el) : el;
          for (const name of Object.keys(p.attrs)) {
            const v = p.attrs[name];
            // instance-scoped attrs (see setAttrProp) touch ONLY their
            // occurrence — the live twin of the overlay's onlyNth path.
            if (p.attrsNth && Object.prototype.hasOwnProperty.call(p.attrsNth, name)) {
              if (el === insts[p.attrsNth[name]]) {
                if (v == null) applyEl.removeAttribute(name);
                else applyEl.setAttribute(name, v);
              }
              continue;
            }
            if (v == null) applyEl.removeAttribute(name);
            else applyEl.setAttribute(name, v);
          }
        }
      }
    }
  }

  // The ONE overlay frame law (SSE + Realtime alike): a doc with a rev we
  // already hold is our own echo (or older) — ignored; anything newer is
  // adopted whole, applied live, and said so with the transient live chip.
  function overlayFrame(doc) {
    if (!doc || typeof doc.rev !== 'number') return;
    if (doc.rev !== 0 && doc.rev <= S.overlay.rev) return;
    const hadPatches = Object.keys(S.overlay.patches).length > 0;
    const isRevert = doc.rev === 0 && hadPatches;
    if (doc.rev === 0 && !hadPatches) return;
    adoptOverlayDoc(doc);
    liveChip();
    if (isRevert) {
      // Revert-to-published from another surface: snap back. Text with
      // captured `was` restores live; attrs converge by reload.
      resumeReload();
      return;
    }
    // The animator-converge law applies to viewers too: a frame carrying
    // text settles by one reload; attr-only frames stay purely live.
    convergeAfterText();
  }
  function adoptOverlayDoc(doc) {
    S.overlay = { patches: (doc && doc.patches) || {}, rev: (doc && doc.rev) || 0 };
    applyOverlayToDom(S.overlay.patches);
    noteOverlaySig();
    S.overlayReady = true;
  }

  // The resync READ (the socket-pool law's other half): frames missed
  // while hidden never replay, so on show the row is read and treated as
  // a frame — the truth, re-applied whole by the one dispatcher.
  async function syncOverlay() {
    if (S.mode !== 'author' && S.mode !== 'guest') return;
    try {
      let doc = null;
      if (S.static) {
        const r = await sbClient().from('arxa_dial_overlays')
          .select('patches,rev').eq('design_id', S.static.designId).limit(1);
        if (!r.error && r.data && r.data[0]) {
          doc = { patches: r.data[0].patches || {}, rev: r.data[0].rev || 0 };
        }
      } else {
        const r = await api('GET', '/overlay');
        if (r && r.overlay) doc = { patches: r.overlay.patches || {}, rev: r.overlay.rev || 0 };
      }
      if (doc) overlayFrame(doc);
      else if (Object.keys(S.overlay.patches).length) overlayFrame({ patches: {}, rev: 0 });
    } catch (_) {}
  }

  // The live chip (decision 9): transient, unobtrusive, never per-frame
  // toast spam. Says WHY the page just changed under this viewer, fades.
  let liveChipTimer = null;
  function liveChip() {
    liveChipEl.classList.add('open');
    liveChipEl.style.display = 'flex';
    clearTimeout(liveChipTimer);
    liveChipTimer = setTimeout(() => { liveChipEl.style.display = 'none'; }, 4000);
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
  function setAttrProp(key, name, value, origin, opts) {
    const p = patchFor(key);
    const prev = Object.prototype.hasOwnProperty.call(p.attrs, name)
      ? p.attrs[name] : null;
    p.attrs[name] = value || null; // empty clears the attribute
    // Media attrs resolve through the ONE descent: a stamped wrapper's src
    // lands on the img/video it carries, and the origin instance is mapped
    // the same way so per-instance scoping keeps pointing at the tapped one.
    const mediaAttr = MEDIA_ATTRS.indexOf(name) >= 0;
    const insts = mediaAttr
      ? targetsForKey(key).map(mediaOf).filter(Boolean)
      : targetsForKey(key);
    if (mediaAttr && origin) origin = mediaOf(origin) || origin;
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
    dropPatchIfEmpty(key);
    if (!(opts && opts.noUndo) && value !== prev) {
      pushUndo({ kind: 'attr', key: key, attr: name, from: prev, to: value || null });
    }
    scheduleSave();
  }
  function setTextContent(key, value, origin, opts) {
    const p = patchFor(key);
    const insts = targetsForKey(key);
    if (p.text == null && insts.length) {
      // First text edit captures seed-route provenance: was = this
      // instance's pre-edit text (the eject-bake value anchor); nth =
      // its occurrence index, recorded ONLY when instances diverge —
      // data-backed rows get per-instance bakes and per-instance live
      // apply, homogeneous repeats keep every-row semantics; page rides
      // for slug correlation.
      const o = origin && insts.indexOf(origin) >= 0 ? origin : insts[0];
      p.was = o.textContent;
      if (origin && insts.some((el) => el.textContent !== insts[0].textContent)) {
        p.nth = Math.max(0, insts.indexOf(origin));
      }
      p.page = location.pathname;
      // Locale targeting (2026-08-24): the bake writes ONLY the locale
      // being edited — <html lang> first, else the leading /xx/ pathname
      // segment. Absent both, the bake updates every locale (old law).
      const hl = (document.documentElement.lang || '').toLowerCase().slice(0, 2);
      if (/^[a-z]{2}$/.test(hl)) p.locale = hl;
      else {
        const seg = location.pathname.split('/')[1] || '';
        if (/^[a-z]{2}$/.test(seg)) p.locale = seg;
      }
    }
    const prev = p.text != null ? p.text : null;
    p.text = value;
    const scoped = p.nth != null && insts[p.nth] ? [insts[p.nth]] : insts;
    for (const el of scoped) {
      if (isTextEditable(el)) el.textContent = value;
    }
    if (!(opts && opts.noUndo) && value !== prev) {
      pushUndo({ kind: 'text', key: key, from: prev, to: value });
    }
    scheduleSave();
  }

  // ── the edit bar: session undo/redo + Revert to published ────────────
  const editBar = h('div', { id: 'editbar' });
  const undoBtn = h('button', { class: 'ebundo', text: '↺ Undo', title: 'Cmd+Z' });
  const redoBtn = h('button', { class: 'ebredo', text: '↻ Redo', title: 'Shift+Cmd+Z' });
  const revertAllBtn = h('button', { class: 'ebrevert', text: 'Revert all', title: 'Drop every live edit — everyone back to the published page' });
  undoBtn.addEventListener('click', () => { if (S.inlineEditing == null) doUndo(); });
  redoBtn.addEventListener('click', () => { if (S.inlineEditing == null) doRedo(); });
  revertAllBtn.addEventListener('click', () => revertPublished());
  editBar.appendChild(undoBtn);
  editBar.appendChild(redoBtn);
  editBar.appendChild(revertAllBtn);
  root.appendChild(editBar);
  function updateEditBar() {
    // Hidden while the tray is open (the sheet owns the corner; the bar
    // would float over the sheet's glass).
    editBar.classList.toggle('open', !!S.design && !S.tray);
    undoBtn.disabled = !S.undoStack.length;
    redoBtn.disabled = !S.redoStack.length;
    undoBtn.textContent = '↺ Undo' + (S.undoStack.length ? ' (' + S.undoStack.length + ')' : '');
    redoBtn.textContent = '↻ Redo' + (S.redoStack.length ? ' (' + S.redoStack.length + ')' : '');
    revertAllBtn.disabled = !Object.keys(S.overlay.patches).length;
  }

  // ── the live chip element (liveChip() paints it) ──────────────────────
  const liveChipEl = h('div', { id: 'livechip' }, [
    h('span', { class: 'dot' }),
    h('span', { text: 'live — updated' }),
  ]);
  root.appendChild(liveChipEl);

  // ── the selection chip (the smart card's tiny successor) ──────────────
  // Text edits happen ON THE CANVAS; the chip anchors to the selection,
  // says what it is, and carries the element's rare actions: Swap (media)
  // and Revert (drop this element's edits). It tracks its anchor through
  // scrolls/resizes/swaps via the float-tracking loop below.
  const eChip = h('div', { id: 'echip' });
  root.appendChild(eChip);
  // The swap ePanel: the eChip's one popover.
  const ePanel = h('div', { id: 'epanel' });
  root.appendChild(ePanel);

  function renderChipBody() {
    eChip.textContent = '';
    if (!S.selected) return;
    const sel = S.selected;
    const media = mediaOf(sel.el);
    eChip.appendChild(h('span', { class: 'elabel', text: sel.label.split(' · ')[0] }));
    // A stamped wrapper can carry BOTH surfaces (the hero stage holds text
    // layers AND its video) — the hint and the Swap are not either/or.
    if (isTextEditable(sel.el)) {
      eChip.appendChild(h('span', { class: 'hint', text: 'double-click to type' }));
    }
    if (media) {
      const swap = h('button', { text: '⇄ Swap' + (media.tagName === 'VIDEO' ? ' video' : ' image'), title: 'Swap this media' });
      swap.addEventListener('click', (e) => { e.stopPropagation(); openPanel(); });
      eChip.appendChild(swap);
    }
    if (S.overlay.patches[sel.key]) {
      const rev = h('button', { text: 'Revert', title: 'Drop this element’s live edits' });
      rev.addEventListener('click', (e) => {
        e.stopPropagation();
        revertElement(sel.key);
      });
      eChip.appendChild(rev);
    }
    const x = h('button', { class: 'xbtn', text: '×', title: 'Deselect', 'aria-label': 'Deselect' });
    x.addEventListener('click', (e) => { e.stopPropagation(); clearSelOutline(); });
    eChip.appendChild(x);
  }

  function positionChip() {
    if (!S.selected || !S.chipOpen) { return; }
    const el = S.selected.el;
    if (!el.isConnected) { closeChip(); return; }
    eChip.classList.add('open');
    S.chipOpen = true;
    const r = el.getBoundingClientRect();
    // anchor: centered under the element's top edge; flip above when the
    // element hugs the top; clamp inside the viewport.
    const cw = eChip.offsetWidth || 200;
    let x = r.left + r.width / 2 - cw / 2;
    x = Math.min(Math.max(8, x), Math.max(8, innerWidth - cw - 8));
    const ch = eChip.offsetHeight || 34;
    let y = r.top - ch - 8;
    if (y < 8) y = Math.min(r.bottom + 8, Math.max(8, innerHeight - ch - 8));
    eChip.style.left = x + 'px';
    eChip.style.top = y + 'px';
    if (ePanel.classList.contains('open')) positionPanel();
  }
  function openChip() {
    S.chipOpen = true;
    renderChipBody();
    positionChip();
    dialPanelChanged();
  }
  function closeChip() {
    S.chipOpen = false;
    eChip.classList.remove('open');
    closePanel();
    dialPanelChanged();
  }

  function positionPanel() {
    const cw = ePanel.offsetWidth || 280;
    let x = eChip.offsetLeft;
    x = Math.min(Math.max(8, x), Math.max(8, innerWidth - cw - 8));
    let y = eChip.offsetTop + eChip.offsetHeight + 6;
    const ph = ePanel.offsetHeight || 160;
    if (y + ph > innerHeight - 8) y = Math.max(8, eChip.offsetTop - ph - 6);
    ePanel.style.left = x + 'px';
    ePanel.style.top = y + 'px';
  }
  function closePanel() {
    ePanel.classList.remove('open');
  }
  function ePanelOpen() {
    return ePanel.classList.contains('open');
  }
  function openPanel() {
    renderPanelBody();
    ePanel.classList.add('open');
    positionPanel();
  }

  // The swap surface (decision 8): the local designer keeps its server-side
  // search + from-assets (provider keys never reach the browser); the
  // deployed site has no /__dial server, so it gets a paste-URL field. Both
  // write the SAME attrs patch and stream like any other edit.
  function renderPanelBody() {
    ePanel.textContent = '';
    const sel = S.selected;
    if (!sel) return;
    const isVideo = sel.el.tagName === 'VIDEO';
    if (S.static) {
      ePanel.appendChild(h('div', { class: 'sect', text: 'Swap ' + (isVideo ? 'video' : 'image') }));
      const row = h('div', { class: 'prow' });
      const url = h('input', { type: 'text', placeholder: 'https://… image url' });
      const go = h('button', { class: 'btn', text: 'Swap' });
      row.appendChild(url);
      row.appendChild(go);
      ePanel.appendChild(row);
      const note = h('div', { class: 'pnote', text: 'Paste any image URL — it goes live for every viewer.' });
      ePanel.appendChild(note);
      const apply = () => {
        const v = url.value.trim();
        if (!/^https:\/\//.test(v)) { note.textContent = 'Only https:// URLs.'; return; }
        setAttrProp(sel.key, 'src', v, sel.el);
        note.textContent = '✓ swapped — live';
        closePanel();
      };
      go.addEventListener('click', apply);
      url.addEventListener('keydown', (e) => { if (e.key === 'Enter') apply(); e.stopPropagation(); });
      return;
    }
    // Local designer: the media proxy (unchanged law — keys server-side).
    ePanel.appendChild(h('div', { class: 'sect', text: 'Swap ' + (isVideo ? 'video' : 'image') }));
    const row = h('div', { class: 'prow' });
    const q = h('input', { type: 'text', placeholder: isVideo ? 'search Pexels video…' : 'search Unsplash + Pexels…' });
    const go = h('button', { class: 'btn', text: 'Find' });
    row.appendChild(q);
    row.appendChild(go);
    ePanel.appendChild(row);
    const grid = h('div', { class: 'pgrid' });
    ePanel.appendChild(grid);
    const creditLine = h('div', { class: 'pnote' });
    ePanel.appendChild(creditLine);
    go.addEventListener('click', async () => {
      grid.textContent = '';
      creditLine.textContent = 'searching…';
      const r = await api('POST', '/media/search', { q: q.value.trim(), kind: isVideo ? 'video' : 'photo' });
      grid.textContent = '';
      if (!r || !r.results) { creditLine.textContent = (r && r.error) || 'search failed'; return; }
      if (!r.results.length) { creditLine.textContent = 'no results'; return; }
      r.results.forEach((hit) => {
        const b = h('button', { title: hit.credit + ' · ' + hit.provider, style: 'width:64px;height:64px' });
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
          creditLine.textContent = '✓ ' + c.path;
          closePanel();
        });
        grid.appendChild(b);
      });
      creditLine.textContent = r.results.length + ' results — tap to swap in';
    });
    const assetsRow = h('div', { class: 'prow' });
    const loadAssets = h('button', { class: 'btn ghost', text: 'From assets' });
    loadAssets.addEventListener('click', async () => {
      const r = await api('GET', '/media/assets');
      grid.textContent = '';
      if (!r || !r.assets) { creditLine.textContent = (r && r.error) || 'asset list failed'; return; }
      if (!r.assets.length) { creditLine.textContent = 'no local assets yet'; return; }
      r.assets.forEach((path) => {
        const b = h('button', { title: path, text: path.split('/').pop(), style: 'font-size:10px;padding:4px 6px' });
        b.addEventListener('click', () => { setAttrProp(sel.key, 'src', path, sel.el); closePanel(); });
        grid.appendChild(b);
      });
    });
    assetsRow.appendChild(loadAssets);
    ePanel.appendChild(assetsRow);
  }

  // centerElement (kept from the card era): the smooth-scroll law — the
  // artifact may own the wheel (NIBSmoothScroll); scrollIntoView survives,
  // and the lib's scrollTo is the first-class path.
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

  // FLOAT TRACKING (improvement 2, floating-ui autoUpdate practice,
  // 2026-08-25): an anchored panel re-derives its position on every
  // frame-worthy signal — capture-phase scroll (scroll does not bubble,
  // capture still sees nested scroll containers), window resize, and one
  // rAF to coalesce bursts so a fast wheel never thrashes layout reads.
  // Before this the chip clamped ONCE at open and then sat still while
  // its anchor scrolled out from under it.
  let floatTrackRaf = false;
  function trackFloats() {
    if (floatTrackRaf) return;
    floatTrackRaf = true;
    requestAnimationFrame(() => {
      floatTrackRaf = false;
      if (S.chipOpen) positionChip();
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

  // ── the axes plane: style/theme/palette, dial-owned ──────────────────
  // The server already rendered the active pick into the page; these flip
  // it live in THIS document (link.disabled + the html data-theme attr +
  // the design's own palette.js) and keep the URL honest — the URL is the
  // receipt (the Storybook-globals pattern). Authors publish via POST
  // /__dial/axes; guests ride the URL for style/theme as before, but a
  // PALETTE pick publishes for everyone — the share link is the
  // authorization. A persistent badge marks on-screen ≠ published.
  function axesPreviewing() {
    // In-flight publishes are not previews (operator, 2026-09-09): a palette
    // pick IS a publish — without this gate the pvnote flashed in/out for
    // the round-trip's duration and the bottom-anchored tray JUMPED ~55px
    // on every pick. The note still appears the moment a publish FAILS
    // (published stays stale) and for guest style/theme previews, which
    // never enter flight at all.
    if (S.publishing) return false;
    return !!S.axes && (S.axes.current.style !== S.axes.published.style ||
      S.axes.current.theme !== S.axes.published.theme ||
      S.axes.current.palette !== S.axes.published.palette ||
      !fontPickEq(S.axes.current.font, S.axes.published.font));
  }
  // role -> choice-id maps compare by key set + values (the independence
  // law's preview compare: one role flipped = previewing).
  function fontPickEq(a, b) {
    a = a || {}; b = b || {};
    const ka = Object.keys(a), kb = Object.keys(b);
    if (ka.length !== kb.length) return false;
    return ka.every((k) => a[k] === b[k]);
  }
  function applyAxes(style, theme, palette, font) {
    document.querySelectorAll('link[data-axes-style]').forEach((link) => {
      link.disabled = link.getAttribute('data-axes-style') !== style;
    });
    if (!theme || theme === 'system') {
      document.documentElement.removeAttribute('data-theme');
    } else {
      document.documentElement.setAttribute('data-theme', theme);
    }
    // The palette is the page's own plane: palette.js (a script the design
    // ships) owns applying it — the dial only hands the id over, and a
    // design without palette.js simply ignores the pick.
    if (typeof palette === 'string' && palette &&
        window.__arxaPalette && window.__arxaPalette.set) {
      window.__arxaPalette.set(palette);
    }
    // The font plane is the page's own plane the same way: font.js owns
    // the attributes + the css2 link; the dial only hands the picks over.
    if (font && window.__arxaFont && window.__arxaFont.set) {
      Object.keys(font).forEach((role) => window.__arxaFont.set(role, font[role]));
    }
    S.axes.current = {
      style: style, theme: theme || 'system', palette: palette || '',
      font: font || S.axes.current.font || {},
    };
    syncAxesUrl();
    updatePreviewMark();
    if (S.tray === 'theme') renderTraySlide('theme');
    if (S.tray === 'fonts') renderTraySlide('fonts');
  }
  function syncAxesUrl() {
    try {
      const url = new URL(location.href);
      const current = S.axes.current, published = S.axes.published;
      const fontMatch = fontPickEq(current.font, published.font);
      if (current.style === published.style &&
          current.theme === published.theme &&
          current.palette === published.palette &&
          fontMatch) {
        url.searchParams.delete('style');
        url.searchParams.delete('theme');
        url.searchParams.delete('palette');
        url.searchParams.delete('font');
      } else {
        // style joins the receipt only when there IS one — palette-only
        // site axes must not stamp an empty ?style= into the URL. Theme
        // stays verbatim (the app law), palette deletes when cleared.
        if (current.style) url.searchParams.set('style', current.style);
        else url.searchParams.delete('style');
        url.searchParams.set('theme', current.theme);
        if (current.palette) url.searchParams.set('palette', current.palette);
        else url.searchParams.delete('palette');
        // The font receipt rides comma-joined role:id pairs — the same
        // shape the serve seam parses.
        if (!fontMatch) {
          const sig = Object.keys(current.font || {}).map((r) => r + ':' + current.font[r]).join(',');
          if (sig) url.searchParams.set('font', sig);
          else url.searchParams.delete('font');
        } else {
          url.searchParams.delete('font');
        }
      }
      history.replaceState(null, '', url);
    } catch (_) { /* an unwritable URL just keeps its params */ }
  }
  function updatePreviewMark() {
    dock.classList.toggle('previewing', axesPreviewing());
    dockBtn.title = axesPreviewing()
      ? 'Arxa Dial — previewing unpublished changes'
      : 'Arxa Dial — arxa';
  }
  async function flipAxes(patch) {
    if (!S.axes) return;
    // The font patch is per-role (the independence law): merge over the
    // current picks so one dropdown's flip never blanks the others.
    const nextFont = patch.font
      ? Object.assign({}, S.axes.current.font, patch.font)
      : S.axes.current.font;
    const next = {
      style: patch.style || S.axes.current.style,
      theme: patch.theme || S.axes.current.theme,
      // !== undefined, not ||: an explicit '' CLEARS the palette (the
      // delete affordance relies on it); style/theme have no empty state
      // to express, so their || merge stays.
      palette: patch.palette !== undefined ? patch.palette : S.axes.current.palette,
    };
    // Publish law: style/theme flips stay author-only (guests ride the
    // URL, never the store), but a palette pick and a font pick publish
    // for EVERYONE, author or guest — the share link is the authorization
    // (palette Q10; font grill Q5, 2026-09-13). The flight flag rises
    // BEFORE applyAxes: its render must already see the flight, or the
    // pvnote flashes for the round-trip and the tray jumps.
    const willPublish = S.mode === 'author' ||
      patch.palette !== undefined || patch.font !== undefined;
    if (willPublish) S.publishing = (S.publishing || 0) + 1;
    applyAxes(next.style, next.theme, next.palette, nextFont);
    if (!willPublish) return;
    // Only fields for axes the server DECLARED ride the POST: sites (no
    // style/theme axes) send {palette}, apps send {style,theme} (+palette
    // when picked) — empty values never ride. The font map rides whole
    // (the server re-validates membership + merges per role).
    const out = {};
    if (S.axes.styles.length && next.style) out.style = next.style;
    if (S.axes.themes.length && next.theme) out.theme = next.theme;
    if (next.palette) out.palette = next.palette;
    if (nextFont && Object.keys(nextFont).length) out.font = nextFont;
    try {
      const res = await api('POST', '/axes', out);
      if (res && res.ok && res.axes) {
        S.axes.published = {
          style: res.axes.style ?? next.style,
          theme: res.axes.theme ?? next.theme,
          palette: res.axes.palette ?? '',
          font: res.axes.font ?? S.axes.published.font,
        };
        syncAxesUrl();
        updatePreviewMark();
      } else {
        say('Could not publish — the axes store refused');
        // The pick is now a genuine unpublished preview — surface the note
        // (the in-flight gate above kept the click-time render quiet).
        if (S.tray === 'theme') renderTraySlide('theme');
        updatePreviewMark();
      }
    } finally {
      S.publishing--;
    }
  }
  // Delete affordance (author only — seeded palettes are immortal): POST
  // the id, drop the card; a deleted CURRENT palette falls back to the
  // published one, else the first remaining, else no palette at all.
  async function deletePalette(id) {
    const res = await api('POST', '/palettes/delete', { id: id });
    if (!(res && res.ok)) {
      say((res && res.error) || 'Could not delete the palette');
      return;
    }
    S.axes.palettes = S.axes.palettes.filter((p) => p.id !== id);
    if (S.axes.current.palette === id) {
      flipAxes({
        palette: S.axes.published.palette ||
          (S.axes.palettes[0] && S.axes.palettes[0].id) || '',
      });
    } else {
      renderTraySlide('theme');
    }
  }
  // ── the contrast readout (engine client, 2026-09-11) ────────────────
  // The DIAL shows what the engine guarantees: every contracted pair of
  // the APPLIED palette, measured off the page's own computed styles —
  // tokens off the root, keyed rule slots off live elements — with WCAG
  // ratio + APCA Lc (advisory). The Dart derivation stays the ONE home
  // of solving; this is the honest gauge, never a fixer.
  function parseColor(v) {
    var s = String(v || '').trim();
    var m = /^#([0-9a-f]{6})$/i.exec(s);
    if (m) return [parseInt(m[1].slice(0, 2), 16), parseInt(m[1].slice(2, 4), 16), parseInt(m[1].slice(4, 6), 16), 1];
    m = /^rgba?\(([^)]+)\)/i.exec(s);
    if (m) {
      // Computed styles arrive space-separated ('rgb(1 2 3)'); authored
      // custom properties arrive comma-separated. Handle both, plus the
      // modern '/ alpha' suffix.
      var body = m[1], alpha = 1;
      var slash = body.indexOf('/');
      if (slash >= 0) {
        alpha = parseFloat(body.slice(slash + 1));
        body = body.slice(0, slash);
      }
      var parts = body.split(/[\s,]+/).filter(function (x) { return x.length > 0; })
        .map(function (x) { return parseFloat(x); });
      if (parts.length < 3 || parts.slice(0, 3).some(function (x) { return isNaN(x); })) return null;
      // legacy comma serialization carries alpha as the 4th component
      // (Chrome emits rgba(0, 0, 0, 0), not rgb(0 0 0 / 0)) — ignoring it
      // made every transparent ancestor parse as OPAQUE BLACK, blinding
      // effBgOf and the contrast readouts (2026-09-11)
      if (parts.length >= 4 && isFinite(parts[3])) alpha = parts[3];
      return [parts[0] | 0, parts[1] | 0, parts[2] | 0, isFinite(alpha) ? alpha : 1];
    }
    return null;
  }
  function wcagRatio(a, b) {
    function lum(c) {
      function ch(v) { v = v / 255; return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }
      return 0.2126 * ch(c[0]) + 0.7152 * ch(c[1]) + 0.0722 * ch(c[2]);
    }
    var la = lum(a), lb = lum(b), hi = Math.max(la, lb), lo = Math.min(la, lb);
    return (hi + 0.05) / (lo + 0.05);
  }
  function compositeJs(fg, bg, alpha) {
    return [0, 1, 2].map(function (i) { return fg[i] * alpha + bg[i] * (1 - alpha); });
  }
  // ── caret law v2 (2026-09-11): a currentColor caret is AS VISIBLE AS
  // the text — which means it blends INTO the text (a gray caret among
  // gray glyphs reads as a character). MDN caret-color: user agents may
  // pick a different caret color "to ensure good visibility and contrast
  // with the surrounding content" — none do, so the dial does it at
  // edit-entry: scan the text hue toward both poles and keep the first
  // candidate clearing BOTH the effective surface (WCAG 1.4.11's 3:1
  // input-indicator floor) and the text itself (1.5:1 — a cursor must
  // read as a cursor, not a character). Null when nothing clears both:
  // the caller keeps the currentColor base rule.
  function effBgOf(el) {
    var n = el, crossedFixed = false, anc = null;
    while (n && n !== document.documentElement) {
      var cs = getComputedStyle(n);
      if (cs.position === 'fixed' || cs.position === 'sticky') crossedFixed = true;
      var c = parseColor(cs.backgroundColor);
      if (c && c[3] > 0.85) { anc = c; break; }
      n = n.parentElement;
    }
    // overlays (fixed/sticky headers) paint over SIBLINGS — the ancestor
    // answer there is whatever opaque ancestor lies below (often the dark
    // body), so the PAINT STACK takes priority (energize's above-light-
    // theme header reads dark to the walk but beige to the stack)
    if (crossedFixed) {
      var b = el.getBoundingClientRect();
      if (b.bottom > 0 && b.top < window.innerHeight && b.right > 0 && b.left < window.innerWidth) {
        var sx = Math.max(1, Math.min(window.innerWidth - 2, Math.round(b.left + b.width / 2)));
        var sy = Math.max(1, Math.min(window.innerHeight - 2, Math.round(b.top + b.height / 2)));
        var stack = document.elementsFromPoint(sx, sy);
        for (var i = 0; i < stack.length; i++) {
          var s = stack[i];
          if (s === el || el.contains(s)) continue;
          var cs2 = getComputedStyle(s);
          var c2 = parseColor(cs2.backgroundColor);
          if (c2 && c2[3] > 0.85) return c2[3] < 1 ? compositeJs(c2, [255, 255, 255], c2[3]) : c2;
        }
      }
    }
    if (anc) return anc[3] < 1 ? compositeJs(anc, [255, 255, 255], anc[3]) : anc;
    return [255, 255, 255];
  }
  function pickCaretColor(el) {
    var t = parseColor(getComputedStyle(el).color) || [0, 0, 0, 1];
    var b = effBgOf(el);
    var mixTo = function (o, k) {
      return [0, 1, 2].map(function (i) { return Math.round(t[i] * k + o[i] * (1 - k)); });
    };
    var cands = [[255, 255, 255], [17, 17, 23]];
    for (var k = 0.3; k <= 0.9; k += 0.15) {
      cands.push(mixTo([255, 255, 255], k));
      cands.push(mixTo([17, 17, 23], k));
    }
    var best = null, bestScore = -1;
    for (var i = 0; i < cands.length; i++) {
      var c = cands[i];
      var rb = wcagRatio(c, b), rt = wcagRatio(c, t);
      if (rb < 3 || rt < 1.5) continue;
      var score = Math.min(rb, rt);
      if (score > bestScore) { bestScore = score; best = c; }
    }
    return best;
  }
  document._arxaCaretPick = pickCaretColor; // probes audit the same law
  var pairContract = null;
  function loadPairContract() {
    if (pairContract) return Promise.resolve(pairContract);
    if (!window.fetch) return Promise.resolve(null);
    return fetch('/assets/styles/palettes/_template.json').then(function (r) {
      return r.ok ? r.json() : null;
    }).then(function (t) {
      pairContract = t && (t.pairs || []).length ? t : null;
      return pairContract;
    }).catch(function () { return null; });
  }
  function contractHex(side, kind) {
    // Tokens off the root's computed custom properties; keyed rule slots
    // off the live element the template's selector names.
    if (/^--/.test(side)) {
      var v = getComputedStyle(document.documentElement).getPropertyValue(side);
      var c = parseColor(v);
      return c || null;
    }
    if (!pairContract || kind !== 'fg') return null;
    var rule = (pairContract.rules || []).filter(function (r) { return r.key === side; })[0];
    if (!rule) return null;
    var sel = String(rule.sel || '').replace('{id}', S.axes ? S.axes.current.palette : '');
    var el = null;
    try { el = document.querySelector(sel); } catch (e) { el = null; }
    if (!el) return null;
    var isColor = /^\s*color:/.test(String(rule.tpl || ''));
    var cs = getComputedStyle(el);
    return parseColor(isColor ? cs.color : cs.backgroundColor);
  }
  async function resolvePalette(id) {
    var res = await api('POST', '/palettes/resolve', { id: id });
    if (res && res.ok && res.palette) {
      if (Array.isArray(res.palettes)) S.axes.palettes = res.palettes;
      cacheBustPaletteSheet(S.axes.current.palette);
      renderTraySlide('theme');
      say(res.unsolved && res.unsolved.length
        ? 'Re-solved — still failing: ' + res.unsolved.join('; ')
        : 'Re-solved — every contracted pair passes');
    } else {
      say((res && res.error) || 'Could not re-solve');
    }
  }
  async function renderContrastStrip(body) {
    var t = await loadPairContract();
    if (!t || !S.axes) return;
    var rows = [];
    for (var i = 0; i < t.pairs.length; i++) {
      var pr = t.pairs[i];
      var fg = contractHex(pr.fg, 'fg'), bg = contractHex(pr.bg, 'bg');
      if (!fg || !bg) continue;
      var eff = pr.alpha != null ? compositeJs(fg, bg, pr.alpha) : fg;
      var ratio = wcagRatio(eff, bg);
      var target = pr.level === 'body' ? 4.5 : 3.0;
      rows.push(h('div', { style: 'display:flex;gap:8px;align-items:baseline;' +
        'font-size:11px;color:' + (ratio >= target ? '#8fb35a' : '#ff8f8f') + ';' }, [
        h('span', { text: (ratio >= target ? '\u2713 ' : '\u2717 ') + pr.fg + ' on ' + pr.bg }),
        h('span', { text: ratio.toFixed(2) + ':1', style: 'font-weight:600' }),
        h('span', { text: pr.level, style: 'opacity:.6' }),
      ]));
    }
    if (!rows.length) return;
    body.appendChild(h('div', { class: 'sect', text: 'Contrast — this page\u2019s palette' }));
    var box = h('div', { class: 'ctl', style: 'display:grid;gap:3px;' });
    rows.forEach(function (r) { box.appendChild(r); });
    body.appendChild(box);
  }

  // Stripe ink: white or near-black label by relative luminance, so the
  // hover hex stays readable on any pasted palette.
  function stripeInk(hex) {
    const m = /^#?([0-9a-f]{6})$/i.exec(hex || '');
    if (!m) return '#FFFCF0';
    const n = parseInt(m[1], 16);
    const lum = 0.2126 * (n >> 16) + 0.7152 * ((n >> 8) & 255) +
      0.0722 * (n & 255);
    return lum > 150 ? '#14141c' : '#FFFCF0';
  }
  // Stripe click copies the hex (Coolors law); it never applies the palette.
  function copyHex(hex) {
    const plain = (hex || '').toLowerCase();
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(plain).then(
        () => say('Copied ' + plain), () => say(plain));
    } else {
      say(plain);
    }
  }
  // ── the palette editor (Q4, palette-plane-universal) ─────────────────
  // Author-only, design-time: every card carries the affordance (the
  // DEFAULT forks into the one custom slot, everything else edits in
  // place with a stable id), and deployed static mode hides it exactly
  // like the paste row — there is no server to derive against. The
  // session lives in S.palEdit; renderThemeBody rebuilds the panel from
  // it on every re-render, so live frames and axes echoes cost nothing.
  function paletteById(id) {
    if (!S.axes) return null;
    const hit = S.axes.palettes.filter((p) => p.id === id);
    return hit.length ? hit[0] : null;
  }
  function isDefaultPalette(p) {
    // The manifest default IS the base corpus — the one entry carrying no
    // override sheet (palettes.json's own schema law; the dial config
    // never carries defaultId).
    return !!p && !p.sheet;
  }
  function openPaletteEdit(id) {
    const p = paletteById(id);
    if (!p) return;
    S.palEdit = {
      id: p.id, hexes: (p.swatch || []).slice(), name: p.name,
      error: null, busy: false,
    };
    renderTraySlide('theme');
  }
  // In-place edit of the ACTIVE palette: the dressed sheet is cached by
  // href, so repoint its link with a cache-buster — the repaint is
  // visible live (the override rules carry literal hexes, no var hop).
  function cacheBustPaletteSheet(id) {
    const link = document.querySelector('link[data-palette-sheet="' + id + '"]');
    if (!link) return;
    const href = (link.getAttribute('href') || '').split('?')[0];
    if (href) link.setAttribute('href', href + '?v=' + Date.now());
  }
  async function savePaletteEdit() {
    const ed = S.palEdit;
    if (!ed || ed.busy) return; // one flight at a time, like pinsLoading
    ed.busy = true;
    ed.error = null;
    renderTraySlide('theme');
    // A hand edit flips the palette to MANUAL (grilled Q5): the hexes
    // ship verbatim, the readout owns the visibility, Re-solve returns
    // it to AUTO.
    const body = { id: ed.id, hexes: ed.hexes.slice(), auto: false };
    const orig = paletteById(ed.id);
    const name = ed.name.trim();
    // name? rides only when it carries intent — an untouched or emptied
    // field never renames.
    if (name && orig && name !== orig.name) body.name = name;
    const res = await api('POST', '/palettes/update', body);
    ed.busy = false;
    if (res && res.palette && Array.isArray(res.palettes)) {
      // The resync law (the ingest handler's, unchanged): a fork can
      // REPLACE the previous custom server-side, so take the full list
      // the server returns — never a blind push.
      S.axes.palettes = res.palettes;
      // Close only OUR session — a newer one the author opened mid-flight
      // (another card's ✎) belongs to them, not to this response.
      if (S.palEdit === ed) S.palEdit = null;
      if (res.forked) {
        // The fork law: editing the default saved AS the custom slot.
        // Preview the new card locally — publishing stays the user's
        // explicit click (applyAxes never publishes; the pvnote marks
        // previewing, palette.js hot-dresses the newborn sheet).
        applyAxes(S.axes.current.style, S.axes.current.theme, res.palette.id);
        say('Forked to your custom palette — previewing');
      } else {
        if (S.axes.current.palette === ed.id) cacheBustPaletteSheet(ed.id);
        renderTraySlide('theme');
      }
      return;
    }
    // 409 names its conflict, 400 carries the server's own message — both
    // land inline, in the editor they belong to; the session survives.
    let msg = (res && res.error) || 'Could not save the palette';
    if (res && res.conflictsWith &&
        String(msg).indexOf(String(res.conflictsWith)) === -1) {
      msg += ' (' + res.conflictsWith + ')';
    }
    ed.error = String(msg);
    renderTraySlide('theme');
  }
  // The editor panel: one row per swatch color (native picker <-> hex
  // text, synced both ways, plus a remove ×), the add-color control, a
  // name field, save/cancel. The 3..7 law (Q5) gates remove at 3 and add
  // at 7. The default palette's panel opens with the fork-law banner.
  function renderPaletteEditor(body) {
    const ed = S.palEdit;
    const p = ed && paletteById(ed.id);
    if (!ed || !p) { S.palEdit = null; return; } // the id vanished under it
    const panel = h('div', { class: 'paledit' });
    if (isDefaultPalette(p)) {
      // The fork law, stated where the edit happens: the base corpus
      // stays hand-owned — saving the default writes the custom slot.
      panel.appendChild(h('div', {
        class: 'edbanner',
        text: 'Editing the default palette — saving stores it as your ' +
          'custom palette, replacing the current custom.',
      }));
    }
    ed.hexes.forEach((hex, i) => {
      const colorIn = h('input', {
        type: 'color', 'aria-label': 'Color ' + (i + 1),
      });
      colorIn.value = /^#[0-9a-f]{6}$/i.test(hex) ? hex : '#808080';
      const hexIn = h('input', {
        type: 'text', 'aria-label': 'Hex ' + (i + 1), spellcheck: 'false',
      });
      hexIn.value = hex;
      // Bidirectional sync, one law both ways: only a full #rrggbb may
      // enter state — the picker always emits one, typed text earns it
      // on parse, and unparseable text just marks the field (state keeps
      // the last valid hex). Sibling inputs mutate directly — a re-render
      // here would drop the picker's focus mid-drag.
      colorIn.addEventListener('input', () => {
        ed.hexes[i] = colorIn.value;
        hexIn.value = colorIn.value;
        hexIn.classList.remove('bad');
      });
      hexIn.addEventListener('input', () => {
        const m = /^#?([0-9a-f]{6})$/i.exec(hexIn.value.trim());
        if (m) {
          ed.hexes[i] = '#' + m[1].toLowerCase();
          colorIn.value = ed.hexes[i];
          hexIn.classList.remove('bad');
        } else {
          hexIn.classList.add('bad');
        }
      });
      const rem = h('button', {
        class: 'edrem', title: 'Remove this color', text: '\u00d7',
      });
      rem.disabled = ed.hexes.length <= 3; // the 3..7 law (Q5)
      rem.addEventListener('click', () => {
        if (ed.hexes.length <= 3) return;
        ed.hexes.splice(i, 1);
        renderTraySlide('theme');
      });
      panel.appendChild(h('div', { class: 'edrow' }, [colorIn, hexIn, rem]));
    });
    const add = h('button', { class: 'edadd', text: '+ Add color' });
    add.disabled = ed.hexes.length >= 7; // the 3..7 law (Q5)
    add.addEventListener('click', () => {
      if (ed.hexes.length >= 7) return;
      ed.hexes.push('#808080'); // a neutral placeholder — the picker owns taste
      renderTraySlide('theme');
    });
    panel.appendChild(add);
    const nameIn = h('input', {
      type: 'text', 'aria-label': 'Palette name', spellcheck: 'false',
    });
    nameIn.value = ed.name;
    nameIn.addEventListener('input', () => { ed.name = nameIn.value; });
    panel.appendChild(h('div', { class: 'edname' }, [nameIn]));
    if (ed.error) {
      panel.appendChild(h('div', { class: 'ederr', text: ed.error }));
    }
    const cancel = h('button', { class: 'btn ghost', text: 'Cancel' });
    cancel.addEventListener('click', () => {
      S.palEdit = null;
      renderTraySlide('theme');
    });
    const save = h('button', {
      class: 'btn', text: ed.busy ? 'Saving\u2026' : 'Save',
    });
    save.disabled = ed.busy;
    save.addEventListener('click', savePaletteEdit);
    panel.appendChild(h('div', { class: 'btnrow' }, [cancel, save]));
    body.appendChild(panel);
  }
  // Theme slide: the palette plane first (when the server declared
  // palettes), then the style/theme pickers for app designs — moved here
  // unchanged, never deleted. The publish blast radius differs per plane
  // (palette: everyone, author or guest; style/theme: author publishes,
  // a guest previews via the URL), so each carries its own note line.
  // ── the Fonts slide (grilled 2026-09-13) ───────────────────────────────
  // Independent per-role dropdowns (Q1): each role publishes alone — the
  // axes cell is an object role -> choice id. Specimens preview LIVE (Q4):
  // families load from the Google Fonts css2 CDN (CORS-open, display=swap
  // — the same law the site itself loads by) in batched preview links.
  // The searchable catalog (Q3) is author + design-time only: ingestion
  // writes the artifact tree; guests and the deployed dial pick from the
  // declared choices.
  let fontPreviewLinks = {};
  function ensureFontPreview(segments) {
    // One css2 request carries many families; browsers fetch only the
    // faces they render, so batching by 8 keeps requests flat while every
    // specimen gets its real face.
    const pending = segments.filter((s) => s && !fontPreviewLinks[s]);
    if (!pending.length) return;
    for (let i = 0; i < pending.length; i += 8) {
      const batch = pending.slice(i, i + 8);
      batch.forEach((s) => { fontPreviewLinks[s] = true; });
      const link = h('link', {
        rel: 'stylesheet', 'data-font-preview': '1',
        href: 'https://fonts.googleapis.com/css2?' + batch.join('&') + '&display=swap',
      });
      document.head.appendChild(link);
    }
  }
  // The css2 segment law, mirrored from design_fonts.dart (parity: the
  // dropdown's search results build the same segment the server would).
  function css2SegmentForEntry(e) {
    const fam = e.family.replace(/ /g, '+');
    const v = e.variableWght;
    const wght = () => {
      if (v && v.length === 2) return v[0] + '..' + v[1];
      const ws = (e.weights && e.weights.length ? e.weights : [400]).slice();
      return Array.from(new Set(ws)).sort((a, b) => a - b).join(';');
    };
    const w = wght();
    if (!e.italic) {
      return (!v && (!e.weights || e.weights.length <= 1))
        ? 'family=' + fam : 'family=' + fam + ':wght@' + w;
    }
    return 'family=' + fam + ':ital,wght@0,' + w + ';1,' + w;
  }
  function renderFontsBody(body) {
    if (!S.axes || !S.axes.fonts || !S.axes.fonts.roles ||
        !S.axes.fonts.roles.length) {
      body.appendChild(h('div', {
        class: 'ctl', style: 'font-size:12px;color:#9aa0ab',
        text: 'This design declares no font plane.',
      }));
      return;
    }
    S.axes.fonts.roles.forEach((role) => renderFontRole(body, role));
  }
  function renderFontRole(body, role) {
    body.appendChild(h('div', { class: 'sect', text: role.name || role.id }));
    const current = S.axes.current.font || {};
    const def = (S.axes.fonts.default || {})[role.id];
    const activeId = current[role.id] || def ||
      (role.choices[0] && role.choices[0].id);
    ensureFontPreview(role.choices.filter((c) => c.css2).map((c) => c.css2));
    const grid = h('div', { class: 'palgrid' });
    role.choices.slice(0, 8).forEach((c) => {
      const on = c.id === activeId;
      const card = h('button', {
        class: 'fontcard' + (on ? ' on' : ''),
        title: 'Apply ' + c.family + ' to ' + (role.name || role.id),
      });
      const spec = role.id === 'body'
        ? 'Pack my box with five dozen liquor jugs.'
        : 'Arxa — quiet, deliberate craft.';
      card.appendChild(h('span', {
        class: 'fontspec', style: 'font-family:' + c.stack, text: spec,
      }));
      const meta = [h('span', { class: 'palname', text: c.family })];
      if (c.category) meta.push(h('span', { class: 'fontcat', text: c.category }));
      if (c.seeded !== true) {
        meta.push(h('span', { class: 'palchip cchip', text: 'Custom' }));
      }
      if (on) meta.push(h('span', { class: 'palchip onchip', text: 'Active' }));
      card.appendChild(h('span', { class: 'palmeta' }, meta));
      card.addEventListener('click', () => {
        const pick = {}; pick[role.id] = c.id;
        flipAxes({ font: pick });
      });
      // Delete (author, design-time, ingested-only — the palette × law).
      if (S.mode === 'author' && !S.static && c.seeded !== true) {
        const del = h('span', {
          class: 'paldel', title: 'Delete this choice', text: '×',
        });
        del.addEventListener('click', async (e) => {
          e.stopPropagation(); // the × must never fire the card's pick
          const res = await api('POST', '/fonts/delete', { role: role.id, id: c.id });
          if (!(res && res.ok)) {
            say((res && res.error) || 'Could not delete the choice');
            return;
          }
          // The 'fonts' SSE frame rebuilds the slide; if the deleted
          // choice was active, fall back to the role's default.
          if (activeId === c.id) {
            const back = {}; back[role.id] = def || '';
            flipAxes({ font: back });
          }
        });
        card.appendChild(del);
      }
      grid.appendChild(card);
    });
    body.appendChild(grid);
    // The catalog dropdown (Q3 + Q4): author-only, design-time only.
    if (S.mode === 'author' && !S.static) {
      const input = h('input', {
        type: 'text', class: 'fontsearch',
        placeholder: 'Search Google Fonts for ' + (role.name || role.id) + '…',
      });
      const rows = h('div', { class: 'fontrows' });
      let timer = null;
      let seq = 0;
      input.addEventListener('input', () => {
        clearTimeout(timer);
        timer = setTimeout(async () => {
          const q = input.value.trim();
          const mySeq = ++seq;
          if (!q) { rows.textContent = ''; return; }
          const res = await api('GET', '/font-catalog?q=' + encodeURIComponent(q));
          if (mySeq !== seq) return; // a newer keystroke owns the box
          rows.textContent = '';
          if (!res || !res.ok || !res.families || !res.families.length) {
            rows.appendChild(h('div', {
              class: 'ctl', style: 'font-size:12px;color:#9aa0ab',
              text: res && res.error ? res.error : 'No families matched.',
            }));
            return;
          }
          ensureFontPreview(res.families.map(css2SegmentForEntry));
          res.families.slice(0, 20).forEach((e) => {
            const stack = "'" + e.family.replace(/'/g, "\\'") + "', Georgia, serif";
            const row = h('button', { class: 'fontrow', title: 'Pick ' + e.family });
            row.appendChild(h('span', {
              class: 'rspec', style: 'font-family:' + stack,
              text: e.family + ' — The quick brown fox jumps over 1,284 lazy dogs.',
            }));
            row.appendChild(h('span', { class: 'fontcat', text: e.category }));
            row.addEventListener('click', async () => {
              const ing = await api('POST', '/fonts', { role: role.id, family: e.family });
              if (ing && ing.ok && ing.choice) {
                if (ing.fonts) S.axes.fonts = ing.fonts; // the SSE frame lands too
                renderTraySlide('fonts');
                const pick = {}; pick[role.id] = ing.choice.id;
                flipAxes({ font: pick });
              } else {
                say((ing && ing.error) || 'That family did not ingest');
              }
            });
            rows.appendChild(row);
          });
        }, 250);
      });
      body.appendChild(h('div', { class: 'facet' }, [input]));
      body.appendChild(rows);
    }
  }
  function renderThemeBody(body) {
    if (!S.axes) {
      body.appendChild(h('div', {
        class: 'ctl', style: 'font-size:12px;color:#9aa0ab',
        text: 'This design declares no theme axes.',
      }));
      return;
    }
    let paletteNoted = false;
    if (S.axes.palettes.length) {
      body.appendChild(h('div', { class: 'sect', text: 'Palette' }));
      // The grid law (operator, 2026-09-02): at most SIX cards — the five
      // seeded picks first (manifest order), the one custom slot last.
      const seeded = S.axes.palettes.filter((p) => p.seeded === true);
      const custom = S.axes.palettes.filter((p) => p.seeded !== true);
      const grid = h('div', { class: 'palgrid' });
      seeded.concat(custom).slice(0, 6).forEach((p) => {
        const card = h('button', {
          class: 'palcard' + (S.axes.current.palette === p.id ? ' on' : ''),
          title: 'Apply ' + p.name,
        });
        const strip = h('span', { class: 'palstrip' });
        (p.swatch || []).forEach((hex) => {
          const stripe = h('span', {
            class: 'palstripe', style: 'background:' + hex,
          }, [h('i', { text: hex, style: 'color:' + stripeInk(hex) })]);
          stripe.addEventListener('click', (e) => {
            e.stopPropagation(); // a stripe copies its hex, never applies
            copyHex(hex);
          });
          strip.appendChild(stripe);
        });
        card.appendChild(strip);
        const chips = [];
        if (p.seeded !== true) {
          chips.push(h('span', { class: 'palchip cchip', text: 'Custom' }));
        }
        // The contrast law's editor face (2026-09-11): every card wears
        // its solve state — AUTO (the engine guarantees the pairs) or
        // MANUAL (the author's hexes ship verbatim; the gate will say
        // so). One click re-solves either way.
        chips.push(h('span', {
          class: 'palchip',
          style: 'background:' + (p.auto === false ? 'rgba(255,143,143,.2)' : 'rgba(143,179,90,.2)') +
            ';color:' + (p.auto === false ? '#ff8f8f' : '#8fb35a'),
          text: p.auto === false ? 'MANUAL' : 'AUTO',
          title: p.auto === false
            ? 'Hand-edited — ships verbatim; contrast not guaranteed'
            : 'Contrast-solved — WCAG 2.2 AA by construction',
        }));
        chips.push(h('span', { class: 'palchip onchip', text: 'Active' }));
        card.appendChild(h('span', { class: 'palmeta' },
          [h('span', { class: 'palname', text: p.name })].concat(chips)));
        card.addEventListener('click', () => flipAxes({ palette: p.id }));
        // palette CRUD is design-time — the × never renders statically.
        if (S.mode === 'author' && p.seeded !== true && !S.static) {
          const del = h('span', {
            class: 'paldel', title: 'Delete this palette', text: '×',
          });
          del.addEventListener('click', (e) => {
            e.stopPropagation(); // the × must never fire the card's pick
            deletePalette(p.id);
          });
          card.appendChild(del);
        }
        // The edit affordance (Q4): author-only, hidden in static EXACTLY
        // like the paste row. EVERY card carries it — the default forks,
        // the rest edit in place. Like the ×, it never fires the pick.
        if (S.mode === 'author' && !S.static) {
          const edbtn = h('span', {
            class: 'paledbtn', title: 'Edit this palette', text: '\u270e',
          });
          edbtn.addEventListener('click', (e) => {
            e.stopPropagation();
            openPaletteEdit(p.id);
          });
          card.appendChild(edbtn);
          // Re-solve (grilled Q5): back through the contrast engine, back
          // to AUTO. Sits with the ✎ and never fires the pick.
          const rsbtn = h('span', {
            class: 'paledbtn', title: 'Re-solve contrast (back to AUTO)',
            text: '\u26a1', style: 'left:-26px',
          });
          rsbtn.addEventListener('click', (e) => {
            e.stopPropagation();
            resolvePalette(p.id);
          });
          card.appendChild(rsbtn);
        }
        grid.appendChild(card);
      });
      body.appendChild(grid);
      // The editor panel — the same gate as the affordance and the paste
      // row; it renders directly under the grid it edits.
      if (S.mode === 'author' && !S.static && S.palEdit) {
        renderPaletteEditor(body);
      }
      // The contrast strip: the applied palette's contracted pairs, live
      // off the rendered page. The gauge for every AUTO/MANUAL decision.
      renderContrastStrip(body);
      // The Coolors import: author-only, and never in deployed static mode
      // (cfg.static — no live store to take the paste).
      if (S.mode === 'author' && !cfg.static) {
        const input = h('input', {
          type: 'text', placeholder: 'Paste a Coolors link…',
        });
        const add = h('button', { class: 'btn', text: 'Add' });
        const submit = async () => {
          const url = input.value.trim();
          if (!/coolors\.co\//.test(url)) { say('That link did not parse'); return; }
          add.disabled = true;
          const res = await api('POST', '/palettes', { url: url });
          add.disabled = false;
          if (res && res.ok && res.palette) {
            // The one-custom-slot law can REPLACE the previous custom
            // server-side — resync from the full list the server returns,
            // never a blind push (a stale card renders dead: its sheet and
            // tokens block were stripped by the sweep).
            S.axes.palettes = Array.isArray(res.palettes) && res.palettes.length
              ? res.palettes : S.axes.palettes.concat([res.palette]);
            renderTraySlide('theme');
            flipAxes({ palette: res.palette.id });
          } else {
            say((res && res.error) || 'That link did not parse');
          }
        };
        add.addEventListener('click', submit);
        input.addEventListener('keydown', (e) => { if (e.key === 'Enter') submit(); });
        body.appendChild(h('div', { class: 'facet' }, [input]));
        body.appendChild(h('div', { class: 'btnrow' }, [add]));
      }
      // A palette pick publishes for everyone, author OR guest.
      body.appendChild(h('div', {
        class: 'ctl', style: 'font-size:11px;color:#9aa0ab',
        text: S.mode === 'author'
          ? 'Your pick publishes for everyone viewing this design.'
          : 'Your pick publishes for everyone on this design.',
      }));
      paletteNoted = true;
    }
    if (S.axes.styles.length) {
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
    }
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
    if ((S.axes.styles.length || S.axes.themes.length) &&
        // The palette note above already says the author's line
        // word-for-word — the same fact never appears twice on one slide.
        !(paletteNoted && S.mode === 'author')) {
      body.appendChild(h('div', {
        class: 'ctl', style: 'font-size:11px;color:#9aa0ab',
        text: S.mode === 'author'
          ? 'Your pick publishes for everyone viewing this design.'
          : 'Preview applies to your view only — the URL carries it.',
      }));
    }
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
        applyAxes(S.axes.published.style, S.axes.published.theme,
          S.axes.published.palette);
      });
      note.appendChild(reset);
      body.appendChild(note);
    }
  }
  // Incoming slide: the placeholder for what ships next — one centered
  // eyebrow over one muted line, nothing else.
  function renderIncomingBody(body) {
    body.appendChild(h('div', { class: 'incoming' }, [
      h('div', { class: 'eye', text: 'INCOMING FEATURE' }),
      h('div', { class: 'sub', text: 'Work in progress' }),
    ]));
  }

  // Access slide (trim v2): the client-access panel lives HERE now —
  // mint personal links, roster, revoke. Local author only: the slide
  // never enters traySlideList() for guests or the deployed static dial,
  // and the renderer re-checks before touching the API (defense in
  // depth — the static store would refuse /guests anyway).
  function renderAccessBody(body) {
    if (S.mode !== 'author' || S.static) return;
    const panel = ensureGuestShareUI(body, false);
    loadGuests(true).then(() => renderGuestRoster(panel));
  }

  // ── the tray (Studio): glass bottom sheet, snap carousel ─────────────
  // TRIM v2 (grilled 2026-09-10): Theme for EVERYONE, plus Access — the
  // client-link mint/roster — for the LOCAL author only. Guests and the
  // deployed static dial get a one-slide tray (minting is design-time:
  // the static store refuses /guests, and clients never see the surface).
  // The retired six (Edit / Comments / Settings / Tweak / Style / Ship)
  // and the former 'Incoming' placeholder lost only their tray UI; their
  // client functions below stay callable for the ongoing dial rewrite.
  function traySlideList() {
    // The Fonts slide (grilled 2026-09-13): second, right after Theme —
    // for everyone when the artifact declares the plane. Access stays
    // author-local (minting is design-time).
    const hasFonts = !!(S.axes && S.axes.fonts &&
      S.axes.fonts.roles && S.axes.fonts.roles.length);
    if (S.mode === 'author' && !S.static) {
      return hasFonts
        ? [['theme', 'Theme'], ['fonts', 'Fonts'], ['access', 'Access']]
        : [['theme', 'Theme'], ['access', 'Access']];
    }
    return hasFonts ? [['theme', 'Theme'], ['fonts', 'Fonts']] : [['theme', 'Theme']];
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
    // A one-slide tray (guests, deployed) shows no pagination at all.
    dots.style.display = list.length < 2 ? 'none' : '';
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
    // Neither remaining slide carries a bar action — the CTA stays hidden.
    // (Commit / Share / Deploy retired with their slides; the 2026-09-11
    // edit redesign deleted requestCommit outright — the eject bake owns
    // source writes now. ensureGuestShareUI and shipVerb stay callable.)
    ctaBtn.className = 'off';
    ctaBtn.disabled = false;
    ctaBtn.title = '';
    ctaBtn.textContent = '';
  }
  track.addEventListener('scroll', () => {
    if (!S.tray) return;
    S.tray = currentSlideId();
    syncTrayChrome();
  }, { passive: true });

  function renderTraySlide(id) {
    const body = slideBodies[id];
    if (!body) return;
    body.textContent = '';
    if (id === 'theme') return renderThemeBody(body);
    if (id === 'fonts') return renderFontsBody(body);
    if (id === 'access') return renderAccessBody(body);
    if (id === 'incoming') return renderIncomingBody(body);
  }
  function openTray(id) {
    buildTraySlides();
    const list = traySlideList();
    const want = list.find((s) => s[0] === id);
    S.tray = want ? want[0] : list[0][0];
    tray.classList.add('open');
    updateEditBar(); // the bar yields the corner to the sheet
    // Tray swap law: park the dial outright; the timer suspends.
    dock.classList.remove('open');
    S.open = false;
    dialPark();
    list.forEach(([sid]) => renderTraySlide(sid));
    const idx = list.findIndex((s) => s[0] === S.tray);
    requestAnimationFrame(() => {
      track.scrollLeft = idx * track.clientWidth;
      syncTrayChrome();
    });
  }
  function closeTray() {
    S.tray = null;
    tray.classList.remove('open');
    updateEditBar(); // the bar returns with the dial
    // SHEET-CHILDREN LAW (operator, 2026-08-26): whatever the sheet held
    // open closes WITH it — the selection chip (plus its selection:
    // outline, and the Edit Mode arming its outline rows imply),
    // the pin thread popover, and the comment composer. The island returns
    // to its resting state: dial in, nothing else floating.
    if (S.arming) disarm();
    if (S.design) designOff(); // closes the chip, clears the selection
    else if (S.selected) clearSelOutline();
    if (S.activePin) closeThread();
    composer.classList.remove('open');
    dialUnpark(); // spring back in + re-arm the 30s tuck-away fresh
  }

  // ── retired slide bodies (kept callable for the ongoing dial rewrite) ──
  // The locked trim above ended the tray's Edit / Comments / Settings /
  // Tweak / Ship slides, but their renderers and API clients below are
  // NOT deleted — the rewrite re-homes them, and nothing here may vanish
  // under it. Unreferenced by the tray, referenced by the future.
  // (The Edit slide's renderer DIED with the 2026-09-11 redesign — the
  // outline's select-and-card law and the draft ledger have no successor
  // UI to re-home; editing is on-canvas now.)

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
      const title = 'arxa(dial): live edit batch';
      const bodyTxt = 'Committed from the Arxa Dial (Ship slide). ' +
        Object.keys(S.overlay.patches).length + ' element patch keys live in the overlay; ' +
        'the next eject bakes them into source.';
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
    if (id === 'studio') return openTray(S.tray || 'theme');
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
    // Cmd/Ctrl+Z undo, Shift+Cmd+Z / Cmd+Y redo — the session-local stack
    // (decision 3, 2026-09-11). Runs AFTER the inlineEditing branch, and
    // yields to native undo when focus sits in any input/textarea/
    // contenteditable (dial fields live in the shadow root — composedPath
    // sees through the retargeting).
    const mod = e.metaKey || e.ctrlKey;
    const k = (e.key || '').toLowerCase();
    if (mod && !e.altKey && (k === 'z' || k === 'y')) {
      if (S.mode !== 'author') return;
      const t = e.composedPath ? e.composedPath()[0] : e.target;
      const tag = t && t.tagName ? t.tagName.toLowerCase() : '';
      if (tag === 'input' || tag === 'textarea' || (t && t.isContentEditable)) return;
      e.preventDefault();
      if (k === 'y' || e.shiftKey) doRedo();
      else doUndo();
      return;
    }
    if (e.key === 'Escape') {
      if (S.arming) disarm();
      if (S.chipOpen) { closePanel(); clearSelOutline(); return; }
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
    if (S.static) return subscribeRealtime();
    if (liveEs || !eventsAllowed || document.hidden) return;
    try {
      const es = new EventSource(apiUrl('/events'));
      liveEs = es;
    // A RECONNECT is the certain sign frames were missed (socket-pool
    // starvation, a server restart, laptop sleep) — resync instead of
    // trusting the stream. The first open is boot truth: loadOverlay already
    // read it, and the rev guard makes a no-divergence resync a
    // no-op, so a flapping connection never reload-loops.
    let esOpened = false;
    es.addEventListener('open', () => {
      // A reconnect also refetches pins: the server replays what it logged
      // (Last-Event-ID), but a restart's log is empty — without this the
      // board stays stale until someone else acts. loadPins is a read;
      // reads never broadcast, so this cannot loop.
      if (esOpened) { syncOverlay(); loadPins(); }
      esOpened = true;
    });
    es.addEventListener('dial', (ev) => {
      let d = null;
      try { d = JSON.parse(ev.data); } catch (_) {}
      if (d) onLiveFrame(d);
    });
    } catch (_) {}
  }
  // ONE frame law for SSE and Realtime alike: the design-time event stream
  // and the static driver's Supabase channels feed THIS dispatcher — a
  // 'pins' frame refetches the board, an 'axes' frame IS the published
  // truth, an 'overlay' frame IS the live overlay doc (rev-guarded: our
  // own echo never re-applies).
  function onLiveFrame(d) {
      if (!d || d.kind === 'pins') return loadPins();
      // The live overlay changed (author's own echo lands here too — the
      // rev guard inside overlayFrame is the suppressor; the own-save
      // window only defers the rare external frame that arrives while our
      // save is still settling).
      if (d.kind === 'overlay') {
        const since = Date.now() - S.ownSave;
        const doc = (d.data && typeof d.data.rev === 'number')
          ? d.data : null;
        if (doc) {
          if (since > 1500) overlayFrame(doc);
          else {
            clearTimeout(swallowTimer);
            swallowTimer = setTimeout(() => overlayFrame(doc), 1600 - since);
          }
        }
      }
      // The published axes changed (our own POST echoes here too — applying
      // the same pick is idempotent and settles the URL to published).
      // Palette mirrors the style/theme law exactly: the frame is the
      // truth, and the live page re-applies the whole triple at once.
      if (d.kind === 'axes' && d.data && S.axes) {
        S.axes.published = {
          style: d.data.style,
          theme: d.data.theme,
          palette: d.data.palette || '',
          font: d.data.font || {},
        };
        applyAxes(d.data.style, d.data.theme, d.data.palette || '', d.data.font || {});
      }
      // The font plane's LIST changed (ingestion/deletion): the Fonts
      // slide rebuilds its cards + dropdowns from the frame.
      if (d.kind === 'fonts' && d.data && S.axes) {
        S.axes.fonts = d.data;
        if (S.tray === 'fonts') renderTraySlide('fonts');
      }
      // The identity plane: someone minted or revoked — an author holding
      // a roster panel (retired Comments slide; kept callable below)
      // refetches it (read; reads never broadcast, so no loop).
      if (d.kind === 'guests' && S.mode === 'author' && slideBodies.comments) {
        loadGuests(true).then(() => {
          const panel = slideBodies.comments.querySelector('.gstpanel');
          if (panel) renderGuestRoster(panel);
        });
      }
      // ('commit' and 'compose-ack' frames died with the arxa-studio
      // handoff — the 2026-09-11 redesign deleted the Arxa tab; the eject
      // bake replaced the commit loop.)
    }

  // ── realtime (static): Supabase channels feed the SAME frame law ──────
  // One channel per dial table, filtered to this design: pins / replies
  // refetch the board; an axes row change carries the row as the frame's
  // data; an overlays row change carries the live overlay doc (UPDATE =
  // the new patches+rev, DELETE = revert-to-published). The drawings
  // channel retired with the 2026-09-11 edit redesign. The visibility
  // law's static twin: hidden tabs hold no channel; pagehide
  // unsubscribes. A channel failure arms a 30s visibility-gated pins
  // poll — the board degrades to eventually-consistent instead of dying.
  let rtChannels = [];
  let rtPoll = null;
  function subscribeRealtime() {
    if (rtChannels.length || !eventsAllowed || document.hidden) return;
    let c;
    try { c = sbClient(); } catch (_) { armRtFallback(); return; }
    const mk = (table, fn) => c.channel('dial-' + table)
      .on('postgres_changes', {
        event: '*', schema: 'public', table: table,
        filter: 'design_id=eq.' + S.static.designId,
      }, fn)
      .subscribe((status) => {
        if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') armRtFallback();
      });
    rtChannels = [
      mk('arxa_dial_pins', () => onLiveFrame({ kind: 'pins' })),
      mk('arxa_dial_replies', () => onLiveFrame({ kind: 'pins' })),
      mk('arxa_dial_axes', (payload) =>
        onLiveFrame({ kind: 'axes', data: payload && payload.new })),
      mk('arxa_dial_overlays', (payload) => onLiveFrame({
        kind: 'overlay',
        data: payload && payload.new
          ? { patches: payload.new.patches || {}, rev: payload.new.rev || 0 }
          : { patches: {}, rev: 0 }, // DELETE — revert-to-published
      })),
    ];
  }
  function unsubscribeRealtime() {
    if (!rtChannels.length) return;
    let c = null;
    try { c = sbClient(); } catch (_) {}
    rtChannels.forEach((ch) => {
      try { if (c) c.removeChannel(ch); else ch.unsubscribe(); } catch (_) {}
    });
    rtChannels = [];
  }
  function armRtFallback() {
    if (rtPoll) return;
    rtPoll = setInterval(() => { if (!document.hidden) loadPins(); }, 30000);
  }
  document.addEventListener('pagehide', () => {
    unsubscribeRealtime();
    if (rtPoll) { clearInterval(rtPoll); rtPoll = null; }
  });
  // The visibility half of the socket-pool law: release this tab's socket
  // the moment it hides, take it back (and catch up) the moment it shows.
  document.addEventListener('visibilitychange', () => {
    if (!eventsAllowed) return;
    if (document.hidden) {
      if (liveEs) { liveEs.close(); liveEs = null; }
      unsubscribeRealtime(); // static twin of the socket-pool law
    } else {
      syncOverlay(); // missed overlay frames never replay — read the truth
      loadPins();
      if (S.static) staticSyncAxes(); // missed axes frames never replay — read the truth
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
      console.info('[Arxa Dial] unavailable in this context — view-only mirror');
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
    return !!(S.open || S.design || S.arming || S.chipOpen || S.inlineEditing != null);
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
    restoreUndoState(); // the converge reload must not erase the session stack
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
  // Deployed static mode (VERIFY ADDENDUM 17): the worker gated injection
  // itself — no credential, no dial — so the capability probes stay out
  // (there is no /__dial/* to probe). A guest token still has to RESOLVE:
  // resolve_guest_link validates it against the live-link hashes and
  // answers the registered identity; a dead link boots 'invalid', the
  // same surface a dead link boots locally, having made ZERO writes. The
  // author link was hash-verified worker-side — it boots straight in.
  if (S.static) {
    if (S.mode === 'guest') {
      staticResolveGuest().then(async (g) => {
        if (!g) {
          S.mode = 'invalid';
          mountHost();
          applyTweakPrefs();
          say('This share link is expired or invalid');
          return;
        }
        S.guest = { id: g.guest_id, email: g.email, name: g.name };
        S.name = S.guest.name || (S.guest.email.split('@')[0] || 'guest');
        // Guest ordering: pins first (openPinnedOnArrival reads them
        // inside finishBoot), then the overlay read + apply (decision 2 —
        // clients see the author's live edits), then mount, then channels.
        const r = await api('GET', '/pins');
        if (r && r.pins) S.pins = r.pins;
        await loadOverlay();
        finishBoot();
        renderPins();
        updateBadge();
        eventsAllowed = true;
        subscribeEvents();
      });
      return;
    }
    // Static author: the Edit verb is live here now (decision 4) — read
    // pins + overlay, then subscribe to the channels.
    finishBoot();
    api('GET', '/pins').then(async (r) => {
      if (r && r.pins) { S.pins = r.pins; renderPins(); updateBadge(); }
      await loadOverlay();
      eventsAllowed = true;
      subscribeEvents();
    });
    return;
  }
  if (S.mode === 'guest') {
    probeCapable('/pins').then(async (r) => {
      if (!(r && r.pins)) { mirrorNote(); return; }
      S.pins = r.pins;
      await loadOverlay();
      finishBoot();
      renderPins();
      updateBadge();
      eventsAllowed = true;
      subscribeEvents();
    });
    return;
  }
  loadOverlay().then((ok) => {
    if (!ok) { mirrorNote(); return; }
    finishBoot();
    api('GET', '/pins').then((r) => {
      if (r && r.pins) { S.pins = r.pins; renderPins(); updateBadge(); }
      eventsAllowed = true;
      subscribeEvents();
    });
  });
})();
