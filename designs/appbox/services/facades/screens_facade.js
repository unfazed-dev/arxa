// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
// ScreensFacade — composes the registry into view-ready context.
// ViewModels talk to facades, never to repositories or fixtures directly.
// Labels render through the runtime translator: each registry entry carries
// a labelKey into l10n/app_*.arb; the entry's `label` field is the en
// fallback when the key is absent from the active catalog.
import * as screens from '../repositories/screens_repository.js';

export const shellIndexContext = (t = (k) => k) => {
  const labelOf = (e) => {
    if (!e.labelKey) return e.id === 'main.shell' ? t('shell.main') : e.label;
    const tr = t(e.labelKey);
    return tr == e.labelKey ? e.label : tr; // key missing from every catalog → en fallback
  };
  const shells = screens.byShell().map((sh) => ({
    ...sh,
    label: labelOf(sh),
    shells: sh.shells.map((group) => ({
      ...group,
      surfaces: group.surfaces.map((s) => ({ ...s, label: labelOf(s) })),
    })),
  }));
  return {
    shells,
    counts: {
      surfaces: screens.all().filter((e) => !e.id.endsWith('.shell')).length,
      shells: screens.all().filter((e) => e.id.endsWith('.shell')).length,
    },
  };
};
