# One browser engine — port the studio probes onto the lens CDP stack

Status: approved by user 2026-08-03 ("i want and need this sorted and consolidated").
Trigger: arxa drives Chrome through two stacks — the promoted Dart lens
(`arxa/lib/lens.dart` over `arxa/lib/cdp.dart`, probe-runner's replacement)
and ten Node/playwright-core contract probes (`tools/probe-*.mjs` +
`tools/_probe_base.mjs`) for the arxa-studio design. Two engines managing one
concern; same failure shape the vocabulary session just killed. End state: one
engine (lens/cdp), the .mjs suite retired with the same capability-map audit
discipline used to retire probe-runner.

## Non-negotiables (from the probe-runner retirement precedent)

- **Capability map**: every .mjs probe, section by section, ports to Dart or is
  dropped with a written reason. The map is the audit trail.
- **Parity before retirement**: old and new suites run against the same served
  tree and agree (same pass/fail, same failure symptom under mutation) before a
  single .mjs file is archived.
- **`_probe_base.mjs`'s target rules are law**: its explicit-target /
  disposable-project-guard semantics exist because probes once mutated a live
  project (`-probe`/`-test` suffix requirement, no silent default-port
  fallback). The Dart harness ports these rules verbatim.
- **Gaps go into cdp.dart, not around it**: if a probe needs an interaction verb
  cdp.dart lacks (drag sequences, iframe piercing, network-idle waits), the verb
  is added to the one engine — no side-channel Playwright dependency survives.

## Deliverables

1. `arxa/lib/probes/probe_base.dart` — design-probe harness on CdpSession:
   target resolution + disposable guard (ported from _probe_base.mjs), section/
   check reporting in the probes' current output style, assertion helpers.
2. `arxa/lib/probes/probe_<name>.dart` — one module per probe, ten total:
   panel_contract (12 sections), panel_resize, shell_chrome, no_reload, boost,
   composer_draft, context_sync, inspect, explode, flowwalk.
3. CLI: `arxa design probe [names…] --port N` (house style per lens_cli.dart),
   runnable individually and as a suite.
4. Capability map: `docs/probes-capability-map.md` (.mjs verb → Dart port |
   dropped-with-reason), mirroring `.kimi-code/skills/arxa-lens/capability-map.md`.
5. Retirement: `tools/probe-*.mjs` + `_probe_base.mjs` moved to
   `archives/tooling-pre-dart/` with a pointer note; every doc referencing
   tools/probe-*.mjs updated (plans, canon docs, skill docs).
6. Parity evidence recorded in the capability map: side-by-side run results +
   at least one mutation each suite catches identically.

## Waves

- **A (read-only, parallel)**: A1 maps the lens/cdp API surface (verbs, session
  model, waits, house assertion style, CLI wiring) → scratchpad doc; A2 builds
  the .mjs capability inventory (per probe: boots, asserts, helpers, island
  interactions, timing patterns) → scratchpad doc.
- **B**: harness + CLI + capability-map skeleton (reads lens/cdp directly).
- **C (parallel, after B)**: port groups — panel_contract alone; resize+shell_chrome
  (interaction-heavy); no_reload+boost+composer_draft+context_sync;
  inspect+explode+flowwalk (island/iframe-heavy). Each group: port, then run
  against a disposable serve, fix to green.
- **D**: parity run old-vs-new on the same tree (post-phase-5), mutation
  equivalence, retirement + doc sweep, commit.

## Constraints

- Phase 5 (viewer demotion) is in flight in designs/; this work stays in
  arxa/lib/probes + docs until D. Final parity runs on the post-phase-5 tree.
- The .mjs suite stays authoritative until D completes — phases still verify
  against it in the meantime.
- Chrome binary resolution: reuse cdp.dart's existing discovery (ARXA_CHROME
  escape hatch already mirrors the .mjs convention).
