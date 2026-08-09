// Role: stage board view. Composes the three DERIVED factor variants inside the
//   hub shell. It holds no markup of its own — every pixel belongs to a rung.
// Requirements: Q-v2-3, Q-v2-5.
// Relationships: studio_stage_board_viewmodel.js -> this -> the three
//   *_view.<factor>.tsx variants, wrapped by studio_application_hub_shell_view.
// History: created for studio v2.
import type { FC } from 'hono/jsx';
import Shell from '../studio_application_hub_shell_view.tsx';
import Desktop from './studio_stage_board_view.desktop.tsx';
import Tablet from './studio_stage_board_view.tablet.tsx';
import Mobile from './studio_stage_board_view.mobile.tsx';
import type { BoardProps } from './studio_stage_board_view.desktop.tsx';

const StudioStageBoardView: FC<BoardProps & { locale?: string }> = (props) => (
  <Shell brand={props.brand} locale={props.locale}>
    <div data-inspect-view="studio_stage_board_view">
      <div class="rung rung--desktop"><Desktop {...props} /></div>
      <div class="rung rung--tablet"><Tablet {...props} /></div>
      <div class="rung rung--mobile"><Mobile {...props} /></div>
    </div>
  </Shell>
);

export default StudioStageBoardView;
