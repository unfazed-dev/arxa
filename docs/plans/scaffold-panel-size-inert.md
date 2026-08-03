# Panel-size grip is inert on both scaffold screens (set-but-unconsumed, instance 3)

Status: finding only. Nothing committed to source. The defect spans `scaffold_facade.js`
(picker-screen's) and `scaffold_run_facade.js` (mine), so the fix needs the lead.

## Verdict first

Panel-size resize works on `design` and `intake`. It is **inert on both scaffold screens** —
confirmed by render, on picker's screen as well as my own:

| screen | convention | mutate `activity/l` | result |
|---|---|---|---|
| `/design/freeze` | scalar `panelSize` | 200 | `panel-size-s` → **`panel-size-l`** |
| `/intake/brief` | scalar `panelSize` | 200 | `panel-size-s` → **`panel-size-l`** |
| `/scaffold?state=success` (picker) | map `panelSizes` | 200 | `panel-size-s` → `panel-size-s` |
| `/scaffold/run?state=completed` (mine) | map `panelSizes` | 200 | `panel-size-s` → `panel-size-s` |

The working screens are the positive control: the instrument demonstrably detects the change
when one occurs.

## Two void measurements before that, both mine

**Void #1 — closed vocabulary.** I probed `/scaffold/run/panel/size/main/{sm,md,lg,1,2,3}`,
got six 200s and a uniform page, and nearly reported "no exposure." But
`scaffold_run_facade.js:25-26` closes the vocabulary to
`PERSISTABLE_PANELS = ['composer','activity']` and `PANEL_SIZES = ['s','m','l']`, and `:121`
gates the write on both. `main` and all six sizes were inadmissible: **every call hit the
no-op branch.** 200 was never evidence of acceptance — `:124` returns `context(...)`
whether or not it mutated. Same shape as picker's `signedOut` finding: a supported key with
a closed vocabulary, where the rejected value fails silently.

**Void #2 — length-preserving change, byte-length instrument.** After correcting the
vocabulary I still measured page **byte deltas**. Note the control rows above:
`62588 → 62588` on design, `30453 → 30453` on intake. `panel-size-s` and `panel-size-l` are
the same length, so byte delta is **structurally blind** to this defect — it would have
reported +0 on a screen where the feature works perfectly. My instrument could not have
answered the question on any screen, and its zero on mine carried no information.

The second one is the more useful lesson: void #1 was a bad input, void #2 was a
*well-formed instrument measuring a quantity the phenomenon does not move*. My state-ladder
control (pre 24646 / completed 26792 / warning 28350) felt reassuring and licensed nothing —
it proved sensitivity to *state*, a different axis from *panelSize*.

## Mechanism, verified rather than inferred

**Corrected by picker-screen, and their framing is right.** I first called this "scaffold picked
the wrong one of two conventions." There is only one convention: **store a map, emit a resolved
scalar.** `design_facade.js:26`:

```js
const panelSizeFor = (d, panel) => (PANEL_SIZES.includes(d.panelSize?.[panel]) ? d.panelSize[panel] : 's');
```

That reads a per-panel **map** and returns a **scalar**, with `'s'` as the fallback. Storage is
byte-for-byte the same idea as mine (`s.panelSize` map). The scaffold facades simply skip the
resolution step and emit the raw map under a pluralised key nobody reads:

| facade | stores | emits | resolved? |
|---|---|---|---|
| `design_facade.js:892` | `d.panelSize` map | `panelSize:` scalar | yes, via `:26` |
| `intake_facade.js:731` | map | `panelSize:` scalar | yes |
| `build_facade.js:476,548` | map | `panelSize:` scalar | yes |
| **`scaffold_facade.js:173`** | map | **`panelSizes:` raw map** | **no** |
| **`scaffold_run_facade.js:71`** | map | **`panelSizes:` raw map** | **no** |

So the fix is smaller than "reconcile two conventions": the facade resolves per panel, and the
shell's `AP`/`CP` pass it through. Having two persistable panels does not argue for emitting a
map — it argues for emitting one resolved scalar per panel.

Worth noting the same file carries a scar from this exact family (`design_facade.js:22-24`):
`PERSISTABLE_PANELS` was once `['left','right']`, a *position* whitelist guarding a *role* key,
which "would have silently rejected the role key and made every drag-release a no-op." That is
my Void #1 — closed vocabulary, silent rejection — already caught once in this codebase.

Consumption, counted in one invocation with a control alongside:

```
ui/views/  panelSizes    = 0      <- subject
ui/views/  panelSize     = 42     <- the scalar, used by the working screens
ui/views/  composerPanel = 8      <- control, known present
```

No template anywhere reads `panelSizes`. The working screens pass the scalar explicitly,
e.g. `design/_shared.html:203`:

```
{{ pa.top({ label: c.activityLabel, ..., size: c.panelSize, sizeHref: c.panelSizeHref }, true) }}
```

`scaffold/_shared.html` passes neither `size:` nor `sizeHref:` (zero occurrences of either),
building `CP`/`AP` and calling `cp.open(CP)` / `pa.open(AP)` at `:73,:76,:98,:100`.

**Macro-path check** (design mounts `top`/`bottom`, scaffold mounts `open`/`close` — different
macros, so a citation in one proves nothing about the other). Boundaries in
`shared/widgets/activity_panel.html`: `top` is `:69`, `bottom` is `:70`, `open` spans
`:74-83`. The fallback and the drag gate are at `:77` and `:81`, i.e. **inside `open`** —
on scaffold's actual path:

```
size:   (spec.size or 's') if not spec.panelSizePx,
resize: { edge: 'start', persist: 'activity' } if spec.sizeHref
```

With `spec.size` undefined the size resolves to `'s'` on every request, and with `sizeHref`
absent the resize affordance is never rendered. Confirmed at the render level: `panel-size-s`
appears exactly once on both scaffold screens and never changes.

`routes.scaffold.js` registers **two** panelSize routes, both GET (`:20` picker, `:40` run);
the third grep hit at `:10` is a comment. There is **no `panelSizePx` POST** on scaffold,
unlike design (`routes.design.js:23`), so `if not spec.panelSizePx` is always true and the
`size:` branch is the one that fires.

## Layer status, read vs measured

1. routes registered — **read** (`routes.scaffold.js:20,40`)
2. viewmodel handler exported — **read** (`run_viewmodel.js:panelSize`)
3. facade persists to session — **read only, not measured.** I read the assignment at
   `:121-122`; I never observed the session actually retaining it on the scaffold path. The
   render is invariant either way, so this probe cannot distinguish "persisted but unread"
   from "never persisted." It does not change the verdict, and I am not claiming it as live.
4. render never reads the emitted key — **measured**, four screens, positive control

## Open question for the lead

Are the scaffold shells *supposed* to have a resizable activity/composer panel?

- **If yes:** either rename the scaffold emit to the scalar `panelSize` convention, or teach
  `scaffold/_shared.html` to read the map and pass `size:`/`sizeHref:`. Two facades, two
  screens, one shared template — picker and I are both touched.
- **If no:** the two routes, both handlers, the `PERSISTABLE_PANELS`/`PANEL_SIZES` consts and
  the session write are dead code on the scaffold path.

Same class as `composerAction` set-but-unrouted: a facade computing a value no renderer
consumes. Third instance in this task, and the first spanning two owners through a shared
naming divergence rather than one file. Not fixing, not committing.
