import 'package:appbox/l10n/app_localizations.dart';

/// Holds the latest [AppLocalizations] so viewmodels (no BuildContext) can
/// reach translated strings. Assigned from the root MaterialApp builder.
class L10nService {
  late AppLocalizations l10n;
}
