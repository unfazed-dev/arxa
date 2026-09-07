// Role: startup shell at the expanded rung. Brand sits in a left rail with the
//   build identity under it, boot progress to its right — at this width the
//   two are read together, so a slow step is attributable to a build.
// Requirements: Q-v2-1.
// Relationships: mounted by studio_startup_shell_view.tsx.
// History: created for studio v2.
import type { FC } from 'hono/jsx';
import type { StartupShellProps } from './studio_startup_shell_view.tsx';

const StudioStartupShellViewDesktop: FC<StartupShellProps> = ({ brand, tagline, build, children }) => (
  <div class="ceremony">
    <div class="ceremony__stage">
      <div class="ceremony__split">
        <aside class="ceremony__brand-rail">
          <span class="brand"><span class="brand__mark" />{brand}</span>
          <p class="subtitle" style="margin-top: 8px;">{tagline}</p>
          {build ? <p class="muted" style="margin-top: 24px; font-size: 13px;">{build}</p> : null}
        </aside>
        <section>{children}</section>
      </div>
    </div>
  </div>
);

export default StudioStartupShellViewDesktop;
