// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
export const surfaceId = 'intake.interview';

import * as facade from '../../../../../services/facades/intake_facade.js';

const VIEW = 'ui/views/main_shell/intake/interview/interview_view.html';
const SURFACE = 'interview';

export const page = (context, helpers) =>
  helpers.render(context, VIEW, { activeShell: 'intake', ...facade.context(helpers.session(context).data, SURFACE, null, helpers.prefs(context), helpers.translate(context), helpers.locale(context), context.req.query('file'), context.req.query('panel')) });

// A file row: open the file in the main panel (?path=, unknown → empty state).
export const file = (context, helpers) =>
  helpers.render(context, `${VIEW}#fileSwap`, facade.openFile(helpers.session(context).data, SURFACE, context.req.query('path'), helpers.prefs(context), helpers.translate(context), helpers.locale(context)));

// Composer agent chrome: the model pick swaps the stage.
export const model = (context, helpers) =>
  helpers.render(context, `${VIEW}#panelsSwap`, facade.setModel(helpers.session(context).data, SURFACE, context.req.param('id'), helpers.prefs(context), helpers.translate(context), helpers.locale(context)));

// Activity panel view switch: ?view=thread|files — swaps the body.
export const panel = (context, helpers) =>
  helpers.render(context, `${VIEW}#activitySwap`, facade.setActivityView(helpers.session(context).data, SURFACE, context.req.query('view'), helpers.prefs(context), helpers.translate(context), helpers.locale(context)));

// Panel width grip: s/m/l persisted per side for the whole intake shell.
export const panelSize = (context, helpers) =>
  helpers.render(context, `${VIEW}#activityFrameSwap`, facade.setPanelSize(helpers.session(context).data, SURFACE, context.req.param('panel'), context.req.param('size'), helpers.prefs(context), helpers.translate(context), helpers.locale(context)));

// The composer: append the user's message and a simulated agent reply.
export const sendMessage = async (context, helpers) => {
  const form = await helpers.form(context);
  const text = String(form.preset || form.text || '').trim();
  if (!text) return helpers.noContent(context);
  return helpers.render(context, `${VIEW}#panelsSwap`, facade.sendMessage(helpers.session(context).data, SURFACE, text, helpers.prefs(context), helpers.translate(context), helpers.locale(context)));
};

// The mode choice (simple / normal / advanced) picks the question bank.
export const depth = async (context, helpers) => {
  const form = await helpers.form(context);
  return helpers.render(context, `${VIEW}#panelsSwap`, facade.chooseDepth(helpers.session(context).data, String(form.depth || ''), helpers.prefs(context), helpers.translate(context), helpers.locale(context)));
};

// A question card's answer (typed or a suggestion chip).
export const answer = async (context, helpers) => {
  const form = await helpers.form(context);
  const text = String(form.text || '').trim();
  if (!text) return helpers.noContent(context);
  return helpers.render(context, `${VIEW}#panelsSwap`, facade.answerQuestion(helpers.session(context).data, String(form.q || ''), text, helpers.prefs(context), helpers.translate(context), helpers.locale(context)));
};

// A question card's skip affordance.
export const skip = async (context, helpers) => {
  const form = await helpers.form(context);
  return helpers.render(context, `${VIEW}#panelsSwap`, facade.skipQuestion(helpers.session(context).data, String(form.q || ''), helpers.prefs(context), helpers.translate(context), helpers.locale(context)));
};

// Revisit an answered/skipped card: ?q=<id> re-opens its form.
export const edit = (context, helpers) =>
  helpers.render(context, `${VIEW}#panelsSwap`, facade.editQuestion(helpers.session(context).data, context.req.query('q'), helpers.prefs(context), helpers.translate(context), helpers.locale(context)));
