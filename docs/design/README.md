# app_box — Design Docs

Design-facing documentation for app_box: who the product is for, the journeys
it must serve, and the user flows behind every surface. Audience: design,
product, reviewers. Engineering contracts live in
[`docs/plans/architecture.md`](../plans/architecture.md) (§1–§22) — this folder
*cites* that doc, never duplicates its tables (see `AGENTS.md` standing rule:
one source of truth).

## Contents

| Doc | What it is |
|---|---|
| [`personas.md`](personas.md) | **Evan** (founder, 4 operating modes) and **Michelle** (indie iOS+Android dev, the buyer) — proto-personas with jobs-to-be-done, frustrations, and design-must-get-right per mode/persona. |
| [`app-box-persona-design-brief.md`](app-box-persona-design-brief.md) | The handoff brief: product framing, persona/mode model, cross-cutting design constraints (three gates, credential tiers, stub honesty, viewport derivation), pinned-vs-open contract, validation plan, and the 20-surface inventory that seeds `registry.json`. |
| [`app-box-design-generation-brief.md`](app-box-design-generation-brief.md) | The design-generation program: pre-flight checks, viewport ladder, the paste-once foundation prompt, per-mode/persona stage prompts, and the coverage check — for driving `app-box-designer` to the full prototype. |
| [`journeys/evan-founder-journey.md`](journeys/evan-founder-journey.md) | Evan: from client conversation to shipped app — the full pipeline across his four modes (intake → design → freeze → build → ship → remote → CRUD). |
| [`journeys/michelle-buyer-journey.md`](journeys/michelle-buyer-journey.md) | Michelle: the 20-minute evaluation — install → showcase → first project → build → evaluate-and-leave with her own code. |
| [`flows/README.md`](flows/README.md) | The flow-library layout convention, the flow-doc template, and naming rules. Start here before reading any flow. |
| [`flows/research-findings.md`](flows/research-findings.md) | Graded research synthesis (verified / assumed / unknown) from `docs/research/` — the evidence base behind the flows. |
| [`flows/evan-founder/_index.md`](flows/evan-founder/_index.md) | Evan's flow index: 15 flows across 6 tab-group shells. |
| [`flows/michelle-buyer/_index.md`](flows/michelle-buyer/_index.md) | Michelle's flow index: 6 flows across 5 tab-group shells. |

## Reading order (designer)

1. `personas.md` — who you are designing for and why they are different.
2. `app-box-persona-design-brief.md` §1–§3 — product framing, rules, persona
   model.
3. Your persona's journey: `journeys/evan-founder-journey.md` or
   `journeys/michelle-buyer-journey.md`.
4. Brief §5–§6 — cross-cutting constraints and what is pinned vs. open.
5. Driving `app-box-designer`? Run
   `app-box-design-generation-brief.md` top to bottom.
6. Building a specific surface? Start at `flows/README.md` for the template,
   then the persona's `_index.md` to find the flow doc.

## Standing notes

- **Personas are proto-personas** — grounded in the product spec
  (`architecture.md` §1) and measured research (`docs/research/`), not in user
  interviews. Validation plan: brief §8. Do not treat any behavioural claim as
  observed fact.
- **Canonical language is binding** (`architecture.md` throughout): app_box,
  stage_shell, gate (Gate 1 / Gate 2 / Gate 3), registry, surface, freeze,
  scaffold, finding, ledger. Avoid informal synonyms — "approval" is always a
  human gate, never an agent action; "red" always means broken, never payment.
- **Citations over copies.** Pipeline mechanics, gate definitions, kit
  inventories, and surface contracts live in the cited docs. If this folder and
  `architecture.md` disagree, `architecture.md` wins — file it as a bug against
  the doc here.
- **The three gates are visually distinct** from anything an agent can do alone.
  Approval is the product's core claim; it should look like it
  (`app-box-persona-design-brief.md` §5.2).
- **Red must mean broken.** The licence check is a precondition, not a gate
  (`architecture.md` §17). Nothing goes red for money.
