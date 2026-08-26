# Scaffold shell — design brief

Fills the flow gap at `flows.json:63-67` (`design.freeze → build.loop`,
`trigger: "Scaffold"`) with no receiving screen today. Authority for every
decision citation below is `docs/plans/scaffold-shell-kit-picker-decisions.md`
(D-numbers). Do not restate the moodboard (`docs/moodboards/scaffold-stage.md`)
or `config/kit-registry.json`'s 24 kits here — reference by id/tier only.

**Citation correction (flag for review):** the task brief for this document
cited D12–16 and D29 as governing kit-picker readiness/credentials/add-remove
semantics. Those decisions cover post-scaffold iteration/regen (D12), deploy
engine unification (D13), OAuth account connections (D14), studio's own
Supabase/Google/Apple auth (D15), sign-in gating (D16), and BYOK LLM-key
custody (D29) — none govern the kit picker. The decisions that actually do:
**D2** (removal + forced fallback), **D4** (three provenance tiers), **D5**
(dependency resolution / auto-include), **D6** (readiness badges, inform-only,
hard-block only at deploy), **D8** (`kit-manifest.json` sidecar). Used
throughout below. D24/D31/D32 for the non-goals section were correct as given.

## Layout Template

`main_shell_view.html` mounts only header+footer — a scaffold shell needs its
own per-shell composition file (sibling to `design/_shared.html`), not a
change to the shared mount. Five named panels, never referenced by position:

```
grid-template-areas:
  "header  header  header"
  "compose main    activity"
  "footer  footer  footer";
grid-template-columns: minmax(240px,280px) 1fr minmax(280px,340px);
grid-template-rows: auto 1fr auto;
```

Any panel may render nothing (`display:none`, area collapses). Each panel
exposes up to five sections (`top`, `side-start`, `body`, `side-end`,
`bottom`); only `body` is required. `mini_panel` is a widget nested inside a
panel's section, not a sixth panel — the moodboard's panel list
(header/composer/activity/mini/footer) is wrong on this point; the inventory
report's five-panel table is authoritative.

## (a) Scaffold kit picker — `scaffold.picker`

**States:** empty (no prior selection — apply "essentials" defaults per D5's
auto-include, not a blank grid), loading (registry + credentials-check
fetch), error (registry/catalog fetch failure), success (grid interactive),
and **not-entitled/signed-out** — scaffold is a paid, identity-gated action
(D16, D17, D18, D27); route through the existing `workspace.credentials`
screen for identity, don't invent an inline auth surface here.

**Badge model — three independent axes, do not collapse into one badge:**
1. Provenance (D4): declared / inferred / requested, always labeled.
2. Kit maturity: `config/kit-registry.json`'s `phase` field (stable /
   native-first / native-first-partial / n/a) — orthogonal to provenance.
3. Credentials readiness (D6): driven by `credentials check --module kit/<x>`
   against `config/credentials.catalog.json`; missing required keys render a
   "get key" deep-link. Inform-only here — never blocks the picker, only
   blocks at the deploy gate.

Do not conflate axis 3 with BYOK LLM-key custody (D26/D29, Anthropic/OpenAI/
Gemini/DeepSeek/Moonshot/Z.ai) — different credential system, different
screen.

Add/remove: additive by default; removing a design-declared kit surfaces a
warning listing the declaring screens and forces a seed-backed fallback stub
so the build still compiles (D2) — no hard locks. Grouping into 3–4 tiers
(moodboard's Core/Integrations/Platform/Advanced) is a UI layout suggestion,
not decision-backed — treat as a visual-only default, not a data contract.

**Kits field:** none/omitted on this screen's own registry entry — zero
`kits` matches exist in `designs/arxa-studio/models/screens_model/
registry.json` today (studio UI, not the generated app) and per
`kit-selection-mechanics.md` §1, `kits` is only declared on a screen when the
*built app* needs the module.

## (b) Scaffold progress/gate — `scaffold.run`

**States:** empty (queued, not yet started), loading (running), error
(per-surface failure list — which screens/kits failed and why), success
(manifest receipt: resolved kit set, per-surface pass/fail, link to gate
confirm). No not-entitled state — entitlement is checked at `scaffold.picker`
before this screen is reachable.

D7 defines the run surface as `scaffold.picker → scaffold.run → build.loop`
and requires deleting `build.loop`'s existing scaffold fixture row
(`run.en.json:58-70`) so the stage isn't represented twice in the flow.

**Decision overrides moodboard here:** `emit_structure.dart`/`scaffold.dart`
are a deterministic, synchronous, no-LLM, no-subprocess, byte-identical
transform (D24 boundary — no build farm, nothing long-running). The
moodboard's per-kit spinner-to-check row list and animated ring gauge model a
multi-minute CI-style rollout that does not exist here. This screen is a fast
pass/fail receipt with a per-surface manifest, not a live multi-stage
progress dashboard — style it accordingly (a settling/verdict transition, not
a sustained progress view).

**Kits field:** none/omitted — same reasoning as (a); this screen consumes
the resolved `kit-manifest.json` (D8) as input, it does not declare kits
itself.

## (c) Scaffold shell chrome integration

- **Header:** stage label ("Scaffold"), entitlement/account state.
- **Composer:** pinned-context chips carry "kits enabled" state once the
  picker gate closes (moodboard pattern 5) — read-only summary, not an edit
  surface; editing happens back in `scaffold.picker`.
- **Main:** hosts `scaffold.picker` or `scaffold.run` per current sub-stage.
- **Activity:** per-surface pass/fail list for `scaffold.run`, sourced from
  the manifest receipt — reuse the existing carousel-of-views pattern rather
  than adding a panel.
- **Footer:** stage progress breadcrumb (Design → Scaffold → Build); no new
  timeline widget needed for a synchronous transform.

**Kits field:** none/omitted on chrome-level registry entries — same
reasoning as (a)/(b).

## Non-goals

- No build farm; Totem never compiles or ships binaries — hosted pipeline
  stops at scaffold output (D24).
- No managed Supabase kit in v1 — BYO-Supabase only (D31).
- No credits/metered inference in v1 — BYO-LLM key only (D32).
