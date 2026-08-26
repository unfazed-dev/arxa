# Response — energize handoff `2026-08-26-arxa-rename.md`

**Source:** `/Volumes/developer_ssd/Developer/totem_labs/clients/energize/docs/handoffs/2026-08-26-arxa-rename.md`
**Responded at:** `4ca2f17e` (tip when work started) → six commits, `86d73f4b`..`3699b4d6`
**Constraint:** the dial was under concurrent edit (`arxa_dial.dart`, `design_server.dart`,
`arxa_dial_test.dart` dirty throughout). Nothing in this pass touches those three files.

## Verification method

Every finding's quoted error string was grepped against HEAD **before** any fix, to rule
out the possibility that the handoff author was running a stale compiled binary (B1/B2
describe exactly that hazard, so it had to be excluded as a cause of the other findings):

| string | hits in HEAD | verdict |
|---|---|---|
| `cannot find repo root` | 4 | live (`arxa/bin/arxa.dart:309`) |
| `unknown flag` | 17 | live (`design_server.dart:276`) |
| `bad project name` | 5 | live |
| `repo mode: none` | 1 | live |

No finding described dead code. All are real against HEAD.

---

## Fixed (6 commits, one per finding, each independently revertible)

### A1 — `86d73f4b`… → `6edeba3b` · legacy `appbox.json` marker unbinds silently
`arxa/lib/repo_project.dart`. Added `legacyMarkerFile = 'appbox.json'` and
`findLegacyMarkerDir()`. `findRepoProject()` now names the stale marker on the way out
instead of returning null silently — pipeline binding going dead and the dial's axes
plane disabling itself no longer look identical to "this just isn't an arxa project".
Warning is deduped per-dir per-process (`_legacyWarned`) so the per-command walk-up
cannot spam.

Tests: 4 new cases in `arxa/test/repo_project_test.dart` (found / walks up from a subdir /
quiet once renamed / null when neither marker exists). 27/27 pass. **Mutation-verified:**
dropping the "already migrated" guard makes the third case fail, and it passes again on
restore — the test has teeth.

