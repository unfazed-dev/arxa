// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
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
  ['POST', '/design/flows/:flow/move/:screen', prototype.flowMove], // sent-by: tile toolbar (hx-post, dir) + drag.js island (htmx.ajax, index)
  ['POST', '/design/flows/:flow/add/:screen', prototype.flowAdd],
  ['POST', '/design/flows/:flow/remove/:screen', prototype.flowRemove],
  ['POST', '/design/panel/size/:side', prototype.panelSizePx], // posted-by: drag.js island (htmx.ajax)
  ['POST', '/design/undo/:stack', prototype.undo],
  ['POST', '/design/redo/:stack', prototype.redo],
  ['GET', '/design/inspector', prototype.inspector], // activity panel's 4th view (own route: not /design/panel/:view)
  ['POST', '/design/inspector/select', prototype.inspectorSelect], // posted-by: inspect.js island (htmx.ajax, values)
  ['POST', '/design/inspector/unlock', prototype.inspectorUnlock], // posted-by: inspector_pane.html elementCard footer (hx-post="{{ unlockHref }}")

  // design.chat — the one design chat; context chips replace per-screen pages
  ['GET', '/design/chat', chat.page],
  ['POST', '/design/chat/messages', chat.send], // posted-by: c.composerAction (design_facade)
  ['GET', '/design/chat/context/:id', chat.context],
  ['POST', '/design/chat/context/element', chat.elementContext], // posted-by: inspect.js island (fetch)
  ['GET', '/design/chat/context/element/remove', chat.elementContextRemove],
  ['POST', '/design/chat/context/bulk', chat.bulkContext], // posted-by: drag.js island (htmx.ajax)
  ['GET', '/design/chat/model/:id', chat.model],
  ['GET', '/design/chat/tray', chat.tray],
  ['GET', '/design/chat/screen/:id', chat.select],
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
