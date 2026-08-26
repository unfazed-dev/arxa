# Agent brief — eject web productionization

You are implementing an approved plan. Read the plan first; it contains the
locked decisions, verified facts with exact file paths, and per-phase
verification gates. Do not re-litigate strategy; do not expand scope.

## Read first (in order)

1. `docs/plans/eject-web-productionization.md` (this repo, branch
   `arxa-designer-feature`) — the binding plan. Its "Current machinery"
   section has every path you need.
2. `.kimi-code/skills/arxa-designer/built-in-skills/productionize.md` —
   what eject means today.
3. `.kimi-code/skills/arxa-designer/examples/hello-hda/` — the reference
   artifact all phases use.
4. `arxa/lib/design_tools.dart:1208-1303` (eject) and
   `arxa/lib/design_server/worker_assets/worker_shim.js` (the Hono shim
   you are replacing with a real runtime).

## Working agreement

- Work on branch `arxa-designer-feature` in
  `.kimi-code/worktrees/arxa-designer-feature`. Never touch the main
  checkout. Never commit or push unless the user explicitly asks.
- **The artifact contract is frozen**: no changes to artifact format,
  `app.routes.js` shape, registry schema, or lint rules
  (`design_tools.dart:60-71`). All production machinery lives in the eject
  step and emitted `runtime/` modules. If you believe a change requires
  touching the contract, stop and report — that is a decision for the user.
- The Dart design server and `worker_shim.js` are design-time only — do not
  modify them except where a phase explicitly says (Phase 2 vendoring).
- Match the repo's existing conventions (Dart style in arxa, JSDoc style
  in emitted JS). Minimal diffs; no speculative abstractions.
- Every phase ends by running its verification gate from the plan and
  pasting the actual command output into your report. A phase is not done
  while its gate is red.

## Execution order

Phases are sequential through Phase 1; then 2 and 3 may run in parallel;
4 needs 1; 5 needs 1 and 4; 6 is last.

- **Phase 0 (spike, do first, small)**: hello-hda served by real Hono on
  Node, artifact unchanged. Deliverable is the gap list (shim `c` vs real
  Hono `c`) + lens-clean screenshots. If the spike reveals the premise is
  wrong, stop and report — do not patch around it.
- **Phase 1**: `--target=cloudflare|vercel|node` eject scaffold:
  `package.json`, `server.js`/`worker.js`, `runtime/helpers.js`,
  `runtime/realtime.js` (SSE bus — event IDs + replay buffer from day one,
  in-memory default, DO seam documented), fixtures strategy per target,
  `wrangler.toml`/`vercel.json`, README with the one-way-eject statement.
- **Phase 2**: htmx 4 vendoring — add htmx 4.x + bundled `hx-sse`
  extension, remove `idiomorph-ext`/old `sse` for v4 artifacts, keep them
  for 2.x. Morph is core in v4. Pin ≥ the #3606 fix (beta6+).
- **Phase 3**: islands machinery — `runtime/islands.js` (htmx 4 extension:
  `registerExtension`, `htmx_after_process` discovery of `[hx-island]`,
  `hx-island-when` conditions, capture-phase delegated lazy handlers, no
  replay queue, `htmx:before:cleanup` teardown), esbuild per-island chunks
  + SRI + import map, state-in-HTML resume (JSON + `<`-escaping floor),
  `runtime/island-kit.js` (alien-signals + ~120-line binding layer +
  MutationObserver teardown), designer-side micro-islands (toggle, tabs,
  counter, form-state, derived-text).
- **Phase 4**: typing — `tsconfig` checkJs, JSDoc sweep of emitted runtime
  modules, `runtime/routes.{js,d.ts}` codegen from the parsed route table
  (parse, don't eval), `runtime/forms.js` zod convention (benchmark UX
  against Unpoly).
- **Phase 5**: kits — extend `config/kit-registry.json` with `web` objects
  and `config/credentials.catalog.json` reuse; emit facades for supabase,
  stripe, maps; realtime bridges (Supabase via Database Webhooks, Stripe
  `constructEventAsync` + event-ID dedupe); amend ADR-0008.
- **Phase 6**: deploy + the full acceptance gate from the plan, including
  publishing payload/TTI numbers.

## Hard rules

- No new runtime dependencies beyond the plan's list (hono, nunjucks, zod,
  typescript, esbuild, alien-signals, optional devalue, per-target tooling,
  official kit SDKs). Anything else needs explicit user approval.
- Design-time behavior must not change: after your work,
  `arxa design serve` + lint + selftest on hello-hda and
  `designs/arxa-studio` must be exactly as green as before. Run them.
- htmx 4 is beta: isolate every extension-hook usage in
  `runtime/islands.js` alone.
- Report per phase: what was built (paths), gate output, deviations from
  the plan and why, open risks.

## Reference docs in this repo

- Plan: `docs/plans/eject-web-productionization.md`
- Skill contract: `.kimi-code/skills/arxa-designer/SKILL.md`,
  `DESIGN-ARCHITECTURE.md`, `docs/adr/0008-productionize-eject-harden.md`
- Research basis: the plan's strategy/phase sections cite the verified
  claims (htmx 4 beta6 source, alien-signals choice, SSE platform limits,
  resumability mechanics) — trust them, don't re-research.
