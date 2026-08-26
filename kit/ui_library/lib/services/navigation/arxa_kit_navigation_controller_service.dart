import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:arxa_kit_core/arxa_kit_locator.dart';
import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

class ArxaKitNavigationControllerService {
  final _routerService = arxaKitLocator<RouterService>();

  Future<void> navigate(
      {required BuildContext context,
      PageRouteInfo? viewRoute,
      Widget? view}) async {
    if (kIsWeb) {
      await _routerService.navigateTo(viewRoute!);
    } else {
      await Navigator.of(context).push(
        CupertinoPageRoute(
          builder: (context) => view!,
        ),
      );
    }
  }
}
