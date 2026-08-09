// footer_panel.tsx — the shell's footer panel (replaces footer_panel.html).
// A thin instantiation of _panel (role: footer): a body-only strip. The body
// (e.g. the timeline <ol>) is the caller's content, passed as children.
import type { Child } from 'hono/jsx';
import { Open as PanelOpen } from './_panel.tsx';

const PID = 'panel-footer';

interface FooterPanelSpec {
  // element to emit (default 'footer'; 'ol' for the timeline list body)
  tag?: string;
  // body element (default 'div'); the timeline body is an <ol>
  bodyTag?: string;
  // modifier alongside 'panel-body' (e.g. 'timeline')
  bodyClass?: string;
  // replaces the derived body id (the timeline's oob target)
  bodyId?: string;
  // raw attributes on the body (aria-label, hx-swap-oob, ...)
  bodyAttributes?: string;
  class?: string;
  attributes?: string;
  vt?: string;
  children?: Child;
}

// Opens the footer panel: all four edge sections forced off (body-only).
export function Open(spec: FooterPanelSpec) {
  return (
    <PanelOpen
      role="footer"
      id={PID}
      tag={spec.tag ?? 'footer'}
      class={spec.class}
      attributes={spec.attributes}
      vt={spec.vt}
      bodyTag={spec.bodyTag}
      bodyClass={spec.bodyClass}
      bodyId={spec.bodyId}
      bodyAttributes={spec.bodyAttributes}
      top={false}
      sideStart={false}
      sideEnd={false}
      bottom={false}
    >
      {spec.children}
    </PanelOpen>
  );
}

// Close is implicit in JSX — the wrapper's closing tag ends the panel.
export function Close() {
  return null;
}

export { Open as default };
