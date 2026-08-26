// render.tsx — TSX view renderer.
// Resolves view refs (.html paths, for registry parity with viewmodels) to
// hono/jsx components. Splits on `#` for Named Fragment dispatch.
//
// Static registry: all components imported at boot. In production this is
// generated at eject time from the artifact's template inventory.
import type { FC } from 'hono/jsx';
import TimerPage, { Tick } from '../../../examples/hello-hda/ui/views/main_shell/timer/timer_view.tsx';
import HomePage from '../../../examples/hello-hda/ui/views/main_shell/home/home_view.tsx';
import MainShell from '../../../examples/hello-hda/ui/views/main_shell/main_shell_view.tsx';

type ComponentMap = { default: FC<Record<string, unknown>>; [fragment: string]: FC<Record<string, unknown>> };

// Registry keys are .html paths — the viewmodels already use these as registry
// keys (e.g., 'ui/views/main_shell/timer/timer_view.html'). The render function
// maps them to .tsx components.
const registry: Record<string, ComponentMap> = {
  'ui/views/main_shell/main_shell_view.html': {
    default: MainShell as FC<Record<string, unknown>>,
  },
  'ui/views/main_shell/timer/timer_view.html': {
    default: TimerPage as FC<Record<string, unknown>>,
    tick: Tick as FC<Record<string, unknown>>,
  },
  'ui/views/main_shell/home/home_view.html': {
    default: HomePage as FC<Record<string, unknown>>,
  },
};

export function render(viewRef: string, ctx: Record<string, unknown>) {
  const hash = viewRef.indexOf('#');
  const file = hash === -1 ? viewRef : viewRef.slice(0, hash);
  const macro = hash === -1 ? undefined : viewRef.slice(hash + 1);

  const entry = registry[file];
  if (!entry) throw new Error('Unknown view: ' + file);
  const component = macro ? entry[macro] : entry.default;
  if (!component) throw new Error('Unknown fragment: ' + macro);
  return component(ctx);
}
