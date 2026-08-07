import 'dart:async';
import 'package:flutter/material.dart';
import 'package:appbox_kit_motion/appbox_kit_motion.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/common/showcase_tabs_shared/widgets.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/showcase_notes_widgets/widgets.dart';
import 'package:appbox_kit_showcase_app/data/models/showcase_notes_models/models.dart';
import 'package:appbox_kit_showcase_app/enums/showcase_notes_enums/enums.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_folder/showcase_notes_folder_viewmodel.dart';

class ShowcaseNotesFolderViewMobile
    extends ViewModelWidget<ShowcaseNotesFolderViewModel> {
  const ShowcaseNotesFolderViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseNotesFolderViewModel viewModel) {
    final theme = Theme.of(context);

    final actions = [
      if (viewModel.isTrash)
        AppBoxKitNativeIconButton(
          glyph: AppBoxKitGlyphs.delete,
          color: theme.colorScheme.error,
          onPressed: viewModel.confirmEmptyTrash,
        ),
    ];

    // Streams-only: title$ feeds the app bar (a rename lands in place),
    // groups$ feeds the list — the viewmodel holds no relay fields.
    return AppBoxKitStreamBuilder<String>(
      stream: viewModel.title$,
      builder: (context, title) => Scaffold(
        // THE one app bar — AppBoxKitNativeAppBar in Scaffold.appBar (never a sliver,
        // never a stock AppBar) — with the explicit back button + (trash-only)
        // empty-trash action riding on it.
        appBar: AppBoxKitNativeAppBar(
          title: title,
          leading: AppBoxKitNativeIconButton(
            glyph: AppBoxKitGlyphs.back,
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
          child: AppBoxKitStreamBuilder<List<ShowcaseNoteGroup>>(
            stream: viewModel.groups$,
            builder: (context, groups) =>
                // AppBoxKitMotionScope establishes the choreography boundary — group
                // rows below register with .wake(order: i) and rise in on the
                // shared spec's stagger ramp (spec-owned tokens; no local
                // durations).
                AppBoxKitMotionScope(
              child: CustomScrollView(
                slivers: [
                  // Pinned search — sticks under the bar while the list scrolls.
                  // Trash view hides it (nothing to search).
                  // .scrollOcclusion() satisfies pipeline check 1i; it is a no-op
                  // for a pinned header (never covered ⇒ alpha stays 1) but keeps
                  // the glass surface safe if this header ever loses `pinned`.
                  if (!viewModel.isTrash)
                    ShowcaseNotesPinnedSearchBarWidget(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: abxSize16, vertical: abxSize8),
                        child: AppBoxKitNativeSearchBar(
                          hint: 'Search',
                          onChanged: viewModel.setQuery,
                        ).scrollOcclusion(),
                      ),
                    ),
                  if (groups.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: abxSize80),
                          child: Text('No Notes'),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(abxSize16, abxSize8, abxSize16,
                          abxSize80 + MediaQuery.paddingOf(context).bottom),
                      sliver: SliverList.builder(
                        itemCount: groups.length,
                        itemBuilder: (context, i) {
                          final group = groups[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: abxSize16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ShowcaseSectionLabelWidget(group.label),
                                appBoxKitVerticalSpaceSmall,
                                // The kit's grouped-inset section owns the group
                                // card + hairline dividers (replacing the app's
                                // hand-rolled NotesSection); margin zero — the
                                // enclosing SliverPadding already insets 16.
                                AppBoxKitListSection(
                                  margin: EdgeInsets.zero,
                                  children: [
                                    for (final note in group.notes)
                                      ShowcaseNotesNoteRowWidget(
                                        key: ValueKey(note.id),
                                        note: note,
                                        viewModel: viewModel,
                                        onDeletePermanently: () => viewModel
                                            .confirmDeletePermanently(note),
                                        formatDate: _relativeDate,
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
                                edge: AppBoxKitScrollEdge.bottom,
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
        ),
        floatingActionButton: viewModel.isTrash
            ? null
            : AppBoxKitNativeFabMenu(
                glyph: AppBoxKitGlyphs.add,
                items: [
                  const AppBoxKitMenuItem(
                      label: 'New Note', glyph: AppBoxKitGlyphs.compose),
                  for (final action in ShowcaseQuickAction.values)
                    AppBoxKitMenuItem(
                      label: action.label,
                      glyph: switch (action) {
                        ShowcaseQuickAction.camera => AppBoxKitGlyphs.camera,
                        ShowcaseQuickAction.mic => AppBoxKitGlyphs.mic,
                      },
                    ),
                ],
                onSelect: (item) async {
                  ShowcaseQuickAction? action;
                  for (final a in ShowcaseQuickAction.values) {
                    if (a.label == item.label) action = a;
                  }
                  final id = await viewModel.compose();
                  if (id == null || !context.mounted) return;
                  // nested push — root stack must not grow
                  unawaited(context.router.pushNamed(action == null
                      ? 'note/$id'
                      : 'note/$id?quickAction=${action.name}'));
                },
              ),
      ),
    );
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
