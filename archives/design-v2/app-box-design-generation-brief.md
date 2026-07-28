# app_box — Design Generation Brief (design-generation program)

**Audience:** the designer driving **`app-box-designer`** to a complete
interactive prototype of app_box's own desktop app (the dogfood target:
`--targets macos`).
**Status:** living document · owner: product. Repo truth wins on any conflict —
this doc *cites* the SSOT docs, it never paraphrases their tables.
**Companions:** [`app-box-persona-design-brief.md`](app-box-persona-design-brief.md)
(personas, pinned-vs-open contract), [`journeys/`](journeys/) (one journey map
per persona). Those carry the *why*; this doc is the *how-to-run-it*.

> **What this produces:** a complete, clickable, interactive prototype of the
> app_box desktop app in `app-box-designer` (Hono + htmx, zero custom
> client-side JS, genuine MVVM). The prototype carries structure — an authored
> `registry.json`, a `surfaceId` in every viewmodel, and a route table the
> freeze step reads. It is not a pixel mock; it is a typed input to the build
> pipeline.

---

## 1. The rules this program is built on (read once, then follow the stages)

These are not style preferences; each is grounded in measured research
(`docs/research/`) or `architecture.md`:

1. **Viewport ladder first, screens second.** Read the project's `--targets`
   from config and author at every width in the active ladder *before* any
   screen detail. Authoring at phone width only is the single most expensive
   mistake available here — everything omitted gets invented downstream by
   someone who never saw the design (`architecture.md` §11, §12; research:
   `headtohead-train-shell.md` — 1,600 lines of layout were invented in
   `train_shell` alone).
2. **Front-load, then iterate.** One big foundation prompt (§4) establishes
   product, modes, shell, aesthetic, and guardrails. Then build **stage by
   stage** (§5) — never the whole app in one prompt, never drip-fed with no
   foundation either.
3. **Structure is authored while designing, never back-filled.** Every surface
   gets its `registry.json` entry and `surfaceId` while you design it — not
   after. This is what makes the prototype a pipeline input rather than a
   picture (`app-box-designer` SKILL.md, `architecture.md` §14).
4. **Real data, never lorem ipsum.** Placeholder content hides state bugs and
   breaks layout assumptions. Use the seed-true anchors given per stage
   (pipeline state, SARIF findings, the surface inventory from the brief).
5. **Every screen gets its states** — default, loading, error, empty — at page,
   section, and component level. The gates get their distinct visual treatment
   (§5.2 of the persona-design-brief).
6. **Zero custom client-side JavaScript.** The prototype is Hono + htmx + CSS.
   Interactivity comes from htmx attributes and server-rendered responses —
   the same structure the scaffolder later emits as Flutter (`app-box-designer`
   SKILL.md).

## 2. Pre-flight checklist (do this before starting)

Verify these paths exist and are current — every stage pastes from them:

- [ ] [`personas.md`](personas.md) — Evan (4 modes) + Michelle
- [ ] [`app-box-persona-design-brief.md`](app-box-persona-design-brief.md) — constraints, pinned-vs-open, §10 surface inventory
- [ ] [`journeys/evan-founder-journey.md`](journeys/evan-founder-journey.md) — pipeline journey
- [ ] [`journeys/michelle-buyer-journey.md`](journeys/michelle-buyer-journey.md) — evaluation journey
- [ ] [`architecture.md`](../plans/architecture.md) §5 (findings/UI contract), §6 (state machine), §8 (desktop app screens), §11 (targets), §15 (companion), §17 (payment/deploy)
- [ ] [`docs/research/stub-inventory.md`](../research/stub-inventory.md) — wired vs stubbed kits
- [ ] `app-box-designer` skill loaded and `doctor.mjs` passing
- [ ] Project config: `--targets macos` (the dogfood — one viewport, 1280)

Session setup: one `app-box-designer` artifact for app_box's own desktop app,
served at `localhost:4319`. Copy `examples/hello-hda/` and rename. All stages
in the same artifact so structure compounds.

## 3. Stage 0 — viewport ladder + design tokens (before any screen)

