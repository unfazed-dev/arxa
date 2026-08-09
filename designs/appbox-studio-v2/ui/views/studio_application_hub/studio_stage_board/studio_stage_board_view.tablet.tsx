// Role: the board at the medium rung — two columns instead of the wide grid.
//   The io line is kept: a two-column card still has the measure to read it,
//   and losing it here would strand the user between a name and no contract.
// Requirements: Q-v2-1, Q-v2-3, Q-v2-5.
// Relationships: mounted by studio_stage_board_view.tsx.
// History: created for studio v2.
import type { FC } from 'hono/jsx';
import StageBoard from './widgets/stage_board.tsx';
import type { BoardProps } from './studio_stage_board_view.desktop.tsx';

const StudioStageBoardViewTablet: FC<BoardProps> = ({ stages, title, consumesLabel, producesLabel }) => (
  <div data-inspect-surface="studio_stage_board">
    <h1 class="title">{title}</h1>
    <StageBoard stages={stages} consumesLabel={consumesLabel} producesLabel={producesLabel} density="pair" />
  </div>
);

export default StudioStageBoardViewTablet;
