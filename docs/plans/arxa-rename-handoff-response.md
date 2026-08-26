# Response — energize handoff `2026-08-26-arxa-rename.md`

**Source:** `/Volumes/developer_ssd/Developer/totem_labs/clients/energize/docs/handoffs/2026-08-26-arxa-rename.md`
**Status:** every finding closed. 12 commits across two passes, `86d73f4b`..`46ae23b2`.
**Test baseline:** `+1849 All tests passed` before the work and `+1849` after — no regression.

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

## Left deliberately undone
- **A5's product question** — whether `arxa gate` should resolve via the `arxa.json`
  marker when no `config/` is found. The dangerous half (A5b) is fixed; this half is a
  decision about what the gates are *for*.
- **A6's reader** — giving `$schema` teeth changes what documents are accepted.
- **PATH duplicate** — `~/.local/bin/arxa` listed twice; cosmetic.
