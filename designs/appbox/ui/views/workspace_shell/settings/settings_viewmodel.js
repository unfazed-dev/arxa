// appbox:provenance
// generator: app-box  licence: free  project: 662368770980
// Built with app-box (free tier) — https://appbox.dev
export const surfaceId = 'workspace.settings';

// Settings: three cookie prefs (theme / accent / jargon), each with its own
// POST. The cards show the live pref and a same-string example per level.
// Labels/examples live in l10n/app_*.arb — translated here via h.t(c).
const ACCENTS = [
  { id: 'cyan', dot: '#21BFE9' },
  { id: 'violet', dot: '#4E28D5' },
  { id: 'blue', dot: '#3473DF' },
  { id: 'ember', dot: '#DA702C' },
];

// One real string (the ΔE finding) at each level — the honest preview.
const LEVELS = [{ id: 'plain' }, { id: 'balanced' }, { id: 'technical' }];

const VIEW = 'ui/views/workspace_shell/settings/settings_view.html';

export const page = (c, h) => {
  const prefs = h.prefs(c);
  const t = h.t(c);
  return h.render(c, VIEW, {
    activeShell: 'workspace',
    theme: prefs.theme || 'light',
    accent: prefs.accent || 'cyan',
    jargon: prefs.jargon || 'balanced',
    accents: ACCENTS.map((a) => ({ ...a, label: t('settings.accent.' + a.id) })),
    levels: LEVELS.map((l) => ({
      ...l,
      label: t('settings.level.' + l.id + '.label'),
      example: t('settings.level.' + l.id + '.example'),
    })),
  });
};
