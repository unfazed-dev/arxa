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
  // scaffold.run — the scaffold execution surface
  ['GET', '/scaffold/run', run.page],
  ['GET', '/scaffold/run/panel/size/:panel/:size', run.panelSize],
];
