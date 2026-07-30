import 'package:appbox/app/app.bottomsheets.dart';
import 'package:appbox/app/app.dialogs.dart';
import 'package:appbox/app/app.locator.dart';
import 'package:appbox/l10n/app_localizations.dart';
import 'package:appbox/services/l10n_service.dart';
import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

class HomeViewModel extends BaseViewModel {
  final _dialogService = locator<DialogService>();
  final _bottomSheetService = locator<BottomSheetService>();

  // Viewmodels have no BuildContext — translated strings come from the
  // L10nService the root MaterialApp keeps current.
  AppLocalizations get _l10n => locator<L10nService>().l10n;

  String get counterLabel => _l10n.counterLabel(_counter);

  int _counter = 0;

  void incrementCounter() {
    _counter++;
    rebuildUi();
  }

  void showDialog() {
    _dialogService.showCustomDialog(
      variant: DialogType.infoAlert,
      title: _l10n.homeDialogTitle,
      description: _l10n.homeDialogDescription(_counter),
    );
  }

  void showBottomSheet() {
    _bottomSheetService.showCustomSheet(
      variant: BottomSheetType.notice,
      title: _l10n.homeBottomSheetTitle,
      description: _l10n.homeBottomSheetDescription,
    );
  }
}
