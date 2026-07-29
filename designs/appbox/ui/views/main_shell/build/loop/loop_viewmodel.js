export const surfaceId = 'build.loop';

import * as facade from '../../../../../services/facades/build_facade.js';

const VIEW = 'ui/views/main_shell/build/loop/loop_view.html';
const STUB_VIEW = 'ui/views/main_shell/build/loop/screen_stub_view.html';

export const page = (c, h) =>
  h.render(c, VIEW, { activeTab: 'build', ...facade.loopContext(h.session(c).data, c.req.query('artifact') ?? null, h.prefs(c)) });

// Clicking a narrative message swaps the canvas to that artifact.
// ?bar=open also opens the stage bar (the "ask ↩" card action); the bar's
// open state lives in the session (barOpenFor) so it survives swaps.
export const artifact = (c, h) => {
  const ref = `${c.req.param('kind')}/${c.req.param('id')}`;
  if (c.req.query('bar') === 'open') h.session(c).data.barOpenFor = ref;
  return h.render(c, `${VIEW}#canvasSwap`, facade.showArtifact(h.session(c).data, ref, h.prefs(c)));
};

// The composer: append the user's message and a simulated agent reply;
// the reply may pull a new artifact onto the canvas.
export const sendMessage = async (c, h) => {
  const form = await h.form(c);
  const text = String(form.preset || form.text || '').trim();
  if (!text) return h.noContent(c);
  return h.render(c, `${VIEW}#messageSwap`, facade.sendMessage(h.session(c).data, text, h.prefs(c)));
};

export const decide = async (c, h) => {
  const form = await h.form(c);
  return h.render(c, `${VIEW}#decisionSwap`, facade.decide(h.session(c).data, form.gate, form.decision, form.note, h.prefs(c)));
};

// Rail top-bar filter: ?type=stage|gate|findings|evidence|note|all.
export const rail = (c, h) => {
  h.session(c).data.railFilter = c.req.query('type') ?? 'all';
  return h.render(c, `${VIEW}#filterSwap`, facade.loopContext(h.session(c).data, null, h.prefs(c)));
};

// Rail top-bar run control: pause | resume.
export const runControl = async (c, h) => {
  const form = await h.form(c);
  return h.render(c, `${VIEW}#runSwap`, facade.runControl(h.session(c).data, String(form.action), h.prefs(c)));
};

// Stage bar toggle: ?state=open renders the toolbar, ?state=fab the button.
// Evidence canvases carry a chooser first (?mode=thread|review) — the canvas
// has two things to do (talk / inspect designs) and the FAB picks one.
export const bar = (c, h) => {
  const ref = `${c.req.param('kind')}/${c.req.param('id')}`;
  const state = c.req.query('state');
  h.session(c).data.barOpenFor = state === 'fab' ? null : ref;
  h.session(c).data.barMode = state === 'fab' ? null : c.req.query('mode') ?? null;
  return h.render(c, `${VIEW}#barSwap`, facade.loopContext(h.session(c).data, ref, h.prefs(c)));
};

// The design viewer on the evidence canvas: toolbar and filmstrip acts swap
// just the viewer block; the choice lives in the session.
export const evidenceViewer = (c, h) =>
  h.render(c, `${VIEW}#viewerSwap`, facade.setViewer(h.session(c).data, {
    screen: c.req.query('screen'), vp: c.req.query('vp'), bg: c.req.query('bg'), os: c.req.query('os'), mode: c.req.query('mode'),
  }, h.prefs(c)));

// The iframe document: an honest labelled stand-in render of the client's
// designed screen. In the shipped app this src points at the designer
// artifact the daemon serves.
export const screenStub = (c, h) =>
  h.render(c, STUB_VIEW, facade.screenStub(c.req.param('surface'), c.req.query('vp'), h.prefs(c)));

// Stage-bar follow-up: artifact-scoped thread, bar stays open.
export const askArtifact = async (c, h) => {
  const form = await h.form(c);
  const text = String(form.text || '').trim();
  if (!text) return h.noContent(c);
  const ref = `${c.req.param('kind')}/${c.req.param('id')}`;
  return h.render(c, `${VIEW}#scopedSwap`, facade.askArtifact(h.session(c).data, ref, text, h.prefs(c)));
};

// Stage-bar stage control: pause | resume | cancel one stage.
export const stageControl = async (c, h) => {
  const form = await h.form(c);
  return h.render(c, `${VIEW}#controlSwap`, facade.stageControl(h.session(c).data, c.req.param('id'), String(form.action), h.prefs(c)));
};
