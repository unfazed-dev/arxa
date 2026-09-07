# arxa — repo instructions

> Harness-agnostic repo law. Claude Code additionally reads `CLAUDE.md`, which
> carries context-mode MCP routing rules that apply **only** to that harness —
> the two files are deliberately NOT symlinked to each other. Symlinking would
> either hide this law from Claude Code or feed dsh/Pi instructions about MCP
> tools they do not have.

## Install (`./install.sh`)

- `./install.sh` puts `arxa` on PATH from **any** checkout: it derives the
  repo root from its own location, AOT-compiles the CLI to `.build/arxa`, and
  writes a PATH wrapper. Re-run it after pulling; it is idempotent.
- The binary must stay **inside** the checkout — the designer resolves its
  runtime assets by walking up from the running executable to
  `config/arxa.config.json`. A binary elsewhere loses those assets silently
  (`arxa design doctor` then reports MISS).
- `dart run` costs ~1.4s per invocation; the AOT binary costs ~10ms. Hooks fire
  per tool call, so always invoke through the wrapper or `.build/arxa`.
- `./tools/portable-core-test.sh` is the smoke/pressure/stress/portability suite.

## One gate policy, every harness (`harness/`)

- `hooks/arxa-guard.js` is the single per-tool-call policy. Claude Code, dsh,
  and Pi all route through it — see `harness/README.md`. Add a rule once.
- Modes: `ARXA_GUARD_MODE=dev` (default, allow-all) / `using` (the arxa
  checkout is read-only) / `off`.

## Projects live outside the repo (`~/.arxa`)

- `~/.arxa` holds **user projects only** (`~/.arxa/projects/<name>/`,
  with `intake/`, `design/`, `build/`, `settings/` shell dirs). The studio's
  own design stays in the repo (`designs/arxa-studio`). The v2 hub-hosted
  stage-shell tree that replaced v1 on 2026-08-16 was archived on 2026-09-07
  (`archives/arxa-studio-v2/`) when arxa studio became a dsh fork.
- **Never hand-edit generated outputs.** A project's `intake/registry.json`
  and `intake/flows.json`, and the `run.*.json` / `app.*.json` fixtures, are
  generated — edit the seeds/answers (`answers.json`, `*_seed.<locale>.json`,
  the design seeds) and re-run the generators.
- The design server serves the studio with `--project <name>`; the default is
  the **current project** (the `~/.arxa/current` marker).
- The write channel (`POST /__project_write`) is the **only** way studio
  surfaces edit project files.

## Behavior testing

- **Behavior-TDD is mandated** for every scaffolded app and kit package:
  red-first for new code, mocktail/kit-fakes on the repository Ports.
- Test names cite the story-ID verbatim from `map.json`
  (`<story-id> — <behavior sentence>`); kits cite `kit.<package>.<capability>`.
- The canon is `skills/arxa-tester/behavior-tdd-rules.md` — streams rules,
  banned mechanical-test anti-patterns, mocking/static-state discipline.
- `arxa gate tests` enforces it: T1 traceability/no empty stubs,
  T2 anti-pattern scan, T3 `flutter test` green.
