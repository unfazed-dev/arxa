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
| [design/personas.md](design/personas.md) | **Evan** (founder, 4 modes) and **Michelle** (indie iOS+Android dev, the buyer) |
| [design/journeys.md](design/journeys.md) | J0 intake → J10 evaluate-and-leave |
| [design/flows.md](design/flows.md) | 4 mermaid diagrams: pipeline+gates, truth layers, target derivation, test tiers |
| [design/brief.md](design/brief.md) | the 14-surface inventory that seeds `registry.json` |

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
| `~/.agents/skills/kimi-design-htmx` | **MIT** — the designer fork base. 168 non-vendor files |
| `~/.agents/skills/kimi-design-flutter` | viewport archetypes (390/744) — doctrine only |
| `/Volumes/developer_ssd/Developer/totem_labs/stacked_kit/tools` | `pipeline.sh` 1018, gates, `emit_*`, `kit_registry` |
| `…/stacked_kit/showcase_app` | 124 Dart files / 8,626 lines — the desktop app base |
| `…/stacked_kit/deploy` | wired fastlane + shorebird + CF Pages |
| `/Volumes/developer_ssd/Developer/factory/flutter-crew` | `stages/` and `skills/{designer,builder,deployer,review,tester}` |
| `/Volumes/developer_ssd/Developer/applications/p2/design/new-htmx` | the working htmx producer |

---

## 6. 🔴 Open decisions — NOT settled, do not guess

| # | question | why it blocks |
|---|---|---|
| **O1** | **Scaffolded apps depend on ~39 private `stacked_kit` git packages. Michelle cannot pull them.** Publish to pub.dev? Vendor per app? Gate app_box to kit-holders? | Every app app_box produces fails to build for any buyer without repo access. This is the single largest product risk on the board |
| O2 | Licence model and price point | `research/competitors-and-pricing.md` has the comparables; no number chosen |
| O3 | Whether the kit is ever published | collapses O1 and turns vendoring into a shim (§17) |
