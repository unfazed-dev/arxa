// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
// Scaffold-shell route table — same [method, path, handler] shape as
// app.routes.js. Integration: spread into the default export of
// app.routes.js, exactly as the intake and design shells are.
//
// THE VIEWMODEL CONTRACT this file pins, for the two agents authoring the
// screen bodies: each viewmodel exports `page` (full document) and
// `panelSize` (the panel-width persist handler the shared panel base links
// to). Anything beyond that pair is the screen's own business — but the route
// table is a spine file, so a new path is requested through the team lead
// rather than added here by the screen author.
import * as picker from './picker/picker_viewmodel.js';
import * as run from './run/run_viewmodel.js';

export default [
  // scaffold.picker — kit selection (shell root: /scaffold)
  ['GET', '/scaffold', picker.page],
  ['GET', '/scaffold/panel/size/:panel/:size', picker.panelSize],
  // Kit mutations. Every one is a POST: the view posts `<form method="post">`
  // + hx-post, and the kit id travels in the form body as `kit`, never in the
  // query string. `removeConfirm` is the single exception that also reads
  // `?kit=` — the facade emits `confirmHref` with it — so one route serves
  // both entry paths. Measured precedence: `session.pendingRemove` WINS when
  // set, and `?kit=` is only consulted when it is absent (fresh session
  // `?kit=auth` and `?kit=payments` render differently; with pendingRemove
  // set both render the pending kit). The two agree in every real flow.
  // posted-by: picker_view.tsx forms; targets #picker-grid (outerHTML),
  // except removeConfirm which targets #panels (outerMorph).
  ['POST', '/scaffold/add', picker.add], // posted-by: picker_view.tsx `${c.base}/add` form (hx-post)
  ['POST', '/scaffold/remove', picker.remove], // posted-by: picker_view.tsx `${c.base}/remove` form (hx-post)
  ['POST', '/scaffold/remove/confirm', picker.removeConfirm], // posted-by: picker_view.tsx cf.confirmHref form (hx-post)
  // Composer post target. Was declared, unrouted, live 404 — see
  // docs/plans/composer-action-integrity.md.
  ['POST', '/scaffold/messages', picker.sendMessage], // posted-by: c.composerAction (scaffold_facade)
  // Cancel is a server route, not a link back to the page: clearing
  // `session.pendingRemove` is what ends the confirm, and re-rendering
  // `/scaffold` would leave it set and show the dialog again forever.
  ['POST', '/scaffold/remove/cancel', picker.cancelRemove], // posted-by: c.cancelHref (scaffold_facade)
  // scaffold.run — the scaffold execution surface
  ['GET', '/scaffold/run', run.page],
  ['GET', '/scaffold/run/panel/size/:panel/:size', run.panelSize],
  // Landed BEFORE the facade sets `composerAction`, so it is provably inert on
  // arrival: the guard at _shared.html:75 renders no form while the action is
  // falsy. The reverse order is the class-1 defect this shell already shipped
  // once — see docs/plans/composer-action-integrity.md.
  ['POST', '/scaffold/run/messages', run.sendMessage], // posted-by: c.composerAction (scaffold_run_facade)
];
