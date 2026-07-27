export const surfaceId = 'chat.home';

import { chrome } from '../../../../../services/facades/shell_facade.js';
import { transcript } from '../../../../../services/facades/chat_facade.js';

// States named in the brief are server-driven in-page variants, not forks.
const STATES = ["idle", "streaming", "tool-call"];

export const page = (c, h) => {
  const q = c.req.query('state');
  const state = STATES.includes(q) ? q : 'idle';
  return h.render(c, 'ui/views/stage_shell/chat/home/home_view.html', {
    ...chrome('chat'), state, states: STATES, base: '/chat',
    ...transcript(),
  });
};

// The prototype re-renders; it does not persist. Approval and build state
// belong to pipeline state, not to a design artifact pretending to hold them.
export const submit = (c, h) => h.refresh(c);
