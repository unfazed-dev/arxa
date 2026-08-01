# appbox — document index

**Start here.** Every document in this repo, what it settles, and when to read
it. Builder agents: read `plans/implementation/00-README.md` next, then your
assigned plan. Do not read the research unless your plan points you at it.

**Glossary SSOT:** [VOCABULARY.md](VOCABULARY.md) is the sacred single source
of truth for project vocabulary — every human and agent uses its terms, and
word-meaning conflicts resolve there.

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
| [design/brief.md](design/brief.md) | the consolidated design brief — requirements the pipeline consumes |
| [design/story-map.json](design/story-map.json) · [design/story_map.html](design/story_map.html) | the consolidated app's story map — 8 epics, 17 surfaces, 47 stories. Feeds `appbox-designer` directly |
| personas, journeys, flows (archived) | dead context — moved to `archives/design-v2/` in the consolidation (see [plans/consolidate-one-app-plus-daemon.md](plans/consolidate-one-app-plus-daemon.md)) |

---

## 2b. Delivered

Status map refreshed 2026-07-30 (full audit; the consolidation demolition —
commit `3460f01` — deleted plan 08's `app/` and plan 12's `companion/`, and
`appbox-studio/` + `appboxd/` are the shape going forward):

| state | plans |
|---|---|
| ✅ DELIVERED | 01 designer · 02 repo skeleton · 03 vendor tooling · 04 gates (10 gates, selftests + can-fail meta-test) · 05 emit_structure · 06 targets · 07 CRUD · 11 deployer · 13 verification tiers (Tier 1; 2/3 env-blocked) |
| ⚠️ PARTIAL | 09 prototype runtime (static server + viewmodel bundler; no embedded engine — `prototypeRuntime:"embedded"` is a dead config key) · 10 intake (headless yes; wizard UI died with `app/`) · 12 companion (security modules + tests survive in `appbox-studio/lib/security/`; no on-device pairing yet) · 14 dogfood (D1 design healthy; `appbox-studio/` not yet scaffolded from `designs/appbox-studio/`) |
| ◻ RESET | 08 desktop app — `appbox-studio/` is the hand-bootstrapped shell, awaiting the design freeze before scaffolding (by doctrine, no app UI before design approval) |

Also landed outside the plan track: `appboxd/` engine + LLM fabric (E1–E4),
memory module, offline licence + §17 deploy paywall — see
[plans/appbox-engine-llm-fabric.md](plans/appbox-engine-llm-fabric.md) and
[plans/appbox-memory-and-payment.md](plans/appbox-memory-and-payment.md).

## 2c. Consolidation — one app + daemon (2026-07-28)

| doc | contents |
|---|---|
| [plans/consolidate-one-app-plus-daemon.md](plans/consolidate-one-app-plus-daemon.md) | **the shape going forward:** one Stacked app (`appbox-studio/`, web/macOS/iOS/Android) + `appboxd/` daemon; full parity; target detection; provenance-bound approvals; self-host remote (no Totem Cloud); licence-only, pay at first deploy. Supersedes `merge-companion-into-one-flutter-project.md`, amends §17 |
| [design/story-map.json](design/story-map.json) · [design/brief.md](design/brief.md) · [design/story_map.html](design/story_map.html) | the consolidated app's story map — 8 epics, 17 surfaces, 47 stories, R1 Dogfood / R2 Anywhere / R3 Delight. Feeds `appbox-designer` directly |
| [moodboards/](moodboards/) | design references: `builder-and-pipeline.md`, `ai-builders-and-flows-canvas.md`, `companion-and-macos-polish.md` + `shots/` — produced by `skills/appbox-moodboarder/` (story-mapper → moodboarder → designer; `intake.moodboard` surface) |

---

## 3. Plans — the decisions

| doc | contents |
|---|---|
| [plans/architecture.md](plans/architecture.md) | §1–22. The spine, targets, structure contract, gates, payment, deployer, CRUD, designer, playbooks, build order, intake |
| [plans/appbox-engine-llm-fabric.md](plans/appbox-engine-llm-fabric.md) | E1–E4: vault keys, loopback LLM gateway, deterministic stage-runner, model fabric — built 2026-07-30, corrections appended |
| [plans/appbox-memory-and-payment.md](plans/appbox-memory-and-payment.md) | M1–M2 memory module (appboxd-owned, hybrid write path) + P1–P3 monetization (flat licence, watermark free tier, offline signed licence, cloud parked) |
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
| §19 | `appbox-designer` is an **MIT fork**, not a clean-room rewrite |
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
| `skills/appbox-designer/` | ✅ **DELIVERED** (plan 01). The design stage, in this repo. Symlinked to `~/.agents/skills/appbox-designer`. Run `appbox design selftest <dir>` and `appbox design doctor` |
| `skills/appbox-story-mapper/` | ✅ **DELIVERED** (MIT adaptation). Pre-design elicitation: Epic→Feature→Story map → `docs/design/brief.md` + `story-map.json` + `story_map.html`, feeding `appbox-designer` directly (intake bypassed; the brief's surface table is the 10.7 traceability source). Run `appbox emit story-map --self-test` |
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
**Rejected — gating appbox to kit-holders**, which deletes the buyer persona.

**`dependencyMode` is a config value from day one** — see O3.

### ✅ O3 — publishing the kit — **deferred, and non-breaking whenever it happens**

Publishing is a **config flip plus a migration command**, not a
re-architecture, because `config/appbox.config.json` carries
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
