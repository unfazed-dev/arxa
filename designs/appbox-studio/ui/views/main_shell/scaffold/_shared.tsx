// scaffold/_shared.tsx — the scaffold shell's panel set (replaces _shared.html).
// Composer LEFT, main CENTRE, activity RIGHT, laid out by the grid in
// scaffold.css. Macro-only file — importing it from a fragment render emits
// nothing. Chrome is reused, never forked: every panel comes from the shared
// widget homes through the same open/close pair from _panel.tsx.
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
  c: Ctx;
}
export function Thread({ c }: ThreadProps) {
  return (
    <div class="chat-thread" aria-live="polite" {...inspectAttrs('scaffold:thread', { role: 'group' })}>
      {(c.thread ?? []).map((m: Ctx, i: number) => {
        if (m.kind === 'event') {
          return <Txt key={i} name="scaffold:thread:event" class="bt-event">{m.text}</Txt>;
        }
        if (m.from === 'user') {
          return <Txt key={i} name="scaffold:thread:user" class="bt-msg bt-user">{m.text}</Txt>;
        }
        return (
          <Txt key={i} name="scaffold:thread:agent" class="bt-msg bt-agent">
            {m.text}
            {m.link && <Fragment>{' '}<a class="bt-link" href={m.link.href} {...inspectAttrs('scaffold:thread:link', { role: 'action' })}>{m.link.label}</a></Fragment>}
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
  c: Ctx;
  t: TFn;
}
export function ComposerPanel({ c, t }: ComposerPanelProps) {
  const spec = { eyebrow: c.stageEyebrow ?? '', chips: c.chips };
  return (
    <ComposerOpen spec={spec} t={t}>
      <Thread c={c} />
      {c.composerAction && <Field {...c} t={t} />}
    </ComposerOpen>
  );
}

// activityBody — the activity panel's list body.
interface ActivityBodyProps {
  c: Ctx;
}
export function ActivityBody({ c }: ActivityBodyProps) {
  return (
    <ul class="panel-activity-body" id="panel-activity-body" {...inspectAttrs('scaffold:activity:list', { role: 'list' })}>
      {(c.activity?.items ?? []).map((it: Ctx, i: number) => (
        <li key={i} class={`act-row${it.active ? ' is-active' : ''}`}>
          <Label name="scaffold:activity:label" class="act-label">{it.label}</Label>
          {it.meta && <Label name="scaffold:activity:meta" class="act-meta">{it.meta}</Label>}
        </li>
      ))}
    </ul>
  );
}

// activityPanel — the multi-view activity frame wrapping the body.
interface ActivityPanelProps {
  c: Ctx;
  t: TFn;
}
export function ActivityPanel({ c, t }: ActivityPanelProps) {
  const spec = {
    label: c.activity?.label ?? '',
    views: c.activity?.views ?? [],
    size: c.panelSize,
    sizeHref: c.panelSizeHref,
  };
  return (
    <ActivityOpen spec={spec} t={t}>
      <ActivityBody c={c} />
    </ActivityOpen>
  );
}

// panels — the panel row: one swap unit. Every scaffold interaction re-renders
// #panels outerHTML, so panel widths and the activity panel ride along without
// an out-of-band re-feed. The caller fills the main panel.
interface PanelsProps {
  c: Ctx;
  t: TFn;
  children?: Child;
}
export function Panels({ c, t, children }: PanelsProps) {
  return (
    <div class="panels panels-scaffold" id="panels" data-panel={c.panel}>
      <PanelBar panel={c.panel} t={t} />
      <ComposerPanel c={c} t={t} />
      <MainOpen>{children}</MainOpen>
      <ActivityPanel c={c} t={t} />
    </div>
  );
}

// mainEmpty — the main panel's empty read state (nothing selected yet).
export function MainEmpty({ t }: { t: TFn }) {
  return <Empty t={t} />;
}

// accountChip — the header's entitlement/account element.
// Three states: signed-out → Sign in; free → Upgrade; entitled → plan badge.
interface AccountChipProps {
  c: Ctx;
  t: TFn;
}
export function AccountChip({ c, t }: AccountChipProps) {
  const ent = c.entitlement ?? {};
  const entState = !ent.signedIn ? 'signedOut' : ent.entitled ? 'entitled' : 'free';
  return (
    <span class="shell-account" data-entitlement={entState} {...inspectAttrs('scaffold:account', { role: 'group' })}>
      {!ent.signedIn ? (
        <a class="chip chip--muted shell-account-chip" href="/auth" {...inspectAttrs('scaffold:account:signin', { role: 'action' })}>
          <Icon name="log-in" size={13} /> {t('scaffold.chrome.signIn') as string}
        </a>
      ) : !ent.entitled ? (
        <a class="chip chip--accent shell-account-chip" href={ent.accountHref} {...inspectAttrs('scaffold:account:upgrade', { role: 'action' })}>
          <Icon name="sparkles" size={13} /> {t('scaffold.chrome.upgrade') as string}
        </a>
      ) : (
        <a
          class="chip chip--accent shell-account-chip"
          href={ent.accountHref}
          title={t('scaffold.chrome.accountTitle') as string}
          {...inspectAttrs('scaffold:account:plan', { role: 'action' })}
        >
          <Icon name="badge-check" size={13} /> {t(`plans.plan.${ent.plan}.name`) as string}
        </a>
      )}
    </span>
  );
}
