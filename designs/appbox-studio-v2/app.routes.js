import * as dashboard from './ui/views/studio_dashboard_shell/studio_dashboard/studio_dashboard_viewmodel.js';
import * as startup from './ui/views/studio_startup_shell/studio_startup/studio_startup_viewmodel.js';
import * as splash from './ui/views/studio_startup_shell/splash/studio_splash_viewmodel.js';
import * as unknown from './ui/views/studio_unknown_shell/studio_unknown/studio_unknown_viewmodel.js';
import * as auth from './ui/views/studio_auth_shell/studio_auth/studio_auth_viewmodel.js';
import * as intake from './ui/views/studio_intake_shell/studio_intake/studio_intake_viewmodel.js';
import * as design from './ui/views/studio_design_shell/studio_design/studio_design_viewmodel.js';
import * as preferences from './ui/common/preferences_viewmodel.js';
import { booted } from './ui/common/boot_guard_viewmodel.js';

// Landing route of each shell. Required and non-empty — the scaffolder cannot
// derive it, and a shell whose root is unknown gets an invented one.
//
// The hub owns `/` (R1, docs/plans/studio-v2-boot-sequence-wiring.md): the
// root renders the hub frame with the default hosted stage (dashboard) in the
// body outlet, and every hosted stage keeps a flat route of its own (R2) that
// renders the same frame with that shell hosted. Hosted routes are
// boot-guarded with a validated return-to (R3); ceremony shells route bare.
//
// Shells appear here as they land. Q-v2-5 originally cut shells over one at
// a time behind explicit user validation; the owner ruling of 2026-08-16
// landed every shell enabled in one pass, so the full roster routes today.
// An unbuilt shell would still be a disabled stage card in the dashboard
// registry, never a route that resolves to a placeholder.
export const shellRoots = {
  studio_application_hub: '/',
  studio_dashboard_shell: '/dashboard',
  studio_startup_shell: '/startup',
  studio_unknown_shell: '/unknown',
  studio_auth_shell: '/auth',
  studio_intake_shell: '/intake',
  studio_design_shell: '/design',
};

export default [
  ['GET', '/', booted(dashboard.view)],
  ['GET', '/dashboard', booted(dashboard.view)],
  ['POST', '/gates/decide', booted(dashboard.decideGate)],
  ['POST', '/projects/use', booted(dashboard.useProject)],
  ['POST', '/projects/create', booted(dashboard.createProject)],
  ['GET', '/startup', startup.view],
  ['GET', '/splash', splash.view], // the roster law's splash role: a surface under the startup shell (Q-v2-1)
  ['GET', '/unknown', unknown.view],
  ['GET', '/startup/progress', startup.progress],
  ['POST', '/startup/proceed', startup.proceed], // posted-by: boot_checklist.tsx proceed trigger (hx-post, computed ?to return-to)
  // ceremony shells route bare (R4): the auth card never boot-guards
  ['GET', '/auth', auth.view],
  ['POST', '/auth/signin', auth.signin],
  // working shells are boot-guarded with a validated return-to (R2, R3)
  ['GET', '/intake', booted(intake.view)],
  ['POST', '/intake/answer', booted(intake.answer)],
  ['POST', '/intake/upload', booted(intake.upload)],
  ['GET', '/design', booted(design.view)],
  ['POST', '/design/compose', booted(design.compose)],
  // /preferences/accent: no v2 sender has landed (the accent picker is a
  // dashboard-registry follow-up) — the route stays out rather than dead.
  ['POST', '/preferences/theme', preferences.setTheme],
];
