// appbox:provenance
// generator: app-box  licence: free  project: 662368770980
// Built with app-box (free tier) — https://appbox.dev
// Intake routes — same [method, path, handler] shape as app.routes.js.
// Wire by spreading into the default export of app.routes.js; see
// _integration_intake.md for the exact patch.
import * as mapping from './mapping/mapping_viewmodel.js';
import * as brief from './brief/brief_viewmodel.js';
import * as moodboard from './moodboard/moodboard_viewmodel.js';

export default [
  // intake.mapping — Story Mapping (the intake shell root IS the chat interview)
  ['GET', '/intake', mapping.page],
  ['GET', '/intake/artifact/:kind/:id', mapping.artifact],
  ['GET', '/intake/file', mapping.file],
  ['GET', '/intake/model/:id', mapping.model],
  ['GET', '/intake/panel', mapping.panel],
  ['GET', '/intake/panel/size/:side/:size', mapping.panelSize],
  ['POST', '/intake/messages', mapping.sendMessage],
  ['POST', '/intake/depth', mapping.depth],
  ['POST', '/intake/answer', mapping.answer],
  ['POST', '/intake/skip', mapping.skip],
  ['GET', '/intake/edit', mapping.edit],
  ['POST', '/intake/approve', mapping.approve],

  // intake.brief — Design Brief
  ['GET', '/intake/brief', brief.page],
  ['GET', '/intake/brief/artifact/:kind/:id', brief.artifact],
  ['GET', '/intake/brief/file', brief.file],
  ['GET', '/intake/brief/model/:id', brief.model],
  ['GET', '/intake/brief/panel', brief.panel],
  ['GET', '/intake/brief/panel/size/:side/:size', brief.panelSize],
  ['POST', '/intake/brief/messages', brief.sendMessage],

  // intake.moodboard — Moodboard
  ['GET', '/intake/moodboard', moodboard.page],
  ['GET', '/intake/moodboard/artifact/:kind/:id', moodboard.artifact],
  ['GET', '/intake/moodboard/file', moodboard.file],
  ['GET', '/intake/moodboard/model/:id', moodboard.model],
  ['GET', '/intake/moodboard/panel', moodboard.panel],
  ['GET', '/intake/moodboard/panel/size/:side/:size', moodboard.panelSize],
  ['POST', '/intake/moodboard/messages', moodboard.sendMessage],
];
