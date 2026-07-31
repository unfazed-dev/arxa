---
name: review
description: Use as the QC gate before a appbox-built target is released — runs the deterministic contract validator (arch_guard) + the over-engineering review (ponytail-review), checks the manifest hash, and emits a green/red verdict. Trigger on "review the app", "QC", "is it ready", "gate before release".
---

# review — the QC gate (arch_guard + ponytail-review + hash)

## Core principle
Two independent reviewers, both must be green. This role WIRES existing tools;
it builds nothing.

## Gate (run in order, stop on red)
1. **Contract** — `python3 "$FC/stages/arch_guard.py" <target>` (ADR-0003;
   `$FC` = appbox plugin root — on this install `~/Developer/factory/appbox`).
   Exit 0 required. Violations → builder re-emits.
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
- **GREEN** — all four pass → release-ready (hand to deployer).
- **RED** — any fail → back to builder with the specific findings. Never green
  a target with `arch_guard` violations.

## Rules
- Don't add validators inline — extend `arch_guard.py` (deterministic) for new
  contract rules; keep this role as wiring.
- The contract gate is non-negotiable; the economy gate is advisory-but-acted-on
  (findings returned to builder).
