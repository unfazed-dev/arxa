// Role: startup surface at the compact rung. The full checklist is kept rather
//   than collapsed to a single "loading" line: the steps are the only feedback
//   this ceremony has, and hiding them at phone width is exactly the structure
//   the scaffolder would otherwise have to invent. The proceed trigger becomes
//   full-width, where a thumb reaches it.
// Requirements: Q-v2-1 (manual proceed trigger on every rung), Q-v2-3, Q-v2-5.
// Relationships: mounted by studio_startup_view.tsx.
// History: created for studio v2.
import type { FC } from 'hono/jsx';
import Checklist from './widgets/boot_checklist.tsx';
import type { StartupProps } from './studio_startup_view.desktop.tsx';

const StudioStartupViewMobile: FC<StartupProps> = ({ steps, ready, title, proceedLabel }) => (
  <div data-inspect-surface="studio_startup">
    <h1 class="title" style="font-size: 20px;">{title}</h1>
    <Checklist steps={steps} ready={ready} proceedLabel={proceedLabel} block />
  </div>
);

export default StudioStartupViewMobile;
