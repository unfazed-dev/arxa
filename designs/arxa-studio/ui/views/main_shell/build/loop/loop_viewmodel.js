// appbox:provenance
// generator: app-box  licence: free  project: 662368770980
// Built with app-box (free tier) — https://appbox.dev
export const surfaceId = 'build.loop';

import * as facade from '../../../../../services/facades/build_facade.js';

const VIEW = 'ui/views/main_shell/build/loop/loop_view.html';
const STUB_VIEW = 'ui/views/main_shell/build/loop/screen_stub_view.html';

// No build evidence for this project yet. Every loop route below degrades to
// the honest empty state instead of rendering another project's demo run —
// and loopContext is never entered, which matters: it dereferences the
// build.acceptance gate unguarded, so an empty gate list would throw a
// TypeError straight to a 500. The facade owns the test; a viewmodel that
// asked the repository directly would break the layering the selftest gates.
const empty = (context, helpers) => facade.emptyLoopContext(helpers.locale(context), helpers.session(context).data, helpers.prefs(context), helpers.translate(context));

// The empty stage: shell chrome + the "no evidence yet" panel, nothing else.
const emptyPage = (context, helpers, emptyContext) => helpers.render(context, VIEW, { activeShell: 'build', ...emptyContext });

export const page = (context, helpers) => {
  const emptyContext = empty(context, helpers);
  if (emptyContext) return emptyPage(context, helpers, emptyContext);
  return helpers.render(context, VIEW, { activeShell: 'build', ...facade.loopContext(helpers.session(context).data, context.req.query('artifact') ?? null, helpers.prefs(context), helpers.translate(context), helpers.locale(context), context.req.query('file'), context.req.query('panel')) });
};

// A file row: open the file in the main panel (?path=, unknown → empty state).
export const file = (context, helpers) => {
  const emptyContext = empty(context, helpers);
  if (emptyContext) return emptyPage(context, helpers, emptyContext);
  return helpers.render(context, `${VIEW}#fileSwap`, facade.openFile(helpers.session(context).data, context.req.query('path'), helpers.prefs(context), helpers.translate(context), helpers.locale(context)));
};

// Clicking a thread card (or an activity artifact row) opens the artifact
// center-stage and docks the chat right.
export const artifact = (context, helpers) => {
  const emptyContext = empty(context, helpers);
  if (emptyContext) return emptyPage(context, helpers, emptyContext);
  const ref = `${context.req.param('kind')}/${context.req.param('id')}`;
  return helpers.render(context, `${VIEW}#panelsSwap`, facade.showArtifact(helpers.session(context).data, ref, helpers.prefs(context), helpers.translate(context), helpers.locale(context)));
};

// Composer agent chrome: the model pick swaps the stage.
export const model = (context, helpers) => {
  const emptyContext = empty(context, helpers);
  if (emptyContext) return emptyPage(context, helpers, emptyContext);
  return helpers.render(context, `${VIEW}#panelsSwap`, facade.setModel(helpers.session(context).data, context.req.param('id'), helpers.prefs(context), helpers.translate(context), helpers.locale(context)));
};

// Gate context chips: "reject with note" pins the gate above the composer;
// the chip's × unpins it.
export const pinChip = (context, helpers) => {
  const emptyContext = empty(context, helpers);
  if (emptyContext) return emptyPage(context, helpers, emptyContext);
  return helpers.render(context, `${VIEW}#panelsSwap`, facade.pinChip(helpers.session(context).data, context.req.query('ref'), helpers.prefs(context), helpers.translate(context), helpers.locale(context)));
};

export const unpinChip = (context, helpers) => {
  const emptyContext = empty(context, helpers);
  if (emptyContext) return emptyPage(context, helpers, emptyContext);
  return helpers.render(context, `${VIEW}#panelsSwap`, facade.unpinChip(helpers.session(context).data, context.req.query('ref'), helpers.prefs(context), helpers.translate(context), helpers.locale(context)));
};

// The composer: append the user's message and a simulated agent reply.
// With a gate chip pinned, the facade treats the message as the reject
// note + decision (single input path — no separate note field).
export const sendMessage = async (context, helpers) => {
  const emptyContext = empty(context, helpers);
  if (emptyContext) return emptyPage(context, helpers, emptyContext);
  const form = await helpers.form(context);
  const text = String(form.preset || form.text || '').trim();
  if (!text) return helpers.noContent(context);
  return helpers.render(context, `${VIEW}#messageSwap`, facade.sendMessage(helpers.session(context).data, text, helpers.prefs(context), helpers.translate(context), helpers.locale(context)));
};

