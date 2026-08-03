# Viewer topbar theme cluster + canvas bg fix

Requirement: in the design shell's main panel TOP section, remove the
undo/redo icon pair (a duplicate — the bottom mini-panel controller has the
history buttons) and replace it with a canvas APPEARANCE cluster: app-theme
control (auto / light / dark) + the canvas bg swatches (moved up from the
bottom bar). Auto follows the studio theme; light/dark restyle ONLY the
designed app's stubs in the canvas. Also: fix the dead canvas bg swatches.

## Decisions (user-confirmed)

- Cluster lives in the viewer panel's top section (not the app chrome).
- Theme is server-echoed viewer state (like bg/inspect/vp): the control GETs
  `/design/viewer?theme=…`, stubs get `&theme=` on their iframe srcs, auto
  omits the param. Zero custom JS.
- Undo/redo: UI removal only in the topbar; routes and the bottom pair stay.

## Root causes found (systematic-debugging)

1. **Dead bg swatches (light theme)**: state machinery worked end-to-end —
   clicking warm really produced `.panel-viewer.dv-bg-warm` — but the panel
   also carries `.panel`, whose surface background ties `.dv-bg-*` at
   (0,1,0) specificity and loads later, winning the cascade. The dark-theme
   variants outranked `.panel`, which is why only light mode looked dead.
   Fix: compound selectors `.panel-viewer.dv-bg-*` (app.css).
2. **Theme param never reached the session**: the `/design/viewer` handler
   whitelists query keys explicitly (its own comment: "a new viewer param is
   invisible until it is named here") — `theme` had to be named in
   prototype_viewmodel.js. Caught by the first verification run.

## Mechanism

- design_facade: `theme` state key (validated light/dark, null = auto,
  elided from URLs), `theme` in every withParams echo, `themes` + `bgs`
  control arrays at the `v` root, `&theme=` on all three stub src builders
  (tiles are template-built; filmstrip gets it via the viewer arg).
- Stub chain: loop_viewmodel passes `theme` query → build_facade.screenStub
  resolves override-else-`prefs.theme` and exposes raw `themeOverride`,
  which pqs re-propagates so intra-stub nav keeps the override without ever
  pinning auto.
- Templates: topbar renders the cluster from `v` (chrome shrinks to
  `{ title, state }`; `actions` plumbing deleted with its only use);
  mini_panel drops the swatch group.
- i18n: `viewer.theme.*` + `viewer.themeGroup` added, orphaned
  `viewer.undo`/`viewer.redo` removed (en, pl, qps-ploc).

## Verification

Disposable server (4991, portalo, read-only). One async lens expect walks:
topbar has no undo pair + 3 theme chips (auto active) + 3 swatches; bottom
bar keeps history, loses swatches; warm click paints rgb(244,234,216) on the
panel (pre-fix measurement was the failing baseline); dark click themes every
tile src, thumb src and stub document while the studio chrome stays light and
the warm bg survives; auto un-pins the param and stubs return to the studio
theme; strip-sync still marks. Exit 0. The pre-fix runs failing at steps 3
and 4 are the falsifiability evidence for both fixes.
