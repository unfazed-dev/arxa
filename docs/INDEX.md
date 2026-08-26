# arxa — document index

**Start here.** Every document in this repo, what it settles, and when to read
it. Builder agents: read `plans/implementation/00-README.md` next, then your
assigned plan. Do not read the research unless your plan points you at it.

**Glossary SSOT:** [VOCABULARY.md](VOCABULARY.md) is the sacred single source
of truth for project vocabulary — every human and agent uses its terms, and
word-meaning conflicts resolve there.

**Platform laws:** [liquid-glass-allowlist.md](liquid-glass-allowlist.md) is
the **liquid-glass law** (native glass on iOS/macOS 26+: allowlist,
composition rules, deselect protocol — enforced by kit gates + arxa-lint);
[m3e-law.md](m3e-law.md) is its Android sibling for Material 3 Expressive.
The chrome scaffold (`ArxaKitChromeScaffold`) is both laws' reuse unit.

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
| [intake/brief.md](intake/brief.md) | the consolidated design brief — requirements the pipeline consumes |
| [intake/story-map.json](intake/story-map.json) · [intake/story_map.html](intake/story_map.html) | the consolidated app's story map — 8 epics, 17 surfaces, 47 stories. Feeds `arxa-designer` directly |
| personas, journeys, flows (archived) | dead context — moved to `archives/design-v2/` in the consolidation (see [plans/consolidate-one-app-plus-daemon.md](plans/consolidate-one-app-plus-daemon.md)) |

---

## 2b. Delivered

Status map refreshed 2026-08-05 (plan rows still keyed to the 2026-07-30 full
audit; the consolidation demolition — commit `3460f01` — deleted plan 08's
`app/` and plan 12's `companion/`, and `arxa-studio/` + `arxa/` are the
shape going forward):

| state | plans |
|---|---|
| ✅ DELIVERED | 01 designer · 02 repo skeleton · 03 vendor tooling · 04 gates (10 gates, selftests + can-fail meta-test; all 10 ported to Dart `a119460`) · 05 emit_structure · 06 targets · 07 CRUD · 11 deployer (vercel + cloudflare-workers real since 2026-08-01, `261b2ad`/`93cf1ef`) · 13 verification tiers (Tier 1; 2/3 env-blocked) |
| ⚠️ PARTIAL | 09 prototype runtime (static server + viewmodel bundler; no embedded engine — `prototypeRuntime:"embedded"` is a dead config key, still unreferenced 2026-08-05) · 10 intake (headless yes; the wizard UI lives again as the nine `intake.*` surfaces in the studio design, `designs/arxa-studio/structure.json`, served by the design server) · 12 companion (security modules + tests survive in `arxa-studio/lib/security/`; no on-device pairing yet) · 14 dogfood (D1 design healthy; `arxa-studio/` not yet scaffolded from `designs/arxa-studio/`) |
| ◻ RESET | 08 desktop app — `arxa-studio/` is the hand-bootstrapped shell, awaiting the design freeze before scaffolding (by doctrine, no app UI before design approval; no `approval.lock` exists as of 2026-08-05) |

Also landed outside the plan track: `arxa/` engine + LLM fabric (E1–E4),
memory module, offline licence + §17 deploy paywall — see
[plans/arxa-engine-llm-fabric.md](plans/arxa-engine-llm-fabric.md) and
[plans/arxa-memory-and-payment.md](plans/arxa-memory-and-payment.md).
Since that audit: the arxa lens full probe port (2026-07-31, `4f9c458`) and
the retirement of all Python/bash/Node tooling; real `vercel` +
`cloudflare-workers` deploy targets with opt-in live smoke tests (2026-08-01);
port-tested maps providers (2026-08-01, `6b0c447`); and the 2026-08-02→05
design-shell wave — views/flows/proto lenses with inter-flow hand-offs,
state/feedback chips, docked shell panels, canvas widget editing, and the
per-screen reveal-drawer (Composer/Tools/Logic), with the views-lens
components container added and then removed (`7babc79`). The scaffold shell
(`scaffold.picker` / `scaffold.run`) joined the studio design in the same
wave.

