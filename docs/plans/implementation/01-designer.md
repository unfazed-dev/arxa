# 01 — `app-box-designer`

**Goal.** A complete, standalone htmx design skill that produces prototypes the
FSM can freeze — carrying the viewport ladder, surface identity and registry
conventions the upstream lineage does not have.

**Blocks:** 14 (dogfood). **Depends on:** nothing. **Start immediately.**

**Priority: highest.** The founder begins designing the moment this lands.

## Source

| take | from | notes |
|---|---|---|
| the whole skill | `~/.agents/skills/kimi-design-htmx` | **MIT**, 168 non-vendor files |
| viewport archetypes | `~/.agents/skills/kimi-design-flutter/references/layout-archetypes.md` | doctrine only — do not copy Flutter code |
| a working producer to use as the template | `/Volumes/developer_ssd/Developer/applications/p2/design/new-htmx` | 97 ui + 13 services + 10 models |

## Steps

- [ ] **1.1** Copy the skill into the repo as the SSOT:
      `app-box/skills/app-box-designer/`. Exclude `.git/`, `runtime/node_modules/`,
      `agents/vendor/`, `agents/gen-pptx/`.
- [ ] **1.2** Create `THIRD-PARTY-NOTICES.md` at repo root containing the
      upstream MIT licence text and `Copyright (c) 2026 Jim Liu 宝玉` **verbatim**.
      This is a legal condition (`00-README.md` R2 exception 1). Keep the copied
      `LICENSE` file in the skill folder too.
- [ ] **1.3** Delete the non-app-design built-in skills:
      `export-as-pptx-editable`, `export-as-pptx-screenshots`, `make-a-deck`,
      `make-a-doc`, `read-pdf`, `save-as-pdf`, `speaker-notes`,
      `handoff-to-kimi-code`, `productionize`.
      *(`make-a-deck` is where the misleading `1280`-as-slide-width references
      came from — see `../architecture.md` §12.)*
- [ ] **1.4** Keep and retain: `create-design-system`, `use-design-system`,
      `design-system-authoring-guide`, `design-system-preview`,
      `design-components`, `frontend-design`, `hi-fi-design`,
      `interactive-prototype`, `mobile-prototype`, `wireframe`,
      `import-from-figma`, `import-from-html`, `import-from-github`,
      `generate-images`.
- [ ] **1.5** **Strip upstream references** (R2). Grep and rewrite every
      operational mention of `kimi-design`, `kimi-design-htmx`, `kimi code`,
      `baoyu`, `huashu`, `K3`, `p2` in: `SKILL.md`, `CONTEXT.md`,
      `system-prompt.md`, `DESIGN-ARCHITECTURE.md`, `built-in-skills/*.md`,
      `agents/*.md`, and every filename. Rename the skill to
      `app-box-designer` in frontmatter `name:` and all cross-links.
      **Verify with:** `grep -ril 'kimi\|baoyu\|huashu' skills/app-box-designer
      --exclude=LICENSE --exclude=THIRD-PARTY-NOTICES.md` → must return nothing.
- [ ] **1.6** Rewrite `SKILL.md` frontmatter `description:` for app_box's
      trigger surface. It must say the skill produces an **app prototype whose
      structure the app_box pipeline consumes** — not decks, not docs.
- [ ] **1.7** **Add the viewport ladder.** New file
      `references/viewport-ladder.md`, doctrine sourced from
      `kimi-design-flutter/references/layout-archetypes.md`. Content:
      freeze widths **390 / 744 / 1280**, sitting *inside* the MD3 window size
      classes (boundaries 600 / 840), never on a boundary. Which widths apply is
      **derived from targets** (§11) and read from config — never hardcoded (R3).
- [ ] **1.8** Update `mobile-prototype.md`, `hi-fi-design.md` and
      `interactive-prototype.md` to author at **every width in the active
      ladder**, not just phone. This is the gap the lineage cannot supply
      (§12) — measured: zero breakpoint doctrine in 46 upstream doc files.
- [ ] **1.9** **Add the app-architecture contract.** New file
      `references/app-architecture.md` documenting the authored layer (§14):
      - `models/screens_model/registry.json` — `{id, tab, comp, surface, label}`
        plus optional `roles`; `surface: null` **is** the exclusion, so no
        separate exclusions list;
      - `ui/views/<shell>/<tab>/<short>/{<short>_view.html, <short>_viewmodel.js}`;
      - `services/{repositories,facades}/`, `models/<x>_model/*_fixtures.json`;
      - **every viewmodel declares `export const surfaceId = '<id>';`**
      - `app.routes.js` exports the route table **and** `tabRoots`.
- [ ] **1.10** Fold `DESIGN-ARCHITECTURE.md` (87 lines, already the upstream
      "spine architecture contract") into the above rather than replacing it.
      Keep its structure; add the app_box-specific layers.
- [ ] **1.11** Replace `starter-partials/` chassis with a starter that emits the
      structure in 1.9. Use `p2/design/new-htmx` as the reference implementation
      — copy its `server.js`, `harness.js`, `app.routes.js` shape and the
      `services/{repositories,facades}` split. **Strip all p2 domain content**
      (training, seasons, buddies): keep the skeleton, delete the subject matter.
- [ ] **1.12** Add `built-in-skills/declare-structure.md`: how to author
      `registry.json` and `surfaceId` while designing, so structure is never
      back-filled.
- [ ] **1.13** Symlink into the harness skills dir:
      `ln -s <repo>/skills/app-box-designer ~/.agents/skills/app-box-designer`.
      The repo is the SSOT; the symlink is the consumer. Confirm with
      `readlink ~/.agents/skills/app-box-designer`.
- [ ] **1.14** Write `skills/app-box-designer/selftest.sh`: scaffold a
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
6. A human can invoke the skill and produce a prototype whose `registry.json`
   an unmodified `emit_structure` could read.

## Do not

- Do not clean-room rewrite. It is MIT; forking is permitted and §19 settled it.
- Do not copy `agents/gen-pptx/` or any deck/PPTX machinery.
- Do not hardcode 390/744/1280 anywhere in code — they are config values.
