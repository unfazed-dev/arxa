# H7 — full appbox → arxa rename pass

**Status:** OPEN 2026-08-26. Gate (harness validation, staged dispatch check
under H1) passed this date — headless boot activates, guard fires, selftest
PASS, arxa-studio commit `68fe8ee`. Parent:
[arxa-harness-and-distribution.md](arxa-harness-and-distribution.md)
decision 10 / H7. Advisor consult attempted, skipped (no API key), recorded
per convention.

## Ground truth (recon 2026-08-26)

- **app-box repo:** 21,876 case-insensitive mentions across 1,832 tracked
  files. By token: `appbox` 12,716 · `AppBox` 12,729 · `APPBOX` 436 ·
  `app-box` 158 · `appboxd` 1,596 (tokens overlap; sweep must order
  longest-first).
- **By dir:** kit 13,628 · docs 2,906 · appboxd 2,026 · designs 1,205 ·
  skills 909 · archives 506 (archives stay untouched — historical) ·
  gates 214 · config 101 · tools 76 · hooks 72 · harness 53 · memory 43.
- **Dart packages:** 25 × `appbox_kit_*` + `appboxd` (pubspec `name:`
  renames are the breaking kind — imports, `package:` URIs, dir names).
- **Class family:** `AppBoxKit*` (Glyphs, Platform, Action, Colors, …).
- **Cross-repo:** arxa-studio has 65 mentions in 14 files
  (`APPBOX_GUARD_MODE`, `appbox credentials` vault, app-box paths) — must
  flip in the same pass or the guard/vault integration breaks.
- **Live server:** `appbox design serve` running (PID 58735, from
  `.build/`) — must stop before, restart after.
- **Old tooling:** `tools/sweep_rename.sh` is self-corrupted — a previous
  rename pass swept the script's own pattern list, every entry now maps
  old→old. Rebuild with a self-excluding, case-mapped script.
- **Remote:** `github.com/unfazed-dev/app-box.git`.
- **Outward name check (trademark/domain/npm/pub):** NOT done. This pass
  is internal-only: no publishing to pub.dev/npm, no domains touched.

## Token mapping

| Old | New | Notes |
|---|---|---|
| `appbox_kit_*` | `arxa_kit_*` | 25 pubspecs + dirs + `package:` URIs |
| `AppBoxKit*` | `ArxaKit*` | class family |
| `AppBox*` | `Arxa*` | remaining classes |
| `appboxd` (package + dir) | `arxa` | engine package takes the bare name; dir `appboxd/` → `arxa/` |
| `appboxd.dart` (daemon bin) | `arxad.dart` | daemon keeps the -d |
| CLI `appbox` (bin/appbox.dart) | `arxa` | engine owns the `arxa` command |
| studio `bin/arxa-studio.mjs` command | `arxa-studio` | studio cedes `arxa`; clean split, no cross-language wrapper |
| `APPBOX_*` (env: GUARD_MODE, APP) | `ARXA_*` | both repos, same pass, no shim |
| `appbox credentials` (vault verb) | `arxa credentials` | both repos, same pass |
| `app-box` (dir/repo/paths) | `arxa` | local dir + GitHub repo (`unfazed-dev/arxa`, old URL redirects) |
| `appbox` (all other lowercase) | `arxa` | catch-all, applied last |

## Stages

1. **Preflight:** stop design server; resolve untracked
   `docs/guard-findings-2026-08-26.md`; `git tag pre-h7-rename` in both
   repos.
2. **Rebuild sweep script** (`tools/sweep_rename.sh`): patterns
   longest-first, case-mapped per table, self-excluding, skips
   `.git/ build/ .dart_tool/ node_modules/ archives/`; `--check` mode
   first, review counts.
3. **Content sweep** app-box, then **path renames** (dirs/files with
   appbox in the name: `appboxd/`, kit pubspec dirs, docs).
4. **Cross-repo flip** in arxa-studio (65 mentions, 14 files) — guard env
   var, vault verb, checkout paths.
5. **Verify:** `dart analyze` across kit + daemon; rebuild `.build/`
   binary; arxa-studio selftest + headless boot check; guard denies the
   renamed engine dir in using-sessions (re-run the H1 dispatch check).
6. **Repo-level (Q2):** local dir move + GitHub repo rename (redirects
   old URL); update arxa-studio absolute paths; single commit per repo,
   one-line message.
7. **Restart design server** from rebuilt binary; confirm `design serve`
   works against a real design.

## Decisions ledger (locked 2026-08-26, operator-confirmed)

- **Q1: engine takes `arxa`** — package/CLI `arxa`, daemon `arxad.dart`,
  dir `appboxd/` → `arxa/`. Rejected: `arxad`-as-package, `arxa-engine`,
  keeping `appboxd`.
- **Q1b: studio CLI cedes the name** — `bin/arxa-studio.mjs` → `bin/arxa-studio.mjs`,
  command `arxa-studio`. Rejected: subcommand wrapper, path-only invocation.
- **Q2: repo is `arxa`** — local `totem_labs/arxa`, remote
  `unfazed-dev/arxa` (GitHub redirects old URL). Family:
  `arxa` / `arxa-studio` / `arxa-harness`.
- **Q3: clean env/vault flip, no shim** — `ARXA_GUARD_MODE`, `ARXA_APP`,
  `arxa credentials`, both repos in the same pass.
