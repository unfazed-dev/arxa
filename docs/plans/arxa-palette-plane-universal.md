# Arxa — the Universal Palette Plane

Grilled and confirmed 2026-09-10. Twelve decisions locked one-by-one (Q1–Q12), each
with its recommended option chosen. Supersedes `arxa-dial-palettes.md` where the
two disagree on manifest shape; that plan's publication/transport law (its Q1–Q14)
stands untouched.

## Locked decisions

1. **Scope (A).** Every designer artifact SHIPS the palette plane at birth.
   kind:site gets the full dial-switchable plane end-to-end (as arxa-site today).
   kind:app: the HTML design artifact gets the same plane (dial switching works
   identically in the prototype); the Flutter side receives the chosen palette at
   SCAFFOLD time through the existing DTCG path (palette.dart → theme-map). Apps
   never runtime-switch palettes — that stays the style/theme axes' job.
2. **The fallback five (A).** The starter (hello-hda) ships the arxa-site five
   verbatim as the universal fallback set — Marine Blue (default), Lavender Iris,
   Sunset Ember, Orchid Bloom, Forest Neon — ids `marine`, `c-6f58c9`,
   `c-2e1f27`, `c-8e518d`, `c-293f14`, all `seeded: true`. A project
   derivation reseeds ALL five slots wholesale; the fallback survives only in
   projects that never derive. The 5-seeded cap stays.
3. **Derivation sources (all four).** One engine, four source adapters:
   `coolors` (slug → 5 hexes, exists), `url` (lens extractTokens clusters →
   select 5), `image` (NEW lens pixel-sampling probe — headless-Chrome canvas,
   zero native deps), `hexes` (raw list, pad/decimate to law).
4. **In-dial editing (A).** Author-only. NON-default palettes (seeded or custom)
   edit IN PLACE: stable id, swatch/themeColor/sheet/tokens re-derived atomically,
   published picks + ?palette= links never break. Editing the DEFAULT palette
   FORKS into the one custom slot (obeying the one-slot sweep — it replaces the
   previous custom), publishable immediately; the base corpus stays hand-owned.
   Editing into a swatch set identical to another palette refuses, naming the
   conflict.
5. **Variable width (A).** Declaration accepts 3–7 hexes; the plane stays 5-role
   internally (dark/accent/field/beige/paper — the template families). N=5 keeps
   the verified lightness-rank law byte-for-byte. N<5: lightness-rank assigns
   what exists; missing mid-roles interpolate in HSL. N>5: sorted by lightness,
   evenly decimated. No saturation cleverness — the dial editor is the taste
   escape hatch. Manifest keeps source hexes verbatim; cards render N stripes.
   Coolors ingestion stays exactly-5 (their format). Dial editor add/remove
   bounded 3–7. **N=1** (ruled 2026-09-10, the one-brand-color case; legal
   only via brandColors/hexes — the dial editor floors at 3): accent = the
   seed; dark/field/beige/paper = the seed's HCT ramp tones 10/50/90/99
   (palette.dart tonalRamp — deterministic, monochrome by honesty; taste
   correction rides the dial editor like every derivation). **N=2** (same
   ruling): dark = the darker, paper = the lighter, accent = the more
   saturated (ties break darker); field/beige = HSL mixes DARK→PAPER at
   1/3 and 2/3 (never accent→paper — the accent can BE an endpoint, and
   the interpolation would collapse; measured 2026-09-10). For N<3 the manifest swatch is the FIVE NORMALIZED ANCHORS
   (the 3-floor schema law); for N≥3 it stays the verbatim source hexes.
