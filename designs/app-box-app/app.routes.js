// Routes are DERIVED from models/screens_model/registry.json — one GET per
// buildable entry, plus the POSTs that mutate. The arrow never reverses.
import * as shell from './ui/views/stage_shell/stage_shell_viewmodel.js';
import * as projects_home from './ui/views/stage_shell/projects/home/home_viewmodel.js';
import * as projects_new from './ui/views/stage_shell/projects/new/new_viewmodel.js';
import * as design_directions from './ui/views/stage_shell/design/directions/directions_viewmodel.js';
import * as design_surface from './ui/views/stage_shell/design/surface/surface_viewmodel.js';
import * as design_approve from './ui/views/stage_shell/design/approve/approve_viewmodel.js';
import * as build_run from './ui/views/stage_shell/build/run/run_viewmodel.js';
import * as build_finding from './ui/views/stage_shell/build/finding/finding_viewmodel.js';
import * as build_approve from './ui/views/stage_shell/build/approve/approve_viewmodel.js';
import * as ship_targets from './ui/views/stage_shell/ship/targets/targets_viewmodel.js';
import * as ship_confirm from './ui/views/stage_shell/ship/confirm/confirm_viewmodel.js';
import * as chat_home from './ui/views/stage_shell/chat/home/home_viewmodel.js';
import * as settings_credentials from './ui/views/stage_shell/settings/credentials/credentials_viewmodel.js';
import * as settings_devices from './ui/views/stage_shell/settings/devices/devices_viewmodel.js';
import * as settings_kits from './ui/views/stage_shell/settings/kits/kits_viewmodel.js';

export default [
  ['GET',  '/', projects_home.page],
  ['GET',  '/projects/new', projects_new.page],
  ['GET',  '/design', design_directions.page],
  ['GET',  '/design/surface', design_surface.page],
  ['GET',  '/design/approve', design_approve.page],
  ['GET',  '/build', build_run.page],
  ['GET',  '/build/finding', build_finding.page],
  ['GET',  '/build/approve', build_approve.page],
  ['GET',  '/ship', ship_targets.page],
  ['GET',  '/ship/confirm', ship_confirm.page],
  ['GET',  '/chat', chat_home.page],
  ['GET',  '/settings', settings_credentials.page],
  ['GET',  '/settings/devices', settings_devices.page],
  ['GET',  '/settings/kits', settings_kits.page],
  ['POST', '/design/approve/approve', design_approve.approve],
  ['POST', '/build/approve/approve', build_approve.approve],
  ['POST', '/ship/confirm/release', ship_confirm.approve],
  ['POST', '/design/surface', design_surface.submit],
  ['POST', '/build', build_run.submit],
  ['POST', '/chat', chat_home.submit],
  ['POST', '/projects/new', projects_new.submit],
  ['POST', '/prefs/theme', shell.theme],
];

// Required and non-empty: the landing route of every tab. The scaffolder
// cannot derive this — a tab whose root is unknown gets an invented one.
export const tabRoots = {
  projects: '/',
  design:   '/design',
  build:    '/build',
  ship:     '/ship',
  chat:     '/chat',
  settings: '/settings',
};
