// home_view.tablet.tsx — the home body at the tablet rung.
// Same single-column composition as desktop/mobile; app.css widens the card.
// Requirements: viewport-ladder.md — every stated view carries all three
// factor variants; identical composition across rungs is a stated decision.
import type { FC } from 'hono/jsx';
import { HomeBody } from './home_view.sections.tsx';
import type { HomeBodyProps } from './home_view.sections.tsx';

const HomeTablet: FC<HomeBodyProps> = (props) => (
  <HomeBody {...props} rung="tablet" />
);

export default HomeTablet;
