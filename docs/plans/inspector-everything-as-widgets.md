# Inspector: Everything On Screen Is An Inspectable Widget — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every element rendered inside the design shell viewer's screen iframes — containers, rows, buttons, text, labels — is an inspectable widget: hover/click yields an inspector card, with a clickable ancestor breadcrumb (widgets-in-widgets), un-migrated elements shown as `inferred`.

**Architecture:** Widget-first composition — the widget library auto-emits `data-el` + `data-inspect-*` from a single `inspectAttrs()` helper, so identity comes free at every nesting level; new leaf primitives (`Label`, `Heading`, `Txt`) make text a widget. The inspect island gains innermost-target selection, an ancestor-chain payload, and a synthesized-identity fallback (`inferred`) for anything not yet widgetized. A new W7 gate rule makes coverage enforced, not aspirational.

**Tech Stack:** Hono JSX templates (`.tsx`), first-party JS island (`inspect.js`, IIFE, no framework), Dart (`arxa` design server + gates), htmx transport.

## Decisions already made with the user (do not relitigate)

1. **Scope:** artifact screens rendered in viewer tiles only (incl. `designs/arxa-studio` when viewed). Studio chrome around the viewer is NOT inspectable.
2. **Mechanism:** widget-first composition (C) + island inference fallback marked `inferred` (B).
3. **Selection:** innermost widget wins; inspector pane shows full ancestor breadcrumb, each crumb clickable to re-lock.
4. **Depth:** full migration of all studio surfaces now, plus a gate rule (W7) so it can't regress.

## Global Constraints

- **No ad-hoc client JS** — named islands only (`skills/arxa-designer/runtime/vendor/`). All new client behavior goes in `inspect.js`.
- **Vendor SSOT:** the design server serves `skills/arxa-designer/runtime/vendor` (`arxa/lib/design_server.dart:1360`). `.claude/skills/arxa-designer/` and `.kimi-code/skills/arxa-designer/` are **copies, not symlinks** — before first edit run `~/.agents/skills/consultant/scripts/consult.sh gate skill arxa-designer`; after editing, sync both copies byte-identical (`cp`) in the same commit.
- **Commit format:** single line, no author mentions, e.g. `feat: emit inspect identity from widget primitives`.
- **Island contract (ADR-0002):** island only measures and POSTs (`window.parent.htmx.ajax('POST', '/design/inspector/select', {values})`); the server renders the pane. Keep that split.
- **Serve/verify loop:** `dart run arxa/bin/arxa.dart design serve designs/arxa-studio --port 4319` (plain `arxa` is not on PATH). Lint: `dart run arxa/bin/arxa.dart design lint designs/arxa-studio`.
- **Existing gate:** `arxa/lib/gate_design_widgets.dart` holds W1–W6; W7 is added there, same failure-message style (`W7 <file>:<line> — <concrete fix>`).
- **Defensive pane rendering:** `inspector_pane.tsx` guards every scalar / length-checks every list; keep that for all new fields.

---

### Task 1: `inspectAttrs()` helper + leaf text primitives

**Files:**
- Modify: `designs/arxa-studio/ui/common/widgets/primitives.tsx`

**Interfaces:**
- Produces: `inspectAttrs(name: string, meta: {role: string; style?: string; motion?: string; fn?: string}): Record<string,string>` returning `{'data-el': name, 'data-inspect-role': …, 'data-inspect-style': …, 'data-inspect-motion': …, 'data-inspect-fn': …}` (omit undefined keys).
- Produces: `Label`, `Heading`, `Txt` components; all existing primitives (`Chip`, `StatusPill`, `TypeBadge`, `CtaLink`) spread `inspectAttrs`.

- [ ] **Step 1: Add the helper** (top of `primitives.tsx`, exported):

```tsx
// inspectAttrs — the ONE source of widget inspect identity. Every library
// widget spreads this on its root element; screens never hand-write
// data-inspect-* again. name is what the inspect overlay badge shows.
export function inspectAttrs(
  name: string,
  meta: { role: string; style?: string; motion?: string; fn?: string },
): Record<string, string> {
  const a: Record<string, string> = { 'data-el': name, 'data-inspect-role': meta.role };
  if (meta.style) a['data-inspect-style'] = meta.style;
  if (meta.motion) a['data-inspect-motion'] = meta.motion;
  if (meta.fn) a['data-inspect-fn'] = meta.fn;
  return a;
}
```

- [ ] **Step 2: Add leaf text widgets** (same file):