## 2c. Consolidation — one app + daemon (2026-07-28)

| doc | contents |
|---|---|
| [plans/consolidate-one-app-plus-daemon.md](plans/consolidate-one-app-plus-daemon.md) | **the shape going forward:** one Stacked app (`arxa-studio/`, web/macOS/iOS/Android) + `arxa/` daemon; full parity; target detection; provenance-bound approvals; self-host remote (no Totem Cloud); licence-only, pay at first deploy. Supersedes `merge-companion-into-one-flutter-project.md`, amends §17 |
| [intake/story-map.json](intake/story-map.json) · [intake/brief.md](intake/brief.md) · [intake/story_map.html](intake/story_map.html) | the consolidated app's story map — 8 epics, 17 surfaces, 47 stories, R1 Dogfood / R2 Anywhere / R3 Delight. Feeds `arxa-designer` directly |
| [moodboards/](moodboards/) | design references: `builder-and-pipeline.md`, `ai-builders-and-flows-canvas.md`, `companion-and-macos-polish.md` + `shots/` — produced by `skills/arxa-moodboarder/` (story-mapper → moodboarder → designer; `intake.moodboard` surface) |

---

## 3. Plans — the decisions

| doc | contents |
|---|---|
| [plans/architecture.md](plans/architecture.md) | §1–22. The spine, targets, structure contract, gates, payment, deployer, CRUD, designer, playbooks, build order, intake |
| [plans/arxa-engine-llm-fabric.md](plans/arxa-engine-llm-fabric.md) | E1–E4: vault keys, loopback LLM gateway, deterministic stage-runner, model fabric — built 2026-07-30, corrections appended |
| [plans/arxa-memory-and-payment.md](plans/arxa-memory-and-payment.md) | M1–M2 memory module (arxa-owned, hybrid write path) + P1–P3 monetization (flat licence, watermark free tier, offline signed licence, cloud parked) |
| [plans/feature-crud.md](plans/feature-crud.md) | the operational CRUD contract + the round-trip test |
| [plans/stub-remediation.md](plans/stub-remediation.md) | the three test tiers and the `verification` field |
| [plans/implementation/](plans/implementation/) | step-by-step build plans (frozen historical, 2026-07-31) |

### The 2026-07-31 → 2026-08-05 wave (reconciled 2026-08-05 against `ls docs/plans/`)

