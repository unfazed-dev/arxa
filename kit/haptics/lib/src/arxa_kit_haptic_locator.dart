// The kit resolves services through the same StackedLocator singleton the host
// app's generated `locator` uses — both are StackedLocator.instance. This keeps
// arxa_kit_haptics decoupled from any host's app.locator.dart (and from
// arxa_kit core), so it stays portable across Stacked apps; the extension
// imports this and the `arxaKitLocator<T>()` call sites work unchanged.
import 'package:stacked_shared/stacked_shared.dart';

final arxaKitLocator = StackedLocator.instance;