6. **Intake brand colors (A).** `intake.schema.json` gains optional structured
   `brandColors: [{hex, role?, provenance}]` (provenance ∈ client|founder|
   inferred). Priority: client-stated colors outrank references — the default
   palette derives from brand colors first (padding per Q5). A role hint PINS
   that hex to that role even where lightness-rank would place it elsewhere; the
   pinning is recorded. Two hints claiming the SAME role (ruled 2026-09-10):
   FIRST-WINS — statement order is the client's priority — and the arbitration
   is recorded in the palette's evidence alongside the pinnings; never a
   refusal (intake validates shape only; the client's words are not an error).
7. **Moodboard suitors (A).** `tokens.palette` upgrades from prose string to a
   derived palette OBJECT `{name, swatch:[5], anchors:{dark,accent,field,beige,
   paper}, paletteSource:"<boardId>/<reference>", provenance, evidence}`,
   produced by running the engine over the suitor's palette-credited reference.
   `judged` stays legal only when the reference has neither URL nor shot.
   Commission renders actual hexes; remix "palette from C" is a mechanical object
   swap. **Slot-fill law** for a design's seeded five:
   - default slot: brandColors-derived → else winning suitor (remix-applied) →
     else Marine Blue fallback;
   - slots 2–5: the two declined suitors' palettes → remaining selected
     references ranked by weighted score → fallback-five backfill;
   - swatch-set dedup throughout.
8. **Scaffolder (A).** Freeze threads an optional `palettes` block into
   structure.json (the manifest verbatim; absent = no plane, valid for pre-law
   artifacts). Freeze WARNS (advisory, never blocks) when the dial store's
   published pick ≠ manifest default. Scaffold emits the app's color vocabulary
   from the frozen DEFAULT palette only: each anchor → HCT tonalRamp (palette.dart
   reuse), theme roles accent→primary seed, dark→ink/on-surface, paper→background,
   field→surface, beige→card/secondary-surface, APCA-picked on-colors, emitted as
   a DTCG tree through themeMap() into the Dart tree. The other four palettes ride
   structure.json as audit trail only. Coverage gate gains the drift check:
   emitted color tokens must equal the frozen default's anchors (same --check
   discipline as the file-set diff).
9. **Gates (A).** Three hard additions + one advisory, no grandfather list:
   - **P-gate completeness** (design lint): valid palettes.json (default
     resolves, 3–7 law), _template.json + palette.js exist, every manifest
     entry's sheet + tokens block intact on disk.
   - **P-gate template coverage:** every color-bearing rule in the artifact's
     stylesheets must be indexed in _template.json (the leak-killer). The indexer
     (genpalettes.mjs, today a mirrored JS script under a change-one-change-both
     law) is PORTED to Dart as `arxa design palette-index` — one implementation;
     the mirror law dies.
   - **moodboard check:** suitor palette objects validate (5 hexes, complete
     anchors, paletteSource resolves to a selected reference, evidence resolves
     on disk).
   - **Advisory only:** hardcoded-hex sweep outside tokens/palettes with an
     allowlist (intentional non-palette colors exist by law — the #0a0a0a
     stage-island class); notes channel like D9, never a hard fail.
   - **No grandfathering:** pre-law artifacts (energize) are MIGRATED in this
     work — drop in the plane files, reseed the fallback five.
10. **Engine placement (A).** NEW `lib/palette_derive.dart` — the one
    deterministic engine (source adapters, normalization, role-hint pinning,
    slot-fill reseed; pure testable cores). `design_palettes.dart` keeps
    manifest/serve-time/bake, gains `update()`, and its Coolors ingest slims to
    a thin adapter over the engine. `palette.dart` untouched (HCT/tonal/DTCG
    primitives reused by engine + scaffolder). CLI: `arxa palette derive --from
    <input> [--json]`, `arxa palette reseed <design-dir>`, `arxa design
    palette-index <dir> [--check]`. `arxa emit palette` unchanged.
11. **Sequencing (B).** Deploy the verified arxa-site eject FIRST (before any
    arxa-repo edit), then build the plane with arxa-site as the pilot (engine +
    tests → dial/server edit machinery → live verification on the site's design
    server → hello-hda → skills docs + gates → energize migration → full suite),
    and a SECOND deploy ships dial editing.
