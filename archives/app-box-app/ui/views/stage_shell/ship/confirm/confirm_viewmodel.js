export const surfaceId = 'ship.confirm';

import { chrome } from '../../../../../services/facades/shell_facade.js';
import { release } from '../../../../../services/facades/pipeline_facade.js';

// States named in the brief are server-driven in-page variants, not forks.
const STATES = ["pending", "confirmed"];
const VIEW = 'ui/views/stage_shell/ship/confirm/confirm_view.html';

const stateOf = (c, h) => {
  const q = c.req.query('state');
  if (STATES.includes(q)) return q;
  return h.session(c).data.released ? 'confirmed' : 'pending';
};

export const page = (c, h) =>
  h.render(c, VIEW, {
    ...chrome('ship'), state: stateOf(c, h), states: STATES, base: '/ship/confirm',
    ...release(),
  });

// The checkbox is `required`, but a required input is a client-side courtesy —
// it is absent from the body of anyone who posts around the form. The gate
// re-asserts it rather than trusting the markup.
export const approve = async (c, h) => {
  const body = await h.form(c);
  if (!body.ack) {
    return h.render(c, `${VIEW}#gate`,
      { ...chrome('ship'), state: 'pending', ...release() }, 422);
  }
  h.session(c).data.released = true;
  return h.render(c, `${VIEW}#gate`,
    { ...chrome('ship'), state: 'confirmed', ...release() });
};
