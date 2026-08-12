// Role: unknown surface at the compact rung. Same notice, but the home link
//   becomes a full-width tap target (thumb reach) instead of an inline text
//   link — the one factor-genuine change this surface owns.
// Requirements: Q-v2-3, Q-v2-5.
// Relationships: mounted by studio_unknown_view.tsx; composes
//   widgets/unknown_notice.tsx.
// History: created for studio v2; v1 error-page port.
import type { FC } from 'hono/jsx';
import { UnknownNotice } from '../../../widgets/studio_unknown_widgets/widgets.tsx';
import type { UnknownProps } from './studio_unknown_view.desktop.tsx';

const StudioUnknownViewMobile: FC<UnknownProps> = (props) => (
  <section
    class="error-frame error-frame--compact"
    data-inspect-surface="studio_unknown"
    data-inspect-role="section"
    data-inspect-style="v1 error page: full-bleed column, block home link"
    data-inspect-fn="frames the 404 notice on a dead route"
    data-inspect-motion="none"
  >
    <UnknownNotice {...props} />
  </section>
);

export default StudioUnknownViewMobile;
