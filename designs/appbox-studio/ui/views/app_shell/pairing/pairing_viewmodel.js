// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
export const surfaceId = 'app.pairing';

import * as facade from '../../../../services/facades/app_facade.js';

const VIEW = 'ui/views/app_shell/pairing/pairing_view.html';

export const page = (c, h) => h.render(c, VIEW, facade.pairingContext(h.session(c).data, h.locale(c)));

// Pairing code from the desktop QR. Match → session paired, 303 back to /pair
// (renders the confirmation); mismatch → re-render with the error.
export const confirm = async (c, h) => {
  const form = await h.form(c);
  const ok = facade.confirmPairing(h.session(c).data, String(form.code || ''), h.locale(c), h.t(c));
  if (ok) return c.redirect('/pair', 303);
  return h.render(c, VIEW, facade.pairingContext(h.session(c).data, h.locale(c)), 422);
};