Read `--targets macos` from config → active ladder = desktop (1280) only.
Load the design system into the artifact:

```
These are app_box's brand tokens and design system. Build the design system
from them exactly — improve never means rebrand.

Aesthetic direction: tool-grade clarity. The desktop app is a viewer and
controller over pipeline state — every surface renders data that comes from
work/ (run.json, history.jsonl, findings/*.sarif, logs/*). The aesthetic
should read as a professional instrument, not a consumer dashboard.

Colour direction: warm-neutral surfaces with a signal palette. Three gate
states must be visually distinct:
- Gate pending/neutral: muted, structural
- Gate green (approved): success signal, earned
- Gate red (broken): danger signal, unmistakable — red ALWAYS means broken,
  never payment (architecture.md §17)

Explicitly avoid: glassmorphism, stock "AI dashboard" aesthetics, emoji as
icons, centered-everything layouts, purple/blue gradients, generic system-font
look. The desktop app is dogfooded — it is the first bespoke stacked-MVVM app
app_box is judged by (architecture.md §8).
```

Author the viewport-ladder widths from config. For `--targets macos`, that is
1280 desktop only — but design with the awareness that the same surfaces serve
mobile/tablet when a different project targets them.

**Gate — do not proceed until:** the design system renders a sample card with
the correct tokens, the signal palette, and the three gate-state swatches.

## 4. The foundation prompt (paste once, immediately after Stage 0)

```
CONTEXT — read all of it before designing anything.

app_box is a desktop application that takes a client conversation to a shipped,
bespoke Flutter app in opinionated Stacked MVVM. It runs a pipeline with three
human gates. The desktop UI is a viewer and controller over pipeline state —
it is NEVER a source of truth. Everything it renders comes from work/ (run.json,
history.jsonl, findings/*.sarif, logs/*). Closing the app loses nothing; a run
continues headless.

CANONICAL VOCABULARY (binding in every label, everywhere): app_box, stage_shell,
gate (Gate 1 / Gate 2 / Gate 3), registry, surface, freeze, scaffold, finding,
ledger, SARIF, viewport, targets.
Never write: "auto-approved", "payment gate failed", "AI generated", or any
phrase that implies an agent can mint a gate approval.

PERSONA MODEL (defines who you are designing for):
- Evan (founder): operates the pipeline in four modes — intake, autonomous-build,
  red-gate recovery, ship. Every surface is his. He needs depth: gates, ledgers,
  SARIF findings, drift detection, escape hatches.
- Michelle (buyer): evaluates app_box in 20 minutes on a fresh machine. She
  needs honesty and a fast first win. She will never read the docs.

SHELL MODEL (one stage_shell, six tab-groups):
- projects: home (empty/list/loading), new (form/validating/error), splash, showcase
- design: directions (3-up/one approved), surface (live preview/stale),
  approve (GATE 1 — pending/approved)
- build: run (idle/running/green/red), finding (file/line/rule/fix),
  approve (GATE 2), recovery (red-gate diagnose/fix/re-run)
- ship: targets (fastlane/shorebird/CF Pages), confirm (GATE 3 — the triple:
  target+version+account), released
- chat: home (idle/streaming/tool-call)
- settings: credentials (vault tier stated), devices (paired/revoke),
  kits (wired vs STUBBED — never offer a target that throws), pair (QR/fingerprint)

THE THREE GATES (must be visually distinct from anything automated):
- Gate 1 (design approve): the frozen design is the right one. Bind approval to
  the design hash. An agent can present; it cannot approve.
- Gate 2 (build accept): the scaffolded work is shippable. Green build accepted.
- Gate 3 (ship confirm): the strictest — names target+version+account, requires
  the person to confirm that exact triple. The only gate that writes to the
  outside world and cannot be undone.

CREDENTIAL TIERS (stated on screen):
- BYO key → OS vault (macOS Keychain). UI says "stored in the macOS Keychain."
- Harness present → shell out to an authenticated CLI. app_box never sees a token.

STUB HONESTY: settings.kits shows wired-vs-stubbed for every kit. 5 of 23 kits
are partial; Stripe, PayPal, auth providers, map providers, Vercel all throw
UnimplementedError. A kit that throws must be labelled STUBBED before the user
builds against it.

RED MEANS BROKEN: the licence check is a precondition, NOT a gate. It runs
before the builder phase and fails with a licence message. It must NEVER appear
as a red gate — that teaches people to distrust red.

REAL DATA ANCHORS (use these, never lorem ipsum):
- Pipeline state: intake → prototype → freeze → scaffold → review → ship
- A red gate finding: file `lib/ui/views/train_shell/session_runner/session_runner_view.dart`,
  line 42, rule `enforce_design` check 5, "desktop layout missing — 0 of 1
  expected files"
- SARIF finding: partialFingerprints stable across runs → "is this the same
  failure as Tuesday?"
- Kit inventory: 18 wired, 5 partial (Stripe=stub, PayPal=stub, Vercel=stub)
- Ledger: stage → status, content_hash, outputs, timestamp

ACCESSIBILITY: WCAG 2.2 AA — target sizes, contrast on the signal palette,
screen-reader labels on native chrome. Gate states must be distinguishable by
shape/text, not colour alone.

OUT OF SCOPE (do not design): real payment/backend integration, the iOS
companion app (separate artifact), any feature not in the 20-surface inventory,
any rebranding of the loaded tokens.

INSTRUCTION — design the complete stage_shell for app_box's desktop app as an
interactive prototype: the six tab-groups populated for Evan, with the gate
badge in the stage surface showing pipeline phase and gate state. Go beyond the
basics — include every surface this shell implies, each with default/loading/
error/empty states. For anything underspecified here, flag it in comments
instead of guessing. Complete means: every tab-group has its root screen with
all states, using the loaded design tokens and the real data above.
```

