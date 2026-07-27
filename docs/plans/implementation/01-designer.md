# 01 — `app-box-designer`

**STATUS: COMPLETE** — executed 2026-07-27. All 15 steps done, selftest 14/14 with a demonstrated negative for every check. Five amendments to the plan are recorded at the bottom; each one was a defect in the plan, not a deviation from it.

**Goal.** A complete, standalone htmx design skill that produces prototypes the
FSM can freeze — carrying the viewport ladder, surface identity and registry
conventions the upstream lineage does not have.

**Blocks:** 14 (dogfood). **Depends on:** nothing. **Start immediately.**

**Priority: highest.** The founder begins designing the moment this lands.

## ⚠️ The designer REQUIRES Node. That is correct and intended.

Do not confuse this with plan 09. Three different surfaces:

| surface | Node? | runs on | size |
|---|---|---|---|
| **this skill, at design time** | **yes** | the designer's machine, inside a harness | **22 MB `node_modules`**, dev-only |
| the desktop app serving a prototype (plan 09) | **no** | the buyer's machine | ~1 MB `flutter_js` |
| a bundled JS runtime binary | rejected | — | ~90 MB |

`runtime/` needs `hono`, `@hono/node-server`, `nunjucks`, and `playwright`
(dev) for the render and console checks. **Plan 09's "no Node on `PATH`"
constrains the buyer's machine only — never this one.** Stripping Node from the
designer would break the render gate, which is the check that catches a surface
whose fonts 404.

## Source

| take | from | notes |
|---|---|---|
| the whole skill | `~/.agents/skills/kimi-design-htmx` | **MIT**, 168 non-vendor files |
| viewport archetypes | `~/.agents/skills/kimi-design-flutter/references/layout-archetypes.md` | doctrine only — do not copy Flutter code |
| a working producer to use as the template | `/Volumes/developer_ssd/Developer/applications/p2/design/new-htmx` | 97 ui + 13 services + 10 models |

## Steps

- [x] **1.1** Copy the skill into the repo as the SSOT:
      `app-box/skills/app-box-designer/`. Exclude `.git/`, `runtime/node_modules/`,
      `agents/vendor/`, `agents/gen-pptx/`.
- [x] **1.2** Create `THIRD-PARTY-NOTICES.md` at repo root containing the
      upstream MIT licence text and `Copyright (c) 2026 Jim Liu 宝玉` **verbatim**.
      This is a legal condition (`00-README.md` R2 exception 1). Keep the copied
      `LICENSE` file in the skill folder too.
- [x] **1.3** Delete the non-app-design built-in skills:
      `export-as-pptx-editable`, `export-as-pptx-screenshots`, `make-a-deck`,
      `make-a-doc`, `read-pdf`, `save-as-pdf`, `speaker-notes`,
      `handoff-to-kimi-code`, `productionize`.
      *(`make-a-deck` is where the misleading `1280`-as-slide-width references
      came from — see `../architecture.md` §12.)*
- [x] **1.4** Keep and retain: `create-design-system`, `use-design-system`,
      `design-system-authoring-guide`, `design-system-preview`,
      `design-components`, `frontend-design`, `hi-fi-design`,
      `interactive-prototype`, `mobile-prototype`, `wireframe`,
      `import-from-figma`, `import-from-html`, `import-from-github`,
      `generate-images`.
- [x] **1.5** **Strip upstream references** (R2). Grep and rewrite every
      operational mention of `kimi-design`, `kimi-design-htmx`, `kimi code`,
      `baoyu`, `huashu`, `K3`, `p2` in: `SKILL.md`, `CONTEXT.md`,
      `system-prompt.md`, `DESIGN-ARCHITECTURE.md`, `built-in-skills/*.md`,
      `agents/*.md`, and every filename. Rename the skill to
      `app-box-designer` in frontmatter `name:` and all cross-links.
      **Verify with:** `grep -ril 'kimi\|baoyu\|huashu' skills/app-box-designer
      --exclude=LICENSE --exclude=THIRD-PARTY-NOTICES.md` → must return nothing.
- [x] **1.6** Rewrite `SKILL.md` frontmatter `description:` for app_box's
      trigger surface. It must say the skill produces an **app prototype whose
      structure the app_box pipeline consumes** — not decks, not docs.
- [x] **1.7** **Add the viewport ladder.** New file
      `references/viewport-ladder.md`, doctrine sourced from
      `kimi-design-flutter/references/layout-archetypes.md`. Content:
      freeze widths **390 / 744 / 1280**, sitting *inside* the MD3 window size
      classes (boundaries 600 / 840), never on a boundary. Which widths apply is
      **derived from targets** (§11) and read from config — never hardcoded (R3).
- [x] **1.8** Update `mobile-prototype.md`, `hi-fi-design.md` and
      `interactive-prototype.md` to author at **every width in the active
      ladder**, not just phone. This is the gap the lineage cannot supply
      (§12) — measured: zero breakpoint doctrine in 46 upstream doc files.
