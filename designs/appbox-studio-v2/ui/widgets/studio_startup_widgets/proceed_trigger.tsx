// kind: cta-link
// Role: the manual hand-off out of a ceremony shell. Disabled until the shell
//   reports ready; pressing it is the ONLY thing that advances a stage.
// Requirements: Q-v2-1 ("stage advancement is user-gated, never implicit").
// Relationships: composed by boot_checklist.tsx; posts to the route the caller
//   names, so the same trigger serves every ceremony shell that lands later.
// History: created for studio v2.
import type { FC } from 'hono/jsx';

export interface ProceedTriggerProps {
  href: string;
  label: string;
  ready: boolean;
  block?: boolean;
  widgetId?: string;
}

const ProceedTrigger: FC<ProceedTriggerProps> = ({ href, label, ready, block, widgetId = 'proceed_trigger' }) => (
  <button
    type="button"
    class={`button${block ? ' button--block' : ''}`}
    hx-post={href}
    disabled={!ready}
    aria-disabled={ready ? undefined : 'true'}
    data-inspect-widget={widgetId}
  >
    {label}
  </button>
);

export default ProceedTrigger;
