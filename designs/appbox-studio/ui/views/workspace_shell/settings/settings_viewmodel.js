// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
export const surfaceId = 'workspace.settings';

// Settings: four cookie prefs (theme / accent / font / jargon), each with its
// own POST. The cards show the live pref and a same-string example per level.
// Labels/examples live in l10n/app_*.arb — translated here via h.t(c).
// Swatch list + display dots come from the SSOT (models/theme.json).
import { swatches } from '../../../../services/theme_tokens.js';
const ACCENTS = () => swatches().map((s) => ({ id: s.name, dot: s.dot }));

// Font rows come from the other SSOT (models/fonts.json) the same way. Their
// labels are NOT sent through h.t(c) like the accent labels are: "Lexend" and
// "JetBrains Mono" are proper nouns that stay put in every locale, so the
// family name lives once in fonts.json instead of being restated per ARB.
import { fontMenu, defaultFont } from '../../../../services/font_tokens.js';

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
    font: prefs.font || defaultFont(),
    fonts: fontMenu(),
    jargon: prefs.jargon || 'balanced',
    accents: ACCENTS().map((a) => ({ ...a, label: t('settings.accent.' + a.id) })),
    levels: LEVELS.map((l) => ({
      ...l,
      label: t('settings.level.' + l.id + '.label'),
      example: t('settings.level.' + l.id + '.example'),
    })),
  });
};
