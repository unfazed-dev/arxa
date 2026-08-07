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
import { TypeBadge, StatusPill, inspectAttrs } from '../../../common/widgets/primitives.tsx';

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
    <span class="msg-detail">
      <b>{label}</b> {value}
      {mark && <em class="chip thread-badge"> {t('inspector.inferred') as string}</em>}
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
      <header class="msg-meta">
        {el.kind && <TypeBadge type={el.kind} />}
        {el.inferred && (
          <span class="chip thread-badge" {...inspectAttrs('inspector:inferred', { role: 'status' })} title={t('inspector.inferredTitle') as string}>
            {t('inspector.inferred') as string}
          </span>
        )}
        {locked && (
          <span class="chip thread-badge" title={t('inspector.lockedTitle') as string}>
            <Icon name="lock" size={12} /> {t('inspector.locked') as string}
          </span>
        )}
      </header>
      <span class="msg-text"><code>{el.name}</code></span>
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
      {el.screenId && <span class="msg-detail muted">{el.screenId}</span>}
      <MetaRow label={t('inspector.role') as string} value={el.role?.value} mark={el.role?.inferred} t={t} />
      <MetaRow label={t('inspector.style') as string} value={el.style} mark={false} t={t} />
      <MetaRow label={t('inspector.motion') as string} value={el.motion} mark={false} t={t} />
      <MetaRow label={t('inspector.fn') as string} value={el.fn?.value} mark={el.fn?.inferred} t={t} />
      <footer class="msg-foot">
        <span class="msg-cta">
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
            >
              {t('design.inContext') as string} <Icon name="check" size={14} />
            </a>
          ) : el.pinHref ? (
            <form hx-post={el.pinHref} hx-target="#panels" hx-swap="outerMorph" hx-push-url="false">
              <input type="hidden" name="screen" value={el.screenId} />
              <input type="hidden" name="name" value={el.name} />
              <input type="hidden" name="kind" value={el.kind} />
              <button class="cta-main" type="submit">{t('design.pinToContext') as string} <Icon name="pin" size={14} /></button>
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
      <header class="msg-meta">
        <TypeBadge type="screen" label={sc.epic} />
        {sc.state && <StatusPill state={sc.state} size="sm" t={t} />}
      </header>
      <span class="msg-text"><code>{sc.id}</code></span>

      <span class="msg-detail"><b>{t('inspector.states') as string}</b></span>
      <span class="msg-meta">
        {sc.states && sc.states.length > 0 ? (
          sc.states.map((st, i) => (
            <span
              key={i}
              class="chip thread-badge"
              title={t(`inspector.source.${st.source ?? 'declared'}`) as string}
            >
              {st.name}{st.source === 'derived' ? ` · ${t('inspector.derived') as string}` : ''}
            </span>
          ))
        ) : (
          <span class="msg-detail muted">{t('inspector.noStates') as string}</span>
        )}
      </span>

      {/* States the kit implies but the screen never declares — only when there is one. */}
      {sc.missingStates && sc.missingStates.length > 0 && (
        <Fragment>
          <span class="msg-detail"><b>{t('inspector.missingStates') as string}</b></span>
          {sc.missingStates.map((ms, i) => (
            <span key={i} class="msg-detail">{ms.name}{ms.why ? ` — ${ms.why}` : ''}</span>
          ))}
        </Fragment>
      )}

      <span class="msg-detail"><b>{t('inspector.kits') as string}</b></span>
      <span class="msg-meta">
        {sc.kits && sc.kits.length > 0 ? (
          sc.kits.map((k, i) => <span key={i} class="chip thread-badge">{k.label ?? k.id}</span>)
        ) : (
          <span class="msg-detail muted">{t('inspector.noKits') as string}</span>
        )}
      </span>

      <span class="msg-detail"><b>{t('inspector.edges') as string}</b></span>
      {sc.edges && sc.edges.length > 0 ? (
        sc.edges.map((e, i) => (
          <span key={i} class="msg-detail">
            {e.flowLabel ?? e.flow} · {e.trigger} <Icon name="arrow-right" size={12} /> <code>{e.to}</code>
            {e.element ? <span class="muted"> ({e.element})</span> : null}
          </span>
        ))
      ) : (
        <span class="msg-detail muted">{t('inspector.noEdges') as string}</span>
      )}

      {sc.annotations && (
        <Fragment>
          <footer class="msg-foot">
            <span class="msg-detail">
              {t('inspector.coverage', { covered: sc.annotations.covered, total: sc.annotations.total, pct: sc.annotations.pct }) as string}
            </span>
          </footer>
          {sc.annotations.missing && sc.annotations.missing.length > 0 && (
            <Fragment>
              <span class="msg-detail"><b>{t('inspector.uncovered') as string}</b></span>
              {sc.annotations.missing.map((m, i) => <span key={i} class="msg-detail"><code>{m}</code></span>)}
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
    <div class="av-list" id="av-list">
      {ins && ins.mode === 'element' && ins.element ? (
        <ElementCard el={ins.element} locked={ins.locked} unlockHref={ins.unlockHref} t={t} />
      ) : ins && ins.mode === 'screen' && ins.screen ? (
        <ScreenCard sc={ins.screen} t={t} />
      ) : (
        <p class="muted">{(ins?.hint) || (t('inspector.empty') as string)}</p>
      )}
    </div>
  );
}
