// home_view.tablet.tsx — the home body at the tablet rung.
// Same single-column composition as desktop/mobile; app.css widens the card.
// Requirements: viewport-ladder.md — every stated view carries all three
// factor variants; identical composition across rungs is a stated decision.
import type { FC } from 'hono/jsx';
import { HomeBody } from '../../../widgets/hello_home_widgets/widgets.tsx';
import type { HomeBodyProps } from '../../../widgets/hello_home_widgets/widgets.tsx';

const HomeTablet: FC<HomeBodyProps> = (props) => (
  <HomeBody {...props} rung="tablet" />
);

export default HomeTablet;
