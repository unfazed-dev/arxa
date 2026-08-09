// prototype_view.tsx — design.prototype, the artboard surface (replaces prototype_view.html).
// Three panels: activity LEFT, artboards in the main panel, composer RIGHT.
// Composition-only: this file owns no chrome of its own — it composes the shared
// design panels and delegates viewer/inspector/widget-editor fragments.
import type { FC } from 'hono/jsx';
import { Fragment } from 'hono/jsx';
import MainShellView from '../../main_shell_view.tsx';
import {
  Panels,
  FileView,
  RunBar,
  ScreenList,
  ActivityPanel,
  ActivitySwap as SharedActivitySwap,
  type DesignCtx,
} from '../_shared.tsx';
import { DesignViewer, RevealDrawer } from '../../shared/widgets/design_viewer.tsx';
import { Pane as WidgetEditorPane } from '../../shared/widgets/widget_editor.tsx';
import { Pane as InspectorPaneComp } from '../inspector_pane.tsx';
import { Top as ActivityTop, Bottom as ActivityBottom } from '../../shared/widgets/activity_panel.tsx';
import { Timeline as TimelineEl } from '../../shared/widgets/timeline.tsx';
import { inspectAttrs } from '../../../../common/widgets/primitives.tsx';

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
function renderTimeline(c: PrototypeViewProps, oob: boolean, translate: TFn) {
  return <TimelineEl timeline={c.timeline as any} oob={oob} label={translate('design.timelineLabel') as string} translate={translate} />;
}

// ---- the viewer (chrome defined HERE — title + run state only) ----
function StageViewer({ c, translate }: { c: PrototypeViewProps; translate: TFn }) {
  return (
    <DesignViewer
      v={c.viewer as any}
      chrome={{
        title: translate('design.artboardsEyebrow', { count: c.counts?.screens }) as string,
        state: c.run?.state,
      }}
      translate={translate}
    />
  );
}

function CanvasBoard({ c, translate }: { c: PrototypeViewProps; translate: TFn }) {
  return (
    <section class="mp-content" id="mp-content" aria-live="polite">
      <article class="artifact screen-artifact evidence-artifact" {...inspectAttrs('design-prototype:artboard', { role: 'group' })}>
        {StageViewer({ c, translate })}
      </article>
    </section>
  );
}

// ---- main content: open file, else the artboards ----
function MainContent({ c, translate }: { c: PrototypeViewProps; translate: TFn }) {
  if (c.fileView) return <FileView c={c} translate={translate} />;
  return CanvasBoard({ c, translate });
}

// ---- panels (the whole panels block, one swap unit) ----
export function RenderPanels(c: PrototypeViewProps) {
  return <Panels c={c} translate={c.translate}>{MainContent({ c, translate: c.translate })}</Panels>;
}

// ---- Fragment responses ----
export function PanelsSwap(c: PrototypeViewProps) {
  return RenderPanels(c);
}

export function ActivitySwap(c: PrototypeViewProps) {
  return <SharedActivitySwap c={c} translate={c.translate} />;
}

export function InspectorPane(c: PrototypeViewProps) {
  return <InspectorPaneComp c={c as any} translate={c.translate} />;
}

export function WidgetEditor(c: PrototypeViewProps) {
  return <WidgetEditorPane {...(c as any)} translate={c.translate} />;
}

export function InspectorSwap(c: PrototypeViewProps) {
  const spec = {
    label: c.activityLabel ?? '',
    views: c.activityViews ?? [],
    size: c.panelSize,
    sizeHref: c.panelSizeHref,
  };
  return (
    <Fragment>
      <InspectorPaneComp c={c as any} translate={c.translate} />
      <ActivityTop spec={spec} oob={true} />
      <ActivityBottom spec={spec} oob={true} translate={c.translate} />
    </Fragment>
  );
}

export function ActivityFrameSwap(c: PrototypeViewProps) {
  return <ActivityPanel c={c} translate={c.translate} />;
}

export function ViewerSwap(c: PrototypeViewProps) {
  return StageViewer({ c, translate: c.translate });
}

export function DrawerSwap(c: PrototypeViewProps) {
  const v = c.viewer as any;
  if (!v?.drawers) return null;
  return (
    <Fragment>
      {(v.screens ?? []).filter((s: any) => s.id === c.drawerScreen).map((s: any) => (
        <RevealDrawer key={s.id} v={v} s={s} translate={c.translate} />
      ))}
    </Fragment>
  );
}

export function FileSwap(c: PrototypeViewProps) {
  return MainContent({ c, translate: c.translate });
}

export function FilterSwap(c: PrototypeViewProps) {
  return (
    <Fragment>
      <ScreenList c={c} translate={c.translate} />
      <RunBar c={c} oob={true} translate={c.translate} />
    </Fragment>
  );
}

// ---- Page ----
const PrototypeView: FC<PrototypeViewProps> = (props) => (
  <MainShellView
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
