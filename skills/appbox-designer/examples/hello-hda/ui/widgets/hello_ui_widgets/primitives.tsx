// primitives.tsx — the app's text + interaction vocabulary. Every visible
// string and every interactive element flows through one of these, so each
// resolves to its own data-el on inspect (the W7 law). hello-hda has ONE
// shell, so these live in a feature folder, not common/ — promotion to
// ui/widgets/common/<group>/ is earned by a second shell consumer, never
// by intent (showcase-anatomy.md §2).
import type { FC, Child } from 'hono/jsx';

// inspectAttrs — the ONE source of widget inspect identity. Every library
// widget spreads this on its root element; views never hand-write
// data-inspect-* again.
export function inspectAttrs(
  name: string,
  meta: { role: string; style?: string },
): Record<string, string> {
  const attributes: Record<string, string> = {
    'data-el': name,
    'data-inspect-role': meta.role,
  };
  if (meta.style) attributes['data-inspect-style'] = meta.style;
  return attributes;
}

interface TextProps {
  name?: string;
  class?: string;
  id?: string;
  children?: Child;
}

// Label — inline text (chips, values, button captions).
export const Label: FC<TextProps> = (props) => (
  <span data-arxa-id="ui-widgets-hello_ui_widgets-primitives-e1"
    class={props.class}
    id={props.id}
    {...inspectAttrs(props.name ?? 'label', { role: 'label', style: 'text · label' })}
  >
    {props.children}
  </span>
);

// Heading — a heading level with widget identity.
export const Heading: FC<TextProps & { level?: 1 | 2 }> = (props) => {
  const Tag = `h${props.level ?? 2}` as 'h2';
  return (
    <Tag
      class={props.class}
      id={props.id}
      {...inspectAttrs(props.name ?? 'heading', { role: 'heading', style: 'text · heading' })}
    >
      {props.children}
    </Tag>
  );
};

// Txt — a body paragraph.
export const Txt: FC<TextProps> = (props) => (
  <p data-arxa-id="ui-widgets-hello_ui_widgets-primitives-e2"
    class={props.class}
    id={props.id}
    {...inspectAttrs(props.name ?? 'text', { role: 'text', style: 'text · body' })}
  >
    {props.children}
  </p>
);

// ActionButton — the ONLY button in the app that is not a widget-library
// internal. Carries the htmx wiring the caller needs (post/target/swap);
// the caption is a child, so translated or literal text both render.
export interface ActionButtonProps {
  name?: string;
  class?: string;
  type?: 'submit' | 'button';
  hxPost?: string;
  hxTarget?: string;
  hxSwap?: string;
  disabled?: boolean;
  children?: Child;
  [key: string]: unknown;
}

export const ActionButton: FC<ActionButtonProps> = (props) => (
  <button data-arxa-id="ui-widgets-hello_ui_widgets-primitives-e3"
    class={props.class ?? 'btn'}
    type={props.type ?? 'button'}
    hx-post={props.hxPost}
    hx-target={props.hxTarget}
    hx-swap={props.hxSwap}
    disabled={props.disabled}
    {...inspectAttrs(props.name ?? 'action', { role: 'button', style: 'action · primary' })}
  >
    {props.children}
  </button>
);

// CtaLink — navigational call-to-action anchor with widget identity. An <a>
// is interactive, so bare anchors in surfaces always trip W7; route every
// navigation CTA through here. Children carry the caption (and any glyphs).
export interface CtaLinkProps {
  name?: string;
  class?: string;
  href: string;
  children?: Child;
}

export const CtaLink: FC<CtaLinkProps> = (props) => (
  <a data-arxa-id="ui-widgets-hello_ui_widgets-primitives-e4"
    class={props.class ?? 'btn'}
    href={props.href}
    {...inspectAttrs(props.name ?? 'cta', { role: 'link', style: 'action · link' })}
  >
    {props.children}
  </a>
);