| doc | contents |
|---|---|
| [plans/arxa-dart-only-tooling.md](plans/arxa-dart-only-tooling.md) | **COMPLETE** — Python/bash/Node tooling retired to `archives/tooling-pre-dart/`; one `arxa` Dart binary. Rust-port challenge reaffirmed 2026-08-21 (addendum) |
| [plans/rust-port-closure-and-surgical-lens.md](plans/rust-port-closure-and-surgical-lens.md) | decisions locked 2026-08-21 — Rust port CLOSED; evidence bundle + drill-down compare, capture manifest, bounded auto-loop, semantic dictionary + provenance gate (prefix now `arxa-`, see amendment), read-only arxa in using-sessions + `lens eval`, feedback dial + Supabase, a11y toolbox island — **amended 2026-08-23**: feedback dial becomes the Design Dial (two modes, Draft Overlay + manual Publish, Share Link guest access, pin kanban) |
| [plans/arxa-harness-and-distribution.md](plans/arxa-harness-and-distribution.md) | decisions locked 2026-08-21 — arxa brand + `arxa-` prefix; dedicated harness forked from dsh with Pi DNA + delegated engine; Studio/BYO/operator flavors; emit-boundary payment gate; stub skills + `arxa brief`; engine-owned memory; Clients/stages panel; portable core first |
| [plans/arxa-lens-full-port.md](plans/arxa-lens-full-port.md) | **COMPLETE** (2026-07-31, `4f9c458`) — full probe-runner port onto the arxa lens; skills dartified |
| [plans/canvas-redesign-contract.md](plans/canvas-redesign-contract.md) | **SUPERSEDED 2026-07-30** — retired rail/mini-rail chrome contract |
| [plans/design-shell-canvas-redesign.md](plans/design-shell-canvas-redesign.md) | **SUPERSEDED 2026-07-30** — chrome decision record replaced by the panel architecture |
| [plans/merge-companion-into-one-flutter-project.md](plans/merge-companion-into-one-flutter-project.md) | **SUPERSEDED 2026-07-28** by `consolidate-one-app-plus-daemon.md` |
| [plans/design-viewer-per-lens-hover-and-flow-mode.md](plans/design-viewer-per-lens-hover-and-flow-mode.md) | per-lens hover toolbars + flow mode (Slice 7 shipped 2026-08-02) |
| [plans/htmx-no-reload-interaction.md](plans/htmx-no-reload-interaction.md) | no-reload interaction; Lever 1 landed 2026-08-02, levers 2–3 specified |
| [plans/media-3d-animation-games.md](plans/media-3d-animation-games.md) | **superseded 2026-08-02** — studio rename + media/3D/game islands; its demo Portalo replaced by the ecommerce project |
| [plans/views-explode-lens-interflow-and-shell-panels.md](plans/views-explode-lens-interflow-and-shell-panels.md) | views-lens rows, inter-flow hand-offs, two-axis state/feedback, shell panels, kit mirror; **Slice 4 (explode column) superseded 2026-08-05** — container removed |
| [plans/design-derived-contract-probes.md](plans/design-derived-contract-probes.md) | approved 2026-08-03 — probes for the apps arxa builds, not just the studio |
| [plans/dock-bounce-headless-chrome.md](plans/dock-bounce-headless-chrome.md) | investigation — dock bounce NOT REPRODUCED headless; `--visible` bounces at 780ms |
| [plans/flows-answers-ssot-and-canvas-undo.md](plans/flows-answers-ssot-and-canvas-undo.md) | `answers.json` as flows SSOT + canvas undo/redo; closes task #30 |
| [plans/intake-build-project-aware.md](plans/intake-build-project-aware.md) | intake + build go project-aware; Slice A in flight, Slice B superseded by the slice-b plan |
| [plans/one-browser-engine-studio-probes-to-lens.md](plans/one-browser-engine-studio-probes-to-lens.md) | approved 2026-08-03 — one browser engine; studio probes onto the lens CDP stack |
| [plans/slice-b-story-map-moodboard-prd-adr.md](plans/slice-b-story-map-moodboard-prd-adr.md) | Slice B — story-map + moodboard project wiring + PRD/ADR emission |
| [plans/smart-panels-top-body-bottom.md](plans/smart-panels-top-body-bottom.md) | **delivered** — one panel/section vocabulary; SSOT `_integration_panels.md` |
| [plans/widget-panel-vocabulary-reconciliation.md](plans/widget-panel-vocabulary-reconciliation.md) | decisions locked 2026-08-03 — one widget/panel vocabulary across designer/scaffolder/builder |
| [plans/accounts-auth-and-provisioning.md](plans/accounts-auth-and-provisioning.md) | studio sign-in, OAuth account connections, provisioning flows |
| [plans/byok-llm-key-custody.md](plans/byok-llm-key-custody.md) | BYOK LLM key custody (D29; CORS-verified research) |
| [plans/canvas-tiles-interact-in-place.md](plans/canvas-tiles-interact-in-place.md) | views/flows tiles interactive to their own screen (landed `06b752b`) |
| [plans/composer-action-integrity.md](plans/composer-action-integrity.md) | proposed — composer action integrity defect class |
| [plans/deploy-engine-unification.md](plans/deploy-engine-unification.md) | D13 — unify deploy engine: kit runtime + arxa governance |
| [plans/distribution-and-platforms.md](plans/distribution-and-platforms.md) | D23 — v1 surfaces: macOS app+daemon, iOS/Android controller, Totem-hosted web |
| [plans/entitlement-backend-runbook.md](plans/entitlement-backend-runbook.md) | D17/D18 backend half as a deployment runbook — Supabase schema, `/activate` contract, the exact JWT claims the local verifier expects |
| [plans/filmstrip-viewport-sync.md](plans/filmstrip-viewport-sync.md) | filmstrip ↔ viewport two-way sync (views lens) |
| [plans/handoff-inspector-viewmodel.md](plans/handoff-inspector-viewmodel.md) | the `design_facade.js` viewmodel contract for the inspector pane (D14–D17) |
| [plans/handoff-reveal-drawer-remaining.md](plans/handoff-reveal-drawer-remaining.md) | **DONE 2026-08-05** — all five reveal-drawer increments merged |
| [plans/increment-3-edit-arming-resize-handles.md](plans/increment-3-edit-arming-resize-handles.md) | edit arming + resize handles; backend + arming shipped, sizing modes blocked on a CSS gap |
| [plans/monetization-and-entitlements.md](plans/monetization-and-entitlements.md) | Free/Pro/Scale tiers + entitlement backend; **D17/D18 move the paywall from deploy to scaffold** — amends §17 |
| [plans/post-scaffold-iteration.md](plans/post-scaffold-iteration.md) | how a project changes after the first `emit scaffold`; regen/ownership boundaries |
| [plans/provenance-routed-text-editing-and-font-menu.md](plans/provenance-routed-text-editing-and-font-menu.md) | increment 4 — provenance-routed copy edits + the 4-font menu |
| [plans/scaffold-panel-size-inert.md](plans/scaffold-panel-size-inert.md) | finding — panel-size grip inert on both scaffold screens |
| [plans/scaffold-picker-phase3-verification.md](plans/scaffold-picker-phase3-verification.md) | scaffold.picker phase-3 verification (lint + lens + live routes) |
| [plans/scaffold-run-composer-checker-review.md](plans/scaffold-run-composer-checker-review.md) | review of the (unshipped) `composer-action-check.js` |
| [plans/scaffold-run-handoff-findings.md](plans/scaffold-run-handoff-findings.md) | scaffold.run authoring handoff findings |
| [plans/scaffold-shell-kit-picker-decisions.md](plans/scaffold-shell-kit-picker-decisions.md) | the grilling-round-2 decision log (D1–D37) — governs kit picker, monetization, accounts, BYOK |
| [plans/scaffold-shell-spine-verification.md](plans/scaffold-shell-spine-verification.md) | scaffold shell spine behavioural verification |
| [plans/scaffold-shell-viewmodel-context-binding.md](plans/scaffold-shell-viewmodel-context-binding.md) | `c.*` undefined root cause; supersedes the wiring-gap hypothesis |
| [plans/screen-reveal-drawer-composer-tools-logic.md](plans/screen-reveal-drawer-composer-tools-logic.md) | **shipped 2026-08-05** — per-screen reveal-drawer (Composer/Tools/Logic); components container removed |
| [plans/viewer-theme-cluster-and-bg-fix.md](plans/viewer-theme-cluster-and-bg-fix.md) | topbar appearance cluster + canvas bg fix |
| [plans/widget-editing-autolayout-and-manager.md](plans/widget-editing-autolayout-and-manager.md) | widget editing grill record (auto-layout resize, text/font/colour); 2-col-split section superseded by the reveal-drawer plan |

