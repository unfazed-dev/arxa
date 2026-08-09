// Role: startup surface at the medium rung. Same full checklist as expanded —
//   the card is wide enough to hold it — but the explanatory subtitle is
//   dropped: inside a centred card the heading and the steps already read as
//   one unit, and the extra line pushes the list below the fold.
// Requirements: Q-v2-1, Q-v2-3, Q-v2-5.
// Relationships: mounted by studio_startup_view.tsx.
// History: created for studio v2.
import type { FC } from 'hono/jsx';
import Checklist from './widgets/boot_checklist.tsx';
import type { StartupProps } from './studio_startup_view.desktop.tsx';

const StudioStartupViewTablet: FC<StartupProps> = ({ steps, ready, title, proceedLabel }) => (
  <div data-inspect-surface="studio_startup">
    <h1 class="title">{title}</h1>
    <Checklist steps={steps} ready={ready} proceedLabel={proceedLabel} />
  </div>
);

export default StudioStartupViewTablet;