```tsx
interface TextProps { name?: string; fn?: string; class?: string; children?: unknown }

export function Label(props: TextProps) {
  return (
    <span class={props.class} {...inspectAttrs(props.name ?? 'label', { role: 'label', style: 'text · label', fn: props.fn })}>
      {props.children}
    </span>
  );
}

export function Heading(props: TextProps & { level?: 1 | 2 | 3 }) {
  const Tag = `h${props.level ?? 2}` as 'h2';
  return (
    <Tag class={props.class} {...inspectAttrs(props.name ?? 'heading', { role: 'heading', style: 'text · heading', fn: props.fn })}>
      {props.children}
    </Tag>
  );
}

export function Txt(props: TextProps) {
  return (
    <p class={props.class} {...inspectAttrs(props.name ?? 'text', { role: 'text', style: 'text · body', fn: props.fn })}>
      {props.children}
    </p>
  );
}
```

- [ ] **Step 3: Retrofit `Chip`, `StatusPill`, `TypeBadge`, `CtaLink`** — spread `inspectAttrs` on each root element. Name pattern: `chip:<label>`, `status:<label>`, `type:<label>`, `cta:<label>` (mirrors the existing `data-el="hero:…"`/`list-item:Block N` convention in `screen_stub_view.tsx`).

- [ ] **Step 4: Verify + commit** — `dart run arxa/bin/arxa.dart design lint designs/arxa-studio` clean; serve and confirm a chip in any rendered screen shows the hover badge in inspect mode. `git commit -m "feat: inspectAttrs helper and leaf text primitives with auto inspect identity"`.

### Task 2: Retrofit the remaining widget library

