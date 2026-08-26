// arxa:provenance
// generator: arxa  licence: free  project: 662368770980
// Built with arxa (free tier) — https://arxa.dev

// shared_anatomy.tsx — the showcase-anatomy shell frame for design views
// (Q13 parallel-run). Composition is byte-identical to the legacy shell: the
// only delta is the ratified inspect identity, stamped in the DOM at emit
// time so the inspector reads it instead of inferring it (see
// app-architecture.md "Every surface stamps its inspect identity").
//
// The wrappers use `display:contents` deliberately: they contribute identity
// attributes without contributing layout, so htmx swap targets, CSS and the
// dual-render probe's visual diff see the same tree as the legacy shell.
//
// Node vocabulary is CLOSED at registry v1.3.0 (two members, ratified):
// `anatomy:shell.surface` on the shell frame, `anatomy:view.body` on the
// view's own body subtree. The registry
// (skills/arxa-scaffolder/kind-resolution.registry.json#/anatomyNodes)
// is the authority — never add ids here without a registry version bump.
import type { FC } from 'hono/jsx';
import MainShellView from '../../main_shell_view.tsx';

export const ANATOMY_NODE_SHELL_SURFACE = 'anatomy:shell.surface';
export const ANATOMY_NODE_VIEW_BODY = 'anatomy:view.body';

/// The stamped triple as JSX-spreadable attributes. JS spells the third slot
/// `nodeId`; the DOM spelling is the ratified `data-inspect-*` prefix.
export const anatomyAttrs = (
  screenId: string,
  surfaceId: string,
  nodeId: string,
) => ({
  'data-inspect-screen': screenId,
  'data-inspect-surface': surfaceId,
  'data-inspect-node': nodeId,
});

export type AnatomyShellViewProps = {
  screenId: string;
  surfaceId: string;
  surface: unknown;
  // Everything else is passed through to MainShellView untouched.
  [key: string]: unknown;
};

/// The anatomy twin of MainShellView: same props, same composition, plus the
/// two stamped nodes — shell frame (`anatomy:shell.surface`) one level up,
/// view body (`anatomy:view.body`) directly around the surface content.
export const AnatomyShellView: FC<AnatomyShellViewProps> = ({
  screenId,
  surfaceId,
  surface,
  ...rest
}) => (
  <MainShellView
    {...(rest as any)}
    surface={
      <div
        style="display:contents"
        {...anatomyAttrs(screenId, surfaceId, ANATOMY_NODE_SHELL_SURFACE)}
      >
        <div
          style="display:contents"
          {...anatomyAttrs(screenId, surfaceId, ANATOMY_NODE_VIEW_BODY)}
        >
          {surface}
        </div>
      </div>
    }
  />
);
