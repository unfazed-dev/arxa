import 'dart:io';

/// Result of one external command, owned by appbox_kit_deploy.
class AppBoxKitProcessResult {
  const AppBoxKitProcessResult({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  bool get ok => exitCode == 0;

  @override
  String toString() => 'AppBoxKitProcessResult(exitCode: $exitCode)';
}

/// Port for running external CLIs (flutter, fastlane, shorebird, wrangler).
///
/// Targets depend on this interface only, so command shapes are asserted in
/// tests with ScriptedAppBoxKitProcessRunner and no real toolchain.
abstract interface class AppBoxKitProcessRunner {
  Future<AppBoxKitProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  });
}

/// Real runner backed by dart:io [Process.run].
class AppBoxKitIoProcessRunner implements AppBoxKitProcessRunner {
  const AppBoxKitIoProcessRunner();

  @override
  Future<AppBoxKitProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    try {
      final result = await Process.run(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        runInShell: true,
      );
      return AppBoxKitProcessResult(
        exitCode: result.exitCode,
        stdout: '${result.stdout}',
        stderr: '${result.stderr}',
      );
    } on ProcessException catch (e) {
      return AppBoxKitProcessResult(exitCode: 127, stderr: e.message);
    }
  }
}
