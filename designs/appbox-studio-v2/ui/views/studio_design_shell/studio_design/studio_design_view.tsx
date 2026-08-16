/// This is the user interface for studio_design.
///
/// Role: the design surface view — the canvas studio. Hosted by
/// studio_design_shell_view: composes the three DERIVED factor variants
/// (desktop: activity | canvas | inspector; tablet: canvas over
/// inspector; mobile: canvas + composer sheet) and hands the rung trio
/// to the shell as its `surface`.
///
/// Requirements:
/// 1. [Desktop/tablet/mobile for every studio view] — Q-v2-3
/// 2. [Canvas: desktop = full studio; tablet shows tablet+mobile of the
///    designed app; mobile shows mobile only] — registry design_canvas note
/// 3. [Inspect triple + annotation quad on every emitted element] — Q-v2-5
///
/// Relationships: studio_design_viewmodel.js -> this -> the three
/// *_view.<factor>.tsx variants, wrapped by studio_design_shell_view.tsx.
///
/// History: git log --follow -- ui/views/studio_design_shell/studio_design/studio_design_view.tsx

import type { FC } from 'hono/jsx';
import Shell from '../studio_design_shell_view.tsx';
import Desktop from './studio_design_view.desktop.tsx';
import Tablet from './studio_design_view.tablet.tsx';
import Mobile from './studio_design_view.mobile.tsx';
import type { DesignProps } from './studio_design_view.desktop.tsx';

const StudioDesignView: FC<DesignProps & { locale?: string; activeShell: string }> = (props) => (
  <Shell
    {...props}
    surface={
      <div data-inspect-view="studio_design_view">
        <div class="rung rung--desktop"><Desktop {...props} /></div>
        <div class="rung rung--tablet"><Tablet {...props} /></div>
        <div class="rung rung--mobile"><Mobile {...props} /></div>
      </div>
    }
  />
);

export default StudioDesignView;
