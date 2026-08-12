// Role: unknown surface at the expanded rung. The v1 error page verbatim:
//   code over message over hint over home link, optically centred, wide
//   34rem measure — at this width the hint reads on one line.
// Requirements: Q-v2-3, Q-v2-5.
// Relationships: mounted by studio_unknown_view.tsx; composes
//   widgets/unknown_notice.tsx.
// History: created for studio v2; v1 error-page port
//   (designs/appbox-studio/assets/css/error_surface.css).
import type { FC } from 'hono/jsx';
import { UnknownNotice } from '../../../widgets/studio_unknown_widgets/widgets.tsx';

export interface UnknownProps {
  code: string;
  msg: string;
  hint: string;
  homeHref: string;
  homeLabel: string;
}

const StudioUnknownViewDesktop: FC<UnknownProps> = (props) => (
  <section
    class="error-frame error-frame--expanded"
    data-inspect-surface="studio_unknown"
    data-inspect-role="section"
    data-inspect-style="v1 error page: centred column, wide measure"
    data-inspect-fn="frames the 404 notice on a dead route"
    data-inspect-motion="none"
  >
    <UnknownNotice {...props} />
  </section>
);

export default StudioUnknownViewDesktop;
