/// This is the user interface for studio_intake.
///
/// Role: the intake surface view — the interview. Hosted by
/// studio_intake_shell_view: composes the three DERIVED factor variants
/// (desktop: thread + upload rail; tablet/mobile: stacked) and hands
/// the rung trio to the shell as its `surface`.
///
/// Requirements:
/// 1. [Desktop/tablet/mobile for every studio view] — Q-v2-3
/// 2. [Manual advancement — every answer is a user trigger] — Q-v2-1
/// 3. [Inspect triple + annotation quad on every emitted element] — Q-v2-5
///
/// Relationships: studio_intake_viewmodel.js -> this -> the three
/// *_view.<factor>.tsx variants, wrapped by studio_intake_shell_view.tsx.
///
/// History: git log --follow -- ui/views/studio_intake_shell/studio_intake/studio_intake_view.tsx

import type { FC } from 'hono/jsx';
import Shell from '../studio_intake_shell_view.tsx';
import Desktop from './studio_intake_view.desktop.tsx';
import Tablet from './studio_intake_view.tablet.tsx';
import Mobile from './studio_intake_view.mobile.tsx';
import type { IntakeProps } from './studio_intake_view.desktop.tsx';

const StudioIntakeView: FC<IntakeProps & { locale?: string; activeShell: string }> = (props) => (
  <Shell
    {...props}
    surface={
      <div data-inspect-view="studio_intake_view">
        <div class="rung rung--desktop"><Desktop {...props} /></div>
        <div class="rung rung--tablet"><Tablet {...props} /></div>
        <div class="rung rung--mobile"><Mobile {...props} /></div>
      </div>
    }
  />
);

export default StudioIntakeView;
