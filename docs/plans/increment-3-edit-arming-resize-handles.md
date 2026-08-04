# Increment 3 — edit arming + resize handles (Figma-style sizing modes)

Status: **backend + arming shipped; sizing modes BLOCKED on a CSS delivery gap.**

## What shipped in this increment

| Piece | File | Note |
|---|---|---|
| Per-attribute value table | `services/facades/design_facade.js` | `W_ATTR_VALUES` replaces the single k-scale check — one enforcement point, modes validate against modes |
| `data-resize-x/y` vocabulary | same | `hug\|fill\|fixed`, the contract's OWN values |
| `resizeX`/`resizeY` chip state | `widgetEditorContext` | same toggle-off rule as the k chips |
| Edit arming toggle | `armWidgetEdit` + `/design/widget/arm` | session state; disarm also drops selection |
| Arm chip | `design_viewer.html` topbar | real `<button aria-pressed>` — it toggles a mode, it does not navigate |
| Armed tile click → select | `canvas.js` `wireFrames` | armed-ness read at CLICK time, never captured at wire time |

## The blocker (primary-source, verified)

**No stylesheet loaded by a canvas tile implements the Auto Layout contract.**
The sizing-mode attributes are written to source correctly and then render nothing.

Evidence chain:

1. The contract rules exist in exactly one file —
   `skills/appbox-designer/starter-partials/widgets/widgets.css`:
   ```
   79 [data-resize-x="hug"]   { width: fit-content; }
   80 [data-resize-x="fill"]  { flex-grow: 1; min-width: 0; }
   81 [data-resize-x="fixed"] { flex-shrink: 0; }
   82 [data-resize-y="hug"]   { height: fit-content; }
   83 [data-resize-y="fill"]  { align-self: stretch; }
   84 [data-resize-y="fixed"] { flex-shrink: 0; }
   ```
   That file is a **starter partial**: it is installed into a scaffolded
   project as `assets/css/widgets.css`.

   An **uncapped** search (`grep -rn 'data-resize-x' --include=*.css
   --include=*.html`) returns hits in that file and nowhere else — no second
   copy, no inline `<style>` block.

2. The tile document is `ui/views/main_shell/build/loop/screen_stub_view.html`.
   An **uncapped** `grep -n 'stylesheet\|\.css\|<style'` on it returns exactly
   four links — `app.css`, `theme.css`, `appshell.css`, `media.css`. **It never
   links `widgets.css`.**

3. The studio's own `designs/appbox-studio/assets/css/widgets.css` is a
   **name collision, not the same file** — 375 lines of studio chrome
   (`.chip`, `.prov-chip`). It contains zero occurrences of `data-pad`,
   `data-gap`, `data-resize` or `data-layout`. Verified across all five
   stylesheets: every count is 0.

4. The project overlay in `appboxd/lib/design_server/worker.dart` (L187–210)
   serves only `design/surfaces/**.html`, `design/l10n/app_*.arb` and
   `**.json`. **It serves no CSS at all**, so a bound project's own
   `assets/css/widgets.css` never reaches the tile; `/assets/css/*` always
   resolves to the studio artifact.

**This predates Increment 3.** Increment 2's `data-pad`/`data-gap` chips have
the same defect: they write correct source and produce no visible change.
The write-through path was verified by re-reading source, never by looking at
a tile, which is why it went unnoticed.

## Why I did not just fix it

The three available fixes all cost something the project's one-vocabulary
discipline says is not mine to spend unilaterally:

- **Copy the rules into the studio's `assets/css/widgets.css`** — creates a
  SECOND physical copy of the layout contract. The vocabulary then has two
  homes that can drift, which is the exact failure the discipline exists to
  prevent.
- **Serve project CSS from the worker overlay** (Dart, L187–210) — probably
  the correct long-term answer, since it makes the tile show the project's
  real styling rather than the studio's. It is a change to the daemon, out of
  this increment's scope, and untestable without a bound project.
- **Extract the contract to one file served at a stable URL** and have the
  starter partial reference it — keeps one home, but changes what every
  scaffolded project links, i.e. a scaffold-contract change.

There is a fourth option, and it is probably the cheapest correct one:

- **Serve the contract through the existing `/assets/vendor/` channel.**
  `design_server.dart:478` maps `/assets/vendor/<rel>` straight onto
  `skills/appbox-designer/runtime/vendor/`, and that channel already carries
  CSS as well as JS (`design_tools.dart:1191` matches `\.(?:js|css)`;
  `gate_design_widgets.dart:680` allowlists the prefix). So the layout
  contract could be ONE physical file served to the stub, with no second copy
  and no daemon change — only a `<link>` in `screen_stub_view.html`. The open
  question is whether the contract should then move out of, or be shared
  with, the starter partial that projects receive; that is the part worth
  deciding deliberately.