**Deliberately NOT wired: `design_axes.dart`.** It is the second surface the handoff
names, and it is a clean file, so editing it was available. Skipped because
`resolveArtifactMarker()` returning null is a *normal* state there ("Null = no marker =
the dial offers no axes at all"), so a stderr warning in that path risks one line per
artifact on every design-server boot. Verifying that requires running the server, which
means touching the dial. `findLegacyMarkerDir` is exported, so wiring it later is two
lines. **Open — see Deferred.**

### A2 — `86d73f4b` · widgets.css named Flutter classes that do not exist
`skills/arxa-designer/starter-partials/widgets/widgets.css`. Predates the rename (was
`AppBoxKitFilterChip`, equally nonexistent). Verified against real class declarations:

| line | was | now | evidence |
|---|---|---|---|
| 381 | `ArxaKitListTile/Section` | `ArxaKitListTile / ArxaKitListSection` | `kit/ui_library/lib/widgets/arxa_kit_list_section.dart:22` |
| 868 | `ArxaKitChip / ArxaKitFilterChip` | `ArxaKitChip / ArxaKitChipCarousel` | `kit/ui_library/lib/widgets/arxa_kit_chip_carousel.dart:27` |

`ArxaKitFilterChip` = 0 hits, `ArxaKitSection` = 0 hits. Comment-box alignment preserved.
Confirmed no golden/fixture pins the old strings (grep across `*.dart`/`*.css`/`*.json`/
`*.html` outside `starter-partials/`: zero hits), so nothing emitted still carries them.

### A3 — `1e349e01` · `serve` and `commission` undocumented
`arxa/lib/design_cli.dart`. Both added to `_usage`. Mechanically confirmed the block is
now complete: all 17 `case` labels in the dispatch appear in the usage text, zero
undocumented. (The handoff named these two; `selftest`/`ds-check`/`record-asset`/
`ds-import`/`probe` were already documented further down the block.)

### A4 (half) — `2bb3dfda` · `--help` parsed as a positional
`arxa/lib/project_cli.dart`. `_usage()` now takes an exit code — 0 when help was *asked
for*, 2 on misuse. `_isHelp()` intercepts at the dispatch level and, critically, inside
`_init` *before* the first positional becomes a project name.

Verified functionally: `project --help` → 0, `project init --help` → 0 + usage (was
`bad project name`), `project bogus-sub` → 2 (regression intact).

**Half deferred:** `arxa design serve --help` fails at `design_server.dart:276`, a file
under concurrent edit. Not touched. **Open — see Deferred.**

### A6 — `3699b4d6` · `$schema` banner is write-only
`arxa/lib/emit_structure.dart`. The handoff is right that no runtime consumer validates
it, but slightly overstates "nothing asserts on it" — `arxa/test/scaffold_test.dart:36`
pins the literal `arxa/structure@2`. Documented that precisely next to the constant:
provenance only, no reader, the test is what makes a silent bump fail. Adding a reader
that asserts would change behaviour (it could reject existing documents), so that is a
decision, not a cleanup — left to you.

### A7 — `bdc0d086` · intake stage README omits three artifacts
`arxa/lib/stage_readmes.dart`. Added `prd.md` (written at `intake.dart:1251`),
`decisions.json` and the `adr/` directory (both `decision_log.dart:348`). Predates the
rename.

---

## Confirmed defect the handoff did NOT catch

### A5b · six repo-root resolvers, two contradictory policies
Found while investigating A5. The same walk-up for the same file
(`config/arxa.config.json`) is implemented **six times**, and they disagree about what
"not found" means:

| site | on exhaustion |
|---|---|
| `arxa/lib/scaffold.dart:1140` `findRepoRoot()` | **returns `Directory.current`** |
| `arxa/lib/lens_cli.dart:924` `_findRepoRoot()` | **returns `Directory.current`** |
| `arxa/lib/deploy_cli.dart:124` `_findRepoRoot()` | `null` |
| `arxa/lib/design_tools.dart:3708` `_findRepoRoot()` | `null` |
| `arxa/lib/design_selftest.dart:239` `_findRepoRoot()` | `null` |
| `arxa/bin/arxa.dart:307` `_findRepoRoot()` | `null` → hard exit 2 |

**This is reachable, not theoretical.** `arxa emit scaffold` is a user command
(`arxa/bin/arxa.dart:400`, `:658`). `scaffold_cli.dart:103` calls the *cwd-falling-back*
resolver with `Directory.current.path`, then at `:104-105` builds:

```
<repoRoot>/pipeline/state/targets.derivation.json
<repoRoot>/config/arxa.config.json
```

Run from a client repo, the walk-up exhausts, `repoRoot` silently becomes **the client
repo**, and both paths point at files that do not exist there. So where `arxa gate`
fails loudly (A5), `arxa emit scaffold` proceeds against a wrong root — the same
underlying gap with the worse failure mode.

Not fixed here: consolidating six resolvers is a cross-file refactor, and picking the
surviving policy is the same decision A5 raises. Deliberately left intact rather than
half-migrated while the dial is under edit.

---

## Needs your decision — not fixed

### B2 · stale `appbox` shim is LIVE, not dead — the only item with ongoing cost
Sharper than the handoff has it. `~/.pub-cache/bin/appbox` still exists and execs:

```
/Volumes/developer_ssd/Developer/totem_labs/app-box/appboxd/bin/appbox.dart
```

**That directory still exists.** So this is not a dangling shim that errors — it is a
working entrypoint into the *pre-rename engine*. Anything still calling `appbox` gets the
old code silently, with no warning that it is a fork. `arxa` on PATH is unaffected
(`~/.local/bin/arxa` wins), so nothing is broken today, but this is the one finding where
doing nothing keeps costing:

```sh
rm ~/.pub-cache/bin/appbox
```

Not run — it is outside the repo, on your machine. Also noticed: `which -a arxa` prints
`~/.local/bin/arxa` twice, so PATH carries a duplicate entry. Cosmetic.

### A5 · `arxa gate` cannot run from a repo-mode project
Confirmed at `arxa/bin/arxa.dart:309`. `config/arxa.config.json` exists only in the arxa
checkout — verified absent from every client repo under `clients/`. So a repo-mode client
project genuinely cannot resolve one.

The question is whether that is a bug or a category boundary: the gates check *arxa's own*
engine invariants, so "run them from a client repo" may be meaningless. If it is
meaningful, the fix is to resolve via the `arxa.json` marker (`repo_project.dart`) when no
`config/` is found. **Whichever way that lands, it should settle A5b at the same time** —
one policy, one resolver. Not inventing that policy.

### C · SPEC.md does not name the `.navbar--top` markup hook
**Confirmed.** `navbar--top` = 0 hits in `skills/arxa-designer`, while `SPEC.md:179`
already refers to "the `--alt` discriminator this swap requires" without ever naming it —
exactly the gap the handoff describes.

**Blocked on direction of truth, and the handoff's caution was right.** The real class
exists upstream, in the *energize* repo:
- `clients/energize/studio/design/ui/styles/common/families.css`
- `clients/energize/docs/technique-layer/component-craft.md`
- SSOT: `clients/energize/docs/technique-layer/component-specs.md`

`SPEC.md:5` states component-specs.md "remains the SSOT" and that SPEC is compiled from
it. Editing `SPEC.md` directly would either be overwritten on the next compile or silently
fork from the SSOT. **The fix belongs in energize's technique-layer, then recompile** —
unless the line-169 prose is arxa-authored rather than compiled, which only you can
confirm. Not editing either repo unilaterally.

### B1 · installed wrapper bakes the repo root
`~/.local/bin/arxa` hard-codes `REPO='/Volumes/.../arxa'` at install time. If the repo
moves, the failure message says `run: $REPO/install.sh` — naming the path that just
stopped existing. `install.sh --check` already exists (`install.sh:29,57`). One-line
message fix; low value, no data at risk. Say the word.

### B3 · no action
The handoff itself concludes it is not a defect. Agreed on read; nothing to do.

---

## Deferred purely by the dial constraint

Both are ready to land the moment the dial settles:

1. **A4's other half** — intercept `--help` in `design_server.dart`'s flag parser
   (`:276`), so `arxa design serve --help` stops reporting `unknown flag: --help`.
2. **A1's second surface** — wire `findLegacyMarkerDir` into `design_axes.dart`'s
   `resolveArtifactMarker`, *if* the boot-time noise question above resolves in favour
   of warning there.

## Still open from the prior session

`gate_freeze_test.dart`, `serve_scope_test.dart`, `entitlement_test.dart` (×3) exited
`254` (spawned subprocess failed to compile) during a full run against a tree that was
being edited concurrently. Believed to be a race with in-flight dial edits, **not
verified** — the re-run was deliberately not performed. Worth one clean run once the dial
is at rest.
