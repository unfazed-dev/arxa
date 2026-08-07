# Consolidated review — eject web productionization (pre-merge)

Date: 2026-08-06. Reviewers: 6 subagent audits (TSX migration, eject
scaffold, islands/htmx4, typing/kits, scaffolder-inputs trace, gates
re-run) over the uncommitted working tree, cross-corroborated. The reviewed
state was committed as-is; this document is the fix backlog.

Verdict: **not merge-ready at review time.** The spine is real and verified
(eject→node boots, typechecks, serves, lens-clean; timers/locale/fragments
correct; vendor SRI hashes recomputed and matching; scaffolder inputs
byte-identical). But the shipped JavaScript had never been executed, the
freeze gate blocks TSX designs, and the TSX migration is half-finished at
the seams.

## Blockers

### Runtime (ejected app)

- **R1 — every island dead on arrival.** `runtime/eject/assets/island-kit.js:32`
  calls `effectScope()` bare (alien-signals 3.2.1 requires `effectScope(fn)`
  → stop fn; `.run()`/`.stop()` don't exist); `:37` calls `fn(el, ctx)` —
  `fn` undefined (param is `init`). Also `runtime/vendor/form-state_island.js:24`
  uses `computed` without destructuring it. Found by two independent
  reviewers; Dart tests can't see it (no JS execution).
- **R2 — SSE bus never attached.** `attachSse(app)` (`runtime/realtime.js:54`)
  imported nowhere → `GET /__events` 404s while the README advertises
  realtime.
- **R3 — Cloudflare target serves no vendor assets.** Eject copies vendor to
  `runtime/vendor/` but `wrangler.toml [assets]` points at `./assets` →
  `/assets/vendor/htmx4.min.js` 404s on Workers → inert pages on the primary
  target. (Vercel has no equivalent route either.)
- **R4 — typed-route moat inert.** ejected `tsconfig.json:3` has
  `checkJs: false` (plan mandates true); nothing imports generated
  `runtime/routes.js` → "renaming a route breaks typecheck" is false.
- **R5 — `islands.js` uses the htmx-2 extension API** (`onEvent`,
  `htmx:afterProcessNode`, `htmx:beforeCleanupElement`) against htmx 4
  beta6 — dead code; discovery survives only via the `htmx.onLoad` alias.
  The file's comment claims it's the single hook call-site to fix — and
  it's wrong for the pinned runtime. Separately: old glue islands
  (`canvas.js`, `game_island.js`, `map_island.js`, `rive_island.js`,
  `three_island.js`) still listen for v2 event names → silently inert
  under htmx 4.

### Pipeline

- **P1 — freeze gate broken for TSX designs.** `gate_freeze.dart:278-283`
  requires `ui/views/**/*_view.html`; zero exist post-migration →
  `appbox gate freeze` fails. Also `_inputsHash` (:331-340) folds
  `*_view.html` bytes into the approval stamp — with zero matches the view
  layer silently drops out of freeze invalidation. (Scaffolder inputs
  themselves are intact: `scaffold.dart`/`emit_structure.dart` never read
  view templates; `structure.json` inputs byte-identical.)
- **P2 — hello-hda fails its own lint.** W1 widget scope
  (`form_field.tsx`, `list_row.tsx` belong in `main_shell/shared/widgets/`),
  W5 pill radius in `assets/css/app.css:27`.
- **P3 — selftest regressions.** New kit-catalog-mirror check
  (`design_selftest.dart:113`) has no negative mutation → deterministic
  `design_selftest_test.dart` failure (branch regression; passes on
  master). And render boot fails when the artifact path is **relative**
  (worker can't fetch `app.routes.js`); absolute paths work. Fix:
  absolutize `artifactDir` before worker boot.
- **P4 — TSX migration seams.**
  (a) Authoring docs still teach Nunjucks the server can no longer render
  (`Unknown view`): `DESIGN-ARCHITECTURE.md:23`, `runtime/README.md:129-204`,
  `system-prompt.md` (28 refs), `references/ui-recipes.md` (64 `{%…%}`
  snippets), `SKILL.md:121` → `starter-partials/` (all `.html`),
  `CONTEXT.md`, `built-in-skills/use-design-system.md`,
  `import-from-figma.md`.
  (b) Project overlay edits dead files: `project_repository.js:211-214`
  (`hasPartial` keys off `__templates` = `.html`-only),
  `widget_repository.js:30-33` (`screenFile()` → `.html`, `INCLUDE_RE` =
  nunjucks), `/project-src/` exposes only `.html` (`worker.dart:207`) —
  studio edits via `/__project_write` mutate stale source while the iframe
  renders `.tsx`: **edits silently have no effect**.
  (c) Numeric-guard regression: `_shared.tsx:180`
  `{s.card?.threadCount && (<span…>)}` renders literal "0" badges —
  visible in the implementation's own evidence (`tsx-design-final.png` vs
  `master-design-final.png`), unflagged. Sweep all `&&` guards on numeric
  props in both artifacts.

## Majors

- **M1** — SSE framing: `formatSse` interpolates multi-line HTML raw; each
  continuation line needs its own `data:` prefix (`realtime.js:106-111`).
- **M2** — icons degrade to placeholders on Workers: `icon.tsx loadIcon`
  only calls `readFileSync`; the bundled `preload.iconSvg` path is dead.
- **M3** — session cookie unsigned + no `secure: true` (`state.js:13-22`);
  plan says cookie-signed. Either hono signed cookies or documented
  equivalence.
- **M4** — `vercel.json` uses legacy `builds`/`routes` with a *listening*
  server.js; no exported request handler → almost certainly undeployable.
  Either fix the entry shape or mark the target deferred in README.
- **M5** — `ctx.partial` pre-render exists only in the design-time shim
  (`worker_shim.js:178-188`); eject `helpers.js` drops it → studio-class
  artifacts (build_facade.js:318) render a path string. Port the 10 lines.
- **M6** — kit facades read `process.env` at module scope → throws on
  Workers (env arrives via fetch-handler `env` binding). Pass env in.
- **M7** — Stripe/Supabase realtime bridges are comments, not code: no
  dedupe set, no `waitUntil`, no webhook handlers, no republish to
  realtime.js.
- **M8** — 422 forms have no client wiring: htmx ignores non-2xx by
  default; no response-targets config, no focus management, no field-error
  convention, no README example (Unpoly benchmark falls short).
- **M9** — TSX syntax error kills all routes until next save (esbuild error
  only to server stderr; nunjucks era surfaced per-route). Route esbuild
  errors into the 5xx surface.
- **M10** — hx-island inert at design time: nothing in the design server
  loads `islands.js`/`island-kit.js`; plan says design-time keeps eager
  loading. Add the eager path.
- **M11** — SRI fails open when island manifest missing (`islands.js:29`),
  and manifest injection anchors on literal `<div id="toasts"` — silent
  no-op if base changes. Fail closed or warn loudly.
- **M12** — benchmark doc (`docs/review/eject-payload-benchmark.md`) uses
  an unsourced SPA baseline and arithmetic TTI estimates — not publishable
  as the plan's Phase 6 evidence. Needs methodology, real reference build,
  medians.

## Minors (fix in passing)

hx-sse allowlist row lacks SRI `expect` pin; `crypto.subtle` needs secure
context (undocumented); `islands.js` full-subtree attribute scan per swap
(O(elements×attrs)); delegated-chunk `import()` has no catch; arming leaks
for disposed-before-condition islands; `defineIsland` public API missing;
timer/drag/canvas retrofit to state-in-HTML not done; maps.js 3-provider
generality vs 1 wired provider + dead `GOOGLE_MAPS_API_KEY` path;
publishable→client-config emission missing; route-table regex loose
(hyphenated paths → invalid JS keys); missing `// @ts-check` on
islands.js/island-kit.js/server.js/worker.js; ejected default port 4319
collides with the design server; `wrangler` in dependencies not
devDependencies; stale source `render.tsx` (overwritten every eject);
unpinned `npx esbuild` shell-outs; CLI help missing `--target`/`--kits`;
provenance HTML comment lost in TSX output; stale comments
(`worker.dart:132,154`, `design_server.dart:4`, `emit_structure.dart:570`,
`docs/appbox-system-map.md:144`); no `.tsx` lint fixtures / no
`generateRenderTsx` unit tests.

## Optimizations (approved for the fix pass)

- Cache the esbuild render bundle keyed on `.tsx` content hash; call
  `node_modules/.bin/esbuild` directly (hot-reload cost).
- Delete `nunjucks.min.js` + its `worker_page.html` script tag (90 KB/boot;
  attribution already removed).
- `hasPartial` asks the render registry, not `__templates`.
- Lint rule or codemod banning `{numericProp && (...)}` in `.tsx`.
- Narrow icon-scan regex (`worker.dart:160-163`) to `<Icon name=`.
- Delete dead `Templates` interface, `bag.c = bag`, unused `artifactDir`
  param (grep first).
- One browser-level island smoke test (Playwright is already a dev dep) —
  would have caught R1.
- Regenerate `evidence/tsx-vs-master/` with a written diff report +
  `#tick` fragment byte-compare (plan's Phase A gate); resolve the
  `product-390` 2.58% delta (cause UNKNOWN).

## Decisions taken with the user (2026-08-06)

1. Commit reviewed state before fixes (done).
2. Fix scope = everything, including docs rewrite and project-overlay
   single-sourcing (touches `~/.appbox` projects — regenerate, never
   hand-edit).
3. Both artifacts move to htmx 4 (studio migrates off 2.0.10; restore
   hello-hda's dropped config intent — `allowEval:false` equivalent,
   extensions — under htmx 4 semantics).
