// widgets.tsx — barrel for studio_application_hub_widgets; external consumers import from here.
export { Header } from './header.tsx';
export { Rail } from './rail.tsx';
export { Tabbar } from './tabbar.tsx';
export { destinations, type TFn, type Preferences, type Project, type Destination } from './destinations.tsx';
export { default as HeaderPanel, Close as HeaderPanelClose } from './header_panel.tsx';
export { default as FooterPanel, Close as FooterPanelClose } from './footer_panel.tsx';
export { Panel, Top, Bottom, SideStart, SideEnd, BodyOob, TopOob, BottomOob, SideEndOob, Resize } from './panel.tsx';
