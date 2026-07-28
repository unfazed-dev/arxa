export const surfaceId = 'chat.home';

import { chrome } from '../../../../../services/facades/shell_facade.js';
import { transcript } from '../../../../../services/facades/chat_facade.js';

// States named in the brief are server-driven in-page variants, not forks.
const STATES = ["idle", "streaming", "tool-call"];
const VIEW = 'ui/views/stage_shell/chat/home/home_view.html';

const sentIn = (c, h) => (h.session(c).data.sent ??= []);

export const page = (c, h) => {
  const q = c.req.query('state');
  const state = STATES.includes(q) ? q : 'idle';
  return h.render(c, VIEW, {
    ...chrome('chat'), state, states: STATES, base: '/chat',
    ...transcript(), sent: sentIn(c, h),
  });
};

// The message lands in the session before the panel renders, so the swap and a
// later reload show the same transcript. No reply is faked: app_box answering
// is the pipeline's job, and a prototype that invents one is lying on the
// surface whose whole promise is "changes land as edits, never as claims".
export const submit = async (c, h) => {
  const body = String((await h.form(c)).body ?? '').trim();
  if (body) sentIn(c, h).push(body);
  return h.render(c, `${VIEW}#panel`, {
    ...chrome('chat'), state: 'idle', ...transcript(), sent: sentIn(c, h),
  });
};
