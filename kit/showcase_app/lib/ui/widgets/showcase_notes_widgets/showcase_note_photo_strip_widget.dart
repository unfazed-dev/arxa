/// A widget is a reusable UI piece composed by views. It receives data via
/// constructor params or [AppBoxKitStreamBuilder] bindings and renders its
/// slice of the surface — it holds no business logic and never decides when
/// an action runs.
///
/// This is the user interface for the horizontal photo-attachment strip — tap
/// opens a fullscreen viewer, long-press removes.
///
/// Requirements:
/// 1. [Photo display] — attach-a-photo-to-a-note
/// Attached photos render as a horizontal strip of thumbnails.
/// 2. [Remove photo] — attach-a-photo-to-a-note
/// Long-press confirms removal of a photo attachment.
///
/// Relationships:
///
///   ┌──────────────────────────────┐
///   │   note photo strip widget    │
///   └──────────────────────────────┘
///   ACT ▼
///   [1-2]
///   ┌──────────────────────────────┐
///   │    note editor viewmodel     │
///   └──────────────────────────────┘
///      ════════ abxAction ════════
///
///  actions (ACT)
///    1. resolvePath
///    2. confirmRemoveAttachment
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_notes_widgets/showcase_note_photo_strip_widget.dart
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_showcase_app/data/models/showcase_notes_models/models.dart';
import 'package:appbox_kit_showcase_app/ui/common/app_colors.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_note_editor/showcase_note_editor_viewmodel.dart';

class ShowcaseNotePhotoStripWidget extends StatelessWidget {
  const ShowcaseNotePhotoStripWidget({
    super.key,
    required this.viewModel,
    required this.photos,
  });
  final ShowcaseNoteEditorViewModel viewModel;
  final List<ShowcaseNoteAttachmentModel> photos;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 84,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: photos.length,
          separatorBuilder: (_, __) => appBoxKitHorizontalSpaceSmall,
          itemBuilder: (context, i) {
            final attachment = photos[i];
            return FutureBuilder<String>(
              future: viewModel.resolvePath(attachment),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const SizedBox(
                    width: 84,
                    height: 84,
                    child: Center(child: AppBoxKitNativeLoadingIndicator(size: 20)),
                  );
                }
                final file = File(snap.data!);
                return GestureDetector(
                  onTap: () => _openViewer(context, file),
                  onLongPress: () =>
                      viewModel.confirmRemoveAttachment(attachment),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(abxRad12),
                    child: Image.file(
                      file,
                      width: 84,
                      height: 84,
                      fit: BoxFit.cover,
                    ),
                  ),
                );
              },
            );
          },
        ),
      );

  void _openViewer(BuildContext context, File file) => showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          // ponytail: media lightboxes are always black regardless of theme —
          // a deliberate platform constant, not a theme leak.
          backgroundColor: kcBlack,
          insetPadding: EdgeInsets.zero,
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(child: Image.file(file)),
              ),
              Positioned(
                top: abxSize8,
                right: abxSize8,
                child: AppBoxKitNativeIconButton(
                  glyph: AppBoxKitGlyphs.close,
                  color: kcWhite,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      );
}
