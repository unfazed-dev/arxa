# app-box — repo instructions

## Projects live outside the repo (`~/.appbox`)

- `~/.appbox` holds **user projects only** (`~/.appbox/projects/<name>/`,
  with `intake/`, `design/`, `build/`, `settings/` shell dirs). The studio's
  own design stays in the repo (`designs/appbox-studio-v2` — the hub-hosted
  stage-shell design that replaced v1 on 2026-08-16; v1 remains in-tree as
  the retained visual-parity reference and the flow-services parity suite).
- **Never hand-edit generated outputs.** A project's `intake/registry.json`
  and `intake/flows.json`, and the `run.*.json` / `app.*.json` fixtures, are
  generated — edit the seeds/answers (`answers.json`, `*_seed.<locale>.json`,
  the design seeds) and re-run the generators.
- The design server serves the studio with `--project <name>`; the default is
  the **current project** (the `~/.appbox/current` marker).
- The write channel (`POST /__project_write`) is the **only** way studio
  surfaces edit project files.

## Behavior testing

- **Behavior-TDD is mandated** for every scaffolded app and kit package:
  red-first for new code, mocktail/kit-fakes on the repository Ports.
- Test names cite the story-ID verbatim from `map.json`
  (`<story-id> — <behavior sentence>`); kits cite `kit.<package>.<capability>`.
- The canon is `skills/appbox-tester/behavior-tdd-rules.md` — streams rules,
  banned mechanical-test anti-patterns, mocking/static-state discipline.
- `appbox gate tests` enforces it: T1 traceability/no empty stubs,
  T2 anti-pattern scan, T3 `flutter test` green.
