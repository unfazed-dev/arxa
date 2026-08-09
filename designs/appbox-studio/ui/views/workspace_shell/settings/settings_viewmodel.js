// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
export const surfaceId = 'workspace.settings';

// Settings: four cookie prefs (theme / accent / font / jargon), each with its
// own POST. The cards show the live pref and a same-string example per level.
// Labels/examples live in l10n/app_*.arb — translated here via helpers.translate(context).
// Swatch list + display dots come from the SSOT (models/theme.json).
import { swatches } from '../../../../services/theme_tokens.js';
const ACCENTS = () => swatches().map((swatch) => ({ id: swatch.name, dot: swatch.dot }));

// Font rows come from the other SSOT (models/fonts.json) the same way. Their
// labels are NOT sent through helpers.translate(context) like the accent labels are: "Lexend" and
// "JetBrains Mono" are proper nouns that stay put in every locale, so the
// family name lives once in fonts.json instead of being restated per ARB.
import { fontMenu, defaultFont } from '../../../../services/font_tokens.js';

// One real string (the ΔE finding) at each level — the honest preview.
const LEVELS = [{ id: 'plain' }, { id: 'balanced' }, { id: 'technical' }];

import * as facade from '../../../../services/facades/app_facade.js';

const VIEW = 'ui/views/workspace_shell/settings/settings_view.html';

export const page = (context, helpers) => {
  const prefs = helpers.prefs(context);
  const translate = helpers.translate(context);
  return helpers.render(context, VIEW, {
    activeShell: 'workspace',
    prefs,
    project: facade.chromeProject(),
    theme: prefs.theme || 'light',
    accent: prefs.accent || 'cyan',
    font: prefs.font || defaultFont(),
    fonts: fontMenu(),
    jargon: prefs.jargon || 'balanced',
    accents: ACCENTS().map((accent) => ({ ...accent, label: translate('settings.accent.' + accent.id) })),
    levels: LEVELS.map((level) => ({
      ...level,
      label: translate('settings.level.' + level.id + '.label'),
      example: translate('settings.level.' + level.id + '.example'),
    })),
  });
};