Non-doc artifacts in `docs/plans/` (working files of the scaffold-shell
sessions, not decisions): `composer-action-check.js`, `handoff-l10n-w7.json`,
`scaffold-composer-guard.patch`, `scaffold-routes.patch`,
`scaffold-picker-thread-keys-helper.py`, `increment-3-evidence/`.

### Architecture sections worth knowing by number

| § | settles |
|---|---|
| §11 | `--targets` is platform-only; viewports derive; freeze at 390/744/1280 |
| §12 | human gates; the design skills do not solve viewports; no Tailwind flag |
| §13 | the htmx producer is already MVVM — 8,454 lines the freeze discards |
| §14 | authored `registry.json` → derived tree → generated `structure.json` |
| §15 | the iOS companion owns the prototype view; the FAB carries channel state |
| §16 | targets drive form-factor emission (macOS ⇒ 3 files, not 5) |
| §17 | vendor the kit at a pinned SHA; payment gate (placement since amended to pay-at-scaffold — `monetization-and-entitlements.md` D17/D18); deployer |
| §18 | CRUD writes the registry, never scaffolded Dart; delete is the gap |
| §19 | `arxa-designer` is an **MIT fork**, not a clean-room rewrite |
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

**Later additions:**

- [research/deterministic-screenshot-capture.md](research/deterministic-screenshot-capture.md)
  — what actually guarantees a stable screenshot: `document.fonts.ready`'s
  spec-documented gap, why double-rAF is a heuristic and not a contract, which
  animation types `getAnimations()` cannot reach (SMIL, GIF/APNG, cross-origin
  iframes), why CDP virtual time is excluded, and the capture-until-two-match
  stability loop that backstops all of it. Every claim graded HOT/WARM/COLD
  against a primary source. Feeds the W1 amendment in
  [plans/rust-port-closure-and-surgical-lens.md](plans/rust-port-closure-and-surgical-lens.md).
