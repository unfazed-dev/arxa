---
name: appbox-reviewer
description: Use when a appbox-built target is ready for its pre-release QC gate — runs the deterministic contract validator (arch_guard) + the over-engineering review (ponytail-review), checks the manifest hash, and emits a green/red verdict. Trigger on "review the app", "QC", "is it ready", "gate before release".
---

# review — the QC gate (arch_guard + ponytail-review + hash)

> Per-skill playbook (the folded canon for this phase): [`REVIEWER_playbook.mdx`](REVIEWER_playbook.mdx)

## Core principle
Two independent reviewers, both must be green. This role WIRES existing tools;
it builds nothing.
When CI stands the pipeline ([`appbox-cicd`](../appbox-cicd/SKILL.md)), this
verdict becomes a required status check — CI enforces the call, this role
still owns it.

## Pipeline position

Stage 6 of `appbox-orchestrator` (Ø, front door) → `appbox-story-mapper / appbox-moodboarder` (0, optional) → `appbox-intake` (1) → `appbox-designer` (2) → `appbox-scaffolder` (3) → `appbox-builder` (4) → `appbox-tester` (5) → `appbox-reviewer` (6) → `appbox-deployer` (9) — cross-cutting: `appbox-lint` (7), `appbox-lens` (8), `appbox-cicd` (10, day-zero frame wrapping all stages). HUMAN GATE 2 (the review verdict) sits here; a REJECT rewinds the FSM to design. Stage numbers and every stage's input/output artifacts: `docs/research/pipeline-map.md` §1; the visual map: `docs/appbox-system-map.md`; the CLI FSM phases: `appboxd/lib/phases.dart`.

- **Upstream:** `appbox-tester` (the passing suite + freeze this gate consumes) and `appbox-builder` (arch_guard violations → builder re-emits; ponytail findings → builder cuts).
- **Downstream:** `appbox-deployer` — ships only after the GREEN verdict; `appbox-designer` receives the rewind on REJECT.

## Gate (run in order, stop on red)
1. **Contract** — `appbox gate arch --target <dir>` (ADR-0003;
   resolved relative to the appbox repo root). Exit 0 required. Violations
   → builder re-emits. (arch_guard is a forward reference — not yet vendored.)
2. **Code economy** — `/ponytail-review` on the diff (built extension points +
   any generated-layer drift). Flags: reinvented stdlib, unneeded deps,
   speculative abstractions, dead flexibility. Each finding → builder cuts it.
3. **Reproducibility** — the target's `.appbox/manifest.json` `blueprintHash`
   must equal the package's `golden.sha256`. Mismatch = drifted from the
   blueprint → re-emit (appbox-replay), OR the operator diverged (surface
   honestly; update mode = gated diff, not byte-replay — ADR-0002 #3).
4. **Ponytail-debt** — `/ponytail-debt` lists every `ponytail:` deferral; none
   should hide a bug farm.

## Verdict
- **GREEN** — all four pass → release-ready (hand to deployer). A GREEN
  verdict names its visual evidence and the lens verbs that produced it —
  tester goldens (`lens compare`), smoke captures (`lens check`), and for
  locked intake criteria the commission's cited motion proofs (two settle
  states / burst). A verdict that cannot name its instruments is a claim,
  not evidence.
- **RED** — any fail → back to builder with the specific findings. Never green
  a target with `arch_guard` violations.

## Rules
- Don't add validators inline — extend `arch_guard.py` (deterministic) for new
  contract rules; keep this role as wiring.
- The contract gate is non-negotiable; the economy gate is advisory-but-acted-on
  (findings returned to builder).
