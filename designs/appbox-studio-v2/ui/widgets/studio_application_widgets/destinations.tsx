// destinations.tsx — the hub's shell destinations, shared by the hub widgets
// (header / tabbar / rail). Rebuilt per call (not hoisted to module scope)
// so translate() resolves against the current request's locale, never a frozen one.

export type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

export interface Prefs {
  theme?: string;
  [key: string]: unknown;
}

export interface Project {
  name?: string;
  savedLabel?: string;
}

export interface Destination {
  id: string;
  label: string;
  icon: string;
  href: string;
}

export function destinations(translate: TFn): Destination[] {
  return [
    { id: 'intake',    label: translate('tab.intake')   as string, icon: 'square-pen', href: '/intake' },
    { id: 'design',    label: translate('tab.design')   as string, icon: 'pen-tool',   href: '/design' },
    { id: 'scaffold',  label: translate('tab.scaffold') as string, icon: 'blocks',     href: '/scaffold' },
    { id: 'build',     label: translate('tab.build')    as string, icon: 'hammer',     href: '/build' },
    { id: 'workspace', label: translate('tab.settings') as string, icon: 'settings',   href: '/workspace' },
  ];
}
