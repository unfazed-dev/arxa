// scaffold/shared.tsx — the scaffold shell's panel set (replaces _shared.html).
// Composer LEFT, main CENTRE, activity RIGHT, laid out by the grid in
// scaffold.css. Macro-only file — importing it from a fragment render emits
// nothing. Chrome is reused, never forked: every panel comes from the shared
// widget homes through the same open/close pair from panel.tsx.
import { Fragment, type Child } from 'hono/jsx';
import Icon from '../../../../runtime/icon.tsx';
import { inspectAttrs, Label, Txt } from '../../../common/widgets/primitives.tsx';
import { Open as ActivityOpen } from '../shared/widgets/activity_panel.tsx';
import { Open as ComposerOpen } from '../shared/widgets/composer_panel.tsx';
import { Field } from '../shared/widgets/composer.tsx';
import { Open as MainOpen, PanelBar, Empty } from '../../../common/widgets/main_panel.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;
type Ctx = Record<string, any>;
export type ScaffoldCtx = Ctx;

// thread — the scaffold's narrative thread (events + user/agent messages).
interface ThreadProps {
  context: Ctx;
}
export function Thread({ context }: ThreadProps) {
  return (
    <div class="chat-thread" aria-live="polite" {...inspectAttrs('scaffold:thread', { role: 'group' })}>
      {(context.thread ?? []).map((message: Ctx, index: number) => {
        if (message.kind === 'event') {
          return <Txt key={index} name="scaffold:thread:event" class="bt-event">{message.text}</Txt>;
        }
        if (message.from === 'user') {
          return <Txt key={index} name="scaffold:thread:user" class="bt-msg bt-user">{message.text}</Txt>;
        }
        return (
          <Txt key={index} name="scaffold:thread:agent" class="bt-msg bt-agent">
            {message.text}
            {message.link && <Fragment>{' '}<a class="bt-link" href={message.link.href} {...inspectAttrs('scaffold:thread:link', { role: 'action' })}>{message.link.label}</a></Fragment>}
          </Txt>
        );
      })}
    </div>
  );
}

// composerPanel — thread + (gated) composer inside the shared frame.
// cm.field is gated on c.composerAction: a surface with no mutation renders
// no field rather than a field wired to an empty action.
interface ComposerPanelProps {
  context: Ctx;
  translate: TFn;
}
export function ComposerPanel({ context, translate }: ComposerPanelProps) {
  const spec = { eyebrow: context.stageEyebrow ?? '', chips: context.chips };
  return (
    <ComposerOpen spec={spec} translate={translate}>
      <Thread context={context} />
      {context.composerAction && <Field {...context} translate={translate} />}
    </ComposerOpen>
  );
}

// activityBody — the activity panel's list body.
interface ActivityBodyProps {
  context: Ctx;
}
export function ActivityBody({ context }: ActivityBodyProps) {
  return (
    <ul class="panel-activity-body" id="panel-activity-body" {...inspectAttrs('scaffold:activity:list', { role: 'list' })}>
      {(context.activity?.items ?? []).map((it: Ctx, index: number) => (
        <li key={index} class={`act-row${it.active ? ' is-active' : ''}`}>
          <Label name="scaffold:activity:label" class="act-label">{it.label}</Label>
          {it.meta && <Label name="scaffold:activity:meta" class="act-meta">{it.meta}</Label>}
        </li>
      ))}
    </ul>
  );
}

// activityPanel — the multi-view activity frame wrapping the body.
interface ActivityPanelProps {
  context: Ctx;
  translate: TFn;
}
export function ActivityPanel({ context, translate }: ActivityPanelProps) {
  const spec = {
    label: context.activity?.label ?? '',
    views: context.activity?.views ?? [],
    size: context.panelSize,
    sizeHref: context.panelSizeHref,
  };
  return (
    <ActivityOpen spec={spec} translate={translate}>
      <ActivityBody context={context} />
    </ActivityOpen>
  );
}

// panels — the panel row: one swap unit. Every scaffold interaction re-renders
// #panels outerHTML, so panel widths and the activity panel ride along without
// an out-of-band re-feed. The caller fills the main panel.
interface PanelsProps {
  context: Ctx;
  translate: TFn;
  children?: Child;
}
export function Panels({ context, translate, children }: PanelsProps) {
  return (
    <div class="panels panels-scaffold" id="panels" data-panel={context.panel}>
      <PanelBar panel={context.panel} translate={translate} />
      <ComposerPanel context={context} translate={translate} />
      <MainOpen>{children}</MainOpen>
      <ActivityPanel context={context} translate={translate} />
    </div>
  );
}

// mainEmpty — the main panel's empty read state (nothing selected yet).
export function MainEmpty({ translate }: { translate: TFn }) {
  return <Empty translate={translate} />;
}

// accountChip — the header's entitlement/account element.
// Three states: signed-out → Sign in; free → Upgrade; entitled → plan badge.
interface AccountChipProps {
  context: Ctx;
  translate: TFn;
}
export function AccountChip({ context, translate }: AccountChipProps) {
  const ent = context.entitlement ?? {};
  const entState = !ent.signedIn ? 'signedOut' : ent.entitled ? 'entitled' : 'free';
  return (
    <span class="shell-account" data-entitlement={entState} {...inspectAttrs('scaffold:account', { role: 'group' })}>
      {!ent.signedIn ? (
        <a class="chip chip--muted shell-account-chip" href="/auth" {...inspectAttrs('scaffold:account:signin', { role: 'action' })}>
          <Icon name="log-in" size={13} /> {translate('scaffold.chrome.signIn') as string}
        </a>
      ) : !ent.entitled ? (
        <a class="chip chip--accent shell-account-chip" href={ent.accountHref} {...inspectAttrs('scaffold:account:upgrade', { role: 'action' })}>
          <Icon name="sparkles" size={13} /> {translate('scaffold.chrome.upgrade') as string}
        </a>
      ) : (
        <a
          class="chip chip--accent shell-account-chip"
          href={ent.accountHref}
          title={translate('scaffold.chrome.accountTitle') as string}
          {...inspectAttrs('scaffold:account:plan', { role: 'action' })}
        >
          <Icon name="badge-check" size={13} /> {translate(`plans.plan.${ent.plan}.name`) as string}
        </a>
      )}
    </span>
  );
}
