// Design-tab route table — same [method, path, handler] shape as
// app.routes.js. Integration: spread into the default export of
// app.routes.js (see _integration_design.md, next to this file).
import * as prototype from './prototype/prototype_viewmodel.js';
import * as chat from './chat/chat_viewmodel.js';
import * as freeze from './freeze/freeze_viewmodel.js';

export default [
  // design.prototype — the design prototype viewer (tab root: /design)
  ['GET', '/design', prototype.page],
  ['GET', '/design/rail', prototype.rail],
  ['GET', '/design/screen/:id', prototype.screen],
  ['GET', '/design/viewer', prototype.viewer],
  ['GET', '/design/bar/:id', prototype.bar],
  ['POST', '/design/screen/:id/messages', prototype.askScreen],

  // design.chat — per-screen conversation thread
  ['GET', '/design/chat', chat.page],
  ['GET', '/design/chat/screen/:id', chat.select],
  ['POST', '/design/chat/screen/:id/messages', chat.send],
  ['POST', '/design/chat/screen/:id/revert/:cp', chat.revert],

  // design.freeze — freeze & trace
  ['GET', '/design/freeze', freeze.page],
  ['POST', '/design/freeze/recheck', freeze.recheck],
];