Recommendation: option 4 for delivery, keeping a single physical home for the
contract; the worker-overlay fix (option 2) remains the right long-term answer
for showing a project's own styling in tiles, but is a larger change.

## Verification

The contract validator was exercised directly against the facade (13 cases,
all passing). The cases that matter are the cross-vocabulary ones, which the
old single-table check would have got wrong:

| case | expect | result |
|---|---|---|
| `data-pad=12`, `data-gap=24`, `data-pad=""` | accept | accept |
| `data-pad=10`, `data-gap=7` | **400** | 400 |
| `data-resize-x` = `hug`/`fill`/`fixed` | accept | accept |
| `data-resize-x=stretch` | **400** | 400 |
| `data-resize-y=12` (k value on a mode attr) | **400** | 400 |
| `data-pad=fill` (mode value on a k attr) | **400** | 400 |
| `data-bogus=12` | **400** | 400 |

All five changed JS files pass `node --check`; all three ARB files parse and
carry the eight new keys (`en`, `pl`, `qps-ploc`).

The `bodyAttrs` expression was rendered through the real Nunjucks build
(`worker_assets/nunjucks.min.js`) and the real `_panel.html` `body()` macro
shape, in all four states — the `| safe` emission means the JSON survives raw
inside the single-quoted attribute, and `JSON.parse` of the emitted value
round-trips:

```
armed+selected  -> …dv-flow-canvas" id="design-viewer" data-wedit-armed="1"
                   data-wedit-sel='{"screen":"portalo.home","kind":"card","index":0}'
disarmed        -> …dv-flow-canvas" id="design-viewer">
armed,no sel    -> …dv-flow-canvas" id="design-viewer" data-wedit-armed="1">
static build    -> …dv-flow-canvas" id="design-viewer" data-static="1">
```

The last row matters: the pre-existing `data-static="1"` path is unchanged by
the concatenation.

## Browser verification (added after the offline pass)

The offline pass above was not sufficient, and skipping the browser hid three
defects — two of which made the increment non-functional:

1. **The design view did not render at all.** The `bodyAttrs` rationale was
   written as a `{# … #}` comment *inside* the `{% set P = { … } %}` dict
   literal. That is a parse error, not a no-op: every `/design` request was a
   500. The offline check rendered the `bodyAttrs` *expression* in isolation,
   which is exactly why it passed while the page it lives on could not load.
2. **Selection never reached the canvas.** `widgetSelect`/`clearWidget`
   returned the slim `widgetEditorContext` and the client swapped it into the
   per-screen `.dv-wedit` slot. So the editor opened, but the canvas body's
   `data-wedit-sel` — the attribute `drag.js` hangs the handles off — was
   never refreshed, and **no resize handle ever appeared**, from either the
   canvas or the explode-row entry point. Fixed by following the arm path's
   own precedent: select and clear now return the full `stageContext` and the
   posters use the arm chip's `#design-viewer` / `morph:outerHTML` contract,
   so one response carries both the editor and the canvas attrs. `morph`
   keeps the tiles from reloading (asserted in the harness).
3. A stale-rect race in the harness, not the app: measuring click coordinates
   mid-morph aimed the click at nothing.

Verified in headless Chrome against the real `portalo` project by
`appboxd/tool/shot_increment3.dart`, which drives the actual UI (clicks the
arm chip, then clicks a real `[data-el]` widget) rather than poking routes:

```
PASS  baseline is DISARMED
PASS  clicking the chip ARMS the canvas
PASS  clicking a widget SELECTS it (server-side)
PASS  resize handles are hung on the selection (found 8)
PASS  hug/fill/fixed chips render
PASS  tiles preserved across the selection morph (not reloaded)
```

Screenshots in `docs/plans/increment-3-evidence/`. The third shows the
Ceramics card selected with its handles and the editor bound to
`design/surfaces/home.html`.

The write-through and the validator were also exercised over the wire against
the real project: `data-resize-x=fill` reached `surfaces/home.html`, and
`stretch`, `data-pad=10` and `data-bogus` were each refused with a 400. The
test mutation was reverted through the app's own toggle-off (`value=""`), so
the project is byte-identical to where it started.

## Consequence for this increment

Arming, selection, the resize handles, the per-attribute validator and the
mode chips now work end-to-end in a browser. What still cannot be shown is a
tile **visibly reflowing** when a mode is applied — nothing in the tile
implements the sizing contract yet, so the mode is recorded in the source and
reflected in the chips, but the rendered tile does not change shape. A
screenshot claiming otherwise would be claiming a capability the served CSS
does not have.
