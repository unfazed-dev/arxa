// ShellFacade — the chrome every surface renders inside.
// The four pipeline stages are a real sequence and carry their ordinal; chat
// and settings are utilities and deliberately do not.
import * as pipeline from '../repositories/pipeline_repository.js';

const UTIL = [
  { id: 'chat',     label: 'Chat',     href: '/chat' },
  { id: 'settings', label: 'Settings', href: '/settings' },
];
const HREF = { projects: '/', design: '/design', build: '/build', ship: '/ship' };

export const chrome = (tab) => ({
  tab,
  stages: pipeline.stages().map((s) => ({ ...s, href: HREF[s.id] })),
  utils: UTIL,
});
