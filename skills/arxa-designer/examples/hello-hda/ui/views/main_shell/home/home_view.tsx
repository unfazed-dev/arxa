// home_view.tsx — home page (replaces home_view.html).
// Default export HomePage: wraps MainShell and mounts the three DERIVED
// factor variants through the library's Ladder — the ladder CSS shows
// exactly one.
import type { FC } from 'hono/jsx';
import MainShell from '../main_shell_view.tsx';
import { Ladder } from '../../../widgets/hello_shell_widgets/widgets.tsx';
import Desktop from './home_view.desktop.tsx';
import Tablet from './home_view.tablet.tsx';
import Mobile from './home_view.mobile.tsx';

type TranslateFn = (key: string, vars?: Record<string, unknown>) => unknown;

interface NavItem {
  id: string;
  label: string;
  icon?: string;
  href: string;
  current?: boolean;
}

interface ListRowData {
  id: string;
  title: string;
  subtitle?: string;
  detail?: string;
  icon?: string;
  href?: string;
  chevron?: boolean;
  oob?: boolean;
}

interface HomePageProps {
  locale?: string;
  locales?: string[];
  translate: TranslateFn;
  rail?: unknown;
  rows?: ListRowData[];
  demoCount?: number;
  prefs?: { accent?: string; [key: string]: unknown };
  [key: string]: unknown;
}

const HomePage: FC<HomePageProps> = ({ translate, locale, locales = [], rail, rows, demoCount, prefs }) => (
  <MainShell
    title={translate('home.pageTitle') as string}
    locale={locale}
    locales={locales}
    translate={translate}
    rail={rail as { brand?: string; drawer?: boolean; items: NavItem[] }}
  >
    <Ladder
      desktop={<Desktop translate={translate} rows={rows} demoCount={demoCount} accent={prefs?.accent} rung="desktop" />}
      tablet={<Tablet translate={translate} rows={rows} demoCount={demoCount} accent={prefs?.accent} rung="tablet" />}
      mobile={<Mobile translate={translate} rows={rows} demoCount={demoCount} accent={prefs?.accent} rung="mobile" />}
    />
  </MainShell>
);

export default HomePage;
