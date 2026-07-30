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
  ['GET', '/intake/close', mapping.close],
  ['GET', '/intake/model/:id', mapping.model],
  ['GET', '/intake/rail', mapping.rail],
  ['GET', '/intake/rail/size/:side/:size', mapping.railSize],
  ['POST', '/intake/messages', mapping.sendMessage],
  ['POST', '/intake/depth', mapping.depth],
  ['POST', '/intake/answer', mapping.answer],
  ['POST', '/intake/skip', mapping.skip],
  ['GET', '/intake/edit', mapping.edit],
  ['POST', '/intake/approve', mapping.approve],

  // intake.brief — Design Brief
  ['GET', '/intake/brief', brief.page],
  ['GET', '/intake/brief/artifact/:kind/:id', brief.artifact],
  ['GET', '/intake/brief/close', brief.close],
  ['GET', '/intake/brief/model/:id', brief.model],
  ['GET', '/intake/brief/rail', brief.rail],
  ['GET', '/intake/brief/rail/size/:side/:size', brief.railSize],
  ['POST', '/intake/brief/messages', brief.sendMessage],

  // intake.moodboard — Moodboard
  ['GET', '/intake/moodboard', moodboard.page],
  ['GET', '/intake/moodboard/artifact/:kind/:id', moodboard.artifact],
  ['GET', '/intake/moodboard/close', moodboard.close],
  ['GET', '/intake/moodboard/model/:id', moodboard.model],
  ['GET', '/intake/moodboard/rail', moodboard.rail],
  ['GET', '/intake/moodboard/rail/size/:side/:size', moodboard.railSize],
  ['POST', '/intake/moodboard/messages', moodboard.sendMessage],
];
