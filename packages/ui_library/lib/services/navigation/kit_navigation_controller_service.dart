import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:appbox_kit_core/kit_locator.dart';
import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

class KitNavigationControllerService {
  final _routerService = locator<RouterService>();

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
