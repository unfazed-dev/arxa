// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev

// Q13 parallel-run shell selector.
//
// Selects between a view's legacy shell template and its showcase-anatomy
// twin, so both trees can be rendered from one running server and diffed
// view-by-view without a restart.
//
// `.js`, not `.ts`, deliberately: viewmodels are native ESM importing with
// explicit extensions, and the eject copier (design_tools.dart:1360) takes
// only *.js, *.d.ts and *.tsx — a plain .ts would neither resolve at runtime
// nor survive the eject. See docs/plans/q13-parallel-run-design-shell.md
// finding 7.

/// Views cut over to the anatomy shell by default, in cutover order.
/// Empty today: every view still renders its legacy shell, so the build is
/// byte-identical until a name is added here. Adding a name IS the cutover.
const kDefaultAnatomyViews = [];

/// Probe/CI override: `APPBOX_ANATOMY_VIEWS=chat,freeze` flips views without
/// editing source, so the dual-render probe can drive both trees in one pass.
/// Guarded — the eject runtime is not guaranteed to expose `process`.
function envAnatomyViews() {
  const env =
    typeof process !== 'undefined' && process && process.env
      ? process.env.APPBOX_ANATOMY_VIEWS
      : undefined;
  if (typeof env !== 'string' || env.length === 0) return null;
  return env.split(',').map((s) => s.trim()).filter(Boolean);
}

/// The effective default set. Env wins over source when present.
export const abxAnatomyViews = envAnatomyViews() ?? kDefaultAnatomyViews;

/// Resolve which shell template `viewName` should render.
///
/// Precedence: explicit `?abxShell=anatomy|legacy` on the request, then the
/// default set above. The query param is per-request and never sticky, so a
/// probe can A/B the same screen in one session.
///
/// IMPORTANT: resolve ONCE per request and reuse the result across every
/// handler in the viewmodel — `page` is not the only handler that renders
/// this template. Siblings render `${resolved}#Fragment` for htmx swaps, and
/// mixing a legacy fragment into an anatomy page is a silent hybrid that no
/// first-paint probe will catch. See finding 8.
export const abxResolveShellView = (c, viewName, base, anatomy) => {
  const forced = c.req.query('abxShell');
  if (forced === 'anatomy') return anatomy;
  if (forced === 'legacy') return base;
  return abxAnatomyViews.includes(viewName) ? anatomy : base;
};