**Gate — do not proceed until:** the shell renders with correct tab composition
for Evan, the gate badge shows pipeline state, vocabulary is canonical, and the
three gate surfaces are visually distinct from automated steps.

## 5. Stage prompts (run in order; one stage = one paste + its named files)

Every stage prompt ends with the same one-line reminder — *"Canonical
vocabulary per the foundation; respect the loaded design tokens; author the
`registry.json` entry and `surfaceId` while designing; flag underspecified
areas in comments instead of guessing."* It is deliberate robustness against
context drift.

### Stage 1 — Evan intake: the projects shell

**Paste with:** [`journeys/evan-founder-journey.md`](journeys/evan-founder-journey.md)
(phases 0–1) + `personas.md` (intake mode).

```
Design Evan's projects shell end-to-end, following his journey phases 0–1:
Intake (elicits, never generates — the brief is the client's words; every
registry entry traces to something the brief asked for) → New project (name,
brand, targets — targets shown as consequence: "iPhone and iPad layouts, no
desktop", not the flag) → Project list (empty state with wording, list with
pipeline phase per project, loading). The showcase app auto-launches on first
run — that launch IS the pitch. Reminder: canonical vocabulary per the
foundation; respect the loaded design tokens; author the registry entry while
designing; flag underspecified areas in comments.
```

**Gate:** intake form → new project → project list is clickable; empty state
has wording, not a blank surface; targets show consequence not flag.

### Stage 2 — Evan design: prototype directions + Gate 1

**Paste with:** `journeys/evan-founder-journey.md` (phases 2–3) +
`app-box-persona-design-brief.md` §5.2 (the three gates).

```
Design Evan's design shell: three directions in htmx, iterated, one approved.
The directions surface shows 3-up with one marked approved; the live preview
surface shows the selected direction at the active viewport width with a stale
indicator when the underlying design has moved. The approve surface (GATE 1)
is visually distinct from anything automated — it states what is being approved,
binds to the design hash, and requires explicit confirmation. An agent can
prepare and present; it cannot approve. Reminder: canonical vocabulary per the
foundation; respect the loaded design tokens; author the registry entry while
designing; flag underspecified areas in comments.
```

**Gate:** three directions → approve one → hash-bound confirmation; Gate 1
surface is visually distinct.

