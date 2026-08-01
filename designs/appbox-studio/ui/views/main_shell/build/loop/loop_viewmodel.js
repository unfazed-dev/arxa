// appbox:provenance
// generator: app-box  licence: free  project: 662368770980
// Built with app-box (free tier) — https://appbox.dev
export const surfaceId = 'build.loop';

import * as facade from '../../../../../services/facades/build_facade.js';

const VIEW = 'ui/views/main_shell/build/loop/loop_view.html';
const STUB_VIEW = 'ui/views/main_shell/build/loop/screen_stub_view.html';

export const page = (c, h) =>
  h.render(c, VIEW, { activeShell: 'build', ...facade.loopContext(h.session(c).data, c.req.query('artifact') ?? null, h.prefs(c), h.t(c), h.locale(c), c.req.query('file'), c.req.query('panel')) });

// A file row: open the file in the main panel (?path=, unknown → empty state).
export const file = (c, h) =>
  h.render(c, `${VIEW}#fileSwap`, facade.openFile(h.session(c).data, c.req.query('path'), h.prefs(c), h.t(c), h.locale(c)));

// Clicking a thread card (or an activity artifact row) opens the artifact
// center-stage and docks the chat right.
export const artifact = (c, h) => {
  const ref = `${c.req.param('kind')}/${c.req.param('id')}`;
  return h.render(c, `${VIEW}#panelsSwap`, facade.showArtifact(h.session(c).data, ref, h.prefs(c), h.t(c), h.locale(c)));
};

// Composer agent chrome: the model pick swaps the stage.
export const model = (c, h) =>
  h.render(c, `${VIEW}#panelsSwap`, facade.setModel(h.session(c).data, c.req.param('id'), h.prefs(c), h.t(c), h.locale(c)));

// Gate context chips: "reject with note" pins the gate above the composer;
// the chip's × unpins it.
export const pinChip = (c, h) =>
  h.render(c, `${VIEW}#panelsSwap`, facade.pinChip(h.session(c).data, c.req.query('ref'), h.prefs(c), h.t(c), h.locale(c)));

export const unpinChip = (c, h) =>
  h.render(c, `${VIEW}#panelsSwap`, facade.unpinChip(h.session(c).data, c.req.query('ref'), h.prefs(c), h.t(c), h.locale(c)));

// The composer: append the user's message and a simulated agent reply.
// With a gate chip pinned, the facade treats the message as the reject
// note + decision (single input path — no separate note field).
export const sendMessage = async (c, h) => {
  const form = await h.form(c);
  const text = String(form.preset || form.text || '').trim();
  if (!text) return h.noContent(c);
  return h.render(c, `${VIEW}#messageSwap`, facade.sendMessage(h.session(c).data, text, h.prefs(c), h.t(c), h.locale(c)));
};

export const decide = async (c, h) => {
  const form = await h.form(c);
  return h.render(c, `${VIEW}#decisionSwap`, facade.decide(h.session(c).data, form.gate, form.decision, form.note, h.prefs(c), h.t(c), h.locale(c)));
};

// Activity panel: ?view=run|thread|artifacts|commits|files switches the
// panel's view; ?type=stage|gate|findings|evidence|note|all filters the thread.
export const panel = (c, h) => {
  const view = c.req.query('view');
  if (view) return h.render(c, `${VIEW}#activityViewSwap`, facade.setActivityView(h.session(c).data, view, h.prefs(c), h.t(c), h.locale(c)));
  return h.render(c, `${VIEW}#filterSwap`, facade.setThreadFilter(h.session(c).data, c.req.query('type') ?? 'all', h.prefs(c), h.t(c), h.locale(c)));
};

// Panel width grip: s/m/l persisted per side, whole-panel re-render.
export const panelSize = (c, h) =>
  h.render(c, `${VIEW}#activityFrameSwap`, facade.setPanelSize(h.session(c).data, c.req.param('side'), c.req.param('size'), h.prefs(c), h.t(c), h.locale(c)));

// Run control (run view): pause | resume the whole line.
export const runControl = async (c, h) => {
  const form = await h.form(c);
  return h.render(c, `${VIEW}#runSwap`, facade.runControl(h.session(c).data, String(form.action), h.prefs(c), h.t(c), h.locale(c)));
};

// The design viewer on the evidence canvas: controller acts swap just the
// viewer block; the choice lives in the session. panel rides along so the
// mini panel tabs round-trip.
export const evidenceViewer = (c, h) =>
  h.render(c, `${VIEW}#viewerSwap`, facade.setViewer(h.session(c).data, {
    bg: c.req.query('bg'), panel: c.req.query('panel'),
  }, h.prefs(c), h.t(c), h.locale(c)));

// The iframe document: an honest labelled stand-in render of the client's
// designed screen. In the shipped app this src points at the designer
// artifact the daemon serves.
export const screenStub = (c, h) =>
  h.render(c, STUB_VIEW, facade.screenStub(c.req.param('surface'), c.req.query('vp'), h.prefs(c), h.locale(c), { embed: c.req.query('embed') === '1', inspect: c.req.query('inspect') === '1', still: c.req.query('still') === '1' }));

// Stage control (run view): pause | resume | cancel one stage.
export const stageControl = async (c, h) => {
  const form = await h.form(c);
  return h.render(c, `${VIEW}#controlSwap`, facade.stageControl(h.session(c).data, c.req.param('id'), String(form.action), h.prefs(c), h.t(c), h.locale(c)));
};
