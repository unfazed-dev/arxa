// home_view.desktop.tsx — the home body at the desktop rung.
// Single column at expanded width too — the list card simply gets more room; no
// TSX-level divergence from tablet/mobile.
// Requirements: viewport-ladder.md — every stated view carries all three
// factor variants; identical composition across rungs is a stated decision.
import type { FC } from 'hono/jsx';
import { HomeBody } from '../../../widgets/hello_home_widgets/widgets.tsx';
import type { HomeBodyProps } from '../../../widgets/hello_home_widgets/widgets.tsx';

const HomeDesktop: FC<HomeBodyProps> = (props) => (
  <HomeBody {...props} rung="desktop" />
);

export default HomeDesktop;