**Files (modify each; spread `inspectAttrs` on the component's root — and on meaningful inner regions where the widget has them):**
- `designs/arxa-studio/ui/common/widgets/_panel.tsx`, `chrome.tsx`, `header_panel.tsx`, `main_panel.tsx`
- `designs/arxa-studio/ui/views/main_shell/shared/widgets/activity_panel.tsx`, `composer_panel.tsx`, `composer.tsx`, `design_viewer.tsx`, `footer_panel.tsx`, `mini_panel.tsx`, `timeline.tsx`, `widget_editor.tsx`

**Interfaces:**
- Consumes: `inspectAttrs` from Task 1 (import from `ui/common/widgets/primitives.tsx`).

- [ ] **Step 1:** For each file, import `inspectAttrs` and spread on the root element of every exported component. Role vocabulary (keep to these): `nav`, `hero`, `heading`, `label`, `text`, `action`, `list`, `list row`, `card`, `panel`, `toolbar`, `input`, `image`, `group`.
- [ ] **Step 2:** These widgets are studio *chrome* — identity attributes are inert outside an armed iframe (the island only runs in screen renders), so no behavior change is expected in the shell. Confirm with `dart run arxa/bin/arxa.dart lens check http://localhost:4319/` (console clean).
- [ ] **Step 3:** Commit — `git commit -m "feat: widget library emits inspect identity from inspectAttrs"`.

### Task 3: Inspect island — innermost target, ancestor chain, inference fallback

**Files:**
- Modify: `skills/arxa-designer/runtime/vendor/inspect.js` (SSOT — run the gate-skill check first; sync `.claude/` + `.kimi-code/` copies in the same commit)

**Interfaces:**
- Produces POST values to `/design/inspector/select`: existing fields **plus** `inferred` (`'1'`/absent) and `chain` — JSON string, outermost→innermost, `[{el, role, inferred}]` (each entry's `el` is the `data-el` name or synthesized name; `role` from dataset or heuristic).

- [ ] **Step 1: Widen targeting.** Where hover currently resolves `e.target.closest('[data-el]')`, resolve the raw `e.target` element first (innermost wins). If it carries `data-el` → identified path unchanged. If not → build synthesized identity:

```js
// ponytail: tag-map heuristic, extend the map before reaching for anything smarter
const ROLE_BY_TAG = { H1:'heading',H2:'heading',H3:'heading',H4:'heading',H5:'heading',H6:'heading',
  P:'text',SPAN:'text',LABEL:'label',BUTTON:'action',A:'action',IMG:'image',SVG:'image',
  UL:'list',OL:'list',LI:'list row',NAV:'nav',HEADER:'nav',FOOTER:'group',SECTION:'group',
  INPUT:'input',SELECT:'input',TEXTAREA:'input' };
const synthesize = (el) => ({
  name: el.dataset.el || (el.textContent || '').trim().slice(0, 24) || el.tagName.toLowerCase(),
  role: el.dataset.inspectRole || ROLE_BY_TAG[el.tagName] || 'group',
  inferred: el.dataset.el ? '' : '1',
});
```

  Skip only: the island's own overlay nodes, `<body>`, `<html>`, `<script>`, `<style>`.
- [ ] **Step 2: Ancestor chain.** Walk `el.parentElement` up to `<body>`; keep every element that has `data-el` **or** bears a role per `synthesize` heuristic worth showing (elements with `data-el` always; un-annotated ancestors only if they'd synthesize to something ≠ bare `group` OR they have `data-el` descendants — simplest correct filter: keep `data-el` ancestors + the immediate parent). Serialize outermost→innermost into `chain`. Include the hovered element itself as the last entry.
- [ ] **Step 3: POST additions.** Add `inferred` and `chain` to the `values` object of the existing `htmx.ajax('POST','/design/inspector/select',…)` call. Overlay badge shows the synthesized name for inferred elements, tinted at reduced opacity (add a `.inferred` style to the overlay label, or inline `opacity:.6`).
- [ ] **Step 4: Sync copies.** `cp skills/arxa-designer/runtime/vendor/inspect.js .claude/skills/arxa-designer/runtime/vendor/inspect.js && cp skills/arxa-designer/runtime/vendor/inspect.js .kimi-code/skills/arxa-designer/runtime/vendor/inspect.js`
- [ ] **Step 5: Verify** — serve, open a screen tile with inspect armed, hover a bare `<p>` in any un-migrated screen: badge appears, POST fires (check server log / pane swap). Commit — `git commit -m "feat: inspect island infers identity for unannotated elements and reports ancestor chain"`.

### Task 4: Select handler + inspector pane breadcrumb

**Files:**
- Modify: `designs/arxa-studio/ui/views/main_shell/design/routes.design.js` (the `inspectorSelect` handler)
- Modify: `designs/arxa-studio/ui/views/main_shell/design/inspector_pane.tsx`

**Interfaces:**
- Consumes: POST fields `inferred`, `chain` (Task 3).
- Produces viewmodel fields on `c.inspector.element`: `inferred?: boolean` (whole-element flag) and `chain?: Array<{el: string; role?: string; inferred?: boolean; selectHref?: string}>` (outermost→innermost; last entry is the current element, no `selectHref`).

- [ ] **Step 1: Handler.** In `inspectorSelect`, parse `chain` (guard: `try { JSON.parse } catch { [] }` — trust boundary: island input), store it in the session next to the existing element fields, and mark `inferred` on the element. Chain entries get `selectHref` built the same way existing pane actions echo state (each crumb re-locks by POSTing `/design/inspector/select` with that entry's stored fields — the island already measured them; no client re-measure needed).
- [ ] **Step 2: Pane breadcrumb.** In `inspector_pane.tsx` element card, above the existing role/style/motion/fn rows:

```tsx
{Array.isArray(el.chain) && el.chain.length > 1 && (
  <nav class="insp-crumbs" aria-label={t('inspector.chainAria') as string}>
    {el.chain.map((c, i) => (
      <Fragment key={i}>
        {i > 0 && <span class="insp-crumb-sep">›</span>}
        {c.selectHref
          ? <button class={`insp-crumb${c.inferred ? ' is-inferred' : ''}`} hx-post={c.selectHref} hx-target="#panels" hx-swap="outerHTML">{c.el}</button>
          : <span class={`insp-crumb is-current${c.inferred ? ' is-inferred' : ''}`}>{c.el}</span>}
      </Fragment>
    ))}
  </nav>
)}
```

  Reuse the pane's existing INFERRED marking treatment for `.is-inferred` (grey/inferred styling) and add `.insp-crumbs` styles beside the pane's existing CSS (wrap, small type, separator muted). All strings via `t()` — no hardcoded copy.
- [ ] **Step 3: Whole-element inferred banner.** When `el.inferred`, render the pane's existing inferred marker at card level (the element was never widgetized — visible debt marker per decision 2).
- [ ] **Step 4: Verify** — hover nested content: pane shows `screen › card › row › label` style crumbs; click an ancestor crumb: pane re-locks to it; lock survives morphs (lock lives in session — unchanged). Commit — `git commit -m "feat: inspector pane ancestor breadcrumb with inferred markers"`.

### Task 5: W7 gate rule — no anonymous text/interactive elements in surfaces

**Files:**
- Modify: `arxa/lib/gate_design_widgets.dart`
- Test: wherever W1–W6 tests live (locate with `grep -rn "gate_design_widgets" arxa/test/` and follow the existing test pattern — same fixture style, red-first)

**Interfaces:**
- Produces: rule **W7** — *in surface/view templates outside widget-library dirs (`ui/common/widgets/`, `ui/*/shared/widgets/`, `<surface>/widgets/`), a rendered HTML element that bears literal text content or is interactive (`button|a|input|select|textarea`) must carry widget identity: literal `data-el` attribute, a spread of `inspectAttrs(…)`, or be a library-widget invocation.* Failure message: `W7 <file>:<line> — wrap this <tag> in a library widget (Label/Heading/Txt/…) or spread inspectAttrs(...)`.

- [ ] **Step 1: Write the failing test** — fixture surface template containing `<span>Raw text</span>` fails with a W7 message naming file+line; the same content as `<Label>Raw text</Label>` and as `<span data-el="x">…</span>` passes.
- [ ] **Step 2: Run it, confirm it fails** (`dart test` on the gate's test file).
- [ ] **Step 3: Implement W7** in `gate_design_widgets.dart` following the W1–W6 shape (the file already parses template sources and builds the include graph — reuse its file-walk; scan JSX source lines, not rendered output). Detection is source-level: a lowercase-tag JSX element whose children include a non-whitespace text literal or `{t(` call, or whose tag is in the interactive set, without `data-el`/`inspectAttrs` in its attribute span. `// ponytail: line-regex scan like the sibling rules, not a JSX parser — upgrade only if false positives appear in practice`.
- [ ] **Step 4: Run test to green.** Note: the full gate over `designs/arxa-studio` will (correctly) fail until Task 6 completes — the test fixtures are green, the studio tree is the migration backlog. Print the W7 count; it is Task 6's progress meter.
- [ ] **Step 5: Commit** — `git commit -m "feat: W7 gate rule requires widget identity on text and interactive elements"`.

### Task 6: Migrate all studio surfaces to widget-first

**Files:** every W7-failing template under `designs/arxa-studio/ui/` (47 surface files total; the W7 output from Task 5 is the authoritative worklist). Batch by directory:
1. `ui/views/main_shell/design/**` (incl. `chat/`, `freeze/`, `prototype/`, `inspector_pane.tsx`)
2. `ui/views/main_shell/build/**` (`screen_stub_view.tsx` keeps its hand-written `data-el` — already compliant)
3. remaining `ui/views/**` and `ui/common/**` non-widget templates

**Interfaces:**
- Consumes: `Label`, `Heading`, `Txt`, `inspectAttrs` (Task 1); W7 output (Task 5).

- [ ] **Step 1 (per batch):** Replace raw text-bearing elements with `Label`/`Heading`/`Txt` (or spread `inspectAttrs` where a bespoke element is structurally necessary — e.g. elements whose tag/attrs the leaf widgets don't cover). Interactive elements get `inspectAttrs` with role `action`/`input`. Repeated intra-shell patterns that emerge → promote to `ui/views/main_shell/shared/widgets/` per W1 placement law, don't inline-copy.
- [ ] **Step 2 (per batch):** `dart run arxa/bin/arxa.dart design lint designs/arxa-studio` + run the W-gate — W7 count strictly decreases, W1–W6 stay green.
- [ ] **Step 3 (per batch):** Visual regression — `arxa lens shoot` the affected routes at **every width in the active ladder** (read the ladder from config per skill rules); compare against pre-migration shots (shoot a baseline set before batch 1). Zero intended visual delta: this is a structural refactor.
- [ ] **Step 4 (per batch):** Commit — `git commit -m "refactor: migrate <batch> surfaces to widget-first inspect identity"`.
- [ ] **Step 5 (final):** W7 count is 0 over `designs/arxa-studio`.

### Task 7: End-to-end verification

- [ ] Serve: `dart run arxa/bin/arxa.dart design serve designs/arxa-studio --port 4319` (background).
- [ ] `dart run arxa/bin/arxa.dart design lint designs/arxa-studio` — clean; W-gate (W1–W7) — green.
- [ ] `dart run arxa/bin/arxa.dart lens check http://localhost:4319/` — console clean.
- [ ] Manual/probe pass in the design shell viewer with a tile's inspect armed: (1) hover any text → labelled badge + pane card; (2) hover a button → `action` card with breadcrumb to its screen root; (3) crumb click re-locks; (4) an intentionally-raw element in a scratch fixture shows `inferred`; (5) lock survives a morph; (6) pin still POSTs `/design/chat/context/element`.
- [ ] Commit anything outstanding; hand back for review (the plan author reviews — user instruction).
