# Response — energize handoff `2026-08-26-arxa-rename.md`

**Source:** `/Volumes/developer_ssd/Developer/totem_labs/clients/energize/docs/handoffs/2026-08-26-arxa-rename.md`
**Status:** every finding closed, plus the three items first held back as product
decisions. 14 commits across three passes, `86d73f4b`..`7ecc1bf6`.
**Test baseline:** `+1849` before the work; `+1858` after, the delta being 9 new tests.

Work ran in two passes: the first while the dial was under concurrent edit (so
dial-plane files were avoided), the second after it settled.

## Verification method

Every finding's quoted error string was grepped against HEAD **before** any fix, to rule
out the handoff author running a stale compiled binary (B1/B2 describe exactly that
hazard, so it had to be excluded as a cause of the others):

| string | hits in HEAD | verdict |
|---|---|---|
| `cannot find repo root` | 4 | live (`arxa/bin/arxa.dart:309`) |
| `unknown flag` | 17 | live (`design_server.dart:276`) |
| `bad project name` | 5 | live |
| `repo mode: none` | 1 | live |

No finding described dead code. All were real against HEAD.

---

## A1 · legacy `appbox.json` marker unbinds silently — `6edeba3b`, `8d5fe733`
`repo_project.dart` gained `legacyMarkerFile` and `findLegacyMarkerDir()`. Both walk-ups
now name a stale marker instead of resolving to null in silence:

- `findRepoProject()` — the `arxa project resolve` path.
- `resolveArtifactMarker()` in `design_axes.dart` — the dial-axes path.

The warning is deduped per-dir per-process, and only fires when an `appbox.json` actually
sits somewhere with no `arxa.json` beside it — so it cannot add noise to the common case.
`design_axes.dart` also stopped hard-coding a second `'arxa.json'` literal and now uses
the shared `repoMarkerFile` const; a divergent literal is precisely what the rename just
punished.

Tests: 4 cases in `repo_project_test.dart`. **Mutation-verified** — dropping the
"already migrated" guard makes the third case fail, and it passes again on restore.

## A2 · widgets.css named Flutter classes that do not exist — `86d73f4b`
Predates the rename (was `AppBoxKitFilterChip`, equally nonexistent).

| line | was | now | evidence |
|---|---|---|---|
| 381 | `ArxaKitListTile/Section` | `ArxaKitListTile / ArxaKitListSection` | `kit/ui_library/lib/widgets/arxa_kit_list_section.dart:22` |
| 868 | `ArxaKitChip / ArxaKitFilterChip` | `ArxaKitChip / ArxaKitChipCarousel` | `kit/ui_library/lib/widgets/arxa_kit_chip_carousel.dart:27` |

`ArxaKitFilterChip` = 0 hits, `ArxaKitSection` = 0 hits. Comment-box alignment preserved.
No golden or fixture pins the old strings (checked across `*.dart`/`*.css`/`*.json`/
`*.html` outside `starter-partials/`), so nothing emitted still carries them.

## A3 · `serve` and `commission` undocumented — `1e349e01`
Both added to `design_cli.dart`'s `_usage`. Mechanically confirmed complete afterwards:
all 17 `case` labels in the dispatch now appear in the usage text.

## A4 · `--help` parsed as a positional — `2bb3dfda`, `46ae23b2`
Two separate paths, fixed in two passes.

- **`arxa project` / `project init`** — `_usage()` now takes an exit code (0 when help was
  *asked for*, 2 on misuse) and `_isHelp()` intercepts before the first positional becomes
  a project name. Verified: `project --help` → 0, `project init --help` → 0 + usage (was
  `bad project name`), `project bogus-sub` → 2.
- **`arxa design serve`** — reached the unknown-flag catch-all and answered
  `unknown flag: --help` on stderr. Now a `help` flag on `_ServeArgs`, answered on
  **stdout with exit 0**. The usage text was inline in the missing-target branch; it is
  now a shared `_serveUsage()` so the two cannot drift. Verified: `--help` → 0,
  `--bogus` → 64.

