// chat_view.tsx — design.chat, the one design chat (replaces chat_view.html).
// Composition, not markup: this surface owns no chrome. Panels and fragments
// delegate to prototype_view; chat adds only panelsSwap/drawerSwap/revertSwap
// (the revert path appends a notify toast OOB) and the footer timeline.
import type { FC } from 'hono/jsx';
import { Fragment } from 'hono/jsx';
import MainShellView from '../../main_shell_view.tsx';
import {
  PanelsSwap as ProtoPanelsSwap,
  DrawerSwap as ProtoDrawerSwap,
  RenderPanels,
  type PrototypeViewProps,
} from '../prototype/prototype_view.tsx';
import { Timeline as TimelineEl } from '../../shared/widgets/timeline.tsx';
import { inspectAttrs } from '../../../../common/widgets/primitives.tsx';

type ChatViewProps = PrototypeViewProps;

// ---- Fragment responses ----
export function PanelsSwap(c: ChatViewProps) {
  return ProtoPanelsSwap(c);
}

export function DrawerSwap(c: ChatViewProps) {
  return ProtoDrawerSwap(c);
}

export function RevertSwap(c: ChatViewProps) {
  return (
    <Fragment>
      {ProtoPanelsSwap(c)}
      <div hx-swap-oob="beforeend:#toasts">
        <div class="toast" id="toast-revert" {...inspectAttrs('design-chat:toast', { role: 'text' })}>{c.t('design.revertToast') as string}</div>
      </div>
    </Fragment>
  );
}

// ---- Page ----
const ChatView: FC<ChatViewProps> = (props) => (
  <MainShellView
    title={props.t('design.chat.pageTitle') as string}
    locale={props.locale}
    activeShell={props.activeShell ?? 'design'}
    prefs={props.prefs as { accent?: string; [key: string]: unknown }}
    project={props.project as { name?: string; savedLabel?: string }}
    mainClass="shell-main-loop"
    footer={
      <TimelineEl
        timeline={props.timeline as any}
        label={props.t('design.timelineLabel') as string}
        t={props.t}
      />
    }
    surface={RenderPanels(props)}
    t={props.t}
  />
);

export default ChatView;
