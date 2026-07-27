export const surfaceId = 'stage.shell';

// The shell renders the chrome; surfaces fill its {% block surface %}.
import { chrome } from '../../../services/facades/shell_facade.js';

export const page = (c, h) =>
  h.render(c, 'ui/views/stage_shell/stage_shell_view.html', chrome('projects'));

// Appearance is a preference, so it round-trips to the server and comes back
// as a full refresh. No client-side theme switching exists.
// 'system' is stored explicitly rather than as an absent value, so choosing it
// after an override is a real choice and not a reset.
const THEMES = ['system', 'light', 'dark'];

export const theme = async (c, h) => {
  const body = await c.req.parseBody();
  const t = THEMES.includes(body.theme) ? body.theme : 'system';
  h.setPrefs(c, { theme: t });
  return h.refresh(c);
};
