/// This is the user interface for studio_design at the compact rung.
///
/// Role: the design studio at mobile width — the canvas shows the
/// designed app's mobile rung only (registry note); the inspector and
/// needs-you chips collapse into disclosures; the composer sheet is the
/// pinned bottom of the scroll.
///
/// Requirements:
/// 1. [Desktop/tablet/mobile for every studio view] — Q-v2-3
/// 2. [Mobile canvas shows mobile only] — registry design_canvas note
///
/// Relationships: mounted by studio_design_view.tsx; composes the same
/// widgets as the desktop variant, folded.
///
/// History: git log --follow -- ui/views/studio_design_shell/studio_design/studio_design_view.mobile.tsx

import type { FC } from 'hono/jsx';
import { DesignCanvas, InspectorPanel, ComposerSliderPanel, NeedsYouStrip } from '../../../widgets/studio_design_widgets/widgets.tsx';
import type { DesignProps } from './studio_design_view.desktop.tsx';

const StudioDesignViewMobile: FC<DesignProps> = (props) => (
  <main
    class="design-stage design-stage--mobile"
    data-inspect-surface="studio_design"
    data-inspect-role="section"
    data-inspect-style="single column: chips disclosure, mobile-only canvas, folded inspector, pinned sheet"
    data-inspect-fn="hosts the canvas where the designed app is inspected and composed"
    data-inspect-motion="reveal"
  >
    <h1 class="display sr-only" data-inspect-role="heading" data-inspect-style="screen-reader heading" data-inspect-fn="names the stage for assistive tech" data-inspect-motion="none">
      {props.title}
    </h1>
    <details class="design-chips-details">
      <summary>{props.needsYouLabel}</summary>
      <NeedsYouStrip label={props.needsYouLabel} chips={props.chips} stacked />
    </details>
    <DesignCanvas title={props.canvasTitle} tiles={props.tiles.filter((tile) => tile.rung === 'mobile')} />
    <InspectorPanel title={props.inspectorTitle} tabs={props.inspectorTabs} folded />
    <ComposerSliderPanel
      title={props.composerTitle}
      placeholder={props.composerPlaceholder}
      sendLabel={props.composerSend}
      zoomLabel={props.zoomLabel}
      gridLabel={props.gridLabel}
    />
  </main>
);

export default StudioDesignViewMobile;
