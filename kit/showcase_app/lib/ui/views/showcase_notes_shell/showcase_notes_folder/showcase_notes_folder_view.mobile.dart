import 'dart:async';
import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:appbox_kit_motion/appbox_kit_motion.dart';
import 'package:ui_library/ui_library.dart';
import 'package:appbox_kit_showcase_app/notes/models/note.dart';
import 'package:appbox_kit_showcase_app/ui/common/showcase_tabs_shared.dart';
import 'showcase_notes_folder_viewmodel.dart';
import '../showcase_note_editor/showcase_note_editor_viewmodel.dart';
import 'package:appbox_kit_showcase_app/ui/common/showcase_notes_shared.dart';

class ShowcaseNotesFolderViewMobile
    extends ViewModelWidget<ShowcaseNotesFolderViewModel> {
  const ShowcaseNotesFolderViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseNotesFolderViewModel viewModel) {
    final theme = Theme.of(context);
    final groups = viewModel.groups;

    final actions = [
      if (viewModel.isTrash)
        KitNativeIconButton(
          glyph: KitGlyphs.delete,
          color: theme.colorScheme.error,
          onPressed: () => _confirmEmptyTrash(context, viewModel),
        ),
    ];

    return Scaffold(
      // THE one app bar — KitNativeAppBar in Scaffold.appBar (never a sliver,
      // never a stock AppBar) — with the explicit back button + (trash-only)
      // empty-trash action riding on it.
      appBar: KitNativeAppBar(
        title: viewModel.title,
        leading: KitNativeIconButton(
          glyph: KitGlyphs.back,
          onPressed: () => context.popRoute(),
        ),
        actions: actions,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        // top: false — the fixed app bar owns the status-bar inset;
        // bottom: false — host shell uses extendBody, so the list scrolls under
        // the floating tab bar; clearance lives in the trailing padding.
        top: false,
        bottom: false,
        // KitMotionScope establishes the choreography boundary — group rows
        // below register with .wake(order: i) and rise in on the shared
        // spec's stagger ramp (spec-owned tokens; no local durations).
        child: KitMotionScope(
          child: CustomScrollView(
            slivers: [
              // Pinned search — sticks under the bar while the list scrolls.
              // Trash view hides it (nothing to search).
              // .scrollOcclusion() satisfies pipeline check 1i; it is a no-op
              // for a pinned header (never covered ⇒ alpha stays 1) but keeps
              // the glass surface safe if this header ever loses `pinned`.
              if (!viewModel.isTrash)
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _PinnedSearchDelegate(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: kSize16, vertical: kSize8),
                      child: KitNativeSearchBar(
                        hint: 'Search',
                        onChanged: viewModel.setQuery,
                      ).scrollOcclusion(),
                    ),
                  ),
                ),
              if (groups.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: kSize80),
                      child: Text('No Notes'),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(kSize16, kSize8, kSize16,
                      kSize80 + MediaQuery.paddingOf(context).bottom),
                  sliver: SliverList.builder(
                    itemCount: groups.length,
                    itemBuilder: (context, i) {
                      final group = groups[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: kSize16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ShowcaseSectionLabel(group.label),
                            verticalSpaceSmall,
                            // The kit's grouped-inset section owns the group
                            // card + hairline dividers (replacing the app's
                            // hand-rolled NotesSection); margin zero — the
                            // enclosing SliverPadding already insets 16.
                            KitListSection(
                              margin: EdgeInsets.zero,
                              children: [
                                for (final note in group.notes)
                                  _NoteRow(
                                    key: ValueKey(note.id),
                                    note: note,
                                    viewModel: viewModel,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      )
                          // iOS 26 scroll edge effects (ADR 0010): the content
                          // softens where it slides under pinned chrome — the
                          // pinned search header is detected zero-config via
                          // getOffsetToReveal; the floating tab bar sits outside
                          // the scrollable, so it needs an explicit occlusion.
                          .scrollEdgeEffect()
                          .scrollEdgeEffect(
                            edge: KitScrollEdge.bottom,
                            occlusionPadding: kShowcaseTabBarBlockHeight,
                          )
                          // Lazy list: rows wake in build (≈viewport) order —
                          // acceptable here, groups are few and above the fold.
                          .wake(order: i);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
      floatingActionButton: viewModel.isTrash
          ? null
          : KitNativeFabMenu(
              glyph: KitGlyphs.add,
              items: const [
                KitMenuItem(label: 'New Note', glyph: KitGlyphs.compose),
                KitMenuItem(label: 'New Photo', glyph: KitGlyphs.camera),
                KitMenuItem(label: 'New Voice', glyph: KitGlyphs.mic),
              ],
              onSelect: (item) async {
                // ponytail: a module-level intent slot on the editor viewmodel
                // routes New Photo / New Voice to auto-open the camera / mic on
                // first load — avoids route query-param plumbing + codegen.
                final action = switch (item.label) {
                  'New Photo' => 'camera',
                  'New Voice' => 'mic',
                  _ => null,
                };
                final id = await viewModel.compose();
                if (id == null || !context.mounted) return;
                ShowcaseNoteEditorViewModel.pendingAction = action;
                // nested push — root stack must not grow
                unawaited(context.router.pushNamed('note/$id'));
              },
            ),
    );
  }
}

/// Pinned search-bar header. Min height keeps the bar tappable when collapsed;
/// max height gives it breathing room at the top of the scroll.
class _PinnedSearchDelegate extends SliverPersistentHeaderDelegate {
  _PinnedSearchDelegate({required this.child});
  final Widget child;

  static const _min = 56.0;
  static const _max = 72.0;

  @override
  double get minExtent => _min;
  @override
  double get maxExtent => _max;
  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SizedBox(height: _max, child: child),
    );
  }

  @override
  bool shouldRebuild(_PinnedSearchDelegate oldDelegate) =>
      child != oldDelegate.child;
}

Future<void> _confirmEmptyTrash(
    BuildContext context, ShowcaseNotesFolderViewModel viewModel) async {
  if (await confirmDialog(context,
      title: 'Empty Recently Deleted',
      message: 'Notes will be permanently deleted. This cannot be undone.',
      actionLabel: 'Delete All',
      destructive: true)) {
    await viewModel.emptyTrash();
  }
}

Future<void> _confirmDeletePermanently(BuildContext context,
    ShowcaseNotesFolderViewModel viewModel, Note note) async {
  if (await confirmDialog(context,
      title: 'Delete Note',
      message: 'This note will be permanently deleted.',
      actionLabel: 'Delete',
      destructive: true)) {
    await viewModel.deletePermanently(note);
  }
}

/// Today → time ('9:41'), Yesterday → 'Yesterday', else 'dd/MM/yy'.
// ponytail: 24-hour clock, no am/pm — matches the brief's example digits
// without pulling in intl for a single label.
String _relativeDate(DateTime updatedAt) {
  final local = updatedAt.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final daysAgo = today.difference(day).inDays;
  if (daysAgo <= 0) {
    return '${local.hour}:${local.minute.toString().padLeft(2, '0')}';
  }
  if (daysAgo == 1) return 'Yesterday';
  final dd = local.day.toString().padLeft(2, '0');
  final mm = local.month.toString().padLeft(2, '0');
  final yy = (local.year % 100).toString().padLeft(2, '0');
  return '$dd/$mm/$yy';
}

/// One note row: swipe actions differ by scope (trash vs. live folder), tap
/// always opens the editor. `confirmDismiss` always returns false — the
/// stream rebuild moves/removes the row once the mutation lands.
class _NoteRow extends StatelessWidget {
  const _NoteRow({super.key, required this.note, required this.viewModel});

  final Note note;
  final ShowcaseNotesFolderViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTrash = viewModel.isTrash;

    return Dismissible(
      key: ValueKey(note.id),
      direction: DismissDirection.horizontal,
      background: Container(
        color: isTrash ? theme.colorScheme.tertiary : theme.colorScheme.primary,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: kSize20),
        child: Icon(
          isTrash
              ? KitGlyphs.restore.icon
              : (note.pinned ? KitGlyphs.unpin.icon : KitGlyphs.pin.icon),
          color: isTrash
              ? theme.colorScheme.onTertiary
              : theme.colorScheme.onPrimary,
        ),
      ),
      secondaryBackground: Container(
        color: theme.colorScheme.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: kSize20),
        child: Icon(KitGlyphs.delete.icon, color: theme.colorScheme.onError),
      ),
      confirmDismiss: (direction) async {
        if (isTrash) {
          if (direction == DismissDirection.endToStart) {
            await _confirmDeletePermanently(context, viewModel, note);
          } else {
            await viewModel.restore(note);
          }
        } else {
          if (direction == DismissDirection.endToStart) {
            await viewModel.moveToTrash(note);
          } else {
            await viewModel.togglePin(note);
          }
        }
        return false;
      },
      child: InkWell(
        onTap: () => context.router.pushNamed('note/${note.id}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: kSize16, vertical: kSize12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      note.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (note.pinned) ...[
                    horizontalSpaceTiny,
                    Icon(KitGlyphs.pin.icon,
                        size: kSize14, color: theme.colorScheme.primary),
                  ],
                ],
              ),
              verticalSpaceTiny,
              Text(
                '${_relativeDate(note.updatedAt)}  ${note.snippet}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
