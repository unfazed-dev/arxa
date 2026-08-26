// home_blocks.tsx — the home body's structural containers: ListSection and
// ListCard (the greetings list), CtaLine (a standalone call-to-action line),
// Swatch (the accent color chip) and HxForm (an htmx form container). The
// markup lives here so the sections file composes invocations only (W9).
import type { FC, Child } from 'hono/jsx';

export interface ListSectionProps {
  children?: Child;
}

export const ListSection: FC<ListSectionProps> = ({ children }) => (
  <section data-arxa-id="ui-widgets-hello_home_widgets-home_blocks-e1" class="list-section">{children}</section>
);

export interface ListCardProps {
  children?: Child;
}

export const ListCard: FC<ListCardProps> = ({ children }) => (
  <div data-arxa-id="ui-widgets-hello_home_widgets-home_blocks-e2" class="list-section__card">{children}</div>
);

export interface CtaLineProps {
  children?: Child;
}

export const CtaLine: FC<CtaLineProps> = ({ children }) => <p data-arxa-id="ui-widgets-hello_home_widgets-home_blocks-e3">{children}</p>;

export const Swatch: FC = () => <span data-arxa-id="ui-widgets-hello_home_widgets-home_blocks-e4" class="swatch"></span>;

export interface HxFormProps {
  post: string;
  swap?: string;
  children?: Child;
}

export const HxForm: FC<HxFormProps> = ({ post, swap = 'none', children }) => (
  <form data-arxa-id="ui-widgets-hello_home_widgets-home_blocks-e5" hx-post={post} hx-swap={swap}>{children}</form>
);
