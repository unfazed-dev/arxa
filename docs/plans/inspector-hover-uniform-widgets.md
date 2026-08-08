# Inspector Hover: Uniform Badge + Widget-Only Targeting — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One invariant inspector badge (studio-accent, on-accent text, pinned font) on every surface, and hover/click that only ever targets authored widgets (`[data-el]`) — never svg paths, bare spans, or inferred containers — so the composer slider panel always receives coherent widget context.

**Architecture:** All changes land in the vendored inspect island + the two templates that load vendor scripts + the Dart lint/probe suite. The island stays dependency-free. Identity remains authored-only via `inspectAttrs()` (see `docs/plans/inspector-everything-as-widgets.md`); the tag-map inference (`ROLE_BY_TAG`) stops feeding hover.

**Tech Stack:** vanilla JS island (`inspect.js`), Hono/JSX templates (tsx), Dart design server + probes.

## Global Constraints

- `inspect.js` exists as three byte-identical copies (regular files, NOT symlinks): `skills/appbox-designer/runtime/vendor/inspect.js`, `.claude/skills/appbox-designer/runtime/vendor/inspect.js`, `.kimi-code/skills/appbox-designer/runtime/vendor/inspect.js`. Edit `skills/...` then copy to the other two; verify all three share one md5 before committing.
- Decided vocabulary: badge = the hover label; widget = element carrying `data-el`; screen fallback = the only surviving "inferred" case.
- Studio accent tokens: `theme.css` — cyan light `#0C87A8`, cyan dark `#45D5F5`; `--on-accent` is `#FFFCF0` (light accents) / `#100F0F` (dark-theme accents). Island literal fallback stays `#0891b2` only as last resort.

### Task 1: Accent resolution + badge restyle (inspect.js)

**Files:** Modify: `skills/appbox-designer/runtime/vendor/inspect.js` (~L47–52 `accent()`, ~L148–160 `fillReadout`, ~L210–226 `showOverlay`); copy to the two sibling paths.

- [ ] **Step 1: `accents()` resolver.** Replace `accent()` with a resolver returning `{ accent, onAccent }`. Order: (1) `window.parent.document.querySelector('#app')` computed `--accent`/`--on-accent` (same-origin; island already uses `parent.htmx`; wrap in try/catch for detached frames), (2) local `[data-accent]` host, (3) literals `#0891b2` / `#FFFCF0`.
- [ ] **Step 2: badge cssText.** `background:${accent}; color:${onAccent}; font-size:11px; line-height:1.4; padding:4px 10px; border-radius:6px 6px 6px 0; white-space:nowrap; box-shadow:0 2px 8px rgba(0,0,0,.25);` — drop the `#1e1e2e` dark palette and the accent border-left. Add `font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;` on the label container.
- [ ] **Step 3: readout lines.** Name line: `font-weight:600;color:inherit;` (keep `opacity:.7` only for the screen-fallback case). Sub line: `font-size:10px;opacity:.75;color:inherit;` — remove hardcoded `#fff`/`#7f849c`/`#cdd6f4`.
- [ ] **Step 4: outline.** Keep `box-shadow:inset 0 0 0 2px ${accent};background:${accent}1a;` — it follows the new resolver automatically.
- [ ] **Step 5:** Sync all three copies; `md5 -q` on each must match. Commit: `fix: inspect badge follows studio accent with on-accent text and pinned font`

### Task 2: Widget-only hover targeting (inspect.js)

**Files:** Modify: same three copies (~L61–110 `inspectTarget`, `synthesize`, `buildChain`, `measure`).

