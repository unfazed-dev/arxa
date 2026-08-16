// chat_view.tsx — design.chat, the one design chat (replaces chat_view.html).
// Composition, not markup: this surface owns no chrome. Panels and fragments
// delegate to prototype_view; chat adds only panelsSwap/drawerSwap/revertSwap
// (the revert path appends a notify toast OOB) and the footer timeline.
import type { FC } from 'hono/jsx';
import { Fragment } from 'hono/jsx';
import StudioDesignShellView from '../studio_design_shell_view.tsx';
import {
  PanelsSwap as ProtoPanelsSwap,
  DrawerSwap as ProtoDrawerSwap,
  RenderPanels,
  type PrototypeViewProps,
} from '../studio_design_prototype/studio_design_prototype_view.tsx';
import { Timeline as TimelineEl } from '../../../widgets/common/studio_panels/widgets.tsx';
import { inspectAttrs } from '../../../widgets/common/studio_primitives/widgets.tsx';

type ChatViewProps = PrototypeViewProps;

// ---- Fragment responses ----
export function PanelsSwap(context: ChatViewProps) {
  return ProtoPanelsSwap(context);
}

export function DrawerSwap(context: ChatViewProps) {
  return ProtoDrawerSwap(context);
}

export function RevertSwap(context: ChatViewProps) {
  return (
    <Fragment>
      {ProtoPanelsSwap(context)}
      <div hx-swap-oob="beforeend:#toasts">
        <div class="toast" id="toast-revert" {...inspectAttrs('design-chat:toast', { role: 'text' })}>{context.translate('design.revertToast') as string}</div>
      </div>
    </Fragment>
  );
}

// ---- Page ----
const ChatView: FC<ChatViewProps> = (props) => (
  <StudioDesignShellView
    title={props.translate('design.chat.pageTitle') as string}
    locale={props.locale}
    activeShell={props.activeShell ?? 'design'}
    prefs={props.prefs as { accent?: string; [key: string]: unknown }}
    project={props.project as { name?: string; savedLabel?: string }}
    mainClass="shell-main-loop"
    footer={
      <TimelineEl
        timeline={props.timeline as any}
        label={props.translate('design.timelineLabel') as string}
        translate={props.translate}
      />
    }
    surface={RenderPanels(props)}
    translate={props.translate}
  />
);

export default ChatView;
