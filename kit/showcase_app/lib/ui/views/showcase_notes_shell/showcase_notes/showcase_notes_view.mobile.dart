import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:appbox_kit_motion/appbox_kit_motion.dart';
import 'package:ui_library/ui_library.dart';
import 'package:appbox_kit_showcase_app/notes/models/note_folder.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_auth/showcase_notes_auth_view.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_create_account/showcase_notes_create_account_view.dart';
import 'package:appbox_kit_showcase_app/ui/common/showcase_notes_shared.dart';
import 'package:appbox_kit_showcase_app/ui/common/showcase_tabs_shared.dart';
import 'showcase_notes_viewmodel.dart';

class ShowcaseNotesViewMobile extends ViewModelWidget<ShowcaseNotesViewModel> {
  const ShowcaseNotesViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseNotesViewModel viewModel) {
    final theme = Theme.of(context);
    final session = viewModel.session;

    // Signed out: the tab root IS the auth surface — no gate card, no route
    // push. The session stream swaps this for the Folders list in place. The
    // create-account panel is the same in-place swap, owned by the VM so the
    // choice survives the transient views rebuilding.
    if (session == null) {
      if (viewModel.showCreateAccount) {
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
    }

    final overview = viewModel.overview;

    return Scaffold(
      // THE one app bar — KitNativeAppBar in Scaffold.appBar (never a sliver,
      // never a stock AppBar) — with the new-folder + overflow actions on it.
      appBar: KitNativeAppBar(
        title: 'Folders',
        actions: [
          KitNativeIconButton(
            glyph: KitGlyphs.newFolder,
            onPressed: () => _showNewFolderDialog(context, viewModel),
          ),
          KitNativePopupMenu(
            glyph: KitGlyphs.more,
            items: const [
              KitMenuItem(
                label: 'Sign Out',
                glyph: KitGlyphs.signOut,
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
        // KitMotionScope establishes the choreography boundary — sections
        // below register with .wake(order: n) and rise in on the shared
        // spec's stagger ramp (spec-owned tokens; no local durations).
        child: KitMotionScope(
          child: CustomScrollView(
            slivers: [
              // Account subtitle — a thin sliver at the top of the list.
              if (overview != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: kSize16, vertical: kSize4),
                    child: Text(
                      session.user.displayName ?? session.user.email ?? '',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ),
              if (overview == null)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: kSize32),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else
                ..._foldersSlivers(context, viewModel),
              // Clearance so the last row can scroll out from under the
              // floating tab bar (viewport itself extends behind it).
              SliverToBoxAdapter(
                child: SizedBox(height: MediaQuery.paddingOf(context).bottom),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build the three sections (All Notes / user folders / Recently Deleted) as
  /// slivers that stagger in. Each section is a SliverToBoxAdapter holding a
  /// [KitListSection]; the stagger index counts sections, not rows, so the rhythm
  /// reads as one rise per group. The VM is the single source — overview is
  /// accessed through it, never re-typed here.
  ///
  /// The rise-in (`.wake()`) is applied to the [KitListSection] BOX inside the
  /// `SliverToBoxAdapter`, never to the sliver itself — `KitWake` choreographs
  /// box children only (it inserts box render-objects), so waking a
  /// `SliverPadding` would hand the Viewport a non-sliver child and trip
  /// "RenderViewport expected a RenderSliver". Waking the inner box preserves
  /// the staggered rise-in while keeping the sliver protocol intact.
  List<Widget> _foldersSlivers(
    BuildContext context,
    ShowcaseNotesViewModel viewModel,
  ) {
    final theme = Theme.of(context);
    final overview = viewModel.overview!;
    final admin = viewModel.adminOverview;

    Widget allNotesSection() => KitListSection(
          margin: EdgeInsets.zero,
          children: [
            _Row(
              glyph: KitGlyphs.notes,
              label: 'All Notes',
              trailingCount: overview.allCount,
              onTap: () => context.router.pushNamed('folder/all'),
            ),
          ],
        );

    Widget foldersSection() => KitListSection(
          margin: EdgeInsets.zero,
          children: [
            for (final folder in overview.folders)
              _FolderRow(
                folder: folder,
                count: overview.liveCountByFolder[folder.id] ?? 0,
                viewModel: viewModel,
              ),
          ],
        );

    Widget trashSection() => KitListSection(
          margin: EdgeInsets.zero,
          children: [
            _Row(
              glyph: KitGlyphs.delete,
              label: 'Recently Deleted',
              trailingCount: overview.trashCount,
              onTap: () => context.router.pushNamed('folder/trash'),
            ),
          ],
        );

    /// Wraps a [KitListSection] box in the bottom scroll edge effect (ADR
    /// 0010: content softens where it slides under the floating tab bar —
    /// external to the scrollable, so the occlusion is explicit; no top edge,
    /// the fixed app bar never underlaps this scrollable), then in a
    /// staggered rise-in (`.wake`), then in the sliver padding that positions
    /// it. Waking the box (not the sliver) is what keeps the viewport happy —
    /// see the method doc. Timing/stagger come from the enclosing
    /// [KitMotionScope]'s spec, not local tokens.
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
                  edge: KitScrollEdge.bottom,
                  occlusionPadding: kShowcaseTabBarBlockHeight,
                )
                .wake(order: index),
          ),
        );

    // Admin-only: every folder across every owner, read-only. Rendered as one
    // more grouped section in the same stagger ramp — presence of the data
    // (adminOverview != null) is the only gate, the view adds no role logic.
    Widget adminSection() => KitListSection(
          margin: EdgeInsets.zero,
          children: [
            for (final folder in admin!.folders)
              _AdminFolderRow(
                folder: folder,
                count: admin.liveCountByFolder[folder.id] ?? 0,
              ),
          ],
        );

    final trashIndex = overview.folders.isNotEmpty ? 2 : 1;
    final slivers = <Widget>[
      staggeredSliver(
        padding: const EdgeInsets.fromLTRB(kSize16, kSize12, kSize16, kSize4),
        section: allNotesSection(),
        index: 0,
      ),
      if (overview.folders.isNotEmpty)
        staggeredSliver(
          padding:
              const EdgeInsets.symmetric(horizontal: kSize16, vertical: kSize4),
          section: foldersSection(),
          index: 1,
        ),
      staggeredSliver(
        padding: admin == null
            ? const EdgeInsets.fromLTRB(kSize16, kSize4, kSize16, kSize80)
            : const EdgeInsets.symmetric(horizontal: kSize16, vertical: kSize4),
        section: trashSection(),
        index: trashIndex,
      ),
      if (admin != null) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding:
                const EdgeInsets.fromLTRB(kSize16, kSize12, kSize16, kSize4),
            child: Text(
              'All users (admin)',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ),
        staggeredSliver(
          padding: const EdgeInsets.fromLTRB(kSize16, kSize4, kSize16, kSize80),
          section: adminSection(),
          index: trashIndex + 1,
        ),
      ],
    ];
    return slivers;
  }
}

Future<void> _showNewFolderDialog(
    BuildContext context, ShowcaseNotesViewModel viewModel) async {
  final name =
      await textInputDialog(context, title: 'New Folder', hint: 'Name');
  if (name != null) await viewModel.createFolder(name);
}

Future<void> _showRenameDialog(BuildContext context,
    ShowcaseNotesViewModel viewModel, NoteFolder folder) async {
  final name = await textInputDialog(context,
      title: 'Rename Folder', initial: folder.name);
  if (name != null) await viewModel.renameFolder(folder, name);
}

/// A single tappable folder-list row: glyph, label, trailing count, chevron.
/// A thin adapter over [KitListTile] (the kit's grouped-list row idiom) so
/// call sites keep passing the count as an int.
class _Row extends StatelessWidget {
  const _Row({
    required this.glyph,
    required this.label,
    required this.trailingCount,
    required this.onTap,
  });

  final KitGlyph glyph;
  final String label;
  final int trailingCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => KitListTile(
        glyph: glyph,
        title: label,
        trailingValue: '$trailingCount',
        showChevron: true,
        onTap: onTap,
      );
}

/// Admin-section row: folder name + owner id subtitle + live count. Read-only
/// by design — folder detail streams are owner-scoped, so navigating into
/// another user's folder would show an empty list and read as a bug. The
/// section demonstrates role-gated *visibility*, nothing more.
class _AdminFolderRow extends StatelessWidget {
  const _AdminFolderRow({required this.folder, required this.count});

  final NoteFolder folder;
  final int count;

  @override
  Widget build(BuildContext context) => KitListTile(
        glyph: KitGlyphs.folder,
        title: folder.name,
        subtitle: folder.owner,
        trailingValue: '$count',
      );
}

/// A folder row: swipe-to-delete (confirmed), long-press-to-rename, tap to
/// open. `confirmDismiss` always returns false — the section rebuilds off
/// [ShowcaseNotesViewModel.overview]'s stream once the mutation lands, so the
/// Dismissible never needs to remove the row itself.
class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.folder,
    required this.count,
    required this.viewModel,
  });

  final NoteFolder folder;
  final int count;
  final ShowcaseNotesViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dismissible(
      key: ValueKey(folder.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: theme.colorScheme.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: kSize20),
        child: Icon(KitGlyphs.delete.icon, color: theme.colorScheme.onError),
      ),
      confirmDismiss: (_) async {
        if (await confirmDialog(context,
            title: 'Delete Folder',
            message: 'Notes in "${folder.name}" will move to Recently Deleted.',
            actionLabel: 'Delete',
            destructive: true)) {
          await viewModel.deleteFolder(folder);
        }
        return false;
      },
      child: GestureDetector(
        onLongPress: () => _showRenameDialog(context, viewModel, folder),
        child: _Row(
          glyph: KitGlyphs.folder,
          label: folder.name,
          trailingCount: count,
          onTap: () => context.router.pushNamed('folder/${folder.id}'),
        ),
      ),
    );
  }
}
