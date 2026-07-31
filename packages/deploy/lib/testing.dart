/// Test doubles for appbox_kit_deploy — import 'package:appbox_kit_deploy/testing.dart'.
library;

import 'src/process/kit_process_runner.dart';

/// Scripted [KitProcessRunner]: records every command as a single string
/// (`executable arg1 arg2 …`) in [commandsRun] and answers from [script]
/// by longest-matching command prefix. Unscripted commands succeed with
/// exit code 0.
class ScriptedProcessRunner implements KitProcessRunner {
  ScriptedProcessRunner({Map<String, KitProcessResult>? script})
      : script = script ?? <String, KitProcessResult>{};

  /// Command-prefix → result. E.g. `{'wrangler pages deploy':
  /// KitProcessResult(exitCode: 1, stderr: 'boom')}`.
  final Map<String, KitProcessResult> script;

  /// Full command lines, in invocation order.
  final List<String> commandsRun = <String>[];

  /// workingDirectory passed for each call, parallel to [commandsRun].
  final List<String?> workingDirectories = <String?>[];

  /// environment passed for each call, parallel to [commandsRun].
  final List<Map<String, String>?> environments = <Map<String, String>?>[];

  @override
  Future<KitProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final command = '$executable ${arguments.join(' ')}'.trim();
    commandsRun.add(command);
    workingDirectories.add(workingDirectory);
    environments.add(environment);

    String? bestPrefix;
    for (final prefix in script.keys) {
      if (command.startsWith(prefix) &&
          (bestPrefix == null || prefix.length > bestPrefix.length)) {
        bestPrefix = prefix;
      }
    }
    return bestPrefix == null
        ? const KitProcessResult(exitCode: 0)
        : script[bestPrefix]!;
  }
}
