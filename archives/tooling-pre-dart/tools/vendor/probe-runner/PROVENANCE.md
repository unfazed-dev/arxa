# PROVENANCE — probe-runner

- **Source:** `~/.claude/skills/probe-runner` (Totem Labs' own tool)
- **Copied:** 2026-07-28
- **Licence:** Totem Labs internal — no third-party licence required.
- **Update policy:** re-copy from the source skill; the copy in this repo
  (`tools/vendor/probe-runner/`) is canonical for appbox. Do not patch it
  here piecemeal — fix upstream, then re-vendor.
- **Excluded on copy:** `__pycache__`, `.DS_Store`.
- **Consumers:** `skills/appbox-tester`, `skills/appbox-moodboarder`, and
  the appboxd daemon (shells out to its scripts per
  `docs/plans/consolidate-one-app-plus-daemon.md`, O1 vendoring pattern).

Canonical source repo: /Users/unfazed-mac/.agents/skills.shared/probe-runner (~/.claude/skills/probe-runner resolves there), SHA b514c0f.
