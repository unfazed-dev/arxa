// composer.tsx — the composer card (replaces composer.html's `field` macro).
// ONE reusable composer for the composer panel of every shell (intake/design/
// build): a borderless textarea over an action bar (+ tools, the LLM model
// menu, the round send), with an optional screens filmstrip tray that
// auto-expands when something is pinned. Menus are zero-JS <details> opening
// upward. Macro library file — imported directly by view components.
import { Fragment } from 'hono/jsx';
import Icon from '../../../../../runtime/icon.tsx';
import { inspectAttrs } from '../../../../common/widgets/primitives.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

interface Suggestion {
  value?: string;
  label?: string;
}

interface MenuOption {
  label: string;
  blurb: string;
  href: string;
  active?: boolean;
}

interface ModelMenu {
  label: string;
  options: MenuOption[];
}

interface StripThumb {
  id: string;
  label?: string;
  tone?: string;
  inContext?: boolean;
  dim?: boolean;
  src: string;
  contextHref?: string;
  protoHref?: string;
  active?: boolean;
}

interface TrayContext {
  first: string;
  extra?: number;
}

interface PinnedElement {
  screenId: string;
  name: string;
  kind: string;
  tone?: string;
  removeHref?: string;
}

interface ContextChip {
  id: string;
  label: string;
  tone?: string;
  removeHref: string;
}

interface ComposerProps {
  t: TFn;
  composerAction?: string;
  placeholder?: string;
  suggestions?: (Suggestion | string)[];
  modelMenu?: ModelMenu;
  filmstrip?: StripThumb[] | null;
  trayContext?: TrayContext | null;
  elements?: PinnedElement[];
  undoRedo?: { chat: { canUndo?: boolean; canRedo?: boolean } };
  undoHref?: string;
  redoHref?: string;
  tray?: { open?: boolean; toggleHref: string };
  swapTarget?: string;
  contextChips?: ContextChip[];
  draftSent?: boolean;
  scope?: string;
}

