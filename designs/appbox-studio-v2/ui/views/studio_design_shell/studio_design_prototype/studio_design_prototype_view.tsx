// prototype_view.tsx — design.prototype, the artboard surface (replaces prototype_view.html).
// Three panels: activity LEFT, artboards in the main panel, composer RIGHT.
// Composition-only: this file owns no chrome of its own — it composes the shared
// design panels and delegates viewer/inspector/widget-editor fragments.
import type { FC } from 'hono/jsx';
import { Fragment } from 'hono/jsx';
import StudioDesignShellView from '../studio_design_shell_view.tsx';
import {
  Panels,
  FileView,
  RunBar,
  ScreenList,
  ActivityPanel,
  ActivitySwap as SharedActivitySwap,
  type DesignCtx,
} from '../design_shared.tsx';
import { DesignViewer, RevealDrawer } from '../../../widgets/studio_design_widgets/widgets.tsx';
import { Pane as WidgetEditorPane } from '../../../widgets/studio_design_widgets/widgets.tsx';
import { Pane as InspectorPaneComp } from '../inspector_pane.tsx';
import { ActivityPanelTop as ActivityTop, ActivityPanelBottom as ActivityBottom } from '../../../widgets/common/studio_panels/widgets.tsx';
import { Timeline as TimelineEl } from '../../../widgets/common/studio_panels/widgets.tsx';
import { inspectAttrs } from '../../../widgets/common/studio_primitives/widgets.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

export interface PrototypeViewProps extends DesignCtx {
  translate: TFn;
  locale?: string;
  locales?: string[];
  prefs?: { accent?: string; [key: string]: unknown };
  activeShell?: string;
  timeline?: { items: unknown[]; currentId: string };
  viewer?: Record<string, unknown>;
  counts?: { screens?: number; shots?: number };
  run?: { state?: string; number?: number; brief?: string; stateLabel?: string; rungsLabel?: string };
  drawerScreen?: string;
}

// ---- timeline ----
function renderTimeline(context: PrototypeViewProps, oob: boolean, translate: TFn) {
  return <TimelineEl timeline={context.timeline as any} oob={oob} label={translate('design.timelineLabel') as string} translate={translate} />;
}

// ---- the viewer (chrome defined HERE — title + run state only) ----
function StageViewer({ context, translate }: { context: PrototypeViewProps; translate: TFn }) {
  return (
    <DesignViewer
      v={context.viewer as any}
      chrome={{
        title: translate('design.artboardsEyebrow', { count: context.counts?.screens }) as string,
        state: context.run?.state,
      }}
      translate={translate}
    />
  );
}

function CanvasBoard({ context, translate }: { context: PrototypeViewProps; translate: TFn }) {
  return (
    <section class="mp-content" id="mp-content" aria-live="polite">
      <article class="artifact screen-artifact evidence-artifact" {...inspectAttrs('design-prototype:artboard', { role: 'group' })}>
        {StageViewer({ context, translate })}
      </article>
    </section>
  );
}

// ---- main content: open file, else the artboards ----
function MainContent({ context, translate }: { context: PrototypeViewProps; translate: TFn }) {
  if (context.fileView) return <FileView context={context} translate={translate} />;
  return CanvasBoard({ context, translate });
}

// ---- panels (the whole panels block, one swap unit) ----
export function RenderPanels(context: PrototypeViewProps) {
  return <Panels context={context} translate={context.translate}>{MainContent({ context, translate: context.translate })}</Panels>;
}

// ---- Fragment responses ----
export function PanelsSwap(context: PrototypeViewProps) {
  return RenderPanels(context);
}

export function ActivitySwap(context: PrototypeViewProps) {
  return <SharedActivitySwap context={context} translate={context.translate} />;
}

export function InspectorPane(context: PrototypeViewProps) {
  return <InspectorPaneComp context={context as any} translate={context.translate} />;
}

export function WidgetEditor(context: PrototypeViewProps) {
  return <WidgetEditorPane {...(context as any)} translate={context.translate} />;
}

export function InspectorSwap(context: PrototypeViewProps) {
  const spec = {
    label: context.activityLabel ?? '',
    views: context.activityViews ?? [],
    size: context.panelSize,
    sizeHref: context.panelSizeHref,
  };
  return (
    <Fragment>
      <InspectorPaneComp context={context as any} translate={context.translate} />
      <ActivityTop spec={spec} oob={true} />
      <ActivityBottom spec={spec} oob={true} translate={context.translate} />
    </Fragment>
  );
}

export function ActivityFrameSwap(context: PrototypeViewProps) {
  return <ActivityPanel context={context} translate={context.translate} />;
}

export function ViewerSwap(context: PrototypeViewProps) {
  return StageViewer({ context, translate: context.translate });
}

export function DrawerSwap(context: PrototypeViewProps) {
  const viewer = context.viewer as any;
  if (!viewer?.drawers) return null;
  return (
    <Fragment>
      {(viewer.screens ?? []).filter((screen: any) => screen.id === context.drawerScreen).map((screen: any) => (
        <RevealDrawer key={screen.id} v={viewer} s={screen} translate={context.translate} />
      ))}
    </Fragment>
  );
}

export function FileSwap(context: PrototypeViewProps) {
  return MainContent({ context, translate: context.translate });
}

export function FilterSwap(context: PrototypeViewProps) {
  return (
    <Fragment>
      <ScreenList context={context} translate={context.translate} />
      <RunBar context={context} oob={true} translate={context.translate} />
    </Fragment>
  );
}

// ---- Page ----
const PrototypeView: FC<PrototypeViewProps> = (props) => (
  <StudioDesignShellView
    title={props.translate('design.pageTitle') as string}
    locale={props.locale}
    activeShell={props.activeShell ?? 'design'}
    prefs={props.prefs as { accent?: string; [key: string]: unknown }}
    project={props.project as { name?: string; savedLabel?: string }}
    mainClass="shell-main-loop"
    footer={renderTimeline(props, false, props.translate)}
    surface={RenderPanels(props)}
    translate={props.translate}
  />
);

export default PrototypeView;
