import * as dashboard from './ui/views/studio_dashboard_shell/studio_dashboard/studio_dashboard_viewmodel.js';
import * as startup from './ui/views/studio_startup_shell/studio_startup/studio_startup_viewmodel.js';
import * as splash from './ui/views/studio_startup_shell/splash/studio_splash_viewmodel.js';
import * as unknown from './ui/views/studio_unknown_shell/studio_unknown/studio_unknown_viewmodel.js';
import * as auth from './ui/views/studio_auth_shell/studio_auth/studio_auth_viewmodel.js';
import * as interview from './ui/views/studio_intake_shell/studio_intake_interview/studio_intake_interview_viewmodel.js';
import * as personas from './ui/views/studio_intake_shell/studio_intake_personas/studio_intake_personas_viewmodel.js';
import * as isurfaces from './ui/views/studio_intake_shell/studio_intake_surfaces/studio_intake_surfaces_viewmodel.js';
import * as iflows from './ui/views/studio_intake_shell/studio_intake_flows/studio_intake_flows_viewmodel.js';
import * as mapping from './ui/views/studio_intake_shell/studio_intake_mapping/studio_intake_mapping_viewmodel.js';
import * as direction from './ui/views/studio_intake_shell/studio_intake_direction/studio_intake_direction_viewmodel.js';
import * as brief from './ui/views/studio_intake_shell/studio_intake_brief/studio_intake_brief_viewmodel.js';
import * as moodboard from './ui/views/studio_intake_shell/studio_intake_moodboard/studio_intake_moodboard_viewmodel.js';
import * as prototype from './ui/views/studio_design_shell/studio_design_prototype/studio_design_prototype_viewmodel.js';
import * as dchat from './ui/views/studio_design_shell/studio_design_chat/studio_design_chat_viewmodel.js';
import * as freeze from './ui/views/studio_design_shell/studio_design_freeze/studio_design_freeze_viewmodel.js';
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
  // working shells are boot-guarded with a validated return-to (R2, R3).
  // The intake loop is the v1 item-engine route table, ported verbatim
  // (posted-by comments carried) — see ui/views/studio_intake_shell/shared.tsx.
  // intake.interview — the journey's first step (shell root IS the interview)
  ['GET', '/intake', booted(interview.page)],
  ['GET', '/intake/file', booted(interview.file)],
  ['GET', '/intake/model/:id', booted(interview.model)],
  ['GET', '/intake/panel', booted(interview.panel)],
  ['GET', '/intake/panel/size/:panel/:size', booted(interview.panelSize)],
  ['POST', '/intake/messages', booted(interview.sendMessage)], // posted-by: composer.tsx composerAction (intake facade)
  ['POST', '/intake/depth', booted(interview.depth)], // posted-by: interview mode-cards (intake facade)
  ['POST', '/intake/answer', booted(interview.answer)], // posted-by: shared.tsx QCard answer forms (hx-post)
  ['POST', '/intake/skip', booted(interview.skip)], // posted-by: shared.tsx QCard skip forms (hx-post)
  ['GET', '/intake/edit', booted(interview.edit)],
  // intake.personas — item-engine step
  ['GET', '/intake/personas', booted(personas.page)],
  ['GET', '/intake/personas/file', booted(personas.file)],
  ['GET', '/intake/personas/model/:id', booted(personas.model)],
  ['GET', '/intake/personas/panel', booted(personas.panel)],
  ['GET', '/intake/personas/panel/size/:panel/:size', booted(personas.panelSize)],
  ['POST', '/intake/personas/messages', booted(personas.sendMessage)], // posted-by: composer.tsx composerAction (intake facade)
  ['POST', '/intake/personas/confirm', booted(personas.confirm)], // posted-by: shared.tsx ItemActions (hx-post)
  ['POST', '/intake/personas/save', booted(personas.save)], // posted-by: shared.tsx item edit forms (hx-post)
  ['POST', '/intake/personas/skip', booted(personas.skip)], // posted-by: shared.tsx ItemActions (hx-post)
  ['GET', '/intake/personas/edit', booted(personas.edit)],
  ['POST', '/intake/personas/accept-all', booted(personas.acceptAll)], // posted-by: shared.tsx StepFoot (hx-post)
  // intake.surfaces — item-engine step
  ['GET', '/intake/surfaces', booted(isurfaces.page)],
  ['GET', '/intake/surfaces/file', booted(isurfaces.file)],
  ['GET', '/intake/surfaces/model/:id', booted(isurfaces.model)],
  ['GET', '/intake/surfaces/panel', booted(isurfaces.panel)],
  ['GET', '/intake/surfaces/panel/size/:panel/:size', booted(isurfaces.panelSize)],
  ['POST', '/intake/surfaces/messages', booted(isurfaces.sendMessage)], // posted-by: composer.tsx composerAction (intake facade)
  ['POST', '/intake/surfaces/confirm', booted(isurfaces.confirm)], // posted-by: shared.tsx ItemActions (hx-post)
  ['POST', '/intake/surfaces/save', booted(isurfaces.save)], // posted-by: shared.tsx item edit forms (hx-post)
  ['POST', '/intake/surfaces/skip', booted(isurfaces.skip)], // posted-by: shared.tsx ItemActions (hx-post)
  ['GET', '/intake/surfaces/edit', booted(isurfaces.edit)],
  ['POST', '/intake/surfaces/accept-all', booted(isurfaces.acceptAll)], // posted-by: shared.tsx StepFoot (hx-post)
  // intake.flows — item-engine step
  ['GET', '/intake/flows', booted(iflows.page)],
  ['GET', '/intake/flows/file', booted(iflows.file)],
  ['GET', '/intake/flows/model/:id', booted(iflows.model)],
  ['GET', '/intake/flows/panel', booted(iflows.panel)],
  ['GET', '/intake/flows/panel/size/:panel/:size', booted(iflows.panelSize)],
  ['POST', '/intake/flows/messages', booted(iflows.sendMessage)], // posted-by: composer.tsx composerAction (intake facade)
  ['POST', '/intake/flows/confirm', booted(iflows.confirm)], // posted-by: shared.tsx ItemActions (hx-post)
  ['POST', '/intake/flows/save', booted(iflows.save)], // posted-by: shared.tsx item edit forms (hx-post)
  ['POST', '/intake/flows/skip', booted(iflows.skip)], // posted-by: shared.tsx ItemActions (hx-post)
  ['GET', '/intake/flows/edit', booted(iflows.edit)],
  ['POST', '/intake/flows/accept-all', booted(iflows.acceptAll)], // posted-by: shared.tsx StepFoot (hx-post)
  // intake.direction — item-engine step
  ['GET', '/intake/direction', booted(direction.page)],
  ['GET', '/intake/direction/file', booted(direction.file)],
  ['GET', '/intake/direction/model/:id', booted(direction.model)],
  ['GET', '/intake/direction/panel', booted(direction.panel)],
  ['GET', '/intake/direction/panel/size/:panel/:size', booted(direction.panelSize)],
  ['POST', '/intake/direction/messages', booted(direction.sendMessage)], // posted-by: composer.tsx composerAction (intake facade)
  ['POST', '/intake/direction/confirm', booted(direction.confirm)], // posted-by: shared.tsx ItemActions (hx-post)
  ['POST', '/intake/direction/save', booted(direction.save)], // posted-by: shared.tsx item edit forms (hx-post)
  ['POST', '/intake/direction/skip', booted(direction.skip)], // posted-by: shared.tsx ItemActions (hx-post)
  ['GET', '/intake/direction/edit', booted(direction.edit)],
  ['POST', '/intake/direction/accept-all', booted(direction.acceptAll)], // posted-by: shared.tsx StepFoot (hx-post)
  // intake.mapping — Story Map
  ['GET', '/intake/map', booted(mapping.page)],
  ['GET', '/intake/map/artifact/:kind/:id', booted(mapping.artifact)],
  ['GET', '/intake/map/file', booted(mapping.file)],
  ['GET', '/intake/map/model/:id', booted(mapping.model)],
  ['GET', '/intake/map/panel', booted(mapping.panel)],
  ['GET', '/intake/map/panel/size/:panel/:size', booted(mapping.panelSize)],
  ['POST', '/intake/map/messages', booted(mapping.sendMessage)], // posted-by: composer.tsx composerAction (intake facade)
  ['POST', '/intake/map/approve', booted(mapping.approve)], // posted-by: quick-replies r.action (intake facade)
  // intake.brief — Design Brief (carries the approval gate)
  ['GET', '/intake/brief', booted(brief.page)],
  ['GET', '/intake/brief/artifact/:kind/:id', booted(brief.artifact)],
  ['GET', '/intake/brief/file', booted(brief.file)],
  ['GET', '/intake/brief/model/:id', booted(brief.model)],
  ['GET', '/intake/brief/panel', booted(brief.panel)],
  ['GET', '/intake/brief/panel/size/:panel/:size', booted(brief.panelSize)],
  ['POST', '/intake/brief/messages', booted(brief.sendMessage)], // posted-by: composer.tsx composerAction (intake facade)
  ['POST', '/intake/brief/approve', booted(brief.approve)], // posted-by: quick-replies r.action (intake facade)
  // intake.moodboard — Moodboard
  ['GET', '/intake/moodboard', booted(moodboard.page)],
  ['GET', '/intake/moodboard/artifact/:kind/:id', booted(moodboard.artifact)],
  ['GET', '/intake/moodboard/file', booted(moodboard.file)],
  ['GET', '/intake/moodboard/model/:id', booted(moodboard.model)],
  ['GET', '/intake/moodboard/panel', booted(moodboard.panel)],
  ['GET', '/intake/moodboard/panel/size/:panel/:size', booted(moodboard.panelSize)],
  ['POST', '/intake/moodboard/messages', booted(moodboard.sendMessage)], // posted-by: composer.tsx composerAction (intake facade)
  // design.prototype — the design stage (shell root: /design)
  ['GET', '/design', booted(prototype.page)],
  ['GET', '/design/panel', booted(prototype.panel)],
  ['GET', '/design/panel/size/:panel/:size', booted(prototype.panelSize)],
  ['GET', '/design/panel/:view', booted(prototype.panelView)],
  ['GET', '/design/viewer', booted(prototype.viewer)],
  ['GET', '/design/file', booted(prototype.file)],
  ['GET', '/design/screen/:id', booted(prototype.screen)],
  ['POST', '/design/flows/:flow/move/:screen', booted(prototype.flowMove)], // posted-by: design_viewer tile toolbar + drag.js island
  ['POST', '/design/flows/:flow/add/:screen', booted(prototype.flowAdd)],
  ['POST', '/design/flows/:flow/remove/:screen', booted(prototype.flowRemove)],
  ['POST', '/design/panel/size/:panel', booted(prototype.panelSizePx)], // posted-by: drag.js island
  ['POST', '/design/undo/:stack', booted(prototype.undo)],
  ['POST', '/design/redo/:stack', booted(prototype.redo)],
  ['GET', '/design/drawer/:screen', booted(prototype.drawer)],
  ['GET', '/design/inspector', booted(prototype.inspector)],
  ['POST', '/design/inspector/select', booted(prototype.inspectorSelect)], // posted-by: inspect.js island
  ['POST', '/design/inspector/unlock', booted(prototype.inspectorUnlock)],
  ['POST', '/design/widget/arm', booted(prototype.widgetArm)],
  ['POST', '/design/widget/select', booted(prototype.widgetSelect)], // posted-by: canvas.js + drawer Tools strip
  ['POST', '/design/widget/attr', booted(prototype.widgetAttr)],
  ['POST', '/design/widget/text', booted(prototype.widgetText)],
  ['POST', '/design/widget/clear', booted(prototype.widgetClear)],
  // design.chat — the one design chat
  ['GET', '/design/chat', booted(dchat.page)],
  ['POST', '/design/chat/messages', booted(dchat.send)],
  ['GET', '/design/chat/context/:id', booted(dchat.context)],
  ['POST', '/design/chat/context/element', booted(dchat.elementContext)], // posted-by: inspect.js island
  ['GET', '/design/chat/context/element/remove', booted(dchat.elementContextRemove)],
  ['POST', '/design/chat/context/bulk', booted(dchat.bulkContext)], // posted-by: drag.js island
  ['GET', '/design/chat/model/:id', booted(dchat.model)],
  ['GET', '/design/chat/tray', booted(dchat.tray)],
  ['GET', '/design/chat/screen/:id', booted(dchat.select)],
  ['POST', '/design/chat/screen/:id/revert/:cp', booted(dchat.revert)],
  // design.freeze — freeze & trace + the manifest approval gate
  ['GET', '/design/freeze', booted(freeze.page)],
  ['GET', '/design/freeze/file', booted(freeze.file)],
  ['POST', '/design/freeze/messages', booted(freeze.send)],
  ['POST', '/design/freeze/recheck', booted(freeze.recheck)],
  ['GET', '/design/freeze/context/:id', booted(freeze.context)],
  ['GET', '/design/freeze/model/:id', booted(freeze.model)],
  ['GET', '/design/freeze/tray', booted(freeze.tray)],
  // /preferences/accent: no v2 sender has landed (the accent picker is a
  // dashboard-registry follow-up) — the route stays out rather than dead.
  ['POST', '/preferences/theme', preferences.setTheme],
];
