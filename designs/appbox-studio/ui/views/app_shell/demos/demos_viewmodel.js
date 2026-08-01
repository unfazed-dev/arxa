// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
export const surfaceId = 'app.demos';

import * as facade from '../../../../services/facades/app_facade.js';

const VIEW = 'ui/views/app_shell/demos/demos_view.html';

// One card per media-lab screen; title/lede come from the media.* l10n keys.
const DEMOS = [
  { id: 'rive', icon: 'clapperboard' },
  { id: 'lottie', icon: 'sparkles' },
  { id: 'dotlottie', icon: 'package' },
  { id: 'model3d', icon: 'box' },
  { id: 'scene3d', icon: 'orbit' },
  { id: 'game', icon: 'gamepad-2' },
  { id: 'maps', icon: 'map' },
];

export const page = (c, h) => {
  const embed = facade.embedContext(c);
  return h.render(c, VIEW, {
    activeShell: 'app',
    tab: 'demos',
    ...embed,
    demos: DEMOS.map((d) => ({ ...d, href: `/media/${d.id}${embed.qs}` })),
  });
};
