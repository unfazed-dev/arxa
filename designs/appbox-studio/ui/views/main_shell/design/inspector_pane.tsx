// inspector_pane.tsx — the activity panel's inspector view (replaces
// inspector_pane.html). Two cards, one at a time — c.inspector.mode picks:
//   element — an element hovered (transient) or LOCKED (click). The card is
//             the element's own story: role / style / motion / fn, each marked
//             when the server INFERRED it rather than read it (derive+confirm).
//   screen  — nothing hovered/locked: the screen the canvas is showing.
//   empty   — neither.
// The lock lives in the session, never the DOM, so it survives every morph.
// Pin is its own button (POSTs /design/chat/context/element). Read defensively:
// every scalar behind a guard, every list behind a length check, so a viewmodel
// field the facade has not built yet renders an empty-but-valid pane.
// Macro library file — imported directly by the design activity view.
import { Fragment } from 'hono/jsx';
import Icon from '../../../../runtime/icon.tsx';
import { TypeBadge, StatusPill, inspectAttrs, Label, Txt } from '../../../common/widgets/primitives.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

// ---- inspector viewmodel (see header) --------------------------------------
interface InferredField {
  value?: string;
  inferred?: boolean;
}
interface InspectorCrumb {
  el: string;
  inferred?: boolean;
  selectHref?: string | null;
}
interface InspectorElement {
  kind?: string;
  name?: string;
  screenId?: string;
  tone?: string;
  pinned?: boolean;
  pinHref?: string;
  unpinHref?: string;
  inferred?: boolean;
  chain?: InspectorCrumb[];
  role?: InferredField;
  style?: string;
  motion?: string;
  fn?: InferredField;
}
interface ScreenState {
  name: string;
  source?: string;
}
interface MissingState {
  name: string;
  why?: string;
}
interface ScreenKit {
  id: string;
  label?: string;
}
interface ScreenEdge {
  flow?: string;
  flowLabel?: string;
  trigger?: string;
  to: string;
  element?: string;
}
interface ScreenAnnotations {
  covered: number;
  total: number;
  pct: number;
  missing?: string[];
}
interface InspectorScreen {
  id: string;
  epic?: string;
  state?: string;
  states?: ScreenState[];
  missingStates?: MissingState[];
  kits?: ScreenKit[];
  edges?: ScreenEdge[];
  annotations?: ScreenAnnotations;
}
interface Inspector {
  mode?: string;
  element?: InspectorElement;
  screen?: InspectorScreen;
  locked?: boolean;
  unlockHref?: string;
  hint?: string;
}
interface PaneCtx {
  inspector?: Inspector;
}

// metaRow — a metadata row. `mark` renders the inferred badge: the value is
// the server's guess, not something the element declares.
interface MetaRowProps {
  label: string;
  value?: string;
  mark?: boolean;
  t: TFn;
}
export function MetaRow({ label, value, mark, t }: MetaRowProps) {
  if (!value) return null;
  return (
    <span class="msg-detail" {...inspectAttrs('inspector:meta-row', { role: 'group' })}>
      <b {...inspectAttrs('inspector:meta-label', { role: 'label' })}>{label}</b> {value}
      {mark && <em class="chip thread-badge" {...inspectAttrs('inspector:inferred-badge', { role: 'status' })}> {t('inspector.inferred') as string}</em>}
    </span>
  );
}

