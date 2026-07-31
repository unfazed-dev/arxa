/// One environment/tooling precondition checked by a target's doctor().
class KitDoctorCheck {
  const KitDoctorCheck({
    required this.name,
    required this.ok,
    this.detail = '',
  });

  final String name;
  final bool ok;
  final String detail;

  @override
  String toString() => '${ok ? 'PASS' : 'FAIL'} $name'
      '${detail.isEmpty ? '' : ' — $detail'}';
}

/// Outcome of one [KitDeployTarget.deploy] run.
class KitDeployResult {
  const KitDeployResult({
    required this.target,
    required this.ok,
    this.commandsRun = const <String>[],
    this.failureReason,
  });

  /// Target name that produced this result.
  final String target;

  final bool ok;

  /// Human-readable command lines executed, in order.
  final List<String> commandsRun;

  /// Populated when [ok] is false.
  final String? failureReason;

  @override
  String toString() => 'KitDeployResult($target: ${ok ? 'ok' : 'FAILED'}'
      '${failureReason == null ? '' : ' — $failureReason'})';
}
