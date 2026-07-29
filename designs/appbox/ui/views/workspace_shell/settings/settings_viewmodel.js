export const surfaceId = 'workspace.settings';

// Settings: three cookie prefs (theme / accent / jargon), each with its own
// POST. The cards show the live pref and a same-string example per level.
const ACCENTS = [
  { id: 'cyan', label: 'Cyan — brand', dot: '#21BFE9' },
  { id: 'violet', label: 'Violet — brand', dot: '#4E28D5' },
  { id: 'blue', label: 'Blue — blend', dot: '#3473DF' },
  { id: 'ember', label: 'Ember — warm', dot: '#DA702C' },
];

// One real string (the ΔE finding) at each level — the honest preview.
const LEVELS = [
  {
    id: 'plain',
    label: 'Plain — average human',
    example: 'noticeably different — 88/100 on the CartSummary card. A muted text colour only worked in light mode',
  },
  {
    id: 'balanced',
    label: 'Balanced — in between',
    example: '88/100 (ΔE 4.8) on the CartSummary card — muted text token drift',
  },
  {
    id: 'technical',
    label: 'Technical — full jargon',
    example: 'ΔE 4.8 on the CartSummary card — muted text token drift',
  },
];

const VIEW = 'ui/views/workspace_shell/settings/settings_view.html';

export const page = (c, h) => {
  const prefs = h.prefs(c);
  return h.render(c, VIEW, {
    activeTab: 'workspace',
    theme: prefs.theme || 'light',
    accent: prefs.accent || 'cyan',
    jargon: prefs.jargon || 'balanced',
    accents: ACCENTS,
    levels: LEVELS,
  });
};