// elementCard — the element's own story + pin/lock controls.
interface ElementCardProps {
  el: InspectorElement;
  locked?: boolean;
  unlockHref?: string;
  t: TFn;
}
export function ElementCard({ el, locked, unlockHref, t }: ElementCardProps) {
  return (
    <div class={`msg msg-agent${locked ? ` is-active msg-ctx ctx-${el.tone}` : ''}`}>
      <header class="msg-meta" {...inspectAttrs('inspector:card-head', { role: 'group' })}>
        {el.kind && <TypeBadge type={el.kind} />}
        {el.inferred && (
          <span class="chip thread-badge" {...inspectAttrs('inspector:inferred', { role: 'status' })} title={t('inspector.inferredTitle') as string}>
            {t('inspector.inferred') as string}
          </span>
        )}
        {locked && (
          <span class="chip thread-badge" {...inspectAttrs('inspector:locked', { role: 'status' })} title={t('inspector.lockedTitle') as string}>
            <Icon name="lock" size={12} /> {t('inspector.locked') as string}
          </span>
        )}
      </header>
      <span class="msg-text" {...inspectAttrs('inspector:el-name-text', { role: 'text' })}><code {...inspectAttrs('inspector:el-name', { role: 'text' })}>{el.name}</code></span>
      {/* Ancestor breadcrumb — outermost › … › current. Each ancestor is a
          button that POSTs back to /design/inspector/select (selectHref) to
          lock that element; the last entry is the current element (no link). */}
      {Array.isArray(el.chain) && el.chain.length > 1 && (
        <nav class="insp-crumbs" aria-label={t('inspector.chainAria') as string} {...inspectAttrs('inspector:crumbs', { role: 'navigation' })}>
          {el.chain.map((c, i) => (
            <Fragment key={i}>
              {i > 0 && <span class="insp-crumb-sep" {...inspectAttrs('inspector:crumb-sep', { role: 'separator' })} aria-hidden="true">›</span>}
              {c.selectHref ? (
                <button
                  class={`insp-crumb${c.inferred ? ' is-inferred' : ''}`}
                  {...inspectAttrs('inspector:crumb', { role: 'link' })}
                  type="button"
                  hx-post={c.selectHref}
                  hx-target="#av-list"
                  hx-swap="outerHTML"
                  hx-push-url="false"
                >{c.el}</button>
              ) : (
                <span class={`insp-crumb is-current${c.inferred ? ' is-inferred' : ''}`} {...inspectAttrs('inspector:crumb-current', { role: 'text' })}>{c.el}</span>
              )}
            </Fragment>
          ))}
        </nav>
      )}
      {el.screenId && <Label name="inspector:screen-id" class="msg-detail muted">{el.screenId}</Label>}
      <MetaRow label={t('inspector.role') as string} value={el.role?.value} mark={el.role?.inferred} t={t} />
      <MetaRow label={t('inspector.style') as string} value={el.style} mark={false} t={t} />
      <MetaRow label={t('inspector.motion') as string} value={el.motion} mark={false} t={t} />
      <MetaRow label={t('inspector.fn') as string} value={el.fn?.value} mark={el.fn?.inferred} t={t} />
      <footer class="msg-foot">
        <span class="msg-cta" {...inspectAttrs('inspector:card-cta', { role: 'group' })}>
          {/* Pin is an explicit control, not a side effect of clicking — a form,
              because the endpoint reads name/kind off the body. */}
          {el.pinned && el.unpinHref ? (
            <a
              class="cta-main"
              href={el.unpinHref}
              hx-get={el.unpinHref}
              hx-target="#panels"
              hx-swap="outerMorph"
              hx-push-url="false"
              {...inspectAttrs('inspector:unpin', { role: 'action' })}
            >
              {t('design.inContext') as string} <Icon name="check" size={14} />
            </a>
          ) : el.pinHref ? (
            <form hx-post={el.pinHref} hx-target="#panels" hx-swap="outerMorph" hx-push-url="false">
              <input type="hidden" name="screen" value={el.screenId} {...inspectAttrs('inspector:field-screen', { role: 'input' })} />
              <input type="hidden" name="name" value={el.name} {...inspectAttrs('inspector:field-name', { role: 'input' })} />
              <input type="hidden" name="kind" value={el.kind} {...inspectAttrs('inspector:field-kind', { role: 'input' })} />
              <button class="cta-main" type="submit" {...inspectAttrs('inspector:pin', { role: 'action' })}>{t('design.pinToContext') as string} <Icon name="pin" size={14} /></button>
            </form>
          ) : null}
          {locked && unlockHref && (
            <button
              class="cta-main"
              type="button"
              hx-post={unlockHref}
              hx-target="#panel-activity-body"
              hx-swap="innerHTML"
              hx-push-url="false"
              {...inspectAttrs('inspector:unlock', { role: 'action' })}
            >
              {t('inspector.unlock') as string} <Icon name="lock-open" size={14} />
            </button>
          )}
        </span>
      </footer>
    </div>
  );
}

