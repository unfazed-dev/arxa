import 'dart:io';

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_showcase_app/data/models/showcase_notes_models/models.dart';
import 'package:appbox_kit_showcase_app/ui/common/app_colors.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_note_editor/showcase_note_editor_viewmodel.dart';

/// Horizontal strip of photo attachments; tap opens a fullscreen viewer,
/// long-press removes.
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
