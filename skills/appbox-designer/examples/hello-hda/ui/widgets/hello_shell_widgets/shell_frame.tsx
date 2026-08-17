// shell_frame.tsx — the shell's frame containers: ShellFrame (the shell
// root), ShellColumn (the content column beside the nav rail) and ShellMain
// (the hosted surface's outlet). Frame markup is chrome, and chrome lives in
// the library — the shell's factor variants compose these (W9).
import type { FC, Child } from 'hono/jsx';

export interface ShellFrameProps {
  children?: Child;
}

export const ShellFrame: FC<ShellFrameProps> = ({ children }) => (
  <div class="shell">{children}</div>
);

export interface ShellColumnProps {
  children?: Child;
}

export const ShellColumn: FC<ShellColumnProps> = ({ children }) => (
  <div class="shell__col">{children}</div>
);

export interface ShellMainProps {
  children?: Child;
}

export const ShellMain: FC<ShellMainProps> = ({ children }) => (
  <main class="shell-main">{children}</main>
);