12. **Docs + tests (A).** Full paper trail: this plan doc; addendum pointer in
    arxa-dial-palettes.md; designer (SKILL/system-prompt/locked-laws/hello-hda/
    playbook), intake (SKILL/schema/artifacts-and-flows/playbook), moodboarder
    (suitors/record-selection/schema/check/playbook), scaffolder (SKILL/
    contracts-and-verdicts/data-vocabulary-assets/playbook); pipeline-map.md +
    VOCABULARY.md; arxa-lint docs sweep. Tests: palette_derive (adapters,
    N=3/4/6/7, role hints, slot-fill), design_palettes additions (update,
    fork, conflict refusal, variable-N), P-gate, moodboard suitor palettes,
    coverage drift, lens pixel probe; the suite (1896) stays green and grows.

## Architecture

### The engine — lib/palette_derive.dart (NEW)

```dart
enum DeriveKind { coolors, url, image, hexes }

class DerivedPalette {
  final List<String> swatch;           // verbatim source hexes, '#'-prefixed, 3..7
  final Map<String, String> anchors;   // dark/accent/field/beige/paper, '#'-prefixed
  final String suggestedName;
  final Map<String, Object?> evidence; // selection trail (clusters, counts, source)
}

/// Injected so the pure cores stay I/O-free: url → lens extractTokens clusters;
/// image → lens pixel probe clusters. coolors/hexes never touch it.
abstract class ClusterSource {
  Future<List<ColorCluster>> clusters(DeriveKind kind, String input);
}
```

Pure cores (no I/O, fully unit-tested):

