export const surfaceId = 'build.approve';

import { chrome } from '../../../../../services/facades/shell_facade.js';

// States named in the brief are server-driven in-page variants, not forks.
const STATES = ["pending", "approved"];
const VIEW = 'ui/views/stage_shell/build/approve/approve_view.html';

// ?state= is the designer's override; otherwise the gate reports what the
// session records, so the swap and a later reload agree.
const stateOf = (c, h) => {
  const q = c.req.query('state');
  if (STATES.includes(q)) return q;
  return h.session(c).data.buildApproved ? 'approved' : 'pending';
};

export const page = (c, h) =>
  h.render(c, VIEW, {
    ...chrome('build'), state: stateOf(c, h), states: STATES, base: '/build/approve',
  });

export const approve = (c, h) => {
  h.session(c).data.buildApproved = true;
  return h.render(c, `${VIEW}#gate`, { ...chrome('build'), state: 'approved' });
};
