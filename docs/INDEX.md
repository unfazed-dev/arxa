# app_box — document index

**Start here.** Every document in this repo, what it settles, and when to read
it. Builder agents: read `plans/implementation/00-README.md` next, then your
assigned plan. Do not read the research unless your plan points you at it.

**Owner:** Totem Labs. **Founder:** Evan F Pierre Louis.

---

## 1. If you are a builder agent

| read | when |
|---|---|
| [plans/implementation/00-README.md](plans/implementation/00-README.md) | **first, always** — the execution contract |
| [plans/implementation/](plans/implementation/) `NN-*.md` | your assigned plan, in full, before touching anything |
| [plans/architecture.md](plans/architecture.md) | only the § your plan cites |

**You are not asked to decide anything.** Every decision is already made and
recorded. If your plan is ambiguous, stop and report — do not choose.

---

## 2. Design — what we are building and for whom

| doc | contents |
|---|---|
| [design/README.md](design/README.md) | index, reading order, standing notes (canonical language, citation rules) |
| [design/personas.md](design/personas.md) | **Evan** (founder, 4 modes) and **Michelle** (indie iOS+Android dev, the buyer) — proto-personas with JTBD, frustrations, design-must-get-right |
| [design/app-box-persona-design-brief.md](design/app-box-persona-design-brief.md) | handoff brief: actor model, cross-cutting constraints (three gates, credential tiers, stub honesty, viewport derivation), pinned-vs-open, the 20-surface inventory that seeds `registry.json` |
| [design/app-box-design-generation-brief.md](design/app-box-design-generation-brief.md) | design-generation program: viewport ladder, foundation prompt, per-mode/persona stage prompts, coverage check — for driving `app-box-designer` |
| [design/journeys/evan-founder-journey.md](design/journeys/evan-founder-journey.md) | Evan: full pipeline journey (intake → design → freeze → build → ship → remote → CRUD) |
| [design/journeys/michelle-buyer-journey.md](design/journeys/michelle-buyer-journey.md) | Michelle: 20-minute evaluation (install → showcase → first project → build → evaluate-and-leave) |
| [design/flows/README.md](design/flows/README.md) | flow-library layout, flow-doc template, conventions |
| [design/flows/research-findings.md](design/flows/research-findings.md) | graded [V]/[A]/[U] synthesis from `docs/research/` — the evidence behind the flows |
| [design/flows/evan-founder/_index.md](design/flows/evan-founder/_index.md) | Evan's 15 flows across 6 tab-group shells |
| [design/flows/michelle-buyer/_index.md](design/flows/michelle-buyer/_index.md) | Michelle's 6 flows across 5 tab-group shells |

---

## 2b. Delivered

| plan | what exists now |
|---|---|
| [01 — designer](plans/implementation/01-designer.md) | `skills/app-box-designer/` — 17 built-in skills, the viewport ladder (`runtime/ladder.json` + `references/viewport-ladder.md`), the authored-layer contract (`references/app-architecture.md`), `built-in-skills/declare-structure.md`, and a 14-check selftest with a negative case. Five plan defects found and recorded in the plan's Amendments section. |

**Open gap carried into plan 06:** nothing yet derives the active rung list from
a project's `--targets`. The ladder is passed by hand until it lands.

## 2c. Consolidation — one app + daemon (2026-07-28)

| doc | contents |
|---|---|
| [plans/consolidate-one-app-plus-daemon.md](plans/consolidate-one-app-plus-daemon.md) | **the shape going forward:** one Stacked app (`appbox/`, web/macOS/iOS/Android) + `appboxd/` daemon; full parity; target detection; provenance-bound approvals; self-host remote (no Totem Cloud); licence-only, pay at first deploy. Supersedes `merge-companion-into-one-flutter-project.md`, amends §17 |
| [design/story-map.json](design/story-map.json) · [design/brief.md](design/brief.md) · [design/story_map.html](design/story_map.html) | the consolidated app's story map — 8 epics, 17 surfaces, 47 stories, R1 Dogfood / R2 Anywhere / R3 Delight. Feeds `app-box-designer` directly |
| [moodboards/](moodboards/) | design references: `builder-and-pipeline.md`, `ai-builders-and-flows-canvas.md`, `companion-and-macos-polish.md` + `shots/` — produced by `skills/app-box-moodboarder/` (story-mapper → moodboarder → designer; `intake.moodboard` surface) |

---

## 3. Plans — the decisions

| doc | contents |
|---|---|
| [plans/architecture.md](plans/architecture.md) | §1–22. The spine, targets, structure contract, gates, payment, deployer, CRUD, designer, playbooks, build order, intake |
| [plans/feature-crud.md](plans/feature-crud.md) | the operational CRUD contract + the round-trip test |
| [plans/stub-remediation.md](plans/stub-remediation.md) | the three test tiers and the `verification` field |
| [plans/implementation/](plans/implementation/) | step-by-step build plans |

### Architecture sections worth knowing by number

