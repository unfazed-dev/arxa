import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Appearance-sync timing trace, debug builds only. The device-only defect
/// this measures: a native view can present a commanded brightness seconds
/// late, non-deterministically, recovering on scroll
/// (docs/plans/native-glass-theme-lag-measured.md §10-11). A send/ack pair
/// per component per flip separates "Dart sent late / never" from "the
/// native handler ran but the pixels arrived late" — the ack completes when
/// the native handler returns, so no native log plumbing is needed. The
/// lines land in any `flutter run` console (and tools/watch_device.sh
/// captures them to a file). Silent in release.
void cnTrace(String component, String event) {
  if (kDebugMode) {
    debugPrint(
      'CNTrace $component $event t=${DateTime.now().millisecondsSinceEpoch}',
    );
  }
}

/// [MethodChannel.invokeMethod] of `setBrightness` with [cnTrace] timing
/// around it. Error semantics stay with the caller (await or catchError),
/// same as the raw call.
Future<void> cnTracedSetBrightness(
  MethodChannel channel,
  String component,
  bool isDark,
) async {
  cnTrace(component, 'send isDark=$isDark');
  try {
    await channel.invokeMethod('setBrightness', {'isDark': isDark});
  } finally {
    cnTrace(component, 'ack');
  }
}