- `Map<String,String> anchorsForN(List<String> hexes, {List<RoleHint>? roleHints})`
  (`typedef RoleHint = ({String role, String hex})` — the Q5 law:
  - N=5: the existing lightness-rank law (reuse design_palettes' anchorsFor —
    EXPORT it or move it here and re-export; one home).
  - N=3: dark=r0, accent=r1, paper=r2; field = hslMix(accent, paper, 1/3);
    beige = hslMix(accent, paper, 2/3).
  - N=4: dark=r0, accent=r1, field=r2, paper=r3; beige = hslMix(field, paper, 1/2).
  - N=6: ranks 0,1,2,3,5. N=7: ranks 0,1,3,4,6 (floor(i*(N-1)/4)).
  - `hslMix(a, b, t)`: HSL-space lerp, hue by shortest arc, s/l linear —
    the plane's existing HSL math, no new color science.
  - `roleHints` (Q6) rides `typedef RoleHint = ({String role, String hex})`
    as an ORDERED LIST (a Map physically dedupes — first-wins arbitration
    was unreachable until the ENGINE review caught it, 2026-09-10): the
    hinted hex pins to the role; first-wins per role; hints naming absent
    hexes ignored; rank assignment fills the remaining roles over the
    remaining hexes. Companion rulings from the same review: selectSalient
    merges keep the HEAVIER count (max, never sum); planReseed mints
    reserve the fallback's ids (a derived palette never claims one).
- `List<String> selectSalient(List<ColorCluster> clusters)` — the url/image
  selection law, deliberately dumb: merge clusters within RGB euclidean ≤ 12
  (keep the heavier count); rank by count desc, take top 8; sort by HSL
  lightness; decimate/interpolate to exactly 5 via anchorsForN. Taste
  correction is the dial editor's role (Q5).
- `ReseedPlan planReseed({required PaletteManifest fallback, List<DerivedPalette>
  brand, List<DerivedPalette> suitors, List<DerivedPalette> references})` — the
  Q7 slot-fill law: candidates = brand, suitors (winner first, remix applied,
  then declined), references (score-ranked), fallback.palettes (its own default
  first); dedup by sorted swatch set, first wins; take exactly 5; default = first
  candidate. Fresh ids mint `c-<darkhex>` (+ `-n`); fallback entries keep
  their ids. Returns entries + defaultId + human-readable notes (what filled
  each slot and why).

### The lens pixel probe — lib/lens/pixels.dart

`extractPixelClusters(String imagePath)`: the lens daemon's headless Chrome
decodes the image (every browser format free), buckets pixels (alpha < 128
skipped; 8-level-per-channel quantization, band-center representatives,
count-desc/packed-rgb-asc canonical sort, longer side ≤ 128 sampled),
returns clusters in lens/tokens.dart's ColorCluster shape; console/page
errors throw (a poisoned palette never reads as empty). Engine applies the
≤12 RGB-euclidean merge downstream — one merge law, one home.
Implementation notes (landed 2026-09-10): pixels.dart PRE-EXISTED as the
pixel substrate (decodePng/pixelDiff/SSIM/ΔE — untouched); the probe was
appended. Transport is a base64 data: URL through CDP evaluateFunction —
file:// documents get opaque origins in current Chrome, so the spec's
original file://→canvas→getImageData readback throws SecurityError
(measured); Chrome still performs the decode, zero native deps preserved.
CLI: `arxa lens pixels <image> [--out=path]` rides the existing lens
dispatch.

### The template indexer — lib/design_palette_index.dart (NEW)

Faithful Dart port of website/designs/arxa-site/evidence/rebrand/genpalettes.mjs
(constants empirically fitted by the SERVER workstream, 2026-09-10): the
family metric is euclidean d = sqrt((10·Δhue)² + Δs² + Δl²) against the
default palette's anchors (classifies all 21 marine hexes + 8 triplets
exactly — hue-lexicographic provably cannot, the paper/beige cluster needs
saturation); saturation < 12 = palette-NEUTRAL (verbatim passthrough, never
reported); nearest-anchor hue distance > 45° = unindexed + reported (the
P-GATE owns the allowlist — #c0392b, the .waitlist-error error red, is the
ruled intentional case: reported by the indexer, allowlisted at the gate).
The walk is lexicographic over ui/styles/** + assets/css/** minus the
resolved tokens file (rule SET identical to the mjs's hardcoded walk;
59 rules, zero duplicate keys, cascade-equal). JsonEncoder.withIndent(' ')
== JSON.stringify(indent 1) byte-for-byte; the regenerator-pointer comment
is the one forced content diff. Tokens derive from the tokens file's :root
(alpha-as-written, base hex lowercased, single-triplet values take the
shadow: form). Faithful Dart port of website/designs/arxa-site/evidence/rebrand/genpalettes.mjs:
walks the artifact's stylesheets, indexes every color-bearing rule into
assets/styles/palettes/_template.json (anchors/tokens/rules — the existing
format, byte-compatible), then REGENERATES every seeded palette's override
sheet + tokens.css block from palettes.json through the plane's existing
render path (idempotent birth + repair). `--check` mode: diff live CSS
against the template (P4's engine) without writing. After the port lands:
genpalettes.mjs is deleted and the change-one-change-both comment in
design_palettes.dart is removed.

### Server plane — design_palettes.dart / arxa_dial.dart / design_server.dart

- **The two stylesheet layouts (2026-09-10):** site-layout artifacts carry
  ui/styles/common/tokens.css; app-layout artifacts (hello-hda) carry
  assets/css/*.css and no ui/styles tree. The tokens file resolves
  site-layout first, else assets/css/tokens.css (created on demand); the
  corpus walk covers ui/styles/**/*.css + assets/css/**/*.css, always
  excluding the generated assets/styles/palettes/ dir (which every
  artifact uses for sheets, layout-independent).

- `PaletteEntry.fromJson`: swatch length 3..7 (was exactly 5). Save-schema
  comment updated.
- `PaletteIngestion.update(String id, List<String> hexes, {String? name})`:
  - id == defaultId → FORK: derive anchors (anchorsForN), dedup against ALL
    entries, create/replace the single custom slot through the existing
    one-slot sweep; returns (entry, forked: true).
  - else: entry exists or ArgumentError; dedup against OTHER entries →
    ArgumentError naming the conflict; re-derive; rewrite sheet (temp file +
    rename) and tokens block (strip-by-id + append, one write); manifest
    swatch/themeColor/name; save LAST (crash law unchanged).
