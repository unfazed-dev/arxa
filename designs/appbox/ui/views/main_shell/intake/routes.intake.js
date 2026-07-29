// Intake routes — same [method, path, handler] shape as app.routes.js.
// Wire by spreading into the default export of app.routes.js; see
// _integration_intake.md for the exact patch.
import * as mapping from './mapping/mapping_viewmodel.js';
import * as brief from './brief/brief_viewmodel.js';
import * as moodboard from './moodboard/moodboard_viewmodel.js';

export default [
  // intake.mapping — Story Mapping (the intake tab root)
  ['GET', '/intake', mapping.page],
  ['GET', '/intake/filter', mapping.filter],
  ['GET', '/intake/artifact/:kind/:id', mapping.artifact],
  ['GET', '/intake/bar/:kind/:id', mapping.bar],
  ['POST', '/intake/artifact/:kind/:id/messages', mapping.askArtifact],
  ['POST', '/intake/messages', mapping.sendMessage],

  // intake.brief — Design Brief
  ['GET', '/intake/brief', brief.page],
  ['GET', '/intake/brief/artifact/:kind/:id', brief.artifact],
  ['GET', '/intake/brief/bar/:kind/:id', brief.bar],
  ['POST', '/intake/brief/artifact/:kind/:id/messages', brief.askArtifact],
  ['POST', '/intake/brief/messages', brief.sendMessage],

  // intake.moodboard — Moodboard
  ['GET', '/intake/moodboard', moodboard.page],
  ['GET', '/intake/moodboard/filter', moodboard.filter],
  ['GET', '/intake/moodboard/artifact/:kind/:id', moodboard.artifact],
  ['GET', '/intake/moodboard/bar/:kind/:id', moodboard.bar],
  ['POST', '/intake/moodboard/artifact/:kind/:id/messages', moodboard.askArtifact],
  ['POST', '/intake/moodboard/messages', moodboard.sendMessage],
];
