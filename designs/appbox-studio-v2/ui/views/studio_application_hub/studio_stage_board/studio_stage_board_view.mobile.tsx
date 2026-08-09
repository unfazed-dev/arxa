// Role: the board at the compact rung — one card per row, contract line
//   dropped. The stage name plus its enabled state is the decision at phone
//   width; the consumes/produces contract is detail the user opens to read.
// Requirements: Q-v2-1, Q-v2-3, Q-v2-5.
// Relationships: mounted by studio_stage_board_view.tsx.
// History: created for studio v2.
import type { FC } from 'hono/jsx';
import StageBoard from './widgets/stage_board.tsx';
import type { BoardProps } from './studio_stage_board_view.desktop.tsx';

const StudioStageBoardViewMobile: FC<BoardProps> = ({ stages, title, consumesLabel, producesLabel }) => (
  <div data-inspect-surface="studio_stage_board">
    <h1 class="title" style="font-size: 20px;">{title}</h1>
    <StageBoard
      stages={stages}
      consumesLabel={consumesLabel}
      producesLabel={producesLabel}
      density="stack"
      compact
    />
  </div>
);

export default StudioStageBoardViewMobile;
