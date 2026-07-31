# Head-to-head: flutter-crew vs stacked_kit on the same surface

Identical input — p2's `design/new`, surface `train_shell_today_view` — through both
systems, judged by stacked_kit's 73-check `enforce_design.dart`. This is the
end-to-end run that was open question #1 in the spine assessment.

## Result

| | flutter-crew | stacked_kit (p2, already built) |
|---|---|---|
| reaches Dart | **yes** | yes |
| deterministic | **yes — `DONE (deterministic, no LLM)`, `golden.sha256` emitted** | no — a model authors every line |
| design nodes captured | **7 of 112** | (n/a — the model reads the surface) |
| output | 79-line view + 9-line viewmodel | 802 lines across 5 files |
| **73-check verdict** | **FAIL — 4 of 17 applicable checks failed** | **PASS — 73/73** |

**Read the 4/17 with its caveat.** `enforce_design` was pointed at a bare
`today_view.dart`, not a surface *directory*, so only 17 checks applied — 56
presuppose the five-file set. Two of the four failures (`form_factor_files`,
`design_system_doc`) are therefore partly artifacts of the shape I handed it: a
directory would have been demanded to contain files flutter-crew never sets out to
emit. The architectural conclusion does not rest on those two — it rests on
`ScreenTypeLayout` appearing **0 times in 22,738 lines**, which is independent of
how the judge was invoked. The two vocabulary failures (`no_stock_icons`,
`no_adhoc_spacing`) are real and shape-independent.

## The chain, as actually run

`run_pipeline` (parse → **classify** → guard → map_all → synthesize) → `blueprint`
→ `generate_views` → `emit`.

I first ran only `run_pipeline → blueprint` and got extension-point **stubs**
(`TODO(builder)`), and nearly concluded flutter-crew does not emit real views. That
was wrong: `generate_views.py` is the renderer, it is deterministic, and it was not
in the chain I ran. Corrected before it reached a conclusion.

### Where it stopped, and what each stop teaches

1. **`classify` is not optional.** The pipeline halts and prints an agent contract
   demanding N≈4 independent runs scored by an executable oracle
   (`pageScreenSkew` → `surfaceCssValidity` → `distinctIds` → `primitiveCount`,
   explicitly ordered by how gameable each is). This is a materially stricter
   discipline than stacked_kit's single `--fix-cmd` dispatch.
2. **A coverage gate caught my stand-in.** A hand-built probe covering 52 of 112
   nodes was rejected: `NON-EXHAUSTIVE: covers 52/112 (46.4% < 95%)`, exit 1. It
   only proceeded at 100%. The gate works.
3. **Flat-glob layout mismatch.** `_shard_of` globs `design_dir/*.jsx` with no
   recursion; p2 keeps shards in `design/new/jsx/`. Zero views generated until the
   shards were staged flat. Layout mismatch, not a capability gap.
4. **`styles.css` vs `app.css`/`tokens.css`.** The scoring oracle reads
   `<design>/styles.css`; p2 has neither. `surfaceCssValidity` silently biases low
   when classes do not resolve — a quiet degradation, not an error.

## The structural incompatibility

With the layout fixed, it generated: `today <- TrainHome (screens-member.jsx): 7 nodes -> 37 lines`.

**Seven nodes out of 112.** What it captured was the *offline banner* — not the Today
screen. `screens-member.jsx:54`:

```jsx
const TrainHome = ({ role, state, nav, data, params }) => {
  if (role === 'leo') return <TrainHomeLeo .../>;        // role branch
  const branch = (params && params.branch) || '';
  const TrainBanner = () => {
    if (branch === 'offline') return ( … );              // <- this is what got captured
    return null;
  };
  return (
    <Scr …>
      <u.HomeHead …/>
      <u.StateView state={state} empty={{…}}>            // state branch
        <TrainBanner/>
        {streak && <StreakCard …/>}                      // data branch
        {role === 'felix' && ( … the actual Today content … )}
```

**p2's design is branch-matrixed; flutter-crew's capture is not branch-aware.**
Every surface is a function of `role × state × params.branch` — p2 even ships
`branch-matrix.json` (595 KB) and `branch-coverage.html` to track the combinations.
`capture_design` has no notion of which branch is *the* composition, so it took a
subtree and emitted it confidently.

This is the finding that matters for appbox. It is not a bug in either system —
it is two incompatible models of what "a design surface" is:

- **flutter-crew:** one component → one composition → one view. Deterministic
  because the mapping is total.
- **stacked_kit:** one surface → a frozen *rendered* HTML per branch, and a model
  reads it. Handles branching, at the cost of all determinism.

