// kind: cta-link
// Role: the manual hand-off out of a ceremony shell. Disabled until the shell
//   reports ready; pressing it is the ONLY thing that advances a stage.
// Requirements: Q-v2-1 (stage advancement is user-gated, never implicit).
// Relationships: composed by boot_checklist.tsx. Surface-scoped on purpose —
//   it has exactly one consumer today; it earns `ui/widgets/common/<group>/` when a
//   second shell actually imports it, not because it was designed to.
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
    data-el="cta-link"
    data-inspect-role="button"
    data-inspect-style="filled pill, full-width at the compact rung, dimmed while disabled"
    data-inspect-fn="ends the ceremony and opens the studio — the only way past this screen"
    data-inspect-motion="traverse"
    data-inspect-widget={widgetId}
    class={`button${block ? ' button--block' : ''}`}
    hx-post={href}
    disabled={!ready}
    aria-disabled={ready ? undefined : 'true'}
  >
    {label}
  </button>
);

export default ProceedTrigger;
