import 'package:flutter/material.dart';
import 'package:appbox_kit_data/appbox_kit_data.dart' show AppBoxKitAuthSession;
import 'package:appbox_kit_motion/appbox_kit_motion.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_showcase_app/data/models/showcase_notes_models/models.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_auth/showcase_notes_auth_view.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_create_account/showcase_notes_create_account_view.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/common/showcase_tabs_shared/widgets.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/showcase_notes_widgets/widgets.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes/showcase_notes_viewmodel.dart';

class ShowcaseNotesViewMobile extends ViewModelWidget<ShowcaseNotesViewModel> {
  const ShowcaseNotesViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseNotesViewModel viewModel) {
    // Streams-only: every live value binds via AppBoxKitStreamBuilder — session
    // gates auth-vs-folders, showCreateAccount picks the signed-out panel,
    // overview/admin drive the list. The viewmodel holds no relay fields.
    return AppBoxKitStreamBuilder<AppBoxKitAuthSession?>(
      stream: viewModel.session$,
      builder: (context, session) {
        // Signed out: the tab root IS the auth surface — no gate card, no
        // route push. The session stream swaps this for the Folders list in
        // place. The create-account panel is the same in-place swap, owned by
        // the VM so the choice survives the transient views rebuilding.
        if (session == null) {
          return AppBoxKitStreamBuilder<bool>(
            stream: viewModel.showCreateAccount$,
            builder: (context, showCreateAccount) {
              if (showCreateAccount) {
                return Scaffold(
                  body: ShowcaseNotesCreateAccountView(
                    onBackToSignIn: viewModel.closeCreateAccount,
                  ),
                );
              }
              return Scaffold(
                body: ShowcaseNotesAuthView(
                  onCreateAccount: viewModel.openCreateAccount,
                ),
              );
            },
          );
        }

        return Scaffold(
          // THE one app bar — AppBoxKitNativeAppBar in Scaffold.appBar (never a sliver,
          // never a stock AppBar) — with the new-folder + overflow actions on it.
          appBar: AppBoxKitNativeAppBar(
            title: 'Folders',
            actions: [
              AppBoxKitNativeIconButton(
                glyph: AppBoxKitGlyphs.newFolder,
                onPressed: viewModel.createFolderWithPrompt,
              ),
              AppBoxKitNativePopupMenu(
                glyph: AppBoxKitGlyphs.more,
                items: const [
                  AppBoxKitMenuItem(
                    label: 'Sign Out',
                    glyph: AppBoxKitGlyphs.signOut,
                    isDestructive: true,
                  ),
                ],
                onSelect: (_) => viewModel.signOut(),
              ),
            ],
          ),
          body: SafeArea(
            // top: false — the fixed app bar owns the status-bar inset.
            //
            // bottom: false — the host shell uses extendBody, so the viewport must
            // extend behind the floating tab bar (content scrolls under the glass
            // pill). Clearance for the last row is added as a trailing sliver
            // instead of insetting the whole viewport (which produces a hard cut).
            top: false,
            bottom: false,
            child: AppBoxKitStreamBuilder<ShowcaseNotesOverview?>(
              stream: viewModel.overview$,
              builder: (context, overview) {
                if (overview == null) {
                  // Signed in, first overview emission pending.
                  return const Center(child: AppBoxKitNativeLoadingIndicator());
                }
                return AppBoxKitStreamBuilder<ShowcaseNotesAdminOverview?>(
                  stream: viewModel.adminOverview$,
                  builder: (context, admin) =>
                      _foldersScrollView(context, viewModel, session, overview, admin),
                );
              },
            ),
          ),
        );
      },
    );
  }

  /// The signed-in scroll view: grouped rounded sections mirroring iOS Notes'
  /// Folders list (All Notes / user folders / Recently Deleted / admin).
  /// AppBoxKitMotionScope establishes the choreography boundary — sections
  /// below register with .wake(order: n) and rise in on the shared
  /// spec's stagger ramp (spec-owned tokens; no local durations).
  Widget _foldersScrollView(
    BuildContext context,
    ShowcaseNotesViewModel viewModel,
    AppBoxKitAuthSession session,
    ShowcaseNotesOverview overview,
    ShowcaseNotesAdminOverview? admin,
  ) {
    final theme = Theme.of(context);
    return AppBoxKitMotionScope(
      child: CustomScrollView(
        slivers: [
          // Account subtitle — a thin sliver at the top of the list.
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: abxSize16, vertical: abxSize4),
              child: Text(
                session.user.displayName ?? session.user.email ?? '',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ),
          ..._foldersSlivers(context, viewModel, overview, admin),
          // Clearance so the last row can scroll out from under the
          // floating tab bar (viewport itself extends behind it).
          SliverToBoxAdapter(
            child: SizedBox(height: MediaQuery.paddingOf(context).bottom),
          ),
        ],
      ),
    );
  }

  /// Build the sections (All Notes / user folders / Recently Deleted / admin)
  /// as slivers that stagger in. Each section is a SliverToBoxAdapter holding a
  /// [AppBoxKitListSection]; the stagger index counts sections, not rows, so the rhythm
  /// reads as one rise per group. Data arrives as parameters from the
  /// [AppBoxKitStreamBuilder] bindings — never re-read off the viewmodel here.
  ///
  /// The rise-in (`.wake()`) is applied to the [AppBoxKitListSection] BOX inside the
  /// `SliverToBoxAdapter`, never to the sliver itself — `AppBoxKitWake` choreographs
  /// box children only (it inserts box render-objects), so waking a
  /// `SliverPadding` would hand the Viewport a non-sliver child and trip
  /// "RenderViewport expected a RenderSliver". Waking the inner box preserves
  /// the staggered rise-in while keeping the sliver protocol intact.
  List<Widget> _foldersSlivers(
    BuildContext context,
    ShowcaseNotesViewModel viewModel,
    ShowcaseNotesOverview overview,
    ShowcaseNotesAdminOverview? admin,
  ) {
    final theme = Theme.of(context);

    Widget allNotesSection() => AppBoxKitListSection(
          margin: EdgeInsets.zero,
          children: [
            ShowcaseNotesRowWidget(
              glyph: AppBoxKitGlyphs.notes,
              label: 'All Notes',
              trailingCount: overview.allCount,
              onTap: () => context.router.pushNamed('folder/all'),
            ),
          ],
        );

    Widget foldersSection() => AppBoxKitListSection(
          margin: EdgeInsets.zero,
          children: [
            for (final folder in overview.folders)
              ShowcaseNotesFolderRowWidget(
                folder: folder,
                count: overview.liveCountByFolder[folder.id] ?? 0,
                viewModel: viewModel,
                onRename: () => viewModel.renameFolderWithPrompt(folder),
              ),
          ],
        );

    Widget trashSection() => AppBoxKitListSection(
          margin: EdgeInsets.zero,
          children: [
            ShowcaseNotesRowWidget(
              glyph: AppBoxKitGlyphs.delete,
              label: 'Recently Deleted',
              trailingCount: overview.trashCount,
              onTap: () => context.router.pushNamed('folder/trash'),
            ),
          ],
        );

    /// Wraps a [AppBoxKitListSection] box in the bottom scroll edge effect (ADR
    /// 0010: content softens where it slides under the floating tab bar —
    /// external to the scrollable, so the occlusion is explicit; no top edge,
    /// the fixed app bar never underlaps this scrollable), then in a
    /// staggered rise-in (`.wake`), then in the sliver padding that positions
    /// it. Waking the box (not the sliver) is what keeps the viewport happy —
    /// see the method doc. Timing/stagger come from the enclosing
    /// [AppBoxKitMotionScope]'s spec, not local tokens.
    SliverPadding staggeredSliver({
      required EdgeInsetsGeometry padding,
      required Widget section,
      required int index,
    }) =>
        SliverPadding(
          padding: padding,
          sliver: SliverToBoxAdapter(
            child: section
                .scrollEdgeEffect(
                  edge: AppBoxKitScrollEdge.bottom,
                  occlusionPadding: kShowcaseTabBarBlockHeight,
                )
                .wake(order: index),
          ),
        );

    // Admin-only: every folder across every owner, read-only. Rendered as one
    // more grouped section in the same stagger ramp — presence of the data
    // (adminOverview != null) is the only gate, the view adds no role logic.
    Widget adminSection() => AppBoxKitListSection(
          margin: EdgeInsets.zero,
          children: [
            for (final folder in admin!.folders)
              ShowcaseNotesAdminFolderRowWidget(
                folder: folder,
                count: admin.liveCountByFolder[folder.id] ?? 0,
              ),
          ],
        );

    final trashIndex = overview.folders.isNotEmpty ? 2 : 1;
    final slivers = <Widget>[
      staggeredSliver(
        padding: const EdgeInsets.fromLTRB(abxSize16, abxSize12, abxSize16, abxSize4),
        section: allNotesSection(),
        index: 0,
      ),
      if (overview.folders.isNotEmpty)
        staggeredSliver(
          padding:
              const EdgeInsets.symmetric(horizontal: abxSize16, vertical: abxSize4),
          section: foldersSection(),
          index: 1,
        ),
      staggeredSliver(
        padding: admin == null
            ? const EdgeInsets.fromLTRB(abxSize16, abxSize4, abxSize16, abxSize80)
            : const EdgeInsets.symmetric(horizontal: abxSize16, vertical: abxSize4),
        section: trashSection(),
        index: trashIndex,
      ),
      if (admin != null) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding:
                const EdgeInsets.fromLTRB(abxSize16, abxSize12, abxSize16, abxSize4),
            child: Text(
              'All users (admin)',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ),
        staggeredSliver(
          padding: const EdgeInsets.fromLTRB(abxSize16, abxSize4, abxSize16, abxSize80),
          section: adminSection(),
          index: trashIndex + 1,
        ),
      ],
    ];
    return slivers;
  }
}