Neither is right. appbox wants the frozen-HTML-per-branch input (stacked_kit's
`surfaces/*.html`, already branch-resolved) fed into a *deterministic* translator
(flutter-crew's `generate_view`). The frozen surface HTML is precisely the artifact
that makes branch-awareness unnecessary — the branch is resolved at freeze time.

### That recommendation is not a config change — checked before asserting it

`capture_design.py`'s contract is `<home.jsx> <styles.css> <out-spec.json>`, and
`generate_views` calls `cd.build_spec(jsx, css, …)` with JSX **text**. There is no
HTML input path. So "point it at the HTML instead" is not a flag; it is **building
an HTML front-end for `build_spec`**. Larger claim, stated as such.

Two things make it smaller than it sounds, and one makes it real work:

- `parse_html.py` already exists and parsed p2's surface cleanly (112 nodes with
  refs, classes, depth). The *parsing* is solved.
- The hard part of the JSX path does not exist in the HTML path. `build_spec`'s
  bulk is **component expansion** — parsing every `const X = (…) => (…)` and
  inlining usages, because "a flat parse yields disconnected soup." Rendered HTML
  is already flat and already expanded. That work simply is not needed.
- What *is* real work: `build_spec` emits structure + text + **resolved style**
  (layout/type/color via tokens) plus a primitive hint per node. An HTML path must
  produce the same spec shape from computed/inline styles rather than from CSS
  class resolution.

Worth noting what this exposes: `capture_design`'s docstring says *"The design is
static .jsx (no runnable web app), so there is no rendered geometry."* p2's
`surfaces/*.html` **are** rendered, through the headless emit pipeline. p2 has the
artifact flutter-crew's author explicitly says is unavailable — which is why the
integration is worth doing rather than working around.

## The 4 failures, and what each implies

```
✗ no_stock_icons     Icons.circle_outlined — reads as "untuned Flutter"
✗ no_adhoc_spacing   SizedBox(width: 9) — gaps must use the kit helpers
✗ form_factor_files  missing .mobile.dart / .tablet.dart / .desktop.dart
✗ design_system_doc  design-system.md missing
```

The first two are **vocabulary**: flutter-crew emits stock Material and raw
`EdgeInsets`/`TextStyle`; stacked_kit demands kit primitives and tokens. Fixable in
the emitter's token map — this is the cheap half.

The last two are **architectural**, and confirm the token census from the spine
assessment: `ScreenTypeLayout` appears **0 times** in flutter-crew's 22,738 lines.
It emits one view per screen; the whole responsive contract — genuine tablet and
desktop layouts, not a widened phone — does not exist in its model. That is real
work, and it is the honest cost of "port the emitter."

## What this changes in the spine assessment

Nothing in the call, and two things in the detail.

- **Confirmed:** flutter-crew's core really is deterministic end-to-end and really
  does reach Dart with a golden hash. That was an inference from a token census;
  it is now a measurement.
- **Confirmed:** its gates bite. A non-exhaustive classify was rejected at a 95%
  floor rather than silently degraded.
- **Revised down:** "reuse the emitters" is a bigger job than the census implied.
  Not because the emitter is weak — the generated Dart is clean, idiomatic, and
  correctly uses the `ViewModelBase`/`ViewModel` split — but because it must gain
  (a) form-factor dispatch and (b) the kit vocabulary before a single surface can
  clear the 73 checks.
- **New, and the most important:** the input contract, not the emitter, is the
  real integration point. Feed it p2's already-branch-resolved
  `surfaces/<id>.html` instead of the JSX shards, and the branch problem disappears.

## Reproduce

```
FC=<factory>/flutter-crew ; D=<p2>/design/new ; SB=<scratch>
python3 $FC/stages/run_pipeline.py $D/surfaces/train_shell_today_view.html $SB/today \
  --primitives $SB/today/primitives.probe.json --tokens $D/tokens.json
python3 $FC/stages/blueprint.py $SB/today/breakdown.json $SB/today/pkg
cp $D/jsx/*.jsx $D/*.css $SB/flat/            # flat-glob workaround
python3 $FC/stages/generate_views.py $SB/flat $SB/today/breakdown.json $SB/target
dart run <kit>/skills/kit-designer/scripts/enforce_design.dart \
  $SB/target/lib/presentation/today_view.dart
```

**Caveat, stated plainly:** `primitives.probe.json` is a crude mechanical stand-in
for the classify agent (tag→primitive by rule), not a real classify run. It is
sufficient to prove the chain reaches Dart and to expose the branch problem, and it
is *not* evidence about output quality. A real N≈4 classify would improve the
breakdown; it would not change the branch-capture finding, which happens in
`capture_design` from the JSX and is independent of primitives.
