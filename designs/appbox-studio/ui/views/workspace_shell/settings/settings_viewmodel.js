// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
export const surfaceId = 'workspace.settings';

// Settings: three cookie prefs (theme / accent / jargon), each with its own
// POST. The cards show the live pref and a same-string example per level.
// Labels/examples live in l10n/app_*.arb — translated here via h.t(c).
// Swatch list + display dots come from the SSOT (models/theme.json).
import { swatches } from '../../../../services/theme_tokens.js';
const ACCENTS = () => swatches().map((s) => ({ id: s.name, dot: s.dot }));

// One real string (the ΔE finding) at each level — the honest preview.
const LEVELS = [{ id: 'plain' }, { id: 'balanced' }, { id: 'technical' }];

import * as facade from '../../../../services/facades/app_facade.js';

const VIEW = 'ui/views/workspace_shell/settings/settings_view.html';

export const page = (c, h) => {
  const prefs = h.prefs(c);
  const t = h.t(c);
  return h.render(c, VIEW, {
    activeShell: 'workspace',
    prefs,
    project: facade.chromeProject(),
    theme: prefs.theme || 'light',
    accent: prefs.accent || 'cyan',
    jargon: prefs.jargon || 'balanced',
    accents: ACCENTS().map((a) => ({ ...a, label: t('settings.accent.' + a.id) })),
    levels: LEVELS.map((l) => ({
      ...l,
      label: t('settings.level.' + l.id + '.label'),
      example: t('settings.level.' + l.id + '.example'),
    })),
  });
};