// screenCard — the screen's registry joins: states, kits, flow edges,
// annotation coverage. Every list has an honest empty.
interface ScreenCardProps {
  sc: InspectorScreen;
  t: TFn;
}
export function ScreenCard({ sc, t }: ScreenCardProps) {
  return (
    <div class="msg msg-agent">
      <header class="msg-meta" {...inspectAttrs('inspector:sc-meta', { role: 'nav' })}>
        <TypeBadge type="screen" label={sc.epic} />
        {sc.state && <StatusPill state={sc.state} size="sm" t={t} />}
      </header>
      <span class="msg-text" {...inspectAttrs('inspector:sc-id-text', { role: 'text' })}><code {...inspectAttrs('inspector:sc-id', { role: 'text' })}>{sc.id}</code></span>

      <span class="msg-detail" {...inspectAttrs('inspector:states-label', { role: 'group' })}><b {...inspectAttrs('inspector:states-text', { role: 'label' })}>{t('inspector.states') as string}</b></span>
      <span class="msg-meta" {...inspectAttrs('inspector:states-badges', { role: 'group' })}>
        {sc.states && sc.states.length > 0 ? (
          sc.states.map((st, i) => (
            <span
              key={i}
              class="chip thread-badge"
              {...inspectAttrs('inspector:state-badge', { role: 'label' })}
              title={t(`inspector.source.${st.source ?? 'declared'}`) as string}
            >
              {st.name}{st.source === 'derived' ? ` · ${t('inspector.derived') as string}` : ''}
            </span>
          ))
        ) : (
          <Label name="inspector:no-states" class="msg-detail muted">{t('inspector.noStates') as string}</Label>
        )}
      </span>

      {/* States the kit implies but the screen never declares — only when there is one. */}
      {sc.missingStates && sc.missingStates.length > 0 && (
        <Fragment>
          <span class="msg-detail" {...inspectAttrs('inspector:missing-label', { role: 'group' })}><b {...inspectAttrs('inspector:missing-states-text', { role: 'label' })}>{t('inspector.missingStates') as string}</b></span>
          {sc.missingStates.map((ms, i) => (
            <Label key={i} name="inspector:missing-state" class="msg-detail">{ms.name}{ms.why ? ` — ${ms.why}` : ''}</Label>
          ))}
        </Fragment>
      )}

      <span class="msg-detail" {...inspectAttrs('inspector:kits-label', { role: 'group' })}><b {...inspectAttrs('inspector:kits-text', { role: 'label' })}>{t('inspector.kits') as string}</b></span>
      <span class="msg-meta" {...inspectAttrs('inspector:kits-badges', { role: 'group' })}>
        {sc.kits && sc.kits.length > 0 ? (
          sc.kits.map((k, i) => <Label key={i} name="inspector:kit-badge" class="chip thread-badge">{k.label ?? k.id}</Label>)
        ) : (
          <Label name="inspector:no-kits" class="msg-detail muted">{t('inspector.noKits') as string}</Label>
        )}
      </span>

      <span class="msg-detail" {...inspectAttrs('inspector:edges-label', { role: 'group' })}><b {...inspectAttrs('inspector:edges-text', { role: 'label' })}>{t('inspector.edges') as string}</b></span>
      {sc.edges && sc.edges.length > 0 ? (
        sc.edges.map((e, i) => (
          <span key={i} class="msg-detail" {...inspectAttrs('inspector:edge', { role: 'group' })}>
            {e.flowLabel ?? e.flow} · {e.trigger} <Icon name="arrow-right" size={12} /> <code {...inspectAttrs('inspector:edge-to', { role: 'text' })}>{e.to}</code>
            {e.element ? <Label name="inspector:edge-element" class="muted"> ({e.element})</Label> : null}
          </span>
        ))
      ) : (
        <Label name="inspector:no-edges" class="msg-detail muted">{t('inspector.noEdges') as string}</Label>
      )}

      {sc.annotations && (
        <Fragment>
          <footer class="msg-foot">
            <Label name="inspector:coverage" class="msg-detail">
              {t('inspector.coverage', { covered: sc.annotations.covered, total: sc.annotations.total, pct: sc.annotations.pct }) as string}
            </Label>
          </footer>
          {sc.annotations.missing && sc.annotations.missing.length > 0 && (
            <Fragment>
              <span class="msg-detail" {...inspectAttrs('inspector:uncovered-label', { role: 'group' })}><b {...inspectAttrs('inspector:uncovered-text', { role: 'label' })}>{t('inspector.uncovered') as string}</b></span>
              {sc.annotations.missing.map((m, i) => <span key={i} class="msg-detail" {...inspectAttrs('inspector:missing-annotation', { role: 'group' })}><code {...inspectAttrs('inspector:missing-code', { role: 'text' })}>{m}</code></span>)}
            </Fragment>
          )}
        </Fragment>
      )}
    </div>
  );
}

// pane — the pane body. #av-list is the swap handle for the island's hover
// POSTs; the route answers 204 when the inspector is not the active view, so a
// hover can never overwrite the screens list.
interface PaneProps {
  c: PaneCtx;
  t: TFn;
}
export function Pane({ c, t }: PaneProps) {
  const ins = c.inspector;
  return (
    <div class="av-list" id="av-list" {...inspectAttrs('inspector:list', { role: 'group' })}>
      {ins && ins.mode === 'element' && ins.element ? (
        <ElementCard el={ins.element} locked={ins.locked} unlockHref={ins.unlockHref} t={t} />
      ) : ins && ins.mode === 'screen' && ins.screen ? (
        <ScreenCard sc={ins.screen} t={t} />
      ) : (
        <Txt name="inspector:empty" class="muted">{(ins?.hint) || (t('inspector.empty') as string)}</Txt>
      )}
    </div>
  );
}