- [x] **1.9** **Add the app-architecture contract.** New file
      `references/app-architecture.md` documenting the authored layer (§14):
      - `models/screens_model/registry.json` — `{id, tab, comp, surface, label}`
        plus optional `roles`; `surface: null` **is** the exclusion, so no
        separate exclusions list;
      - `ui/views/<shell>/<tab>/<short>/{<short>_view.html, <short>_viewmodel.js}`;
      - `services/{repositories,facades}/`, `models/<x>_model/*_fixtures.json`;
      - **every viewmodel declares `export const surfaceId = '<id>';`**
      - `app.routes.js` exports the route table **and** `tabRoots`.
- [x] **1.10** Fold `DESIGN-ARCHITECTURE.md` (87 lines, already the upstream
      "spine architecture contract") into the above rather than replacing it.
      Keep its structure; add the app_box-specific layers.
- [x] **1.11** **Keep the skill's own `runtime/` — do not adopt p2's
      `server.js`.** These diverged: the skill ships a factored Hono runtime
      (`runtime/lib/{router,state,templates,helpers,timers}.mjs`, `serve.mjs`,
      `eject.mjs`, `console-check.mjs`, `lint.mjs`) while p2 hand-rolled a plain
      `server.js` on nunjucks alone. The skill's is better factored and is what
      the render/console checks target.
      **`runtime/lib/router.mjs` is therefore the routing contract of record**,
      and plan 09's Dart server implements *that* contract — so the design-time
      and shipped runtimes agree by construction rather than by luck.
      Take from `p2/design/new-htmx` only the **application-layer shape**:
      `services/{repositories,facades}` split, `models/<x>_model/*_fixtures.json`,
      and the `registry.json` convention. **Strip all p2 domain content**
      (training, seasons, buddies) — keep the skeleton, delete the subject.
- [x] **1.11b** Do **not** vendor `runtime/node_modules`. Record the dependency
      set in `runtime/package.json` and install at setup. Add a `doctor` check
      that names Node and Playwright when missing, rather than failing obscurely
      inside a render.
- [x] **1.12** Add `built-in-skills/declare-structure.md`: how to author
      `registry.json` and `surfaceId` while designing, so structure is never
      back-filled.
- [x] **1.13** Symlink into the harness skills dir:
      `ln -s <repo>/skills/app-box-designer ~/.agents/skills/app-box-designer`.
      The repo is the SSOT; the symlink is the consumer. Confirm with
      `readlink ~/.agents/skills/app-box-designer`.
- [x] **1.14** Write `skills/app-box-designer/selftest.sh`: scaffold a
      two-surface throwaway producer from the starter, assert the registry
      parses, every viewmodel declares a `surfaceId`, `tabRoots` is non-empty,
      and each surface renders at every ladder width without console errors.

## Done-when

1. `grep -ril 'kimi\|baoyu\|huashu\|flutter-crew' skills/app-box-designer`
   returns **nothing** except `LICENSE`.
2. `THIRD-PARTY-NOTICES.md` exists and contains the upstream copyright line.
3. `references/viewport-ladder.md` and `references/app-architecture.md` exist.
4. `~/.agents/skills/app-box-designer` resolves to the repo copy.
5. `selftest.sh` passes, **including a negative case**: remove one `surfaceId`
   and assert the selftest exits `1` naming that viewmodel (R5).
6. ~~A human can invoke the skill and produce a prototype whose `registry.json`
   an unmodified `emit_structure` could read.~~ **UNSATISFIABLE AS WRITTEN —
   see Amendment A6.** The unmodified emitter cannot read a JSON registry in
   any form. Replaced by: the starter's `registry.json` carries every field
   the emitter extracts (`id`/`tab`/`comp`/`surface`) plus `tabRoots`, so
   plan 05's rewire is a read-path change and nothing else.

## Do not

- Do not clean-room rewrite. It is MIT; forking is permitted and §19 settled it.
- Do not copy `agents/gen-pptx/` or any deck/PPTX machinery.
- Do not hardcode 390/744/1280 anywhere in code — they are config values.

---

## Amendments made during execution

The plan was wrong in five places. Each was fixed and the fix is recorded here
so plan 14 (dogfood) inherits the corrected contract, not the written one.

### A1 — three built-in skills were unlisted

`built-in-skills/` holds **26** files. Step 1.3 deletes 9 and step 1.4 keeps 14
— that accounts for 23. Unlisted: `save-as-standalone-html.md`,
`send-to-figma.md`, `something-cool.md`.

Applied the plan's own principle (keep app-design, drop deck/showcase):
**kept** `save-as-standalone-html` (an artifact export path) and `send-to-figma`
(symmetric with `import-from-figma`, which 1.4 keeps); **deleted**
`something-cool` (a showcase skill, same family as `make-a-deck`).

### A2 — deleting `productionize.md` orphaned a tool the plan keeps

Step 1.3 deletes `productionize.md`; step 1.11 explicitly keeps
`runtime/eject.mjs`, which `productionize.md` documents. Deleting the doc while
shipping the tool left six dangling references. **`productionize.md` was
restored.** Ejecting a prototype into a self-contained Hono app is also directly
useful for app_box's "take your code and leave" position.

### A3 — the lineage ADRs had nowhere to go

