// _panel-activity.tsx — the activity panel (replaces _panel-activity.html).
// THE ACTIVITY PANEL: one of the studio's five ROLE-named panels (header /
// composer / main / activity / footer) — the shell's multi-view panel. It
// owns a top (active view label + resize rail), a body the caller fills via
// children, and a bottom views bar whose icon carousel switches views by
// hx-swapping the body. Self-contained: this file does not import the
// studio's panel component — it copies that file's section shape
// (.panel-top / .panel-body / .panel-bottom on a 3×3 grid, see
// widgets.css) rather than reaching across repos for it.
//
// THE STATEFUL-WIDGET REFERENCE (DESIGN-ARCHITECTURE, "Widget state"):
// all panel state is server session state, namespaced per shell — the DOM is
// never a store.
//   · view switch → carousel targets #panel-activity-body; the response is
//     the body content PLUS top + bottom rendered with oob, so the active
//     icon and label track the server; the panel itself (scroll, width
//     class) is never replaced
//   · width → s|m|l steps rendered as panel-size-* classes from the shell's
//     session (discrete, server-validated — a CSS `resize` drag can never
//     persist without client JS, which the contract forbids); optionally a
//     resize rail (.panel-resize) that the vendored drag.js island wires to
//     POST a px width
//   · stage acts → re-feed body + top + bottom OOB in the same response
//   · page render → frame only; OOB parts are response-only markup
//
// There is no `side` argument. This panel is identified by its ROLE, and its
// id is the constant `panel-activity`; it may sit on either edge of the
// stage, and neither fact belongs in its name.
//
// Usage (composition replaces {% call %}…{{ caller() }}):
//
//   import { ActivityFrame } from '../../common/widgets/_panel-activity.tsx';
//   <ActivityFrame spec={{ label: 'Inspector', views: [...] }} t={t}>
//     …markup for the active view…
//   </ActivityFrame>
//
// spec:
//   label        — the active view's label, shown in the top section
//   views        — [{ id, icon, label, href, active }], one carousel button
//                  each; icon is a Lucide name for <Icon>, href hx-swaps
//                  that view's fragment into #panel-activity-body
//   size?        — 's' | 'm' | 'l' (default 's'): the shell's persisted panel
//                  width (facade session state, panelSize.activity); used as
//                  the panel-size-* class fallback when panelSizePx is unset
//   sizeHref?    — present when the panel can be resized; renders the resize
//                  rail on the panel's start edge (drag.js wires it to POST
//                  px width; live width shown in .panel-resize-width)
//   panelSizePx? — persisted px width; when set, applied as an inline width
//                  style on the panel instead of the panel-size-* fallback
//
// Sibling exports: ActivityLabel · ActivityViews · ActivityTop ·
// ActivityBottom (oob variants for fragment responses) · ActivityFrame.
// Required l10n keys: panel.activity.views, panel.resize (only with
// sizeHref). `t` comes from the render ctx bag ({ prefs, locale, locales, t }).
// Fragment note: starter widgets are not views — a viewmodel can only
// fragment-render named exports of *_view.tsx files.
// CSS: the .panel grid + .panel-activity family in widgets.css. Recipe 19
// in ui-recipes.md.
import type { FC, Child } from 'hono/jsx';
// Icon path note: canonical placement is ui/common/widgets/ (3 deep from the
// artifact root); adjust the runtime/icon.tsx relative path if you place the
// file at a different tier.
import Icon from '../../../runtime/icon.tsx';

type TFn = (key: string, vars?: Record<string, unknown>) => unknown;

interface ActivityView {
  id: string;
  icon: string;
  label: string;
  href: string;
  active?: boolean;
}

interface ActivitySpec {
  label: string;
  views: ActivityView[];
  size?: 's' | 'm' | 'l';
  sizeHref?: string;
  panelSizePx?: number;
}

export const ActivityLabel: FC<{ spec: ActivitySpec }> = ({ spec }) => (
  <strong class="panel-label">{spec.label}</strong>
);

export const ActivityViews: FC<{ spec: ActivitySpec; t: TFn }> = ({ spec, t }) => (
  <nav class="panel-views" aria-label={t('panel.activity.views') as string}>
    {spec.views.map((v) => (
      <a
        class={`panel-views-icon${v.active ? ' is-active' : ''}`}
        href={v.href}
        hx-get={v.href}
        hx-target="#panel-activity-body"
        hx-swap="innerHTML"
        hx-push-url="false"
        title={v.label}
        aria-label={v.label}
        key={v.id}
      >
        <Icon name={v.icon} size={18} />
      </a>
    ))}
  </nav>
);

export const ActivityTop: FC<{ spec: ActivitySpec; oob?: boolean }> = ({ spec, oob }) => (
  <header class="panel-top" id="panel-activity-top" hx-swap-oob={oob ? 'outerHTML' : undefined}>
    <ActivityLabel spec={spec} />
  </header>
);

export const ActivityBottom: FC<{ spec: ActivitySpec; oob?: boolean; t: TFn }> = ({ spec, oob, t }) => (
  <footer class="panel-bottom" id="panel-activity-bottom" hx-swap-oob={oob ? 'outerHTML' : undefined}>
    <ActivityViews spec={spec} t={t} />
  </footer>
);

interface ActivityFrameProps {
  spec: ActivitySpec;
  t: TFn;
  children?: Child;
}

export const ActivityFrame: FC<ActivityFrameProps> = ({ spec, t, children }) => (
  <section
    class={`panel panel-activity${spec.panelSizePx ? '' : ` panel-size-${spec.size ?? 's'}`}`}
    id="panel-activity"
    style={spec.panelSizePx ? `width:${spec.panelSizePx}px` : undefined}
  >
    {spec.sizeHref && (
      <div
        class="panel-resize"
        data-target="panel-activity"
        data-edge="start"
        data-persist="activity"
        title={t('panel.resize') as string}
        aria-label={t('panel.resize') as string}
      ></div>
    )}
    <ActivityTop spec={spec} />
    <div class="panel-body" id="panel-activity-body">
      {children}
    </div>
    <ActivityBottom spec={spec} t={t} />
  </section>
);
