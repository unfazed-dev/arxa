import 'package:flutter/foundation.dart';

import 'kit_tri_state.dart';

/// The typed result of [KitDeviceIntegrityService.check]: a set of device-trust
/// signals, each a [KitTriState].
///
/// Every field defaults to [KitTriState.unknown] so a partial platform
/// implementation can report only what it can actually measure without
/// asserting a false [KitTriState.no].
@immutable
class KitIntegrityReport {
  const KitIntegrityReport({
    this.jailbrokenOrRooted = KitTriState.unknown,
    this.developerMode = KitTriState.unknown,
    this.emulator = KitTriState.unknown,
    this.debuggable = KitTriState.unknown,
  });

  /// iOS jailbreak / Android root detected.
  final KitTriState jailbrokenOrRooted;

  /// Developer mode / options are enabled.
  final KitTriState developerMode;

  /// Running on an emulator / simulator rather than physical hardware.
  final KitTriState emulator;

  /// The app is running in a debuggable build.
  final KitTriState debuggable;

  /// A report with every signal [KitTriState.unknown].
  static const unknown = KitIntegrityReport();

  /// True when any signal is affirmatively [KitTriState.yes].
  ///
  /// Deliberately conservative: an [KitTriState.unknown] signal never counts as
  /// compromised (nor as clean) — callers decide how to treat uncertainty.
  bool get hasCompromiseSignal =>
      jailbrokenOrRooted == KitTriState.yes ||
      developerMode == KitTriState.yes ||
      emulator == KitTriState.yes ||
      debuggable == KitTriState.yes;

  KitIntegrityReport copyWith({
    KitTriState? jailbrokenOrRooted,
    KitTriState? developerMode,
    KitTriState? emulator,
    KitTriState? debuggable,
  }) =>
      KitIntegrityReport(
        jailbrokenOrRooted: jailbrokenOrRooted ?? this.jailbrokenOrRooted,
        developerMode: developerMode ?? this.developerMode,
        emulator: emulator ?? this.emulator,
        debuggable: debuggable ?? this.debuggable,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KitIntegrityReport &&
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
  String toString() => 'KitIntegrityReport(jailbrokenOrRooted: '
      '${jailbrokenOrRooted.name}, developerMode: ${developerMode.name}, '
      'emulator: ${emulator.name}, debuggable: ${debuggable.name})';
}
