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

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

export interface PrototypeViewProps extends DesignCtx {
  t: TFn;
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
function renderTimeline(c: PrototypeViewProps, oob: boolean, t: TFn) {
  return <TimelineEl timeline={c.timeline as any} oob={oob} label={t('design.timelineLabel') as string} t={t} />;
}

// ---- the viewer (chrome defined HERE — title + run state only) ----
function StageViewer({ c, t }: { c: PrototypeViewProps; t: TFn }) {
  return (
    <DesignViewer
      v={c.viewer as any}
      chrome={{
        title: t('design.artboardsEyebrow', { count: c.counts?.screens }) as string,
        state: c.run?.state,
      }}
      t={t}
    />
  );
}

function CanvasBoard({ c, t }: { c: PrototypeViewProps; t: TFn }) {
  return (
    <section class="mp-content" id="mp-content" aria-live="polite">
      <article class="artifact screen-artifact evidence-artifact">
        {StageViewer({ c, t })}
      </article>
    </section>
  );
}

// ---- main content: open file, else the artboards ----
function MainContent({ c, t }: { c: PrototypeViewProps; t: TFn }) {
  if (c.fileView) return <FileView c={c} t={t} />;
  return CanvasBoard({ c, t });
}

// ---- panels (the whole panels block, one swap unit) ----
export function RenderPanels(c: PrototypeViewProps) {
  return <Panels c={c} t={c.t}>{MainContent({ c, t: c.t })}</Panels>;
}

// ---- Fragment responses ----
export function PanelsSwap(c: PrototypeViewProps) {
  return RenderPanels(c);
}

export function ActivitySwap(c: PrototypeViewProps) {
  return <SharedActivitySwap c={c} t={c.t} />;
}

export function InspectorPane(c: PrototypeViewProps) {
  return <InspectorPaneComp c={c as any} t={c.t} />;
}

export function WidgetEditor(c: PrototypeViewProps) {
  return <WidgetEditorPane {...(c as any)} t={c.t} />;
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
      <InspectorPaneComp c={c as any} t={c.t} />
      <ActivityTop spec={spec} oob={true} />
      <ActivityBottom spec={spec} oob={true} t={c.t} />
    </Fragment>
  );
}

export function ActivityFrameSwap(c: PrototypeViewProps) {
  return <ActivityPanel c={c} t={c.t} />;
}

export function ViewerSwap(c: PrototypeViewProps) {
  return StageViewer({ c, t: c.t });
}

export function DrawerSwap(c: PrototypeViewProps) {
  const v = c.viewer as any;
  if (!v?.drawers) return null;
  return (
    <Fragment>
      {(v.screens ?? []).filter((s: any) => s.id === c.drawerScreen).map((s: any) => (
        <RevealDrawer key={s.id} v={v} s={s} t={c.t} />
      ))}
    </Fragment>
  );
}

export function FileSwap(c: PrototypeViewProps) {
  return MainContent({ c, t: c.t });
}

export function FilterSwap(c: PrototypeViewProps) {
  return (
    <Fragment>
      <ScreenList c={c} t={c.t} />
      <RunBar c={c} oob={true} t={c.t} />
    </Fragment>
  );
}

// ---- Page ----
const PrototypeView: FC<PrototypeViewProps> = (props) => (
  <MainShellView
    title={props.t('design.pageTitle') as string}
    locale={props.locale}
    activeShell={props.activeShell ?? 'design'}
    prefs={props.prefs as { accent?: string; [key: string]: unknown }}
    project={props.project as { name?: string; savedLabel?: string }}
    mainClass="shell-main-loop"
    footer={renderTimeline(props, false, props.t)}
    surface={RenderPanels(props)}
    t={props.t}
  />
);

export default PrototypeView;