### Stage 3 — Evan build: run, findings, recovery + Gate 2

**Paste with:** `journeys/evan-founder-journey.md` (phases 4–5) +
`architecture.md` §5 (SARIF findings), §6 (state machine), §17 (licence).

```
Design Evan's build shell: the run view (idle → running → green → red, stage
timeline live, the licence precondition runs BEFORE the phase — never as a red
gate), the finding view (SARIF: file, line, rule, expected, the exact command
to reproduce — "is this the same failure as Tuesday?" via partialFingerprints),
and the recovery flow (red-gate → diagnose → fix → re-run, capped at ESC_LIMIT=3).
The accept surface (GATE 2) requires explicit confirmation of the green build.
Progress must be legible without reading a scrollback. Reminder: canonical
vocabulary per the foundation; respect the loaded design tokens; author the
registry entry while designing; flag underspecified areas in comments.
```

**Gate:** run → red gate → finding with file/line → fix → re-run is clickable;
Gate 2 surface is visually distinct; licence precondition is NOT a red gate.

### Stage 4 — Evan ship: targets + Gate 3

**Paste with:** `journeys/evan-founder-journey.md` (phase 6) +
`architecture.md` §17 (deployer).

```
Design Evan's ship shell: the targets surface (fastlane-ios, fastlane-android,
shorebird, cloudflare-pages — each showing wired/stubbed status; Vercel is a
stub and must NOT be advertised), and the confirm surface (GATE 3 — the
strictest). Gate 3 names the exact target, version and account and requires the
person to confirm that exact triple. It is the only gate that writes to the
outside world and cannot be undone. The confirmation must show the blast radius:
"this submits to the App Store under account X, version Y — irreversible."
Reminder: canonical vocabulary per the foundation; respect the loaded design
tokens; author the registry entry while designing; flag underspecified areas
in comments.
```

**Gate:** targets → confirm the triple is clickable; Gate 3 shows the blast
radius; Vercel is not offered.

### Stage 5 — Evan chat + settings

**Paste with:** `journeys/evan-founder-journey.md` (phases 7–8) +
`architecture.md` §15 (companion), §22 (intake CRUD).

```
Design Evan's chat shell (idle → streaming → tool-call — the chat drives the
pipeline via MCP; show a tool-call in progress with its target stage) and his
settings shell: credentials (which vault tier is active, stated on screen —
"stored in the macOS Keychain"), devices (paired companion, revoke), kits
(wired vs STUBBED for every kit — 18 wired, 5 partial; Stripe/PayPal/Vercel
labelled stub), and pair (QR pairing with TLS fingerprint). Reminder: canonical
vocabulary per the foundation; respect the loaded design tokens; author the
registry entry while designing; flag underspecified areas in comments.
```

**Gate:** chat shows streaming + tool-call; settings shows vault tier, kit
stub status, paired device.

### Stage 6 — Michelle: the evaluation journey

**Paste with:** [`journeys/michelle-buyer-journey.md`](journeys/michelle-buyer-journey.md)
(full file) + `personas.md` (Michelle).

```
Now design for Michelle — the 20-minute evaluation. Re-render the shell from
her perspective: the showcase app launches on install (the pitch — output
quality before she types anything); her first project form shows targets as
consequence not flag ("iPhone and iPad layouts, no desktop"); her build view
shows progress legibly without knowing what a gate is; her credential setup
offers BYO key → OS vault with the tier stated; and the "take your code and
leave" path is obvious — ordinary Stacked MVVM in her own repo, no export tier,
no runtime lock-in. The three gates read as "a human decision point" to someone
who has read no docs. Reminder: canonical vocabulary per the foundation;
respect the loaded design tokens; author the registry entry while designing;
flag underspecified areas in comments.
```

**Gate:** Michelle's path (install → showcase → first project → build → leave)
is clickable; empty states have wording; stubs are labelled.

### Stage 7 — Cross-cutting: the three gates as a system + empty-state wording

**Paste with:** `app-box-persona-design-brief.md` §5.2 (gates), §5.6 (red means
broken).

