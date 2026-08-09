// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
// Design-shell route table — same [method, path, handler] shape as
// app.routes.js. Integration: spread into the default export of
// app.routes.js (see integration_design.md, next to this file).
import * as prototype from './prototype/prototype_viewmodel.js';
import * as chat from './chat/chat_viewmodel.js';
import * as freeze from './freeze/freeze_viewmodel.js';

export default [
  // design.prototype — the design stage (shell root: /design)
  ['GET', '/design', prototype.page],
  ['GET', '/design/panel', prototype.panel],
  ['GET', '/design/panel/size/:panel/:size', prototype.panelSize],
  ['GET', '/design/panel/:view', prototype.panelView],
  ['GET', '/design/viewer', prototype.viewer],
  ['GET', '/design/file', prototype.file],
  ['GET', '/design/screen/:id', prototype.screen],
  ['POST', '/design/flows/:flow/move/:screen', prototype.flowMove], // posted-by: design_viewer.tsx tile toolbar (hx-post, dir) + drag.js island (htmx.ajax, index)
  ['POST', '/design/flows/:flow/add/:screen', prototype.flowAdd], // posted-by: design_viewer.tsx add-to-flow menu (hx-post)
  ['POST', '/design/flows/:flow/remove/:screen', prototype.flowRemove], // posted-by: design_viewer.tsx tile toolbar (hx-post)
  ['POST', '/design/panel/size/:panel', prototype.panelSizePx], // posted-by: drag.js island (htmx.ajax)
  ['POST', '/design/undo/:stack', prototype.undo], // posted-by: composer.tsx undoHref (facade-computed hx-post)
  ['POST', '/design/redo/:stack', prototype.redo], // posted-by: composer.tsx redoHref (facade-computed hx-post)
  ['GET', '/design/drawer/:screen', prototype.drawer], // sent-by: tile toolbar reveal-drawer trigger + drawer tabs (hx-get, ?state= / ?tab=)
  ['GET', '/design/inspector', prototype.inspector], // activity panel's 4th view (own route: not /design/panel/:view)
  ['POST', '/design/inspector/select', prototype.inspectorSelect], // posted-by: inspect.js island (htmx.ajax, values)
  ['POST', '/design/inspector/unlock', prototype.inspectorUnlock], // posted-by: inspector_pane.tsx elementCard footer (hx-post={unlockHref})
  ['POST', '/design/widget/arm', prototype.widgetArm], // posted-by: design_viewer.tsx toolbar arm chip (hx-post={v.weditArmHref})
  ['POST', '/design/widget/select', prototype.widgetSelect], // posted-by: armed tile clicks via canvas.js + the drawer Tools strip (htmx.ajax / hx-post, values)
  ['POST', '/design/widget/attr', prototype.widgetAttr], // posted-by: widget_editor.tsx step chips (hx-post)
  ['POST', '/design/widget/text', prototype.widgetText], // posted-by: design_viewer.tsx .dv-tools-copy-form (hx-post, drawer field routes the #drawerSwap response)
  ['POST', '/design/widget/clear', prototype.widgetClear], // posted-by: design_facade clearHref (facade-computed hx-post)

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
  ['POST', '/design/chat/screen/:id/revert/:cp', chat.revert], // posted-by: design/shared.tsx checkpoint action (hx-post)

  // design.freeze — freeze & trace + the manifest approval gate
  ['GET', '/design/freeze', freeze.page],
  ['GET', '/design/freeze/file', freeze.file],
  ['POST', '/design/freeze/messages', freeze.send],
  ['POST', '/design/freeze/recheck', freeze.recheck],
  ['GET', '/design/freeze/context/:id', freeze.context],
  ['GET', '/design/freeze/model/:id', freeze.model],
  ['GET', '/design/freeze/tray', freeze.tray],
];
