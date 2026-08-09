// Auto-generated route manifest — do not edit.
// Regenerate via `appbox design eject`.
//
// This copy lives in the artifact so the DESIGN server can resolve the same
// `runtime/routes.js` import the ejected tree generates (the design server
// serves artifact files verbatim; there is no design-time codegen step).
// Keep it in sync with app.routes.js — eject always regenerates its own copy
// from app.routes.js, so this file is design-time only.

export const routes = {
  index: () => "/",
  auth: {
    index: () => "/auth",
    signIn: () => "/auth/sign-in",
  },
  prefs: {
    accent: () => "/prefs/accent",
  },
  startup: {
    index: () => "/startup",
    progress: () => "/startup/progress",
    proceed: () => "/startup/proceed",
  },
  unknown: {
    index: () => "/unknown",
  },
};
