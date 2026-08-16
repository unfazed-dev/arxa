// main_shell_view.desktop.tsx — the shell frame at the desktop rung.
// The rail is the primary nav at expanded widths and the bottom tabbar is
// hidden by the ladder CSS; the frame itself is identical across rungs here —
// app.css media queries swap chrome visibility, so this variant composes the
// same chrome and documents that decision.
// Requirements: viewport-ladder.md — every stated view carries all three
// factor variants; a rung that renders the same composition as its sibling
// says so explicitly rather than leaving it ambiguous.
import type { FC } from 'hono/jsx';
import { NavRail, LangSwitcher, BottomNav } from '../../widgets/hello_shell_widgets/widgets.tsx';
import type { MainShellProps } from './main_shell_view.tsx';

const MainShellDesktop: FC<MainShellProps> = ({
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

export default MainShellDesktop;
