# app-box — repo instructions

## Projects live outside the repo (`~/.appbox`)

- `~/.appbox` holds **user projects only** (`~/.appbox/projects/<name>/`,
  with `intake/`, `design/`, `build/`, `settings/` shell dirs). The studio's
  own design stays in the repo (`designs/appbox-studio`).
- **Never hand-edit generated outputs.** A project's `intake/registry.json`
  and `intake/flows.json`, and the `run.*.json` / `app.*.json` fixtures, are
  generated — edit the seeds/answers (`answers.json`, `*_seed.<locale>.json`,
  the design seeds) and re-run the generators.
- The design server serves the studio with `--project <name>`; the default is
  the **current project** (the `~/.appbox/current` marker).
- The write channel (`POST /__project_write`) is the **only** way studio
  surfaces edit project files.
