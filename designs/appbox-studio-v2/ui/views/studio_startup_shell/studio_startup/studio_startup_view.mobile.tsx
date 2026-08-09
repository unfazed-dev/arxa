// Role: startup surface at the compact rung. The full checklist is kept rather
//   than collapsed to a single "loading" line: the steps are the only feedback
//   this ceremony has, and hiding them at phone width is exactly the structure
//   the scaffolder would otherwise have to invent. The proceed trigger becomes
//   full-width and sits at the bottom edge, where a thumb reaches it.
// Requirements: Q-v2-1 (manual proceed trigger on every rung).
// Relationships: mounted by studio_startup_view.tsx.
// History: created for studio v2.
import type { FC } from 'hono/jsx';
import Checklist from '../../../widgets/studio_startup_widgets/boot_checklist.tsx';
import type { StartupProps } from './studio_startup_view.desktop.tsx';

const StudioStartupViewMobile: FC<StartupProps> = ({ steps, ready }) => (
  <div data-inspect-surface="studio_startup">
    <h1 class="title" style="font-size: 20px;">Starting the studio</h1>
    <Checklist steps={steps} ready={ready} block />
  </div>
);

export default StudioStartupViewMobile;