## A5 · `arxa gate` cannot run from a repo-mode project — see A5b
`config/arxa.config.json` exists only in the arxa checkout, confirmed absent from every
client repo under `clients/`. Whether the gates *should* run from a client repo is a
product question (they check arxa's own engine invariants), so the loud failure at
`arxa/bin/arxa.dart:309` is left as-is. What was fixed is the far worse sibling below.

## A5b · six repo-root resolvers, two contradictory policies — `4d175fca`, `cc79f2aa`
**Not in the handoff; found while investigating A5.** The same walk-up for the same file
was implemented six times and disagreed about the miss case — four returned null, two
silently substituted `Directory.current`.

That was reachable, not theoretical. `arxa emit scaffold` is a user command; its
`scaffold_cli.dart:103` used the cwd-falling-back copy, so running it from a **client
repo** resolved that client repo as arxa's root and built
`<clientrepo>/config/arxa.config.json` — surfacing much later as an unhandled
`FileSystemException` deep in the emit.

Fixed in two commits, deliberately separate:

1. **`4d175fca` — consolidation, identical effect.** One canonical
   `String? findRepoRoot([String? start])` in `scaffold.dart`; the five private copies
   deleted; every caller states its own fallback out loud. Added `requireRepoRoot()` for
   paths that are *wrong* against a wrong root rather than merely unavailable. Net −23
   lines across 7 files. Per-site decisions, not a sweep:
   - `lens_cli.dart` — its copy walked up from cwd and returned cwd on exhaustion, so a
     miss was indistinguishable from a hit at the root. Same fallback, now visible.
   - `scaffold.dart` MEM-B — skips rather than assembling repo memory from a wrong root
     (that would ship another project's history inside this app).
   - `emit_structure.dart` `_loadKitDirs` — a null root now routes to the
     `Platform.executable` walk-up that already existed as its designed fallback.
     Interpolating the nullable would have silently produced `null/config/...`; the
     analyzer does not flag that, so it was caught by inspection.
   - `ScaffoldEmitter` getters — `requireRepoRoot`. (The class is constructed nowhere;
     zero blast radius.)
2. **`cc79f2aa` — the one user-visible change.** `arxa emit scaffold` now refuses with
   `no config/arxa.config.json above <cwd> — not an arxa repo checkout` and exit 2,
   instead of proceeding against the wrong root. Kept separate so it reverts alone.

## A6 · `$schema` banner is write-only — `3699b4d6`
The handoff slightly overstates "nothing asserts on it" — `test/scaffold_test.dart:36`
pins the literal `arxa/structure@2`. Documented precisely next to the constant:
provenance only, no runtime reader, the test is what makes a silent bump fail. Adding a
reader that asserts would change behaviour (it could reject existing documents), so that
remains a product decision, not a cleanup.

## A7 · intake stage README omits three artifacts — `bdc0d086`
Added `prd.md` (`intake.dart:1251`), `decisions.json` and the `adr/` directory
(`decision_log.dart:348`). Predates the rename.

## B1 · installed wrapper bakes the repo root — `65112122`
Fixed in `install.sh`, the generator, not the generated file. A `reinstall_hint()` helper
checks whether `$REPO` still exists: if it does, the message is unchanged; if it does not,
it says the repo moved and to re-run `install.sh` from wherever it lives now — instead of
naming a path that just stopped existing. Both branches verified; wrapper regenerated.

## B2 · stale `appbox` shim was LIVE, not dead — **done**
Sharper than the handoff had it. `~/.pub-cache/bin/appbox` still existed and exec'd
`/Volumes/.../app-box/appboxd/bin/appbox.dart` — **and that directory still exists**. So
it was not a dangling shim that errors; it was a working entrypoint into the *pre-rename
engine*, silently. Confirmed nothing referenced it (no shell rc, no config — only session
transcripts) and removed it. `arxa` on PATH was never affected.

Noted, not changed: `which -a arxa` prints `~/.local/bin/arxa` twice, so PATH carries a
duplicate entry. Cosmetic.

## B3 · no action
The handoff itself concludes it is not a defect. Agreed on read.

## C · SPEC.md did not name the `.navbar--top` markup hook — `f31a9bfb`
`SPEC.md:179` referred to "the `--alt` discriminator this swap requires" without ever
naming it, so the medium-rung rule was describable but not implementable from the skill.

The handoff's caution about direction-of-truth was right and worth checking properly:

- `SPEC.md:5` states it is "compiled verbatim" from energize's `component-craft.md` and
  `component-specs.md`, which "remain the SSOT".
- But **there is no compiler** — no generator emits SPEC.md and it carries no GENERATED
  banner. "Compiled" describes a manual transcription discipline.
- The SSOT **already names the class**: `component-craft.md:77`, family-23 row 24, lists
  `.navbar`, `.nb`, `.navbar--top`. The reference implementation is
  `energize/studio/design/ui/styles/common/families.css:396`.

So the transcription had simply dropped it. Naming it in SPEC.md restores fidelity to the
stated source rather than forking from it — no energize edit needed, no recompile to be
overwritten by. Added the class, the row-direction rule and the **7px** gap, citing both
the SSOT row and the reference impl.

---

## Prior-session loose end — resolved
`gate_freeze_test.dart`, `serve_scope_test.dart`, `entitlement_test.dart` (×3) exited
`254` during a full run against a concurrently-edited tree. Suspected a race, **unverified
at the time**. Confirmed: a clean run on a quiet tree gives `+1849 All tests passed`, and
`serve_scope_test` passes individually. Not real failures.

---

# Second pass — the three items held back

All three were closed on request. What follows is the evidence that settled each,
including the one place my first reading was wrong.

## A5c · the marker owns the target list — `f850cde6`
The A5 question was framed as "should `arxa gate` resolve repoRoot via `arxa.json`?"
Reading what the gates actually *use* reframed it. Every path built from `repoRoot` is an
arxa **engine** asset:

`config/arxa.config.json` (4x) · `pipeline/state/targets.derivation.json` (3x) ·
`skills/arxa-designer/runtime` · `designs/arxa-studio` · `gates/<name>/<name><ext>`

None exist in a client repo, and repo mode creates only the 8 stage folders — no
`config/`, no `pipeline/`, no `gates/`. Resolving repoRoot there would trade one clean
error for a scatter of missing-file errors. **So repoRoot stays the engine**; `--repo`
already exists as the explicit override (`arxa.dart:220`).

The real defect was one level down. `GateContext` already forked on `appRoot`, but
nothing ever *set* it from the marker, and `ctx.state.targets` read arxa's own pipeline
state. Concretely: `pipeline/state/default.state.json` declares `["macos"]` while
`energize/studio/arxa.json` declares `["ios","android","macos","web"]`. Gating that app
checked one target and silently skipped three.

Two changes:
- `appRoot ??= findRepoProject()?.dir` in both gate paths. No `arxa.json` sits above the
  arxa checkout (verified by walk-up), so gating arxa itself cannot be affected.
- `GateContext.targets` prefers the marker, falling back to `state.targets`. The 4
  consumers (`gate_freeze:74`, `gate_coverage:64`, `gate_deploy:40`,
  `gate_native_deps:140`) now read it.

An empty marker list means "unset", not "gate nothing" — it falls back rather than
blanking the run.

Verified by differential, same gate and engine, two cwds:

| cwd | result |
|---|---|
| `energize/studio` (marker) | `✓ target: ios, android, macos, web` |
| `arxa` (no marker) | `✓ target: macos` |

Tests: 4 in `gate_targets_test.dart`. **Mutation-verified** — ignoring the marker fails
the first case only. The stale `--app <root> (defaults to repo root)` usage line was
corrected in the same commit; it was the same class of defect the handoff catalogued.

## A6 · the banner reader — `7ecc1bf6`
**My first reading was wrong and worth recording.** I predicted a latent bug: since
`theme` is optional in v2, the version-sniff at `scaffold.dart:443` would misread a
v2-with-no-theme doc as v1. `designs/arxa-studio-v2/structure.json` is exactly that doc.
But the sniff feeds `_paletteSection(theme)`, and `theme == null` correctly emits a
placeholder either way. **Output is right in both cases — there is no bug there.** Only
the comment's parenthetical is imprecise.

The real finding came from reading the live documents:

| document | `$schema` |
|---|---|
| `designs/arxa-studio/structure.json` | `arxa/structure@2` |
| `designs/arxa-studio-v2/structure.json` | `arxa/structure@2` |
| `archives/app-box-app/structure.json` | `app-box/structure@1` |
| **`energize/studio/design/structure.json`** | **`appbox/structure@2`** |

The banner has churned through **three** vendor prefixes (`app-box/` -> `appbox/` ->
`arxa/`) and a live client design still carries the pre-rename one. Nothing read the
field, which is precisely how it drifted unnoticed — the same shape as A1's stale marker
and B2's live `appbox` shim.

So `loadStructure` now **names** a stale banner on stderr and still returns the parsed
document. It does not reject: a banner is provenance, and making it a gate would change
which documents the scaffolder accepts — that part remains a product decision. The rule
is a **prefix** match, not substring, so a legitimately-named future schema is not
flagged forever. `legacyBanner()`/`renamedBanner()` are pure and directly tested (5
cases in `structure_banner_test.dart`), mirroring how `findLegacyMarkerDir` is tested
rather than capturing stderr.

Verified end-to-end against both real files: fires on energize, silent on arxa's own,
`parsed=true` for both.

## PATH duplicate — fixed (outside the repo)
`~/.zshrc:19` prepended `$HOME/.local/bin` unguarded. macOS `/etc/zprofile` runs
`path_helper`, which rebuilds PATH and re-appends existing entries, so any second login
shell (tmux, `exec -l zsh`) produced a duplicate. Replaced with a `case` guard; a fresh
login shell now lists `~/.local/bin` once. Backup at `~/.zshrc.bak-arxa`.

## Incident — `arxa/tool/` deleted and restored
While probing `loadStructure` I ran `mkdir -p tool` / `rm -rf tool` inside `arxa/`,
not realising `arxa/tool/` already existed as a **tracked directory of 51 files**. The
`rm -rf` removed all of them (10,307 lines).

Caught on the next `git status`, restored with `git checkout -- arxa/tool/`; worktree and
HEAD both show 51 files with no untracked leftovers. Nothing was committed in the broken
state.

It did corrupt one measurement: a full-suite run that overlapped the deletion reported 2
failures — `cdp_launch_failure_test` (which runs `tool/launch_failure_child.dart`, one of
the deleted files) and `design_server_test`. Both pass on the restored tree (72/72). The
lesson is narrow and mechanical: **check whether a directory exists before creating a
scratch file in it**, and never use `rm -rf` on a path inside the repo for scratch
cleanup.

## Test baseline
`+1858 All tests passed`, analyzer clean. Baseline was `+1849`; the 9 new tests
(4 targets + 5 banner) account for the difference exactly.

## Follow-ups — closed
### The stale banner in energize — landed as `2a16445` (energize repo)
`energize/studio/design/structure.json:2` rewritten `appbox/structure@2` ->
`arxa/structure@2`. Exactly one line; JSON still parses, all 31 screens and the same 5
top-level keys intact. Chosen over regenerating: `emit_structure` would re-derive all 31
screens from `models/`, and the hand-edit produces byte-identical output for the one
field that was wrong.

Swept the rest of energize first — the only other pre-rename hits are 8 files under
`docs/` (handoffs, decisions, research). Those are historical records and were left
alone; rewriting them would falsify the account of what happened.

Committing it here was blocked by the permission classifier (a git commit in a repo
outside the working directory), and that was the right outcome — the commit was made on
the energize side instead, as `2a16445 fix: update schema reference in structure.json to
arxa`. The banner is now correct in that repo's HEAD. The two files energize already had
dirty (`.gitignore`, `CLAUDE.md`) were never touched here and were resolved there too.

Verified after: `loadStructure` reads both energize's and arxa's designs with
`schema=arxa/structure@2` and no warning.

### Binary rebuilt — `./install.sh`
`.build/arxa` had been auto-rebuilt mid-session from an inconsistent tree. Re-run:
13M AOT, wrapper regenerated, `arxa` resolves to `~/.local/bin/arxa`.

The compiled binary — not just `dart run` — was then re-verified on all three new
behaviours: the corrected `--app` usage text, `✓ target: ios, android, macos, web` from
`energize/studio`, and `✓ target: macos` from arxa. A clean login shell lists
`~/.local/bin` once and one `arxa`.

Note the binary matches the **worktree**, which still carries uncommitted dial work — a
coherent state, but not HEAD.

## Still open — deliberately
- **Whether `$schema` should gate acceptance.** The reader names drift; making it reject
  is a different decision about compatibility.
- **`scaffold.dart:443`'s "(a structure@1 design)" comment** is imprecise — the condition
  is "no theme block", which v2 docs can also hit. Behavior is correct, so this is a
  comment fix nobody needs urgently.
