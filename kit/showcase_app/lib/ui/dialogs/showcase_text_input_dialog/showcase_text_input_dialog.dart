import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

import 'showcase_text_input_dialog_model.dart';

/// Adaptive single-field text dialog. `title` rides on the [DialogRequest];
/// `data` is a record `(initial: String?, hint: String?)`. Save completes
/// with `DialogResponse(confirmed: true, data: trimmed)` — an empty/whitespace
/// entry completes `confirmed: false`, same as cancel.
///
/// Was `textInputDialog()` in ui/common/showcase_notes_shared.dart —
/// converted to a registered DialogService dialog (dialogs live in
/// ui/dialogs/). The field matches the alert's own chrome (CupertinoTextField
/// in a Cupertino alert / Material TextField in a Material one): a CN
/// platform-view field can mis-size inside a dialog overlay, so the native
/// tiering is done by the alert here, not AppBoxKitNativeTextField.
class ShowcaseTextInputDialog
    extends StackedView<ShowcaseTextInputDialogModel> {
  final DialogRequest request;
  final Function(DialogResponse) completer;

  const ShowcaseTextInputDialog({
    super.key,
    required this.request,
    required this.completer,
  });

  static bool _isCupertino(BuildContext context) {
    final platform = Theme.of(context).platform;
    return platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
  }

  @override
  Widget builder(
    BuildContext context,
    ShowcaseTextInputDialogModel viewModel,
    Widget? child,
  ) {
    final params = request.data as ({String? initial, String? hint});
    void save() {
      final trimmed = viewModel.controller.text.trim();
      completer(DialogResponse(confirmed: trimmed.isNotEmpty, data: trimmed));
    }

    return AlertDialog.adaptive(
      title: Text(request.title ?? ''),
      content: _isCupertino(context)
          ? Padding(
              padding: const EdgeInsets.only(top: 12),
              child: CupertinoTextField(
                controller: viewModel.controller,
                autofocus: true,
                placeholder: params.hint,
                onSubmitted: (_) => save(),
              ),
            )
          : TextField(
              controller: viewModel.controller,
              autofocus: true,
              decoration: InputDecoration(hintText: params.hint),
              onSubmitted: (_) => save(),
            ),
      actions: [
        _isCupertino(context)
            ? CupertinoDialogAction(
                onPressed: () => completer(DialogResponse(confirmed: false)),
                child: const Text('Cancel'),
              )
            : TextButton(
                onPressed: () => completer(DialogResponse(confirmed: false)),
                child: const Text('Cancel'),
              ),
        _isCupertino(context)
            ? CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: save,
                child: const Text('Save'),
              )
            : TextButton(
                onPressed: save,
                child: const Text('Save'),
              ),
      ],
    );
  }

  @override
  ShowcaseTextInputDialogModel viewModelBuilder(BuildContext context) =>
      ShowcaseTextInputDialogModel(
          (request.data as ({String? initial, String? hint})).initial);
}
