// composer.tsx — the composer card (replaces composer.html's `field` macro).
// ONE reusable composer for the composer panel of every shell (intake/design/
// build): a borderless textarea over an action bar (+ tools, the LLM model
// menu, the round send), with an optional screens filmstrip tray that
// auto-expands when something is pinned. Menus are zero-JS <details> opening
// upward. Macro library file — imported directly by view components.
import { Fragment } from 'hono/jsx';
import Icon from '../../../../runtime/icon.tsx';
import { inspectAttrs } from '../studio_primitives/widgets.tsx';

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
  translate: TFn;
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
  const { translate } = props;
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
    ? (translate('composer.collapseTray') as string)
    : (translate('composer.showTray') as string);

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
                  {translate('composer.context') as string}
                  {ctxSuffix}
                </span>
                <Icon name="chevron-down" size={14} className="composer-chev" />
              </label>
            </Fragment>
          ) : (
            <p class="cm-tray-head is-static">
              <span class="cm-tray-title">{translate('composer.context') as string}</span>
            </p>
          )}

          {hasChips && (
            <div class="cs-ctx-strip" role="group" aria-label={translate('composer.screensInContext') as string}>
              {props.contextChips!.map((chip) => (
                <span class={`cs-ctx-chip ctx-${chip.tone}`} title={chip.id} key={chip.id}>
                  <span class="cs-ctx-name">{chip.label}</span>
                  <a
                    class="ctx-x"
                    href={chip.removeHref}
                    hx-get={chip.removeHref}
                    hx-target={tgt}
                    hx-swap="outerMorph"
                    hx-push-url="false"
                    aria-label={translate('chat.removeChip', { label: chip.label }) as string}
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
                  <div class="cs-strip" aria-label={translate('composer.screensInContext') as string}>
                    {props.filmstrip!.map((frame) => (
                      <a
                        class={`dv-thumb cs-thumb${frame.inContext ? ` in-ctx ctx-${frame.tone}` : ''}${frame.dim ? ' is-dim' : ''}${frame.active ? ' on' : ''}`}
                        href={frame.protoHref || frame.contextHref}
                        hx-get={frame.protoHref || frame.contextHref}
                        hx-target={frame.protoHref ? '#design-viewer' : tgt}
                        hx-swap="outerMorph"
                        hx-push-url="false"
                        title={frame.label || frame.id}
                        key={frame.id}
                      >
                        <span class="dv-thumb-clip">
                          <iframe id={`dvf-thumb--${frame.id}${sfx}`} src={frame.src} scrolling="no" tabindex={-1} title=""></iframe>
                        </span>
                        <span class="dv-thumb-label"><code>{frame.id}</code></span>
                      </a>
                    ))}
                  </div>
                )}
                {hasEls && (
                  <div class="cs-el-strip" aria-label={translate('composer.elsInContext') as string}>
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
                            aria-label={translate('chat.removeChip', { label: el.name }) as string}
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
            <summary aria-label={translate('composer.tools') as string}>
              <Icon name="plus" size={18} />
            </summary>
            <span class="composer-sugs">
              {props.suggestions.map((suggestion, index) => {
                const val = typeof suggestion === 'string' ? suggestion : suggestion.value;
                const label = typeof suggestion === 'string' ? suggestion : suggestion.label;
                return (
                  <button type="submit" name="preset" value={val} key={index}>
                    {label}
                  </button>
                );
              })}
            </span>
          </details>
        )}

        <span class="composer-undo-redo" role="group" aria-label={translate('miniPanel.historyGroup') as string}>
          <button
            type="button"
            class="ico-btn undo-btn"
            disabled={!canUndo || undefined}
            hx-post={canUndo ? props.undoHref || '/design/undo/chat' : undefined}
            hx-target={canUndo ? tgt : undefined}
            hx-swap={canUndo ? 'outerMorph' : undefined}
            title={translate('miniPanel.undo') as string}
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
            title={translate('miniPanel.redo') as string}
          >
            <Icon name="redo-2" size={16} />
          </button>
        </span>

        <span class="composer-spacer"></span>

        {props.modelMenu && (
          <details class="composer-model">
            <summary aria-label={translate('composer.agentModel') as string} title={translate('composer.agentModel') as string}>
              {props.modelMenu.label} <Icon name="chevron-down" size={14} className="composer-chev" />
            </summary>
            <span class="composer-menu composer-menu-right">
              {props.modelMenu.options.map((option) => (
                <a
                  class={`composer-opt${option.active ? ' on' : ''}`}
                  href={option.href}
                  hx-get={option.href}
                  hx-target={tgt}
                  hx-swap="outerMorph"
                  hx-push-url="false"
                  key={option.href}
                >
                  <span class="composer-opt-label">{option.label}</span>
                  <span class="composer-opt-blurb">{option.blurb}</span>
                  {option.active && <Icon name="check" size={14} className="composer-opt-check" />}
                </a>
              ))}
            </span>
          </details>
        )}

        <button type="submit" class="composer-send" aria-label={translate('composer.send') as string}>
          <Icon name="arrow-up" size={18} />
        </button>
      </div>
    </form>
  );
}
