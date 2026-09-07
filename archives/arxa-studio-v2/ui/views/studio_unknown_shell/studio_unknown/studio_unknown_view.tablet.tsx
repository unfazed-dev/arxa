// Role: unknown surface at the medium rung. Same column, narrowed measure —
//   the hint wraps to two lines rather than stretching thin across 744.
// Requirements: Q-v2-3, Q-v2-5.
// Relationships: mounted by studio_unknown_view.tsx; composes
//   widgets/unknown_notice.tsx.
// History: created for studio v2; v1 error-page port.
import type { FC } from 'hono/jsx';
import { UnknownNotice } from '../../../widgets/studio_unknown_widgets/widgets.tsx';
import type { UnknownProps } from './studio_unknown_view.desktop.tsx';

const StudioUnknownViewTablet: FC<UnknownProps> = (props) => (
  <section
    class="error-frame error-frame--medium"
    data-inspect-surface="studio_unknown"
    data-inspect-role="section"
    data-inspect-style="v1 error page: centred column, narrowed measure"
    data-inspect-fn="frames the 404 notice on a dead route"
    data-inspect-motion="none"
  >
    <UnknownNotice {...props} />
  </section>
);

export default StudioUnknownViewTablet;
