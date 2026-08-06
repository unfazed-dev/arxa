import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../appbox_kit_map_provider.dart';
import '../models/appbox_kit_map_config.dart';

/// Plugin-neutral map widget.
///
/// Resolves a [AppBoxKitMapProvider] per platform ([appBoxKitDefaultProviderFor]) unless an
/// explicit [provider] is given (tests inject a fake; apps can force a
/// backend). App code renders `AppBoxKitMapView(config: ...)` and never touches a
/// map SDK type.
class AppBoxKitMapView extends StatelessWidget {
  const AppBoxKitMapView({
    super.key,
    required this.config,
    this.provider,
    this.onMapCreated,
  });

  final AppBoxKitMapConfig config;

  /// Override backend selection; defaults to
  /// `appBoxKitDefaultProviderFor(defaultTargetPlatform)`.
  final AppBoxKitMapProvider? provider;

  final AppBoxKitMapCreatedCallback? onMapCreated;

  @override
  Widget build(BuildContext context) {
    final resolved = provider ?? appBoxKitDefaultProviderFor(defaultTargetPlatform);
    return resolved.buildMap(config: config, onMapCreated: onMapCreated);
  }
}
