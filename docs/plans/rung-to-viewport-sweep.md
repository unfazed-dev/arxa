# Sweep scope: rename `rung` → `viewport` (appbox-studio-v2)

Status: CLOSED — decision 2026-08-09: **keep `rung`** (option C). No rename.
Rationale: `rung` is skill-ratified (doctrine `viewport-ladder.md`, runtime
contract `ladder.json` `"rungs"` key, `--rungs` flag) and every candidate
replacement collided with a load-bearing term of the codebase or the medium:
`viewport` = the window ("viewport lock"), `span` = 68 `<span>` tags,
`scope` = 71 CSS-scoping uses + `@scope`, `display`/`device` = CSS keyword /
false UA-detection claim. Only zero-collision alternative found: `gauge`
(rejected as unnecessary migration). Scope data below kept for the record.

## Occurrence counts (design dir, case-insensitive)

132 matches across 32 files in `designs/appbox-studio-v2/`:

| Bucket | Files | Hits |
|---|---|---|
| Dashboard views (incl. `.sections/.desktop/.tablet/.mobile`) | 5 | 53 |
| Application hub views | 4 | 24 |
| Startup views + shell views | 9 | 22 |
| CSS (`app.css` 11, `appshell.css` 5, dashboard widgets 4, viewer/panels/intake/dashboard-shell 1 ea) | 8 | 24 |
| Widgets (tabbar/rail/header/main_panel/proceed_trigger/boot_checklist) | 6 | 6 |
| Docs (`README.md`, `intake/emit-findings.md`) | 2 | 4 |

Token shapes: `rung` (87), `Rung` (8), `rungs` (7), `rung--desktop|tablet|mobile`
(5 each), `dv-rungs` (3), `per-rung` (2), `compact-rung` (2), one-offs
(`rung-suffixed`, `Rung-agnostic`, `medium-rung`).

## Findings that complicate the rename

1. **Skill-level contract.** `.claude/skills/appbox-designer/` has 57 `rung`
   occurrences, including `runtime/ladder.json` — a runtime contract with a
   `"rungs"` key, a `--rungs` CLI flag, and `_d_meta.json ladder` selection.
   Doctrine file: `references/viewport-ladder.md` (16 hits). The ratified
   metaphor is **viewport ladder → rungs are positions on it**. Renaming
   rung→viewport makes the rung the ladder.
2. **"viewport" is already a distinct term.** ~14 prose uses in the design mean
   *the actual window*: "THE SHELL IS VIEWPORT-LOCKED" (`app.css:25`),
   "THE VIEWPORT LOCK IS DESKTOP-ONLY" (`panels.css:177`), etc. After the
   rename, "viewport lock" (window) and `.viewport--desktop` (width variant)
   collide — a one-vocabulary violation worse than the status quo.
3. **Blast radius beyond the design.** `rung` also appears in
   `designs/appbox-studio/services/*.js` (v1 facades/repos), the
   `.kimi-code/skills/appbox-designer/` mirror (SSOT-divergence hazard), and
   archived probes. Design-local rename forks vocabulary from the skill;
   full rename is a breaking change to the ladder contract for every design.
4. **Concurrency.** 53 of 132 hits are in `studio_dashboard_shell/` files that
   dash-variants restructured this session, uncommitted. No sweep until that
   work is committed or handed over (commit-concurrency discipline).

## Options

- **A. Design-local sweep** (132 hits, 32 files, one commit): fast, but design
  and skill now disagree on the core term.
- **B. Full sweep incl. skill + ladder.json + v1 + mirrors**: vocabulary stays
  unified but touches a runtime contract and CLI flag surface.
- **C. Keep `rung`**: it is the already-ratified term with a doctrine file;
  the collision analysis suggests `viewport` is the wrong replacement even if a
  rename proceeds (it already names the window).

## Mechanical order (if A or B approved)

1. Wait for / commit dash-variants' dashboard work.
2. CSS classes + `data-*` markers (`rung--*`, `dv-rungs`) in one pass.
3. TSX class strings + comments; then docs (`README.md`, `emit-findings.md`).
4. If B: `ladder.json` `"rungs"` key + `--rungs` flag + `viewport-ladder.md`
   + mirrors, versioned as a contract change.
5. Single commit; re-run design-server compliance/probe checks.
