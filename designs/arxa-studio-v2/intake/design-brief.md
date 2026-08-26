# arxa-studio-v2 — intake design brief

This brief is the intake-stage output for the v2 studio buildout. It distills
the locked rulings; the ruling text itself is the SSOT:
`docs/plans/designer-scaffolder-grill-decisions.md` (Q1–Q15 and the Q-v2
series). On any conflict between this brief and the decision log, the
decision log wins — flag the conflict, do not silently resolve it.

## Purpose / smoke test discipline

This buildout is a smoke test of the refactored arxa-designer skill and
recipe SSOT. If the emitted structure drifts from the showcase recipe, the
finding is a skill/recipe bug: report it and stop — the skill gets fixed and
the emit re-run. Never hand-patch the emitted output to hide drift.

## Identity

- Artifact: `designs/arxa-studio-v2/` — arxa studio itself, designed as
  an arxa app per the showcase recipe.
- The app being designed *inside* the studio's design shell is **Portalo**
  (simulated design content). Portalo is NOT a shell of the studio.
- Splashscreen is NOT a shell — mobile splash surface + brand logo only.

## Structure (locked)

- Recipe grammar sits at the **artifact root** `designs/arxa-studio-v2/`
  (Q-v2-4 as amended 2026-08-08): the manifest's `lib/` is a Dart-medium
  prefix; anatomy §1 translates it to the artifact root for the design
  medium (`app.routes.js` at root, `ui/views/…`, etc.).
- `assets/{studio,portalo}` at the artifact root — the portalo
  feature-scoped assets folder is a studio-only exception to general rule B.
- Structure mirrors `kit/showcase_app/lib` per the feature-recipe SSOT
  (`kit/showcase_app/feature-recipe.manifest.json`), in design-medium
  translation.
- Barrels are named like showcase — never `index`.
- Vocabulary: **hub > shell > view > widgets**. "screen"/"page" are out of
  vocabulary everywhere, including DOM attributes.
- Shell roster: the hub (routes/navigation host, showcase `app.dart`
  analogue), the ceremony shells (startup, unknown, auth) and the design
  shell — exact names and per-shell view/widget rosters per the Q-v2
  entries in the decision log.
- v1 (`designs/arxa-studio/`) is candidates-only reference. Re-derive
  from scratch; never copy v1 structure or file layout.

## Constants & strings (locked)

- All layout/spacing values via arxa kit `abx*` constants (abxPad16,
  abxGapSmall, …); auto-layout tokens `abxFill` / `abxHug`.
- All strings via `abxStr*` constants (Str infix), no hardcoded copy.

## Inspect identity (locked, Q-v2-5)

- DOM inspect attributes use the NEW vocabulary (no `data-inspect-screen`;
  spellings per the ratified triple in the decision log / app-architecture).
- No flip toggle / no legacy dual-render — the user validates manually.
- The `probe_inspect.dart` + docs rename lands in ONE commit with this emit
  (handled outside this brief by the operator).

## Canvas responsiveness (locked)

- Desktop = default, full studio.
- Tablet canvas shows tablet + mobile designs of the designed app.
- Mobile canvas shows only the mobile design.
- Inspect works on all devices.

## Pipeline coupling (locked)

- Studio is a UI to operate on the arxa pipeline; each shell maps to
  pipeline stages with its input/output reflected.
- Per-shell manual triggers in the studio design to proceed to the next
  stage.

## Assets (locked)

- Designer manages assets; defaults from `kit/assets_default/` (arxa
  font, brand icon) when the user provides none — that applies here.
- Google Fonts at design time via CDN/CSS (scaffolder later uses the
  google_fonts package).

## Gates before surfacing

- `arxa design lint <artifact-dir>` clean.
- Structure diff against the feature-recipe manifest: zero unexplained
  deltas.
- Served + lens-checked at every ladder width; console clean.
