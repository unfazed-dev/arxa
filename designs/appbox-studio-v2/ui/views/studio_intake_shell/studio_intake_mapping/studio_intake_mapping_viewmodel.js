// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
export const surfaceId = 'studio_intake_mapping';

import * as facade from '../../../../services/studio_intake_services/facades/studio_intake_facade_service.js';

const VIEW = 'ui/views/studio_intake_shell/studio_intake_mapping/studio_intake_mapping_view.html';
const SURFACE = 'mapping';

export const page = (context, helpers) =>
  helpers.render(context, VIEW, { activeShell: 'intake', ...facade.context(helpers.session(context).data, SURFACE, context.req.query('artifact') ?? null, helpers.prefs(context), helpers.translate(context), helpers.locale(context), context.req.query('file'), context.req.query('panel')) });

// A file row: open the file in the main panel (?path=, unknown → empty state).
export const file = (context, helpers) =>
  helpers.render(context, `${VIEW}#fileSwap`, facade.openFile(helpers.session(context).data, SURFACE, context.req.query('path'), helpers.prefs(context), helpers.translate(context), helpers.locale(context)));

// Open an artifact in the main panel.
export const artifact = (context, helpers) => {
  const ref = `${context.req.param('kind')}/${context.req.param('id')}`;
  return helpers.render(context, `${VIEW}#panelsSwap`, facade.showArtifact(helpers.session(context).data, SURFACE, ref, helpers.prefs(context), helpers.translate(context), helpers.locale(context)));
};

// Composer agent chrome: the model pick swaps the stage.
export const model = (context, helpers) =>
  helpers.render(context, `${VIEW}#panelsSwap`, facade.setModel(helpers.session(context).data, SURFACE, context.req.param('id'), helpers.prefs(context), helpers.translate(context), helpers.locale(context)));

// Activity panel view switch: ?view=thread|artifacts|files — swaps the body.
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

// The approval gate: the "approve the story map" quick-reply flips seed state.
export const approve = (context, helpers) =>
  helpers.render(context, `${VIEW}#panelsSwap`, facade.approveMap(helpers.session(context).data, SURFACE, helpers.prefs(context), helpers.translate(context), helpers.locale(context)));
