export const surfaceId = 'projects.new';

import { chrome } from '../../../../../services/facades/shell_facade.js';

// States named in the brief are server-driven in-page variants, not forks.
const STATES = ["form", "validating", "error"];
const VIEW = 'ui/views/stage_shell/projects/new/new_view.html';

export const page = (c, h) => {
  const q = c.req.query('state');
  const state = STATES.includes(q) ? q : 'form';
  return h.render(c, VIEW, {
    ...chrome('projects'), state, states: STATES, base: '/projects/new',
    name: state === 'form' ? '' : 'Ledgerly',
  });
};

// Validation is the server's, and the answer is 422 + the form again. The
// typed name comes back with it: an error that empties the field you got right
// is a second error.
//
// A valid submit hands the browser to the list. The prototype does not persist
// the project, so nothing on that list claims to be the one you just typed —
// inventing a row is the sort of lie the honesty surfaces exist to rule out.
export const submit = async (c, h) => {
  const body = await h.form(c);
  const name = String(body.name ?? '').trim();
  if (!String(body.client ?? '').trim()) {
    return h.render(c, `${VIEW}#form`,
      { ...chrome('projects'), state: 'error', name }, 422);
  }
  return h.location(c, '/');
};