| § | settles |
|---|---|
| §11 | `--targets` is platform-only; viewports derive; freeze at 390/744/1280 |
| §12 | human gates; the design skills do not solve viewports; no Tailwind flag |
| §13 | the htmx producer is already MVVM — 8,454 lines the freeze discards |
| §14 | authored `registry.json` → derived tree → generated `structure.json` |
| §15 | the iOS companion owns the prototype view; the FAB carries channel state |
| §16 | targets drive form-factor emission (macOS ⇒ 3 files, not 5) |
| §17 | vendor the kit at a pinned SHA; payment gate at builder; deployer |
| §18 | CRUD writes the registry, never scaffolded Dart; delete is the gap |
| §19 | `app-box-designer` is an **MIT fork**, not a clean-room rewrite |
| §21 | build order |
| §22 | intake is an optional phase — **elicits, never generates** |

---

## 4. Research — the evidence

Read [research/README.md](research/README.md) for the ordered index. Nine
documents. Every claim was measured by running the thing.

**The three findings that shaped everything:**

1. **The prototype must carry structure, not pixels.** No producer captures
   tablet/desktop; ~1,600 lines of layout in `train_shell` alone were invented.
2. **`design/new-htmx` is already MVVM** and the freeze throws it away.
3. **A gate that cannot fail is not a gate.** `dep_hash` on mtime, a self-test
   asserting the defective value, an asset check that verified strings instead
   of resolving paths, a drift check guarded on a file htmx does not have —
   every one green.

---

## 5. Where the source material lives

Copy from these. **Do not rewrite what already exists.**

| path | what to take |
|---|---|
| `skills/app-box-designer/` | ✅ **DELIVERED** (plan 01). The design stage, in this repo. Symlinked to `~/.agents/skills/app-box-designer`. Run `./selftest.sh` and `node runtime/doctor.mjs` |
| `skills/app-box-story-mapper/` | ✅ **DELIVERED** (MIT adaptation). Pre-design elicitation: Epic→Feature→Story map → `docs/design/brief.md` + `story-map.json` + `story_map.html`, feeding `app-box-designer` directly (intake bypassed; the brief's surface table is the 10.7 traceability source). Run `python3 scripts/generate_story_map.py --self-test` |
| `~/.agents/skills/kimi-design-htmx` | the fork base — **already forked; do not re-copy** |
| `~/.agents/skills/kimi-design-flutter` | viewport archetypes (390/744) — doctrine only |
| `/Volumes/developer_ssd/Developer/totem_labs/stacked_kit/tools` | `pipeline.sh` 1018, gates, `emit_*`, `kit_registry` |
| `…/stacked_kit/showcase_app` | 124 Dart files / 8,626 lines — the desktop app base |
| `…/stacked_kit/deploy` | wired fastlane + shorebird + CF Pages |
| `/Volumes/developer_ssd/Developer/factory/flutter-crew` | `stages/` and `skills/{designer,builder,deployer,review,tester}` |
| `/Volumes/developer_ssd/Developer/applications/p2/design/new-htmx` | the working htmx producer |

---

## 6. Decisions

### ✅ O1 — how scaffolded apps get their kit dependencies — **SETTLED: scoped vendoring**

Scaffolded apps depended on ~39 **private** `stacked_kit` git packages, which
no buyer can pull. Resolved by **vendoring only the kits an app actually uses**,
derived from targets + selected capabilities.

Measured: the whole kit is **578 files / 57,537 lines / 2.3 MB** of `lib/`
source — **≈1.7 MB** excluding `showcase_app`, against a 4.2–4.6 MB
hello-world Flutter binary. The bloat objection does not survive measurement.

**Rejected — a licence-gated private pub registry** (`unpub` + `unpub_auth`,
`dart pub token add`). Technically real and commercially standard, but the
buyer's shipped app stops resolving dependencies when her licence lapses. That
is runtime lock-in — the incumbent's one-way-export trap in a different costume
— and it contradicts journey J10 and Michelle's second trust condition.
**Rejected — gating app_box to kit-holders**, which deletes the buyer persona.

**`dependencyMode` is a config value from day one** — see O3.

### ✅ O3 — publishing the kit — **deferred, and non-breaking whenever it happens**

Publishing is a **config flip plus a migration command**, not a
re-architecture, because `config/app-box.config.json` carries
`dependencyMode: "vendored" | "hosted"` from the start.

| on publish | outcome |
|---|---|
| already-delivered apps | **keep working untouched** — vendored code has no external dependency |
| new apps | `dependencyMode: "hosted"`, ordinary version constraints |
| the two populations | coexist indefinitely; no forced migration |
| scoping logic (which kits does this app need) | **carries over unchanged** |
| pinning discipline | SHA-pinning becomes version-pinning — `pubspec.lock` does it natively |
| freshness check | becomes `pub outdated` — cheaper |
| the copy step and path-dep rewriting | the only work discarded |
| tooling vendoring (§17) | collapses to a shim, deleted rather than maintained |

**The ordering is asymmetric and favours vendoring first.** Vendored → hosted is
non-breaking. Registry → hosted is not: apps built against a registry need
migration and break on licence lapse in the meantime.

**Vendoring survives publication as an explicit mode**, because it is what makes
"take your code and leave" bulletproof. It becomes a feature, not legacy.

**Concrete reason not to publish yet, independent of strategy:** per
`research/stub-inventory.md`, Stripe, PayPal, both auth providers, both map
providers and Vercel all throw `UnimplementedError`. Publishing 21 packages in
that state buys a bad first impression and immediate semver obligations on an
API that is not stable.

### 🔴 O2 — still open

| # | question | why it blocks |
|---|---|---|
| O2 | Licence model and price point | `research/competitors-and-pricing.md` has the comparables; no number chosen |
