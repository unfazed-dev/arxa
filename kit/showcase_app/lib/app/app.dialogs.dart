// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// **************************************************************************
// StackedDialogGenerator
// **************************************************************************

import 'package:stacked_services/stacked_services.dart';

import 'app.locator.dart';
import '../ui/dialogs/showcase_confirm_dialog/showcase_confirm_dialog.dart';
import '../ui/dialogs/showcase_info_alert_dialog/showcase_info_alert_dialog.dart';
import '../ui/dialogs/showcase_text_input_dialog/showcase_text_input_dialog.dart';

enum DialogType {
  showcaseInfoAlert,
  showcaseConfirm,
  showcaseTextInput,
}

void setupDialogUi() {
  final dialogService = locator<DialogService>();

  final Map<DialogType, DialogBuilder> builders = {
    DialogType.showcaseInfoAlert: (context, request, completer) =>
        ShowcaseInfoAlertDialog(request: request, completer: completer),
    DialogType.showcaseConfirm: (context, request, completer) =>
        ShowcaseConfirmDialog(request: request, completer: completer),
    DialogType.showcaseTextInput: (context, request, completer) =>
        ShowcaseTextInputDialog(request: request, completer: completer),
  };

  dialogService.registerCustomDialogBuilders(builders);
}
