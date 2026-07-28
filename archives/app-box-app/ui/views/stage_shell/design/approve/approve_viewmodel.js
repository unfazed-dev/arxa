export const surfaceId = 'design.approve';

import { chrome } from '../../../../../services/facades/shell_facade.js';

// States named in the brief are server-driven in-page variants, not forks.
const STATES = ["pending", "approved"];
const VIEW = 'ui/views/stage_shell/design/approve/approve_view.html';

// An explicit ?state= is the designer's override; otherwise the gate reports
// what the session actually records. Swapping an "approved" fragment in while
// a reload would still render "pending" is a worse bug than the full reload it
// replaces — so the write happens first and the swap renders from it.
const stateOf = (c, h) => {
  const q = c.req.query('state');
  if (STATES.includes(q)) return q;
  return h.session(c).data.designApproved ? 'approved' : 'pending';
};

export const page = (c, h) =>
  h.render(c, VIEW, {
    ...chrome('design'), state: stateOf(c, h), states: STATES, base: '/design/approve',
  });

export const approve = (c, h) => {
  h.session(c).data.designApproved = true;
  return h.render(c, `${VIEW}#gate`, { ...chrome('design'), state: 'approved' });
};