export function Field(props: ComposerProps) {
  const { t } = props;
  const scope = props.scope ?? '';
  const sfx = scope ? `--${scope}` : '';
  const tgt = props.swapTarget || '#panels';

  const hasStrip = !!(props.filmstrip && props.filmstrip.length);
  const hasEls = !!(props.elements && props.elements.length);
  const hasBody = hasStrip || hasEls;
  const hasChips = !!(props.contextChips && props.contextChips.length);

  const canUndo = !!(props.undoRedo && props.undoRedo.chat.canUndo);
  const canRedo = !!(props.undoRedo && props.undoRedo.chat.canRedo);

  const collapseLabel = props.tray?.open
    ? (t('composer.collapseTray') as string)
    : (t('composer.showTray') as string);

  // Tray title's pinned-context suffix: trayContext ("first +N") when the
  // thumbs live in the viewer, else the first pinned element's name + count.
  const ctxSuffix = props.trayContext
    ? ` · ${props.trayContext.first}${props.trayContext.extra ? ` +${props.trayContext.extra}` : ''}`
    : hasEls
      ? ` · ${props.elements![0].name}${props.elements!.length > 1 ? ` +${props.elements!.length - 1}` : ''}`
      : '';

  return (
    <form
      class="composer"
      id={`composer${sfx}`}
      data-composer-scope={scope || undefined}
      method="post"
      action={props.composerAction}
      hx-post={props.composerAction}
      hx-target={tgt}
      hx-swap="outerMorph"
      {...inspectAttrs('composer', { role: 'input' })}
    >
      {(hasBody || hasChips) && (
        <Fragment>
          {hasBody ? (
            <Fragment>
              <input
                class="cm-tray-cb"
                type="checkbox"
                id={`cm-tray-cb${sfx}`}
                checked={props.tray?.open ? true : undefined}
                hx-get={props.tray?.toggleHref}
                hx-trigger="change"
                hx-target={tgt}
                hx-swap="outerMorph"
                hx-push-url="false"
                aria-label={collapseLabel}
              />
              <label class="cm-tray-head" for={`cm-tray-cb${sfx}`} title={collapseLabel}>
                <span class="cm-tray-title">
                  {t('composer.context') as string}
                  {ctxSuffix}
                </span>
                <Icon name="chevron-down" size={14} className="composer-chev" />
              </label>
            </Fragment>
          ) : (
            <p class="cm-tray-head is-static">
              <span class="cm-tray-title">{t('composer.context') as string}</span>
            </p>
          )}

          {hasChips && (
            <div class="cs-ctx-strip" role="group" aria-label={t('composer.screensInContext') as string}>
              {props.contextChips!.map((s) => (
                <span class={`cs-ctx-chip ctx-${s.tone}`} title={s.id} key={s.id}>
                  <span class="cs-ctx-name">{s.label}</span>
                  <a
                    class="ctx-x"
                    href={s.removeHref}
                    hx-get={s.removeHref}
                    hx-target={tgt}
                    hx-swap="outerMorph"
                    hx-push-url="false"
                    aria-label={t('chat.removeChip', { label: s.label }) as string}
                  >
                    <Icon name="x" size={12} />
                  </a>
                </span>
              ))}
            </div>
          )}

          {hasBody && (
            <div class="cm-tray">
              <div class="cm-tray-clip">
                {hasStrip && (
                  <div class="cs-strip" aria-label={t('composer.screensInContext') as string}>
                    {props.filmstrip!.map((s) => (
                      <a
                        class={`dv-thumb cs-thumb${s.inContext ? ` in-ctx ctx-${s.tone}` : ''}${s.dim ? ' is-dim' : ''}${s.active ? ' on' : ''}`}
                        href={s.protoHref || s.contextHref}
                        hx-get={s.protoHref || s.contextHref}
                        hx-target={s.protoHref ? '#design-viewer' : tgt}
                        hx-swap="outerMorph"
                        hx-push-url="false"
                        title={s.label || s.id}
                        key={s.id}
                      >
                        <span class="dv-thumb-clip">
                          <iframe id={`dvf-thumb--${s.id}${sfx}`} src={s.src} scrolling="no" tabindex={-1} title=""></iframe>
                        </span>
                        <span class="dv-thumb-label"><code>{s.id}</code></span>
                      </a>
                    ))}
                  </div>
                )}
                {hasEls && (
                  <div class="cs-el-strip" aria-label={t('composer.elsInContext') as string}>
                    {props.elements!.map((el) => (
                      <span class={`chip cs-el-chip ctx-${el.tone}`} key={`${el.screenId}:${el.name}`}>
                        <code class="cs-el-name">{el.name}</code>
                        <span class="cs-el-kind">{el.kind}</span>
                        <span class="cs-el-screen muted">{el.screenId}</span>
                        {el.removeHref && (
                          <a
                            class="ctx-x"
                            href={el.removeHref}
                            hx-get={el.removeHref}
                            hx-target={tgt}
                            hx-swap="outerMorph"
                            hx-push-url="false"
                            aria-label={t('chat.removeChip', { label: el.name }) as string}
                          >
                            <Icon name="x" size={12} />
                          </a>
                        )}
                      </span>
                    ))}
                  </div>
                )}
              </div>
            </div>
          )}
        </Fragment>
      )}

      {/* draftSent must break the MORPH identity, not just drop hx-preserve:
          outerMorph matches this node by id and morphs attributes only — a
          textarea's typed text lives in the live `.value` property, which a
          morph never touches, so the sent message would survive the swap.
          Suffixing the id on the one render that follows a send makes the
          morph treat it as a new node: fresh element, empty value. The next
          normal render restores the canonical id (and hx-preserve), replacing
          the already-empty temp node. Nothing else keys on this id. */}
      <textarea
        id={`composer-text${sfx}${props.draftSent ? '--sent' : ''}`}
        hx-preserve={!props.draftSent ? 'true' : undefined}
        name="text"
        rows={1}
        placeholder={props.placeholder}
        aria-label={props.placeholder}
      ></textarea>

      <div class="composer-bar">
        {props.suggestions && props.suggestions.length > 0 && (
          <details class="composer-plus">
            <summary aria-label={t('composer.tools') as string}>
              <Icon name="plus" size={18} />
            </summary>
            <span class="composer-sugs">
              {props.suggestions.map((s, i) => {
                const val = typeof s === 'string' ? s : s.value;
                const label = typeof s === 'string' ? s : s.label;
                return (
                  <button type="submit" name="preset" value={val} key={i}>
                    {label}
                  </button>
                );
              })}
            </span>
          </details>
        )}

        <span class="composer-undo-redo" role="group" aria-label={t('miniPanel.historyGroup') as string}>
          <button
            type="button"
            class="ico-btn undo-btn"
            disabled={!canUndo || undefined}
            hx-post={canUndo ? props.undoHref || '/design/undo/chat' : undefined}
            hx-target={canUndo ? tgt : undefined}
            hx-swap={canUndo ? 'outerMorph' : undefined}
            title={t('miniPanel.undo') as string}
          >
            <Icon name="undo-2" size={16} />
          </button>
          <button
            type="button"
            class="ico-btn redo-btn"
            disabled={!canRedo || undefined}
            hx-post={canRedo ? props.redoHref || '/design/redo/chat' : undefined}
            hx-target={canRedo ? tgt : undefined}
            hx-swap={canRedo ? 'outerMorph' : undefined}
            title={t('miniPanel.redo') as string}
          >
            <Icon name="redo-2" size={16} />
          </button>
        </span>

        <span class="composer-spacer"></span>

        {props.modelMenu && (
          <details class="composer-model">
            <summary aria-label={t('composer.agentModel') as string} title={t('composer.agentModel') as string}>
              {props.modelMenu.label} <Icon name="chevron-down" size={14} className="composer-chev" />
            </summary>
            <span class="composer-menu composer-menu-right">
              {props.modelMenu.options.map((o) => (
                <a
                  class={`composer-opt${o.active ? ' on' : ''}`}
                  href={o.href}
                  hx-get={o.href}
                  hx-target={tgt}
                  hx-swap="outerMorph"
                  hx-push-url="false"
                  key={o.href}
                >
                  <span class="composer-opt-label">{o.label}</span>
                  <span class="composer-opt-blurb">{o.blurb}</span>
                  {o.active && <Icon name="check" size={14} className="composer-opt-check" />}
                </a>
              ))}
            </span>
          </details>
        )}

        <button type="submit" class="composer-send" aria-label={t('composer.send') as string}>
          <Icon name="arrow-up" size={18} />
        </button>
      </div>
    </form>
  );
}
