// destinations.tsx — the hub's shell destinations, shared by the hub widgets
// (header / tabbar / rail). Registry-driven: exactly the shells whose
// registry entries carry a `tab` — the tabbed stages of the pipeline board
// (dashboard 1, intake 2, design 3). Unlanded stages are disabled cards in
// the dashboard registry, never dead nav links (the /scaffold /build
// /workspace hrefs this file once hard-coded were removed with that ruling,
// 2026-08-16). Rebuilt per call (not hoisted to module scope) so translate()
// resolves against the current request's locale, never a frozen one.

export type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

export interface Destination {
  id: string;
  label: string;
  icon: string;
  href: string;
}

/** The tabbed stage roster, in tab order. Mirrors the `tab` fields of
 *  models/screens_model/registry.json — keep the two in step when a stage
 *  shell lands or retires. */
export function destinations(translate: TFn): Destination[] {
  return [
    { id: 'dashboard', label: translate('tab.dashboard') as string, icon: 'layout-dashboard', href: '/' },
    { id: 'intake',    label: translate('tab.intake')   as string, icon: 'square-pen',     href: '/intake' },
    { id: 'design',    label: translate('tab.design')   as string, icon: 'pen-tool',      href: '/design' },
  ];
}
