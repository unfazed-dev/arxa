# 02 — Repo skeleton

**Goal.** The folder layout every other plan writes into, plus the conventions
that make R3 (no hardcode) and R4 (one folder per gate) enforceable.

**Blocks:** 03, 08. **Depends on:** nothing. **Runs parallel to 01.**

## Target layout

```
app-box/
  app/                      the Flutter desktop app          (plan 08)
  companion/                the iOS companion                (plan 12)
  skills/
    app-box-designer/       (plan 01)  ← SSOT, symlinked into ~/.agents/skills
    app-box-intake/         (plan 10)
    app-box-scaffolder/     (plan 03)
    app-box-reviewer/       (plan 03)
    app-box-builder/        (plan 03)
    app-box-deployer/       (plan 11)
  gates/
    _common/                shared helpers — the ONLY sideways import allowed
    freeze/
    structure/
    scaffold/
    coverage/
    review/
    deploy/
  pipeline/
    pipeline.sh             the FSM orchestrator             (plan 03)
    state/                  pipeline state schema + reader
  tools/
    vendor/                 copied upstream tooling + VENDOR.lock (plan 03)
    emit_structure/
    emit_surfaces/
  config/
    app-box.config.json     targets, ladder widths, ports, kit SHA
  docs/
  THIRD-PARTY-NOTICES.md
```

## Steps

- [ ] **2.1** Create the tree above. Every leaf gets a `README.md` stating what
      belongs in it and what does not — one paragraph, no filler.
- [ ] **2.2** Write `config/app-box.config.json` with **every** value that any
      later plan would otherwise inline:
      ```json
      {
        "version": "1.0.0",
        "targets": ["macos"],
        "viewports": { "mobile": 390, "tablet": 744, "desktop": 1280 },
        "viewportClasses": { "compactMax": 599, "mediumMax": 839 },
        "prototypeServer": { "host": "127.0.0.1", "port": 0 },
        "kit": { "repo": "", "sha": "" },
        "escalationLimit": 3
      }
      ```
      `port: 0` means OS-assigned — never a fixed port.
- [ ] **2.3** Write `pipeline/state/` — the state schema and a reader.
      State carries at minimum: current phase, `targets`, approval tokens,
      design hash, kit SHA. **Targets live here, not in flags** (§11).
- [ ] **2.4** Write `gates/_common/` with: state reader, porcelain-diff helper
      (`git status --porcelain`, never `git diff`), SARIF emitter, and the
      pass/fail reporter. Every gate uses these; no gate reimplements them.
- [ ] **2.5** Write `gates/README.md` codifying R4 and R5: one folder per gate,
      each with its own selftest including a negative case, no gate imports a
      sibling, shared logic moves to `_common`.
- [ ] **2.6** Add a repo-level lint script `tools/lint_conventions.sh` that
      **fails** on: absolute paths outside `config/`, a gate importing a sibling
      gate, `git diff --exit-code` used for a regeneration assertion, and any
      of the stripped upstream names (R2) outside `THIRD-PARTY-NOTICES.md`,
      `LICENSE` and `docs/research/`.
- [ ] **2.7** Wire `tools/lint_conventions.sh` into the repo's own test entry
      point so a violation cannot merge.

## Done-when

1. The tree exists; every leaf has a `README.md`.
2. `config/app-box.config.json` parses and holds every tunable named above.
3. `tools/lint_conventions.sh` **passes on the empty tree** and **fails** on a
   planted violation of each of its four rules — prove all four (R5).
4. No plan after this one needs to invent a folder.
