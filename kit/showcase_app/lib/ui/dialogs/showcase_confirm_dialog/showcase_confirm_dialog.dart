import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';
import 'package:ui_library/ui_library.dart';

import 'showcase_confirm_dialog_model.dart';

/// Adaptive cancel/confirm dialog. `title` and the optional `description`
/// ride on stacked's own [DialogRequest] fields; `data` is a record
/// `(actionLabel: String, destructive: bool)`. Confirm completes with
/// `DialogResponse(confirmed: true)`.
///
/// Was `confirmDialog()` in ui/common/showcase_notes_shared.dart — converted
/// to a registered DialogService dialog (dialogs live in ui/dialogs/).
/// Presentation mirrors kitShowNativeDialog's routing: stock M3 AlertDialog
/// on Android, the kit's [KitFrostedAlertDialog] (iOS 26 alert idiom)
/// elsewhere — embedded with popOnAction: false so the DialogService
/// completer owns dismissal.
class ShowcaseConfirmDialog extends StackedView<ShowcaseConfirmDialogModel> {
  final DialogRequest request;
  final Function(DialogResponse) completer;

  const ShowcaseConfirmDialog({
    super.key,
    required this.request,
    required this.completer,
  });

  @override
  Widget builder(
    BuildContext context,
    ShowcaseConfirmDialogModel viewModel,
    Widget? child,
  ) {
    final params = request.data as ({String actionLabel, bool destructive});
    void done(bool confirmed) =>
        completer(DialogResponse(confirmed: confirmed));

    if (!KitPlatform.supportsComposeM3E) {
      return KitFrostedAlertDialog<bool>(
        title: request.title ?? '',
        message: request.description,
        popOnAction: false,
        actions: [
          KitNativeDialogAction(
            label: 'Cancel',
            onPressed: () => done(false),
          ),
          KitNativeDialogAction(
            label: params.actionLabel,
            role: params.destructive
                ? KitDialogActionRole.destructive
                : KitDialogActionRole.primary,
            onPressed: () => done(true),
          ),
        ],
      );
    }
    return AlertDialog(
      title: Text(request.title ?? ''),
      content: request.description == null
          ? null
          : Text(request.description!),
      actions: [
        TextButton(
          onPressed: () => done(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => done(true),
          style: params.destructive
              ? TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                )
              : null,
          child: Text(params.actionLabel),
        ),
      ],
    );
  }

  @override
  ShowcaseConfirmDialogModel viewModelBuilder(BuildContext context) =>
      ShowcaseConfirmDialogModel();
}