- [ ] **Step 1: SVG collapse.** In `inspectTarget(raw)`: if `raw.ownerSVGElement` (or `raw.closest('svg')`), replace `raw` with the `<svg>` element before resolution.
- [ ] **Step 2: widget snap.** Resolve `raw.closest('[data-el]')` (skipping `inspect-*` overlay nodes). Found → return that widget. Not found → return `document.body` sentinel for screen fallback.
- [ ] **Step 3: screen fallback.** For the sentinel: outline the full screen surface, badge shows `body.dataset.surface || 'screen'` with sub `unannotated region`, `inferred:'1'`. This is the ONLY remaining inferred case; `ROLE_BY_TAG` no longer names hover targets (keep the map only if `buildChain` still labels the single allowed non-`data-el` parent — otherwise delete it).
- [ ] **Step 4: breadcrumb.** `buildChain` collects `[data-el]` ancestors only; drop the `grabbedNonDataEl` grab.
- [ ] **Step 5: payload.** `measure()` unchanged in shape; `role` comes only from `data-inspect-role`; click lock posts the widget (or screen fallback) to `/design/inspector/select` exactly as today.
- [ ] **Step 6:** Sync copies. Commit: `fix: inspect hover snaps to nearest authored widget and collapses svg internals`

### Task 3: Vendor cache-busting (`?v=` content hash)

**Files:** Modify: `designs/appbox-studio/ui/common/base.tsx:75-77`, `designs/appbox-studio/ui/views/main_shell/build/loop/screen_stub_view.tsx:119,124` (and the htmx4 tag at :72 keeps its SRI, no `?v=` needed); `designs/appbox-studio/services/facades/design_facade.js` (compute + expose hash map).

- [ ] **Step 1:** In the facade, at module init, hash each file in the served vendor dir (first 12 hex of sha256 of file bytes) into `vendorRev[name]`; expose to view props.
- [ ] **Step 2:** Templates render `src={`/assets/vendor/inspect.js?v=${vendorRev['inspect.js']}`}` — same for `canvas.js`, `drag.js`, `reveal.js`, `flowwalk.js`.
- [ ] **Step 3:** Verify served HTML carries `?v=` (curl the stub route via sandbox), and that changing a byte in inspect.js changes the rev.
- [ ] **Step 4:** Commit: `feat: vendor script tags carry content-hash cache buster`

### Task 4: Lint check — annotation coverage

**Files:** Modify: `appboxd/lib/design_tools.dart` (where `appbox design lint` checks live).

- [ ] **Step 1:** Add check `widget-coverage`: parse served/authored surface HTML; flag visible interactive or text leaves (`button,a,input,select,textarea,h1-h6,p,label,svg`) with no `[data-el]` on self or any ancestor. Report file + selector path.
- [ ] **Step 2:** Run against appbox-studio surfaces; fix any gaps it finds by adding `inspectAttrs()` at the widget boundary (not on leaves inside an annotated widget).
- [ ] **Step 3:** Commit: `feat: design lint flags visible elements outside any authored widget`

### Task 5: Probes

**Files:** Modify: `appboxd/lib/probes/studio/probe_inspect.dart`.

- [ ] **Step 1:** Uniformity probe: hover a widget in studio chrome and in two different artifact tiles; assert computed `font-family` starts with `-apple-system`, `background` equals the studio `--accent` (resolve it from `#app`), `color` equals `--on-accent` — identical across all three.
- [ ] **Step 2:** Targeting probe: dispatch hover on a `path` inside an icon; assert badge name equals the owning widget's `data-el`, never `path`/`svg`. Hover a bare unannotated `div` region; assert screen-fallback badge (`unannotated region`).
- [ ] **Step 3:** Cache probe: assert every vendor `<script src>` in served stub HTML matches `\?v=[0-9a-f]{12}`.
- [ ] **Step 4:** Run the probe suite to green. Commit: `test: probes pin inspect badge uniformity, widget snap, and vendor cache busting`

## Verification (whole plan)

- [ ] `appbox design lint` green including new `widget-coverage` check
- [ ] Probe suite green; hard-refresh not required for new badge (fresh `?v=`)
- [ ] Manual: flip studio accent pref → every badge (chrome + tiles) follows on next hover
