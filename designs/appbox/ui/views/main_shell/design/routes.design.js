// Design-tab route table — same [method, path, handler] shape as
// app.routes.js. Integration: spread into the default export of
// app.routes.js (see _integration_design.md, next to this file).
import * as prototype from './prototype/prototype_viewmodel.js';
import * as chat from './chat/chat_viewmodel.js';
import * as freeze from './freeze/freeze_viewmodel.js';

export default [
  // design.prototype — the design stage (tab root: /design)
  ['GET', '/design', prototype.page],
  ['GET', '/design/rail', prototype.rail],
  ['GET', '/design/rail/:view', prototype.railView],
  ['GET', '/design/viewer', prototype.viewer],
  ['GET', '/design/screen/:id', prototype.screen],

  // design.chat — the one design chat; context chips replace per-screen pages
  ['GET', '/design/chat', chat.page],
  ['POST', '/design/chat/messages', chat.send],
  ['GET', '/design/chat/context/:id', chat.context],
  ['GET', '/design/chat/close', chat.close],
  ['GET', '/design/chat/model/:id', chat.model],
  ['GET', '/design/chat/tray', chat.tray],
  ['GET', '/design/chat/screen/:id', chat.select],
  ['POST', '/design/chat/screen/:id/messages', chat.send],
  ['POST', '/design/chat/screen/:id/revert/:cp', chat.revert],

  // design.freeze — freeze & trace + the manifest approval gate
  ['GET', '/design/freeze', freeze.page],
  ['POST', '/design/freeze/messages', freeze.send],
  ['POST', '/design/freeze/recheck', freeze.recheck],
  ['GET', '/design/freeze/context/:id', freeze.context],
  ['GET', '/design/freeze/close', freeze.close],
  ['GET', '/design/freeze/model/:id', freeze.model],
  ['GET', '/design/freeze/tray', freeze.tray],
];
