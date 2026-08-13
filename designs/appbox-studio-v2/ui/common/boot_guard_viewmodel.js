/// This is the business logic for the boot guard.
///
/// Role: gates every hub-hosted route behind the startup ceremony. The
/// prototype carries structure, not a real boot: "booted" is a cookie the
/// proceed trigger sets, so the guard's shape (redirect out, return-to back
/// in) is reviewable end-to-end without a real session. Ceremony shells
/// (/startup, /unknown, later /auth) are never guarded.
///
/// Requirements:
/// 1. [Hub owns /; startup guards it] — R1, R3
///    (docs/plans/studio-v2-boot-sequence-wiring.md)
/// 2. [Return-to honors only the hosted roster — no open redirect] — R3
///
/// Relationships: wrapped around hosted-route handlers in app.routes.js;
/// studio_startup_viewmodel.js consumes bootTarget/markBooted for the
/// proceed hand-off.
///
/// History: git log --follow -- ui/common/boot_guard_viewmodel.js

/** Hub-hosted routes the boot guard covers and ?to= may name. Grows as
 *  stage shells land (Q-v2-5); /intake and /design join when they exist. */
export const hostedRoots = ['/', '/dashboard'];

const BOOT_COOKIE = 'studio_booted=1';

/** @param {import('hono').Context} context */
export const isBooted = (context) =>
  (context.req.header('cookie') ?? '').split(';').some((part) => part.trim() === BOOT_COOKIE);

/** The validated return-to target: a hosted root or the hub root — never
 *  an arbitrary URL. @param {import('hono').Context} context */
export const bootTarget = (context) => {
  const to = context.req.query('to');
  return hostedRoots.includes(to) ? to : '/';
};

/** Stamps the session booted. Path-wide so every hosted route sees it.
 *  @param {import('hono').Context} context */
export const markBooted = (context) => {
  context.header('Set-Cookie', `${BOOT_COOKIE}; Path=/; SameSite=Lax`);
};

/** Route wrapper: un-booted sessions bounce to the ceremony with a
 *  return-to; booted ones fall through to the hosted handler. */
export const booted = (handler) => (context, helpers) => {
  if (isBooted(context)) return handler(context, helpers);
  const to = context.req.path;
  return context.redirect(`/startup?to=${encodeURIComponent(to)}`, 302);
};
