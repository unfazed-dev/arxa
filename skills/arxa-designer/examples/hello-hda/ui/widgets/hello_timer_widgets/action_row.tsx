// action_row.tsx — the timer's action row container (extend / skip). The
// row is presentation, so it lives in the library; the sections file
// composes <ActionRow> around the ActionButton invocations (W9).
import type { FC, Child } from 'hono/jsx';

export interface ActionRowProps {
  children?: Child;
}

export const ActionRow: FC<ActionRowProps> = ({ children }) => (
  <div data-arxa-id="ui-widgets-hello_timer_widgets-action_row-e1" class="action-row">{children}</div>
);
