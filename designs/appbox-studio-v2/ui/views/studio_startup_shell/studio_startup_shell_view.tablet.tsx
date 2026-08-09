// Role: startup shell at the medium rung. The rail folds above the content into
//   a single centred card — a side rail at 744 would leave the progress column
//   too narrow to hold a step label on one line.
// Requirements: Q-v2-1.
// Relationships: mounted by studio_startup_shell_view.tsx.
// History: created for studio v2.
import type { FC } from 'hono/jsx';
import type { StartupShellProps } from './studio_startup_shell_view.tsx';

const StudioStartupShellViewTablet: FC<StartupShellProps> = ({ brand, tagline, build, children }) => (
  <div class="ceremony">
    <div class="ceremony__stage">
      <section class="ceremony__card">
        <span class="brand"><span class="brand__mark" />{brand}</span>
        <p class="subtitle" style="margin: 8px 0 24px;">{tagline}</p>
        {children}
        {build ? <p class="muted" style="margin-top: 24px; font-size: 13px;">{build}</p> : null}
      </section>
    </div>
  </div>
);

export default StudioStartupShellViewTablet;
