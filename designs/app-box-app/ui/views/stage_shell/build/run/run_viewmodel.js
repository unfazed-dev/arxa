export const surfaceId = 'build.run';

import { chrome } from '../../../../../services/facades/shell_facade.js';
import { run, findings } from '../../../../../services/facades/pipeline_facade.js';

// States named in the brief are server-driven in-page variants, not forks.
const STATES = ["red", "idle", "running", "green"];
const VIEW = 'ui/views/stage_shell/build/run/run_view.html';

const stateOf = (c, h) => {
  const q = c.req.query('state');
  if (STATES.includes(q)) return q;
  return h.session(c).data.buildState ?? 'red';
};

const bag = (state) => ({ ...chrome('build'), state, ...run(), ...findings() });

export const page = (c, h) =>
  h.render(c, VIEW, { ...bag(stateOf(c, h)), states: STATES, base: '/build' });

// Run and Stop are the same route; the button says which. The prototype does
// not simulate a build — Run reaches `running` and stops there, because a fake
// green is the one outcome this surface must never show.
export const submit = async (c, h) => {
  const action = (await h.form(c)).action;
  const state = action === 'stop' ? 'idle' : 'running';
  h.session(c).data.buildState = state;
  return h.render(c, `${VIEW}#panel`, bag(state));
};
