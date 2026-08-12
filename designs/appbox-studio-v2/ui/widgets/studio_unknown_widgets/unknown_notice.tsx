// kind: empty-state
// Role: the 404 notice — status code, message, reassurance hint, and the one
//   way out (home link). One widget because the pieces are meaningless apart:
//   a rung must never render the code without the way home.
// Requirements: Q-v2-5 (inspect triple + annotation quad on every emitted
//   element); registry `studio_unknown_shell.unknown` widgets.
// Relationships: composed by all three studio_unknown_view.<factor>.tsx
//   variants. Surface-scoped on purpose — it has exactly one consumer; it
//   earns `ui/widgets/common/<group>/` when a second shell imports it.
// History: created for studio v2; visuals ported from
//   designs/appbox-studio/ui/views/app_shell/unknown/unknown_view.tsx (v1).
import type { FC } from 'hono/jsx';
import { inspectAttrs, Txt, Heading } from '../common/studio_primitives/widgets.tsx';

export interface UnknownNoticeProps {
  code: string;
  msg: string;
  hint: string;
  homeHref: string;
  homeLabel: string;
  widgetId?: string;
}

const UnknownNotice: FC<UnknownNoticeProps> = ({ code, msg, hint, homeHref, homeLabel, widgetId = 'unknown_notice' }) => (
  <div
    class="error-page-notice"
    {...inspectAttrs(widgetId, {
      role: 'group',
      style: 'v1 error page: code over message over hint over home link, centred',
      motion: 'none',
      fn: 'tells the user the route missed and offers the way home',
    })}
  >
    <Txt name={`${widgetId}:code`} class="error-page-code" fn="names the status so the failure is quotable">{code}</Txt>
    <Heading name={`${widgetId}:msg`} level={1} class="error-page-msg" fn="states what went wrong in one line">{msg}</Heading>
    <Txt name={`${widgetId}:hint`} class="error-page-hint" fn="reassures that no open work was lost">{hint}</Txt>
    <a
      class="error-page-home"
      href={homeHref}
      {...inspectAttrs(`${widgetId}:home`, {
        role: 'action',
        style: 'text link, accent colour',
        motion: 'none',
        fn: 'returns to the dashboard — the only action on a dead route',
      })}
    >
      {homeLabel}
    </a>
  </div>
);

export default UnknownNotice;
