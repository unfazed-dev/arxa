// Role: v1 English string table + minimal translate() for surfaces restyled to the v1
//   design (task #22). The v1 views were authored against l10n keys; the v2
//   design prototype has no l10n runtime, so the English table rides along.
// Source: designs/appbox-studio/l10n/app_en.arb (subset by prefix).
// History: created for the v1-design port; regenerate from the arb, do not
//   hand-edit values.

const STRINGS: Record<string, string> = {
  "nav.open": "Open navigation",
  "nav.more": "More actions",
  "nav.primary": "Primary",
  "nav.quickActions": "Quick actions",
  "nav.openRailbar": "Open the railbar",
  "tab.intake": "Intake",
  "tab.design": "Design",
  "tab.scaffold": "Scaffold",
  "tab.build": "Build",
  "tab.settings": "Settings",
  "hub.daemonChannel": "daemon channel",
  "hub.daemonLive": "daemon live",
  "hub.projectBack": "Project — back to the dashboard",
  "hub.theme.light": "Light theme",
  "hub.theme.dark": "Dark theme",
  "hub.themeShort.light": "Light",
  "hub.themeShort.dark": "Dark",
  "action.newProject": "New project",
  "action.pairDevice": "Pair device",
  "action.approve": "Approve",
  "action.reject": "Reject",
  "dash.pageTitle": "Appbox Studio — Dashboard",
  "dash.greeting": "Good to see you, {name}",
  "dash.gatesNeedYou": "{count, plural, one{{count} gate needs you} other{{count} gates need you}}",
  "dash.projectsTailnet": "{count, plural, one{{count} project on this tailnet} other{{count} projects on this tailnet}}",
  "dash.needsYouH": "Needs you",
  "dash.gatesEmpty": "Nothing needs you — every gate is decided. New gates land here the moment a run goes red or a stage finishes.",
  "dash.projectsH": "Projects",
  "dash.stage.intake": "Intake",
  "dash.stage.design": "Design",
  "dash.stage.build": "Build",
  "dash.stage.gates": "Gates",
  "dash.current": "current",
  "dash.useProject": "Set current",
  "dash.projectsEmpty": "No projects yet — create one below.",
  "dash.open": "open",
  "dash.thisWeek": "This week",
  "wizard.nameLabel": "Project name",
  "wizard.namePlaceholder": "e.g. Foxglove",
  "wizard.targets": "Targets",
  "wizard.create": "Create project",
  "pair.title": "Pair a device",
  "pair.lede": "Scan with the phone or tablet you want to approve gates from.",
  "pair.closeLabel": "Close pairing dialog",
  "pair.qrAria": "Prototype QR placeholder — decorative, not scannable",
  "auth.pageTitle": "Appbox Studio — Sign in",
  "auth.email": "Email",
  "auth.continue": "Continue",
  "auth.createAccount": "Create account",
  "auth.or": "or",
  "splash.connecting": "Connecting to the appbox daemon",
  "status.name.done": "done",
  "status.name.in-progress": "in progress",
  "status.name.blocked": "blocked",
  "status.name.pending": "pending",
  "mainPanel.empty": "Nothing open yet — pick a file or an artifact from the activity panel.",
  "mainPanel.back": "Back",
  "mainPanel.mode.code": "code",
  "mainPanel.mode.doc": "document",
  "mainPanel.mode.image": "image",
  "mainPanel.mode.svg": "svg",
  "mainPanel.mode.pdf": "pdf",
  "mainPanel.mode.video": "video",
  "status.name.green": "green",
  "status.name.red": "red",
  "status.name.recovered": "recovered",
  "status.name.queued": "queued",
  "status.name.held": "held",
  "status.name.active": "active",
  "status.name.approved": "approved",
  "status.name.rejected": "rejected",
  "status.name.cancelled": "cancelled",
  "status.name.pass": "pass",
  "status.name.watch": "watch",
  "status.name.frozen": "frozen",
  "status.name.resolved": "resolved",
  "stage.name.build": "Build",
  "stage.name.design": "Design",
  "stage.name.ship": "Ship",
  "dash.eyebrow": "app",
  "splash.pageTitle": "Appbox Studio",
  "startup.pageTitle": "Portalo",
  "startup.loading": "Loading assets…",
  "startup.step.daemon": "Daemon warm-up",
  "startup.step.kits": "Kits loaded",
  "startup.step.project": "Current project: {name}",
  "app.brand": "Portalo"
};

const PLURAL = /^\{(\w+), plural,\s*one\{(.*?)\}\s*other\{(.*?)\}\}$/s;

export type TFn = (key: string, vars?: Record<string, unknown>) => string;

export const makeT = (): TFn => (key, vars) => {
  let template = STRINGS[key];
  if (template === undefined) return key;
  const pluralMatch = template.match(PLURAL);
  if (pluralMatch && vars) {
    const count = Number(vars[pluralMatch[1]] ?? 0);
    template = count === 1 ? pluralMatch[2] : pluralMatch[3];
  }
  if (vars) for (const [varName, varValue] of Object.entries(vars)) template = template.split(`{}`).join(String(varValue));
  return template;
};
