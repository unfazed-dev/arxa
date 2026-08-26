import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../arxa_kit_map_provider.dart';
import '../models/arxa_kit_map_config.dart';

/// Plugin-neutral map widget.
///
/// Resolves a [ArxaKitMapProvider] per platform ([arxaKitDefaultProviderFor]) unless an
/// explicit [provider] is given (tests inject a fake; apps can force a
/// backend). App code renders `ArxaKitMapView(config: ...)` and never touches a
/// map SDK type.
class ArxaKitMapView extends StatelessWidget {
  const ArxaKitMapView({
    super.key,
    required this.config,
    this.provider,
    this.onMapCreated,
  });

  final ArxaKitMapConfig config;

  /// Override backend selection; defaults to
  /// `arxaKitDefaultProviderFor(defaultTargetPlatform)`.
  final ArxaKitMapProvider? provider;

  final ArxaKitMapCreatedCallback? onMapCreated;

  @override
  Widget build(BuildContext context) {
    final resolved = provider ?? arxaKitDefaultProviderFor(defaultTargetPlatform);
    return resolved.buildMap(config: config, onMapCreated: onMapCreated);
  }
}
