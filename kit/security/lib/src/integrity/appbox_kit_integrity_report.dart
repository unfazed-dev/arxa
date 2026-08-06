import 'package:flutter/foundation.dart';

import 'appbox_kit_tri_state.dart';

/// The typed result of [AppBoxKitDeviceIntegrityService.check]: a set of device-trust
/// signals, each a [AppBoxKitTriState].
///
/// Every field defaults to [AppBoxKitTriState.unknown] so a partial platform
/// implementation can report only what it can actually measure without
/// asserting a false [AppBoxKitTriState.no].
@immutable
class AppBoxKitIntegrityReport {
  const AppBoxKitIntegrityReport({
    this.jailbrokenOrRooted = AppBoxKitTriState.unknown,
    this.developerMode = AppBoxKitTriState.unknown,
    this.emulator = AppBoxKitTriState.unknown,
    this.debuggable = AppBoxKitTriState.unknown,
  });

  /// iOS jailbreak / Android root detected.
  final AppBoxKitTriState jailbrokenOrRooted;

  /// Developer mode / options are enabled.
  final AppBoxKitTriState developerMode;

  /// Running on an emulator / simulator rather than physical hardware.
  final AppBoxKitTriState emulator;

  /// The app is running in a debuggable build.
  final AppBoxKitTriState debuggable;

  /// A report with every signal [AppBoxKitTriState.unknown].
  static const unknown = AppBoxKitIntegrityReport();

  /// True when any signal is affirmatively [AppBoxKitTriState.yes].
  ///
  /// Deliberately conservative: an [AppBoxKitTriState.unknown] signal never counts as
  /// compromised (nor as clean) — callers decide how to treat uncertainty.
  bool get hasCompromiseSignal =>
      jailbrokenOrRooted == AppBoxKitTriState.yes ||
      developerMode == AppBoxKitTriState.yes ||
      emulator == AppBoxKitTriState.yes ||
      debuggable == AppBoxKitTriState.yes;

  AppBoxKitIntegrityReport copyWith({
    AppBoxKitTriState? jailbrokenOrRooted,
    AppBoxKitTriState? developerMode,
    AppBoxKitTriState? emulator,
    AppBoxKitTriState? debuggable,
  }) =>
      AppBoxKitIntegrityReport(
        jailbrokenOrRooted: jailbrokenOrRooted ?? this.jailbrokenOrRooted,
        developerMode: developerMode ?? this.developerMode,
        emulator: emulator ?? this.emulator,
        debuggable: debuggable ?? this.debuggable,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppBoxKitIntegrityReport &&
          runtimeType == other.runtimeType &&
          jailbrokenOrRooted == other.jailbrokenOrRooted &&
          developerMode == other.developerMode &&
          emulator == other.emulator &&
          debuggable == other.debuggable;

  @override
  int get hashCode => Object.hash(
        jailbrokenOrRooted,
        developerMode,
        emulator,
        debuggable,
      );

  @override
  String toString() => 'AppBoxKitIntegrityReport(jailbrokenOrRooted: '
      '${jailbrokenOrRooted.name}, developerMode: ${developerMode.name}, '
      'emulator: ${emulator.name}, debuggable: ${debuggable.name})';
}