- `ingest()` becomes: parseCoolorsSlug → engine derive → shared write path.
- Route `POST /__dial/palettes/update` (author-only; static mode refuses
  cleanly like ingest): body `{id, hexes:[3..7], name?}` → 200 `{palette,
  palettes, forked?}`; 400 invalid hexes/count; 400 unknown id; 409
  `{error, conflictsWith}` on dupes. SSE `palettes` broadcast rides the
  existing design_server wiring.

### The dial editor — skills/arxa-designer/runtime/vendor/arxa-dial.js

- Palette cards gain an edit affordance (author mode only; hidden in static,
  like the paste row).
- Editor panel (inside the Theme slide): one row per swatch color — native
  color input + hex text input + remove ×; add-color button (disabled at 7;
  remove disabled at 3); name field; save/cancel. On the DEFAULT palette a
  banner states the fork law ("saves as your custom palette — replaces the
  current custom").
- Save → POST /__dial/palettes/update → resync `S.axes.palettes` from
  `res.palettes` (the resync law — never blind-push) → re-render grid.
  After a fork: locally preview the forked card (pvnote marks previewing);
  publish stays the user's explicit click. After an in-place edit of the
  ACTIVE palette: repoint that palette's sheet link with a cache-buster so
  the repaint is visible live.
- All new chrome obeys the cursor:auto law; S.publishing gate untouched.

### Scaffolder — emit_structure.dart / scaffold.dart / gate_coverage.dart

- Freeze: palettes.json (when present) threads verbatim into
  structure.json["palettes"] = {default, palettes}. Advisory skew warning when
  Supabase is configured (best-effort read, never blocks).
- Scaffold: frozen default's five anchors → per-anchor tonalRamp → DTCG tree →
  themeMap() → the app's Tier-1 color vocabulary file (placement + naming per
  showcase-anatomy.md + data-vocabulary-assets.md; header records provenance:
  frozen palette id + swatch + "do not hand-edit — re-freeze, re-scaffold").
- gate_coverage: re-render the expected vocabulary from structure.json's
  palettes block and diff against disk (the --check discipline).

### Gates

- NEW lib/gate_design_palettes.dart, wired into design lint: P1 manifest valid
  + default resolves + 3–7 law; P2 _template.json + palette.js exist; P3 every
  entry's sheet + tokens block intact; P4 template coverage via palette-index
  --check. Advisory channel: hardcoded-hex sweep with allowlist.
- moodboard_check.dart: suitor palette object validation (Q9).
- intake: brandColors shape validation (hex pattern, role enum, provenance
  enum); emitter carries the group + writes a machine-readable slot the reseed
  consumes.

### Births + migrations

- **hello-hda:** ships palettes.json (fallback five verbatim, seeded, default
  marine), assets/app/palette.js (verify artifact-agnostic), tokens blocks,
  and a palette-index run over its own corpus (template + four seeded sheets).
  Base styles authored token-driven on Marine Blue. P-gate proves it.
- **energize:** FOUND + MIGRATED 2026-09-10 at
  /Volumes/developer_ssd/Developer/totem_labs/clients/energize/landing/
  design/energize-landing (kind: site, en+fr — the locale-in-path engagement).
  Its corpus was already var-driven (site.css :root): the birth moved its
  authored identity onto five roles ("Energize Teal" — ink #0D0E13, teal
  #0FA3A3 (the --orange var's actual value), warm cremes; accent hint
  recorded) with the corpus's semantic vars re-pointed as role-driven
  ALIASES in a new ui/styles/common/tokens.css (color-mix holds each var's
  in-family position), palette.js + theme-color wired, indexer run
  (5 anchors, 5 tokens, 58 rules, 4 seeded sheets), P-gate CLEAN (the
  rental fleet lavender swatch allowlisted as product content, not chrome),
  and the flip visually verified (energize-teal ↔ marine lens frames — the
  whole shell repaints). The neutral gate gained the anchor-pass refinement
  here: a low-saturation ROLE value (its warm-gray field) must index even
  under s<12 (bestD ≤ 25 always passes). Its grandfather-era moodboard
  (prose palettes) stays valid under the law of its day; deriving fresh
  suitor palettes from its selected references remains an optional later
  step. **designs/arxa-studio** migrated manifest-only (it owns a Flexoki
  [data-accent] axis — the HTML plane would fork it; default "Studio Cyan"
  from its authored identity, freeze-threaded, verified) and
  **mobile_flutter/design** manifest-only (freeze→scaffold touchpoint).
