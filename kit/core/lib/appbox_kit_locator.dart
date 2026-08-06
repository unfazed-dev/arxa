// ponytail: the kit resolves services through the same StackedLocator singleton
// the host app's generated `locator` uses — both are
// StackedLocator.instance. This keeps the kit decoupled from
// any host's app.locator.dart, so it stays portable across Stacked apps;
// kit files import this and
// the existing `appBoxKitLocator<T>()` call sites work unchanged.
import 'package:stacked_shared/stacked_shared.dart';

final appBoxKitLocator = StackedLocator.instance;
