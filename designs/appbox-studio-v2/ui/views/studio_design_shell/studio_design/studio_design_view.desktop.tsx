/// This is the user interface for studio_design at the expanded rung.
///
/// Role: the design studio at desktop width — the v1 canvas/inspector
/// layout restructured, not redesigned: activity rail on the left, the
/// device-tile canvas in the centre (all three rungs of the designed
/// app), the inspector panel on the right, needs-you chips over the
/// canvas, composer sheet pinned to the bottom.
///
/// Requirements:
/// 1. [Desktop/tablet/mobile for every studio view] — Q-v2-3
/// 2. [v1 canvas/inspector layout restructured, not redesigned] — VISUAL PARITY LAW
///
/// Relationships: mounted by studio_design_view.tsx; composes
/// widgets/design_canvas.tsx, inspector_panel.tsx, composer_slider_panel.tsx,
/// needs_you_strip.tsx, activity.tsx.
///
/// History: git log --follow -- ui/views/studio_design_shell/studio_design/studio_design_view.desktop.tsx

import type { FC } from 'hono/jsx';
import { DesignCanvas, InspectorPanel, ComposerSliderPanel, NeedsYouStrip, ActivityPanel } from '../../../widgets/studio_design_widgets/widgets.tsx';

export interface CanvasTile {
  id: string;
  surface: string;
  rung: 'desktop' | 'tablet' | 'mobile';
  width: number;
  src: string;
}

export interface InspectorField {
  id: string;
  label: string;
  value: string;
}

export interface InspectorTab {
  id: string;
  label: string;
  fields: InspectorField[];
}

export interface NeedsYouChip {
  id: string;
  label: string;
  detail: string;
}

export interface ActivityItem {
  id: string;
  time: string;
  actor: string;
  event: string;
}

export interface DesignProps {
  translate: (key: string, vars?: Record<string, unknown>) => unknown;
  title: string;
  tiles: CanvasTile[];
  canvasTitle: string;
  inspectorTitle: string;
  inspectorTabs: InspectorTab[];
  composerTitle: string;
  composerPlaceholder: string;
  composerSend: string;
  zoomLabel: string;
  gridLabel: string;
  needsYouLabel: string;
  chips: NeedsYouChip[];
  activityTitle: string;
  activity: ActivityItem[];
  locale?: string;
  activeShell: string;
  [key: string]: unknown;
}

const StudioDesignViewDesktop: FC<DesignProps> = (props) => (
  <main
    class="design-stage design-stage--desktop"
    data-inspect-surface="studio_design"
    data-inspect-role="section"
    data-inspect-style="v1 three-region studio: activity | canvas | inspector, sheet pinned below"
    data-inspect-fn="hosts the canvas where the designed app is inspected and composed"
    data-inspect-motion="reveal"
  >
    <h1
      class="display sr-only"
      data-inspect-role="heading"
      data-inspect-style="screen-reader heading — the canvas is the visual title"
      data-inspect-fn="names the stage for assistive tech"
      data-inspect-motion="none"
    >
      {props.title}
    </h1>
    <ActivityPanel title={props.activityTitle} items={props.activity} />
    <section class="design-center">
      <NeedsYouStrip label={props.needsYouLabel} chips={props.chips} />
      <DesignCanvas title={props.canvasTitle} tiles={props.tiles} />
      <ComposerSliderPanel
        title={props.composerTitle}
        placeholder={props.composerPlaceholder}
        sendLabel={props.composerSend}
        zoomLabel={props.zoomLabel}
        gridLabel={props.gridLabel}
      />
    </section>
    <InspectorPanel title={props.inspectorTitle} tabs={props.inspectorTabs} />
  </main>
);

export default StudioDesignViewDesktop;