export const decide = async (context, helpers) => {
  const emptyContext = empty(context, helpers);
  if (emptyContext) return emptyPage(context, helpers, emptyContext);
  const form = await helpers.form(context);
  return helpers.render(context, `${VIEW}#decisionSwap`, facade.decide(helpers.session(context).data, form.gate, form.decision, form.note, helpers.prefs(context), helpers.translate(context), helpers.locale(context)));
};

// Activity panel: ?view=run|thread|artifacts|commits|files switches the
// panel's view; ?type=stage|gate|findings|evidence|note|all filters the thread.
export const panel = (context, helpers) => {
  const emptyContext = empty(context, helpers);
  if (emptyContext) return emptyPage(context, helpers, emptyContext);
  const view = context.req.query('view');
  if (view) return helpers.render(context, `${VIEW}#activityViewSwap`, facade.setActivityView(helpers.session(context).data, view, helpers.prefs(context), helpers.translate(context), helpers.locale(context)));
  return helpers.render(context, `${VIEW}#filterSwap`, facade.setThreadFilter(helpers.session(context).data, context.req.query('type') ?? 'all', helpers.prefs(context), helpers.translate(context), helpers.locale(context)));
};

// Panel width grip: s/m/l persisted per side, whole-panel re-render.
export const panelSize = (context, helpers) => {
  const emptyContext = empty(context, helpers);
  if (emptyContext) return emptyPage(context, helpers, emptyContext);
  return helpers.render(context, `${VIEW}#activityFrameSwap`, facade.setPanelSize(helpers.session(context).data, context.req.param('panel'), context.req.param('size'), helpers.prefs(context), helpers.translate(context), helpers.locale(context)));
};

// Run control (run view): pause | resume the whole line.
export const runControl = async (context, helpers) => {
  const emptyContext = empty(context, helpers);
  if (emptyContext) return emptyPage(context, helpers, emptyContext);
  const form = await helpers.form(context);
  return helpers.render(context, `${VIEW}#runSwap`, facade.runControl(helpers.session(context).data, String(form.action), helpers.prefs(context), helpers.translate(context), helpers.locale(context)));
};

// The design viewer on the evidence canvas: controller acts swap just the
// viewer block; the choice lives in the session. panel rides along so the
// mini panel tabs round-trip.
export const evidenceViewer = (context, helpers) => {
  const emptyContext = empty(context, helpers);
  if (emptyContext) return emptyPage(context, helpers, emptyContext);
  return helpers.render(context, `${VIEW}#viewerSwap`, facade.setViewer(helpers.session(context).data, {
    bg: context.req.query('bg'), panel: context.req.query('panel'),
  }, helpers.prefs(context), helpers.translate(context), helpers.locale(context)));
};

// The iframe document: an honest labelled stand-in render of the client's
// designed screen. In the shipped app this src points at the designer
// artifact the daemon serves. Evidence-independent — the design canvas
// drives the viewport (build_facade guards the missing evidence entry), so
// this route keeps working on a project that has never built.
export const screenStub = (context, helpers) =>
  helpers.render(context, STUB_VIEW, facade.screenStub(context.req.param('surface'), context.req.query('vp'), helpers.prefs(context), helpers.locale(context), {
    embed: context.req.query('embed') === '1',
    inspect: context.req.query('inspect') === '1',
    still: context.req.query('still') === '1',
    // Canvas app-theme override (viewer topbar control): light/dark restyle
    // this stub; absent = follow the studio theme (the facade default).
    theme: context.req.query('theme') ?? null,
    // Flow walk: `walk` is the complete parent viewer URL to advance to, so
    // the island never needs to know the viewer's param list. Absent = this
    // is not the walked tile and the island is not loaded at all.
    walk: context.req.query('walk') ?? null,
    walkEl: context.req.query('walkel') ?? '',
    walkTrig: context.req.query('walktrig') ?? '',
    // Scopes the stub's own `next` edge to the flow being walked.
    walkFlow: context.req.query('walkflow') ?? null,
  }));

// Stage control (run view): pause | resume | cancel one stage.
export const stageControl = async (context, helpers) => {
  const emptyContext = empty(context, helpers);
  if (emptyContext) return emptyPage(context, helpers, emptyContext);
  const form = await helpers.form(context);
  return helpers.render(context, `${VIEW}#controlSwap`, facade.stageControl(helpers.session(context).data, context.req.param('id'), String(form.action), helpers.prefs(context), helpers.translate(context), helpers.locale(context)));
};
