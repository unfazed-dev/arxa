export const surfaceId = 'design.freeze';

import * as facade from '../../../../../services/facades/design_facade.js';

const VIEW = 'ui/views/main_shell/design/freeze/freeze_view.html';

export const page = (c, h) =>
  h.render(c, VIEW, { activeTab: 'design', ...facade.freezeContext(h.session(c).data, h.prefs(c)) });

// Re-run the drift check: swaps the drift card and toasts the result.
export const recheck = (c, h) =>
  h.render(c, `${VIEW}#driftSwap`, facade.recheckDrift(h.session(c).data, h.prefs(c)));