- [research/warm-vs-cold-chrome-determinism.md](research/warm-vs-cold-chrome-determinism.md)
  — the question no official source answers: does a REUSED Chrome render
  byte-identically to a freshly-launched one? It gates the daemon-owns-a-browser
  plan, because a speed win that changes pixels is worthless to a tool that
  exists to compare them. Measured, not looked up: three page kinds chosen for
  the caches that warm up (font-shaping, GPU raster/shader, flat control), four
  arms, negative controls proving the instrument can see a 1-in-1024000-pixel
  difference, a render-richness floor so a blank page cannot pass by drawing
  nothing, and a cold-A/cold-B baseline so any warm difference is attributable
  to warmth. **Result: identical in every arm.** Conditional on Chrome build,
  viewport, settle, and a warm window only ~26s deep — a daemon runs for hours,
  which this does not cover.

---

## 5. Where the source material lives

Copy from these. **Do not rewrite what already exists.**

| path | what to take |
|---|---|
| `skills/arxa-designer/` | ✅ **DELIVERED** (plan 01). The design stage, in this repo. Symlinked to `~/.agents/skills/arxa-designer`. Run `arxa design selftest <dir>` and `arxa design doctor` |
| `skills/arxa-story-mapper/` | ✅ **DELIVERED** (MIT adaptation). Pre-design elicitation: Epic→Feature→Story map → `docs/intake/brief.md` + `story-map.json` + `story_map.html`, feeding `arxa-designer` directly (intake bypassed; the brief's surface table is the 10.7 traceability source). Run `arxa emit story-map --self-test` |
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
**Rejected — gating arxa to kit-holders**, which deletes the buyer persona.

**`dependencyMode` is a config value from day one** — see O3.

### ✅ O3 — publishing the kit — **deferred, and non-breaking whenever it happens**

Publishing is a **config flip plus a migration command**, not a
re-architecture, because `config/arxa.config.json` carries
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
`research/stub-inventory.md`, Stripe, PayPal and both auth providers still
throw `UnimplementedError` (verified 2026-08-05 against
`kit/payments/payments_playbook.mdx` and `kit/auth/auth_playbook.mdx`; the
map providers and Vercel named there no longer do — maps went port-tested in
`6b0c447`, the Vercel target became real in `261b2ad`). Publishing 21
packages in that state buys a bad first impression and immediate semver
obligations on an API that is not stable.

### 🔴 O2 — still open

| # | question | why it blocks |
|---|---|---|
| O2 | Licence model and price point | `research/competitors-and-pricing.md` has the comparables; no number chosen |