`docs/adr/0006-parity-port-rebase-drop.md` and `0007-full-fork-from-kimi-design.md`
are entirely about the upstream lineage, so they cannot survive R2 inside the
skill — but they are genuine decision records. Moved to
`docs/research/upstream-lineage/`, where R2 exception 3 permits historical
citation. Load-bearing citations in the skill were repointed to **ADR-0002**
(zero-custom-client-JS boundary), which is the actual reason those capabilities
are absent. `starter-partials/deck/` followed `make-a-deck` out.

### A4 — a blind strip cannot rewrite prose

Regex substitution across 31 files produced grammatical wreckage in exactly the
files that matter most (`SKILL.md` frontmatter, `system-prompt.md` header,
`references/kimi.md`'s harness table, whose contents were harness-specific tool
names). **`SKILL.md` and `references/harness-tools.md` were rewritten by hand**;
`system-prompt.md` was repaired in place. `references/kimi.md` →
`references/harness-tools.md`, restated capability-first because app_box is
harness-agnostic.

Also: `// kimitail:` survived the strip (no word boundary after `kimi`) →
`// tradeoff:`.

### A5 — the documented screenshot command does not work on a fresh install

`npx playwright screenshot` needs `chrome-headless-shell`, which
`playwright install chromium` does not fetch. The plan's verify loop would have
failed on every new machine.

Added **`runtime/shoot.mjs`** — uses the Playwright API, loops the *active*
ladder, and additionally fails on console errors, failed requests, 4xx/5xx and
horizontal overflow. Widths come from **`runtime/ladder.json`**; callers pass
rung *names*. Added `runtime/check_ladder.mjs` (config↔doctrine drift check, no
rung on a boundary) and `runtime/doctor.mjs` (step 1.11b), which runs with zero
dependencies installed and exits non-zero.

## What was verified, not assumed

| | result |
|---|---|
| `selftest.sh` | **15/15 pass**, exit 0 — starter and `designs/app-box-app` |
| `selftest.sh --negative` | **16/16 proven**, exit 0 — one deliberate break per check, each required to flip *that* check, plus one inverse case (a comment naming a banned attribute must NOT trip the linter) |
| every other check's negative | was "proved by hand"; now mechanical — the mutation table in `selftest.sh` is the record. A red baseline aborts with exit 65 instead of handing every mutation a free pass, which is how the starter's own unexempted theme flip surfaced |
| `doctor.mjs` with nothing installed | exit 1, names all 6 missing pieces and the two commands that fix them |
| starter served + rendered | 200 at **compact / medium / expanded**, 0 console errors, 0 failed requests, no horizontal overflow |
| the data spine | facade → repository → fixture → view renders end to end (screenshot read back) |
| `lint.mjs` | clean — zero custom client-side JS |
| `console-check.mjs` | clean |
| upstream identity | `grep -rlIi 'kimi|baoyu|huashu|jimliu|flutter-crew'` returns **nothing** outside `LICENSE` |

## Known gaps

- **`send-to-figma.md` is untested** — it needs a Figma MCP server that is not
  configured here. It fails with a clear message when the tools are absent.
- **The `--targets` → active-rungs derivation is documented, not implemented.**
  `shoot.mjs` accepts `--rungs`/`$APP_BOX_LADDER`/`_d_meta.json`; nothing yet
  computes that list from a project's targets. **That is plan 06's job** —
  until it lands, the rung list is passed by hand.

### A6 — Done-when #6 was unsatisfiable by construction

The criterion asked that an **unmodified** `emit_structure` be able to read the
prototype's `registry.json`. It cannot — for any producer, including p2's.

Measured, by reading `stacked_kit/tools/emit_structure/emit_structure.py`:

- it regex-scrapes `const P2_REGISTRY = [...]` out of **`jsx/app.jsx`** as text
  (`_entries()`, line 56; `app_jsx` resolved at line 85);
- failing that, it globs **`surfaces/*.html`** and derives `id`/`comp` from
  filenames;
- it **never opens a JSON file**, and it requires a `surfaces/` directory.

So no `registry.json` this skill emits — however well formed — can satisfy that
sentence. The criterion described the fix, not the current state. Confirmed by
running it against the starter: `FAIL: …/surfaces/ missing — not a design root`.

**This is the wiring job already identified in `architecture.md` §14** and it
belongs to **plan 05**, not here. What plan 01 *can* guarantee, and now does:

| the emitter extracts | the starter's registry carries |
|---|---|
| `id` | ✅ |
| `tab` | ✅ |
| `comp` | ✅ |
| `surface` (incl. `null`) | ✅ — and `surface: null` is the exclusion |
| `tabRoots` | ✅ exported from `app.routes.js` |

so plan 05's change is a **read path** — JSON instead of a regex over JSX — with
no schema negotiation.

**Note for plan 05:** p2's registry also carries `label` (42/42), `phase`
(42/42) and `roles` (28/42). The emitter reads none of them. `label` and `roles`
are in this skill's contract; **`phase` is deliberately not** — nothing
downstream consumes it. If plan 05 finds a consumer, add it there rather than
retrofitting it into every producer.
