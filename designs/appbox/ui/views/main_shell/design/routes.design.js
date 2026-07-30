// appbox:provenance
// generator: app-box  licence: free  project: 662368770980
// Built with app-box (free tier) — https://appbox.dev
// Design-shell route table — same [method, path, handler] shape as
// app.routes.js. Integration: spread into the default export of
// app.routes.js (see _integration_design.md, next to this file).
import * as prototype from './prototype/prototype_viewmodel.js';
import * as chat from './chat/chat_viewmodel.js';
import * as freeze from './freeze/freeze_viewmodel.js';

export default [
  // design.prototype — the design stage (shell root: /design)
  ['GET', '/design', prototype.page],
  ['GET', '/design/panel', prototype.panel],
  ['GET', '/design/panel/size/:side/:size', prototype.panelSize],
  ['GET', '/design/panel/:view', prototype.panelView],
  ['GET', '/design/viewer', prototype.viewer],
  ['GET', '/design/file', prototype.file],
  ['GET', '/design/screen/:id', prototype.screen],
  ['POST', '/design/layout/artboard/:id', prototype.artboardLayout],
  ['POST', '/design/panel/size/:side', prototype.panelSizePx],
  ['POST', '/design/undo/:stack', prototype.undo],
  ['POST', '/design/redo/:stack', prototype.redo],

  // design.chat — the one design chat; context chips replace per-screen pages
  ['GET', '/design/chat', chat.page],
  ['POST', '/design/chat/messages', chat.send],
  ['GET', '/design/chat/context/:id', chat.context],
  ['POST', '/design/chat/context/element', chat.elementContext],
  ['GET', '/design/chat/context/element/remove', chat.elementContextRemove],
  ['POST', '/design/chat/context/bulk', chat.bulkContext],
  ['GET', '/design/chat/model/:id', chat.model],
  ['GET', '/design/chat/tray', chat.tray],
  ['GET', '/design/chat/screen/:id', chat.select],
  ['POST', '/design/chat/screen/:id/messages', chat.send],
  ['POST', '/design/chat/screen/:id/revert/:cp', chat.revert],

  // design.freeze — freeze & trace + the manifest approval gate
  ['GET', '/design/freeze', freeze.page],
  ['GET', '/design/freeze/file', freeze.file],
  ['POST', '/design/freeze/messages', freeze.send],
  ['POST', '/design/freeze/recheck', freeze.recheck],
  ['GET', '/design/freeze/context/:id', freeze.context],
  ['GET', '/design/freeze/model/:id', freeze.model],
  ['GET', '/design/freeze/tray', freeze.tray],
];
