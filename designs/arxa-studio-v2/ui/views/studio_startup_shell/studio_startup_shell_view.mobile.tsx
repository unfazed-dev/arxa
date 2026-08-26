// Role: startup shell at the compact rung. Full-bleed column: brand at the top,
//   progress under it, build identity pushed to the bottom edge by a spacer so
//   the checklist keeps the optically centred position as steps land.
// Requirements: Q-v2-1.
// Relationships: mounted by studio_startup_shell_view.tsx.
// History: created for studio v2.
import type { FC } from 'hono/jsx';
import type { StartupShellProps } from './studio_startup_shell_view.tsx';

const StudioStartupShellViewMobile: FC<StartupShellProps> = ({ brand, tagline, build, children }) => (
  <div class="ceremony">
    <div class="ceremony__stage" style="align-items: stretch;">
      <div class="ceremony__column">
        <span class="brand"><span class="brand__mark" />{brand}</span>
        <p class="subtitle" style="margin: 0;">{tagline}</p>
        {children}
        <span class="ceremony__spacer" />
        {build ? <p class="muted" style="margin: 0; font-size: 13px;">{build}</p> : null}
      </div>
    </div>
  </div>
);

export default StudioStartupShellViewMobile;
