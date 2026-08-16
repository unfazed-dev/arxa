// widgets.tsx — barrel for studio_design_widgets; external consumers import from here.
export { default as DesignCanvas, type DesignCanvasProps, type CanvasTile } from './design_canvas.tsx';
export { default as InspectorPanel, type InspectorPanelProps, type InspectorTab, type InspectorField } from './inspector_panel.tsx';
export { default as ComposerSliderPanel, type ComposerSliderPanelProps } from './composer_slider_panel.tsx';
export { default as NeedsYouStrip, type NeedsYouStripProps, type NeedsYouChip } from './needs_you_strip.tsx';
export { default as ActivityPanel, type ActivityPanelProps, type ActivityItem } from './activity.tsx';
