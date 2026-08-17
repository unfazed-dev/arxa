// home_blocks.tsx — the home body's structural containers: ListSection and
// ListCard (the greetings list), CtaLine (a standalone call-to-action line),
// Swatch (the accent color chip) and HxForm (an htmx form container). The
// markup lives here so the sections file composes invocations only (W9).
import type { FC, Child } from 'hono/jsx';

export interface ListSectionProps {
  children?: Child;
}

export const ListSection: FC<ListSectionProps> = ({ children }) => (
  <section class="list-section">{children}</section>
);

export interface ListCardProps {
  children?: Child;
}

export const ListCard: FC<ListCardProps> = ({ children }) => (
  <div class="list-section__card">{children}</div>
);

export interface CtaLineProps {
  children?: Child;
}

export const CtaLine: FC<CtaLineProps> = ({ children }) => <p>{children}</p>;

export const Swatch: FC = () => <span class="swatch"></span>;

export interface HxFormProps {
  post: string;
  swap?: string;
  children?: Child;
}

export const HxForm: FC<HxFormProps> = ({ post, swap = 'none', children }) => (
  <form hx-post={post} hx-swap={swap}>{children}</form>
);
