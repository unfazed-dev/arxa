// widgets.tsx — barrel for studio_panels (the loop-shell panel family,
// ported from v1 ui/views/main_shell/shared/widgets + the v1 common panel
// base). Cross-shell by the two-tier law: the composer, activity, main and
// timeline panels are consumed by the intake and design shells alike.
// Explicit aliased re-exports only — panel.tsx and activity_panel.tsx both
// export Top/Bottom and export-* would silently drop the ambiguous names.
export { Panel, Top, Bottom, SideStart, SideEnd, BodyOob, TopOob, BottomOob, SideEndOob, Resize, Panel as Open } from './panel.tsx';
export { Open as MainPanelOpen, PanelBar, Empty, View as MainPanelView, RenderCode, RenderDoc, RenderImage, RenderSvg, RenderPdf, RenderVideo } from './main_panel.tsx';
export { default as MainPanel } from './main_panel.tsx';
export { Open as ComposerPanelOpen, Top as ComposerPanelTop, HeadContent as ComposerHeadContent } from './composer_panel.tsx';
export { Field as ComposerField } from './composer.tsx';
export { Open as ActivityPanelOpen, Top as ActivityPanelTop, Bottom as ActivityPanelBottom, Label as ActivityPanelLabel, Views as ActivityPanelViews } from './activity_panel.tsx';
export { Timeline, Items as TimelineItems } from './timeline.tsx';
export { ControllerPanel, MiniPanel } from './mini_panel.tsx';
