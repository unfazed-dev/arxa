// home_view.mobile.tsx — the home body at the mobile rung.
// Same single-column composition; the shell's bottom tabbar (CSS) is the only
// rung difference this surface has.
// Requirements: viewport-ladder.md — every stated view carries all three
// factor variants; identical composition across rungs is a stated decision.
import type { FC } from 'hono/jsx';
import { HomeBody } from '../../../widgets/hello_home_widgets/widgets.tsx';
import type { HomeBodyProps } from '../../../widgets/hello_home_widgets/widgets.tsx';

const HomeMobile: FC<HomeBodyProps> = (props) => (
  <HomeBody {...props} rung="mobile" />
);

export default HomeMobile;
