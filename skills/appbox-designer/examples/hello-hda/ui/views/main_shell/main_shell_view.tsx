// main_shell_view.tsx — shell layout component (replaces main_shell_view.html).
// Wraps Base and mounts the three DERIVED factor variants in rung divs — the
// ladder CSS shows exactly one at a time, so the hosted surface renders three
// times and only the visible copy is reachable. Per-rung divergence of the
// shell's frame lands in the variants, not here.
import type { FC, Child } from 'hono/jsx';
import Base from '../../common/base.tsx';
import Desktop from './main_shell_view.desktop.tsx';
import Tablet from './main_shell_view.tablet.tsx';
import Mobile from './main_shell_view.mobile.tsx';

export interface NavItem {
  id: string;
  label: string;
  icon?: string;
  href: string;
  current?: boolean;
}

export interface MainShellProps {
  title?: string;
  locale?: string;
  accent?: string;
  locales: string[];
  translate: (key: string, vars?: Record<string, unknown>) => unknown;
  rail?: { brand?: string; drawer?: boolean; items: NavItem[] };
  children?: Child;
}

const MainShell: FC<MainShellProps> = (props) => (
  <Base title={props.title} locale={props.locale} accent={props.accent}>
    <div class="shell">
      <div class="rung rung--desktop"><Desktop {...props} /></div>
      <div class="rung rung--tablet"><Tablet {...props} /></div>
      <div class="rung rung--mobile"><Mobile {...props} /></div>
    </div>
  </Base>
);

export default MainShell;
