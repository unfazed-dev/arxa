// arxa:provenance
// generator: arxa  licence: free  project: 662368770980
// Built with arxa (free tier) — https://arxa.dev

// anatomy/chat/chat_view.tsx — the showcase-anatomy twin of design.chat
// (Q13 parallel-run). Resolved by the viewmodel via abxResolveShellView; the
// legacy twin at ../../chat/chat_view.tsx stays untouched and byte-stable.
//
// Fragment exports are pinned name-for-name to the legacy view (finding 8a:
// the render bundle indexes the named exports, and siblings render
// `${resolved}#Fragment` — a missing name here is a silent hybrid at swap
// time). Fragments swap inner panel content that carries no shell identity,
// so they delegate unchanged; identity lives on the page frame below.
import type { FC } from 'hono/jsx';
import {
  PanelsSwap as LegacyPanelsSwap,
  DrawerSwap as LegacyDrawerSwap,
  RevertSwap as LegacyRevertSwap,
} from '../../chat/chat_view.tsx';
import { RenderPanels, type PrototypeViewProps } from '../../prototype/prototype_view.tsx';
import { Timeline as TimelineEl } from '../../../shared/widgets/timeline.tsx';
import { AnatomyShellView } from '../shared_anatomy.tsx';

type ChatViewProps = PrototypeViewProps;

const SCREEN_ID = 'design.chat';
const SURFACE_ID = 'design.chat';

// ---- Fragment responses (pinned set: panelsSwap, drawerSwap, revertSwap) ----
export function PanelsSwap(context: ChatViewProps) {
  return LegacyPanelsSwap(context);
}

export function DrawerSwap(context: ChatViewProps) {
  return LegacyDrawerSwap(context);
}

export function RevertSwap(context: ChatViewProps) {
  return LegacyRevertSwap(context);
}

// ---- Page ----
const ChatView: FC<ChatViewProps> = (props) => (
  <AnatomyShellView
    screenId={SCREEN_ID}
    surfaceId={SURFACE_ID}
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
