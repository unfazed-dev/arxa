import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:appbox_studio/app/app.bottomsheets.dart';
import 'package:appbox_studio/app/app.dialogs.dart';
import 'package:appbox_studio/app/app.locator.dart';
import 'package:appbox_studio/app/app.router.dart';
import 'package:appbox_studio/l10n/app_localizations.dart';
import 'package:appbox_studio/services/l10n_service.dart';
import 'package:appbox_kit_i18n/appbox_kit_i18n.dart';
import 'package:url_strategy/url_strategy.dart';
import 'package:flutter_animate/flutter_animate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  setPathUrlStrategy();
  await setupLocator(stackedRouter: stackedRouter);
  // KitI18n needs async creation (shared_preferences store + persisted
  // override load), which the generated lazy singletons can't express — so
  // it's created and registered here, before runApp.
  final kitI18n = KitI18n(store: await SharedPreferencesKitLocaleStore.create());
  await kitI18n.load();
  locator.registerSingleton<KitI18n>(kitI18n);
  locator.registerSingleton<L10nService>(L10nService());
  setupDialogUi();
  setupBottomSheetUi();
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    final kitI18n = locator<KitI18n>();
    return ResponsiveApp(
      builder: (_) => ListenableBuilder(
        listenable: kitI18n,
        builder: (context, _) => MaterialApp.router(
          locale: kitI18n.locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerDelegate: stackedRouter.delegate(),
          routeInformationParser: stackedRouter.defaultRouteParser(),
          builder: (context, child) {
            // Viewmodels have no BuildContext — hand them the active strings.
            locator<L10nService>().l10n = AppLocalizations.of(context);
            return child ?? const SizedBox.shrink();
          },
        ),
      ),
    ).animate().fadeIn(
      delay: const Duration(milliseconds: 50),
      duration: const Duration(milliseconds: 400),
    );
  }
}
