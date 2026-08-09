// header_panel.tsx — the shell's header panel (replaces header_panel.html).
// A thin instantiation of _panel (role: header): a body-only <nav> strip with
// no leading/trailing sections. The body is the hub header widget (studio_dashboard_widgets/header.tsx).
import type { Child } from 'hono/jsx';
import { Open as PanelOpen } from './_panel.tsx';

const PID = 'panel-header';

interface HeaderPanelSpec {
  class?: string;
  attributes?: string;
  vt?: string;
  children?: Child;
}

// Opens the header panel: a <nav>, all four edge sections forced off (body-only).
export function Open(spec: HeaderPanelSpec) {
  return (
    <PanelOpen
      role="header"
      id={PID}
      tag="nav"
      class={spec.class}
      attributes={spec.attributes}
      vt={spec.vt}
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
