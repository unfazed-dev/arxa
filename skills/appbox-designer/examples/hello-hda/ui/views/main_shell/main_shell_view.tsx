// main_shell.tsx — shell layout component (replaces main_shell_view.html).
// Wraps Base + composes NavRail, LangSwitcher, BottomNav around the surface.
import type { FC, Child } from 'hono/jsx';
import Base from '../../common/base.tsx';
import NavRail from './shared/widgets/nav_rail.tsx';
import LangSwitcher from './shared/widgets/lang_switcher.tsx';
import BottomNav from './shared/widgets/bottom_nav.tsx';

interface NavItem {
  id: string;
  label: string;
  icon?: string;
  href: string;
  current?: boolean;
}

interface MainShellProps {
  title?: string;
  locale?: string;
  accent?: string;
  locales: string[];
  t: (key: string, vars?: Record<string, unknown>) => unknown;
  rail?: { brand?: string; drawer?: boolean; items: NavItem[] };
  rail_drawer?: { brand?: string; drawer?: boolean; items: NavItem[] };
  children?: Child;
}

const MainShell: FC<MainShellProps> = ({
  title,
  locale,
  accent,
  locales,
  t,
  rail,
  children,
}) => (
  <Base title={title} locale={locale} accent={accent}>
    <div class="shell">
      <NavRail rail={rail} />
      <div class="shell__col">
        <LangSwitcher locales={locales} locale={locale ?? 'en'} t={t as (key: string) => string} />
        <main class="shell-main">{children}</main>
        <BottomNav rail={rail} />
      </div>
    </div>
  </Base>
);

export default MainShell;
