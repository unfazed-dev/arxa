/// This is the user interface for studio_design at the medium rung.
///
/// Role: the design studio at tablet width — the activity rail drops;
/// the canvas shows tablet+mobile of the designed app (registry note),
/// the inspector folds under the canvas, the sheet stays pinned.
///
/// Requirements:
/// 1. [Desktop/tablet/mobile for every studio view] — Q-v2-3
/// 2. [Tablet canvas shows tablet+mobile of designed app] — registry design_canvas note
///
/// Relationships: mounted by studio_design_view.tsx; composes the same
/// five widgets as the desktop variant.
///
/// History: git log --follow -- ui/views/studio_design_shell/studio_design/studio_design_view.tablet.tsx

import type { FC } from 'hono/jsx';
import { DesignCanvas, InspectorPanel, ComposerSliderPanel, NeedsYouStrip } from '../../../widgets/studio_design_widgets/widgets.tsx';
import type { DesignProps } from './studio_design_view.desktop.tsx';

const StudioDesignViewTablet: FC<DesignProps> = (props) => (
  <main
    class="design-stage design-stage--tablet"
    data-inspect-surface="studio_design"
    data-inspect-role="section"
    data-inspect-style="canvas over folded inspector, no activity rail"
    data-inspect-fn="hosts the canvas where the designed app is inspected and composed"
    data-inspect-motion="reveal"
  >
    <h1 class="display sr-only" data-inspect-role="heading" data-inspect-style="screen-reader heading" data-inspect-fn="names the stage for assistive tech" data-inspect-motion="none">
      {props.title}
    </h1>
    <NeedsYouStrip label={props.needsYouLabel} chips={props.chips} />
    <DesignCanvas title={props.canvasTitle} tiles={props.tiles.filter((tile) => tile.rung !== 'desktop')} />
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

export default StudioDesignViewTablet;