```
Final structural pass: design the three gates as a consistent system across the
shell — Gate 1 (design), Gate 2 (build), Gate 3 (ship). Each must be visually
distinct from automated steps, each must require explicit human confirmation,
and Gate 3 must show the blast radius. Design every empty state with real copy
(architecture.md §8: the htmx experiment found empty-state copy simply absent,
and the generator invented it — design it here instead). Verify: red never
appears for payment; stubs are never offered without labelling; state is never
inferred from paint (the FAB carries channel state, not "did the WebView
render"). Reminder: canonical vocabulary per the foundation; respect the loaded
design tokens; flag underspecified areas in comments.
```

**Gate:** all three gates visually consistent and distinct; every empty state
has copy; no red-for-money, no unlabelled stub, no paint-inferred state.

### Stage 8 — States & polish pass

```
Final pass across every screen designed so far: verify each has default,
loading, error, and empty states (page, section, and component level, with
retry actions); WCAG 2.2 AA contrast and target sizes on the signal palette;
gate states distinguishable by shape/text, not colour alone; no placeholder
copy anywhere; no off-palette hardcoded colours; no emoji icons. List in
comments any screen still missing a state.
```

**Gate:** the comment list from this pass is empty or every item has an owner.

## 6. Coverage check (run before calling the prototype done)

The prototype is complete when **no cell is blank** (or carries a justified
N/A) in this chain:

1. **Mode × Journey** — Evan (9 phases), Michelle (6 phases): every phase has
   ≥1 designed screen.
2. **Journey × Screen** — every journey step maps to a concrete screen; every
   screen traces back to a journey step (no orphans, no gaps).
3. **Screen × State** — every screen has default / loading / error / empty.
4. **Screen × Registry** — every screen has its `registry.json` entry and
   `surfaceId` authored.

Then export the artifact — the authored `registry.json` + the view/viewmodel
tree + the route table is the handoff to the freeze step.

## 7. Failure modes this program exists to prevent

- **Screens before viewport ladder** → layouts invented downstream; 1,600 lines
  were invented in `train_shell` alone (research: `headtohead-train-shell.md`).
- **Stubs unlabeled** → Michelle hits `UnimplementedError` on something the UI
  offered her. She abandons the product.
- **Red-for-money** → the licence check appears as a red gate; people learn to
  distrust red; red stops meaning broken.
- **State inferred from paint** → the FAB shows "did the WebView render" instead
  of channel state; a dead server shows a stale render during a client demo.
- **Empty states without copy** → the generator invents copy, or the surface is
  blank. Design the wording here.
- **Agent-minted approval** → a gate that an agent can pass is not a gate. The
  approval token is minted by a person or not at all.
- **Whole-app single prompt** → shallow, generic output. You have stages; use
  them.

## 8. Sources

**Repo (cited):** [`architecture.md`](../plans/architecture.md) §5, §6, §8, §11,
§12, §14, §15, §17, §22 · [`personas.md`](personas.md) ·
[`app-box-persona-design-brief.md`](app-box-persona-design-brief.md) ·
[`journeys/`](journeys/) · [`docs/research/`](../research/README.md) (9 docs).

**Research (consulted 2026-07-28):**
- `headtohead-train-shell.md` — 1,600 lines of layout invented; JSX translation
  captured 7/112 nodes.
- `stub-inventory.md` — 5/23 kits partial; Stripe/PayPal/Vercel throw.
- `remote-control-and-chat.md` — QR pairing, TLS fingerprint, OS vault,
  silently-green macOS failures.
- `prototype-language.md` — 159 JSX / 118 HTMX / 596 Flutter LOC per screen.
- `spine-findings.md` — `dep_hash` stale-green defect; `gen_freshness` holds.
- `competitors-and-pricing.md` — FlutterFlow/Adalo/Lovable pricing, per-seat
  backlash, BYO-key structural advantage.

---

*Maintenance: update this program when the persona set, shell model, surface
inventory, or `app-box-designer` capabilities change — in the same commit as the
SSOT change it mirrors. Last verified against repo truth: 2026-07-28.*
