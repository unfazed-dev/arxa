// main_shell_view.mobile.tsx — the shell frame at the mobile rung.
// Same frame at the compact rung — the bottom tabbar replaces the rail via
// app.css media queries, not via different markup here.
// Requirements: viewport-ladder.md — every stated view carries all three
// factor variants; a rung that renders the same composition as its sibling
// says so explicitly rather than leaving it ambiguous.
import type { FC } from 'hono/jsx';
import { NavRail, LangSwitcher, BottomNav } from '../../widgets/hello_shell_widgets/widgets.tsx';
import type { MainShellProps } from './main_shell_view.tsx';

const MainShellMobile: FC<MainShellProps> = ({
  locales,
  locale,
  translate,
  rail,
  children,
}) => (
  <>
    <NavRail rail={rail} />
    <div class="shell__col">
      <LangSwitcher locales={locales} locale={locale ?? 'en'} translate={translate as (key: string) => string} />
      <main class="shell-main">{children}</main>
      <BottomNav rail={rail} />
    </div>
  </>
);

export default MainShellMobile;