- **arxa-site (the pilot):** picks up the new vendored dial + server on
  rebuild; lens E2E (edit-in-place, add/remove stripe, fork, conflict refusal,
  N-stripe rendering) + leak sweep + dots/tier probes re-run; VERIFY.txt
  ADDENDUM 23; eject v10; second deploy.

## Parallel-work file-ownership map (hard boundaries)

| workstream | owns (only these) |
|---|---|
| DOCS-INTAKE | skills/arxa-intake/** |
| DOCS-MOODBOARD | skills/arxa-moodboarder/** (docs + schema, no Dart) |
| DOCS-SCAFFOLD | skills/arxa-scaffolder/** |
| DOCS-DESIGNER | skills/arxa-designer/** EXCEPT runtime/** and examples/** |
| DOCS-XCUT | arxa/docs/research/pipeline-map.md, arxa/docs/VOCABULARY.md, arxa/docs/plans/arxa-dial-palettes.md |
| ENGINE | arxa/arxa/lib/palette_derive.dart, arxa/arxa/test/palette_derive_test.dart |
| LENS | arxa/arxa/lib/lens/pixels.dart, its test, lens_cli.dart wiring |
| SERVER | arxa/arxa/lib/design_palettes.dart, arxa/arxa/lib/arxa_dial.dart, arxa/arxa/lib/design_server.dart, arxa/arxa/lib/design_palette_index.dart, their tests |
| SCAFFOLD-CODE | arxa/arxa/lib/emit_structure.dart, arxa/arxa/lib/scaffold.dart, arxa/arxa/lib/gate_coverage.dart, their tests |
| DIAL-UI | skills/arxa-designer/runtime/vendor/arxa-dial.js |
| INTAKE-CODE | arxa/arxa/lib/intake.dart, arxa/arxa/lib/intake_artifacts.dart, their tests |
| GATES | arxa/arxa/lib/gate_design_palettes.dart (new), arxa/arxa/lib/moodboard_check.dart, lint wiring, tests |
| HELLO-HDA | skills/arxa-designer/examples/hello-hda/** |

CLI wiring (bin/arxa.dart) + binary rebuild + integration: the orchestrator.
Cross-file needs ride this doc's specs; when a spec is ambiguous, STOP and
surface — never improvise a mapping (the showcase-anatomy law).

## Test plan

palette_derive_test (anchorsForN 3/4/5/6/7 + role hints + hslMix arc;
selectSalient merge/rank/decimate; planReseed order/dedup/fallback);
design_palettes additions (update in place, fork + one-slot sweep, conflict
refusal, 3–7 manifests); pixels probe (fixture image → clusters);
design_palette_index (fixture corpus → template byte-compat + --check diff);
route tests (update 200/400/409, static refusal); scaffold (freeze block,
skew warn, vocabulary emission, coverage drift); P-gate; moodboard suitor
validation; intake brandColors. Full suite green (1896 + new).

## Client theme access + the smoke matrix (2026-09-10)

**Two links hand a client the color themes on a deployed site** (mechanics
in skills/arxa-designer/built-in-skills/productionize.md):

1. **The author link** — `https://<site>/?dial-author=<token>`. ONE per
   design. The first credentialed eject mints it and prints it ONCE; later
   ejects reuse the stored hash. Rotate by setting `ARXA_DIAL_AUTHOR_TOKEN`
   at eject time and re-deploying (the hash is baked into the worker AND
   stored in `arxa_dial_designs.author_token_hash` — a Supabase-only edit
   does nothing until the next eject). arxa-site's token was minted at the
   v9 eject and carried through v10.
2. **Personal guest links (recommended for clients)** — minted on the
   LOCAL design server's dial (tray trim v2, grilled 2026-09-10): dial →
   Studio tray → **Access** slide → client email → "Mint personal link"
   → copy the `?dial=<token>` URL; the link works on the deployed site.
   Per-email attribution, revocable from the same roster (revoke keeps
   their comments). Publish law: a palette pick publishes for EVERYONE,
   author or guest — the link IS the authorization (`publish_palette`
   RPC validates either capability in SQL). A wrong/dead token gets no
   dial at all (Q9). The Access slide is author- and local-only: guests
   and the deployed dial get a one-slide tray (the static store refuses
   /guests outright). **Automint at eject:** the arxa.json `dial` block
   {automint, clientEmail, days} (env ARXA_DIAL_AUTOMINT /
   ARXA_DIAL_CLIENT_EMAIL / ARXA_DIAL_CLIENT_DAYS override) mints the
   client link automatically at every credentialed cloudflare eject —
   idempotent per email, print-once, 90-day default, OFF by default.

Deployed dial = pick + publish + comment. Hex-level editing (the ✎
editor, fork, 3–7 widths) stays on the local design server by locked
decision — the static dial refuses it cleanly.

**Smoke matrix (all green 2026-09-10).** The two pilot probes were
generalized to be manifest-driven (default id/name + the two-layout
tokens-path law read from the artifact, never assumed): `arxa palette
edit` route E2E (25/25) + `lens_palette_edit_ui` dial-editor E2E (17/17)
now pass on **arxa-site** (:4319), **energize** (:4321 — Energize Teal
default card forks correctly), and **hello-hda** (:4322 — the
assets/css/tokens.css layout). New `tool/lens_live_author.dart` proves
the deployed client story end-to-end against
https://arxa-site.evan-pierrelouis.workers.dev (12/12): wrong token → no
dial; right token → author mode; card click → publish_palette writes the
shared row; an anonymous clean-context visitor settles onto the new pick;
the published pick was restored to c-2e1f27 (Sunset Ember) and the
restore verified settling too. Run it per deploy:
`dart run tool/lens_live_author.dart <base-url> <author-token> <restore-id>`.

**Trim v2 + automint verify (2026-09-10, all green).** The tray trim
amendment (Access slide) + eject automint shipped and were proven: unit
38/38 (arxa_dial automint config), axes+server 81/81, editor-UI tray
regression 17/17, `tool/lens_access_slide.dart` 15/15 (author Theme+
Access with the live panel; guest one-slide, no dots, no panel), eject
dry-runs (mint+print-once → idempotent skip → off-by-default silent),
deployed v11 `b3f895f5`: live author 13/13 (incl. the static one-slide
law) and live guest 11/11 (mint locally → boot deployed guest → publish
→ anon settle → restore → revoke → dead-link invalid surface, zero
writes). arxa-site's arxa.json carries no dial block — automint stays
off until a client email exists.

**The contrast engine amendment (2026-09-11, grilled — seven locked
decisions; the full law lives in `arxa-dial-palettes.md` amendment
6).** The universal plane now ships CONTRAST-SOLVED: every override
sheet renders its declared pair contract at WCAG 2.2 AA (4.5:1 body,
3:1 large/non-text) with APCA as advisory-only readouts. The starter
inherits it whole — `hello-hda`'s `_template.json` carries a token-
level contract, its seeded sheets render through the solver, and the
moodboard suitor law is unchanged (measured hexes seed `palettes.json`
VERBATIM — the mandate record; their SHEETS render solved). Anchors
never move; derived hexes do, logged in each sheet header. `auto`
rides the manifest (hand edit → MANUAL → ships verbatim; Re-solve →
AUTO). The P5 gate judges shipped CSS; `palette-index` preserves the
contract across re-indexes. Verified on arxa-site v14: DOM-truth
probe 3/3 pairs, ear + guest regressions ALL PASS, lint clean P1–P5.
