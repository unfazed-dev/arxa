import 'dart:io';

/// Result of one external command, owned by arxa_kit_deploy.
class ArxaKitProcessResult {
  const ArxaKitProcessResult({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  bool get ok => exitCode == 0;

  @override
  String toString() => 'ArxaKitProcessResult(exitCode: $exitCode)';
}

/// Port for running external CLIs (flutter, fastlane, shorebird, wrangler).
///
/// Targets depend on this interface only, so command shapes are asserted in
/// tests with ScriptedArxaKitProcessRunner and no real toolchain.
abstract interface class ArxaKitProcessRunner {
  Future<ArxaKitProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  });
}

/// Real runner backed by dart:io [Process.run].
class ArxaKitIoProcessRunner implements ArxaKitProcessRunner {
  const ArxaKitIoProcessRunner();

  @override
  Future<ArxaKitProcessResult> run(
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
      return ArxaKitProcessResult(
        exitCode: result.exitCode,
        stdout: '${result.stdout}',
        stderr: '${result.stderr}',
      );
    } on ProcessException catch (e) {
      return ArxaKitProcessResult(exitCode: 127, stderr: e.message);
    }
  }
}
