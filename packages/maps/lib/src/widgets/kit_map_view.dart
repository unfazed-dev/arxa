import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../kit_map_provider.dart';
import '../models/kit_map_config.dart';

/// Plugin-neutral map widget.
///
/// Resolves a [KitMapProvider] per platform ([defaultProviderFor]) unless an
/// explicit [provider] is given (tests inject a fake; apps can force a
/// backend). App code renders `KitMapView(config: ...)` and never touches a
/// map SDK type.
class KitMapView extends StatelessWidget {
  const KitMapView({
    super.key,
    required this.config,
    this.provider,
    this.onMapCreated,
  });

  final KitMapConfig config;

  /// Override backend selection; defaults to
  /// `defaultProviderFor(defaultTargetPlatform)`.
  final KitMapProvider? provider;

  final KitMapCreatedCallback? onMapCreated;

  @override
  Widget build(BuildContext context) {
    final resolved = provider ?? defaultProviderFor(defaultTargetPlatform);
    return resolved.buildMap(config: config, onMapCreated: onMapCreated);
  }
}
