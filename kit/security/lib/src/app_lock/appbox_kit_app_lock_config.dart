import 'package:flutter/foundation.dart';

/// Tuning for [AppBoxKitAppLockController].
@immutable
class AppBoxKitAppLockConfig {
  const AppBoxKitAppLockConfig({
    this.lockOnBackgroundAfter = const Duration(seconds: 30),
    this.maxAttempts = 3,
    this.cooldown = const Duration(seconds: 30),
    this.unlockReason = 'Unlock to continue',
  }) : assert(maxAttempts >= 1, 'maxAttempts must be at least 1');

  /// How long the app may be backgrounded before it re-locks on return.
  ///
  /// [Duration.zero] locks on any backgrounding.
  final Duration lockOnBackgroundAfter;

  /// Failed attempts (per method) tolerated before the fallback kicks in:
  /// after this many biometric failures the biometric path is locked out and
  /// only the PIN is offered; after this many PIN failures a [cooldown] starts.
  final int maxAttempts;

  /// How long PIN entry is refused after [maxAttempts] failed PIN attempts.
  final Duration cooldown;

  /// Default localized reason shown in the biometric prompt.
  final String unlockReason;

  AppBoxKitAppLockConfig copyWith({
    Duration? lockOnBackgroundAfter,
    int? maxAttempts,
    Duration? cooldown,
    String? unlockReason,
  }) =>
      AppBoxKitAppLockConfig(
        lockOnBackgroundAfter:
            lockOnBackgroundAfter ?? this.lockOnBackgroundAfter,
        maxAttempts: maxAttempts ?? this.maxAttempts,
        cooldown: cooldown ?? this.cooldown,
        unlockReason: unlockReason ?? this.unlockReason,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppBoxKitAppLockConfig &&
          runtimeType == other.runtimeType &&
          lockOnBackgroundAfter == other.lockOnBackgroundAfter &&
          maxAttempts == other.maxAttempts &&
          cooldown == other.cooldown &&
          unlockReason == other.unlockReason;

  @override
  int get hashCode =>
      Object.hash(lockOnBackgroundAfter, maxAttempts, cooldown, unlockReason);

  @override
  String toString() =>
      'AppBoxKitAppLockConfig(lockOnBackgroundAfter: $lockOnBackgroundAfter, '
      'maxAttempts: $maxAttempts, cooldown: $cooldown)';
}
