import 'package:flutter/foundation.dart';

import 'arxa_kit_tri_state.dart';

/// The typed result of [ArxaKitDeviceIntegrityService.check]: a set of device-trust
/// signals, each a [ArxaKitTriState].
///
/// Every field defaults to [ArxaKitTriState.unknown] so a partial platform
/// implementation can report only what it can actually measure without
/// asserting a false [ArxaKitTriState.no].
@immutable
class ArxaKitIntegrityReport {
  const ArxaKitIntegrityReport({
    this.jailbrokenOrRooted = ArxaKitTriState.unknown,
    this.developerMode = ArxaKitTriState.unknown,
    this.emulator = ArxaKitTriState.unknown,
    this.debuggable = ArxaKitTriState.unknown,
  });

  /// iOS jailbreak / Android root detected.
  final ArxaKitTriState jailbrokenOrRooted;

  /// Developer mode / options are enabled.
  final ArxaKitTriState developerMode;

  /// Running on an emulator / simulator rather than physical hardware.
  final ArxaKitTriState emulator;

  /// The app is running in a debuggable build.
  final ArxaKitTriState debuggable;

  /// A report with every signal [ArxaKitTriState.unknown].
  static const unknown = ArxaKitIntegrityReport();

  /// True when any signal is affirmatively [ArxaKitTriState.yes].
  ///
  /// Deliberately conservative: an [ArxaKitTriState.unknown] signal never counts as
  /// compromised (nor as clean) — callers decide how to treat uncertainty.
  bool get hasCompromiseSignal =>
      jailbrokenOrRooted == ArxaKitTriState.yes ||
      developerMode == ArxaKitTriState.yes ||
      emulator == ArxaKitTriState.yes ||
      debuggable == ArxaKitTriState.yes;

  ArxaKitIntegrityReport copyWith({
    ArxaKitTriState? jailbrokenOrRooted,
    ArxaKitTriState? developerMode,
    ArxaKitTriState? emulator,
    ArxaKitTriState? debuggable,
  }) =>
      ArxaKitIntegrityReport(
        jailbrokenOrRooted: jailbrokenOrRooted ?? this.jailbrokenOrRooted,
        developerMode: developerMode ?? this.developerMode,
        emulator: emulator ?? this.emulator,
        debuggable: debuggable ?? this.debuggable,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArxaKitIntegrityReport &&
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
  String toString() => 'ArxaKitIntegrityReport(jailbrokenOrRooted: '
      '${jailbrokenOrRooted.name}, developerMode: ${developerMode.name}, '
      'emulator: ${emulator.name}, debuggable: ${debuggable.name})';
}
