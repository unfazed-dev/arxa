// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
// Intake routes — same [method, path, handler] shape as app.routes.js.
// Wire by spreading into the default export of app.routes.js; see
// _integration_intake.md for the exact patch.
//
// The shell root /intake IS the interview (the journey's first step); the
// story map lives at /intake/map. The four item-engine steps (personas,
// surfaces, flows, direction) share one route shape: page + the panel chrome
// + confirm/save/skip/edit/accept-all.
import * as interview from './interview/interview_viewmodel.js';
import * as personas from './personas/personas_viewmodel.js';
import * as surfaces from './surfaces/surfaces_viewmodel.js';
import * as flows from './flows/flows_viewmodel.js';
import * as mapping from './mapping/mapping_viewmodel.js';
import * as direction from './direction/direction_viewmodel.js';
import * as brief from './brief/brief_viewmodel.js';
import * as moodboard from './moodboard/moodboard_viewmodel.js';

// The item-engine route set, identical for the four steps.
const stepRoutes = (base, vm) => [
  ['GET', base, vm.page],
  ['GET', `${base}/file`, vm.file],
  ['GET', `${base}/model/:id`, vm.model],
  ['GET', `${base}/panel`, vm.panel],
  ['GET', `${base}/panel/size/:panel/:size`, vm.panelSize],
  ['POST', `${base}/messages`, vm.sendMessage], // posted-by: c.composerAction (intake_facade)
  ['POST', `${base}/confirm`, vm.confirm],
  ['POST', `${base}/save`, vm.save],
  ['POST', `${base}/skip`, vm.skip],
  ['GET', `${base}/edit`, vm.edit],
  ['POST', `${base}/accept-all`, vm.acceptAll],
];

export default [
  // intake.interview — the journey's first step (shell root IS the interview)
  ['GET', '/intake', interview.page],
  ['GET', '/intake/file', interview.file],
  ['GET', '/intake/model/:id', interview.model],
  ['GET', '/intake/panel', interview.panel],
  ['GET', '/intake/panel/size/:panel/:size', interview.panelSize],
  ['POST', '/intake/messages', interview.sendMessage], // posted-by: c.composerAction (intake_facade)
  ['POST', '/intake/depth', interview.depth], // posted-by: r.action quick-replies (intake_facade)
  ['POST', '/intake/answer', interview.answer], // posted-by: intake/_shared.tsx `${base}/answer` forms (hx-post)
  ['POST', '/intake/skip', interview.skip], // posted-by: intake/_shared.tsx `${base}/skip` forms (hx-post)
  ['GET', '/intake/edit', interview.edit],

  // intake.personas / intake.surfaces / intake.flows / intake.direction
  ...stepRoutes('/intake/personas', personas),
  ...stepRoutes('/intake/surfaces', surfaces),
  ...stepRoutes('/intake/flows', flows),
  ...stepRoutes('/intake/direction', direction),

  // intake.mapping — Story Map
  ['GET', '/intake/map', mapping.page],
  ['GET', '/intake/map/artifact/:kind/:id', mapping.artifact],
  ['GET', '/intake/map/file', mapping.file],
  ['GET', '/intake/map/model/:id', mapping.model],
  ['GET', '/intake/map/panel', mapping.panel],
  ['GET', '/intake/map/panel/size/:panel/:size', mapping.panelSize],
  ['POST', '/intake/map/messages', mapping.sendMessage], // posted-by: c.composerAction (intake_facade)
  ['POST', '/intake/map/approve', mapping.approve], // posted-by: r.action quick-replies (intake_facade)

  // intake.brief — Design Brief (carries the approval gate)
  ['GET', '/intake/brief', brief.page],
  ['GET', '/intake/brief/artifact/:kind/:id', brief.artifact],
  ['GET', '/intake/brief/file', brief.file],
  ['GET', '/intake/brief/model/:id', brief.model],
  ['GET', '/intake/brief/panel', brief.panel],
  ['GET', '/intake/brief/panel/size/:panel/:size', brief.panelSize],
  ['POST', '/intake/brief/messages', brief.sendMessage], // posted-by: c.composerAction (intake_facade)
  ['POST', '/intake/brief/approve', brief.approve], // posted-by: r.action quick-replies (intake_facade)

  // intake.moodboard — Moodboard
  ['GET', '/intake/moodboard', moodboard.page],
  ['GET', '/intake/moodboard/artifact/:kind/:id', moodboard.artifact],
  ['GET', '/intake/moodboard/file', moodboard.file],
  ['GET', '/intake/moodboard/model/:id', moodboard.model],
  ['GET', '/intake/moodboard/panel', moodboard.panel],
  ['GET', '/intake/moodboard/panel/size/:panel/:size', moodboard.panelSize],
  ['POST', '/intake/moodboard/messages', moodboard.sendMessage], // posted-by: c.composerAction (intake_facade)
];
