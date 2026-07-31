import 'dart:io';

import 'package:appbox_kit_deploy/appbox_kit_deploy.dart';

/// Minimal CLI:
///   `dart run appbox_kit_deploy doctor --project-name=NAME`
///   `dart run appbox_kit_deploy deploy TARGET --project-name=NAME`
Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    _usage();
    exitCode = 64;
    return;
  }

  String option(String name, String fallback) {
    final prefix = '--$name=';
    return args
        .firstWhere((a) => a.startsWith(prefix), orElse: () => '$prefix$fallback')
        .substring(prefix.length);
  }

  const runner = IoProcessRunner();
  final service = KitDeployService(targets: [
    const FastlaneTarget(runner, platform: 'android'),
    const FastlaneTarget(runner, platform: 'ios'),
    const ShorebirdTarget(runner, mode: ShorebirdMode.release),
    const ShorebirdTarget(runner, mode: ShorebirdMode.patch),
    const CloudflarePagesTarget(runner),
    const VercelTarget(runner),
  ]);

  final config = KitDeployConfig(
    projectName: option('project-name', 'app'),
    workingDirectory: Directory.current.path,
    releaseVersion: args.any((a) => a.startsWith('--release-version='))
        ? option('release-version', '')
        : null,
    flutterVersion: args.any((a) => a.startsWith('--flutter-version='))
        ? option('flutter-version', '')
        : null,
    environment: Platform.environment,
  );

  switch (args.first) {
    case 'doctor':
      final report = await service.doctor(config);
      report.forEach((target, checks) {
        stdout.writeln(target);
        for (final check in checks) {
          stdout.writeln('  $check');
        }
      });
    case 'deploy' when args.length >= 2:
      final result = await service.deployTo(args[1], config);
      stdout.writeln(result);
      for (final command in result.commandsRun) {
        stdout.writeln('  \$ $command');
      }
      if (!result.ok) exitCode = 1;
    default:
      _usage();
      exitCode = 64;
  }
}

void _usage() {
  stderr.writeln('Usage:');
  stderr.writeln('  appbox_kit_deploy doctor [--project-name=<name>]');
  stderr.writeln(
    '  appbox_kit_deploy deploy <target> [--project-name=<name>] '
    '[--release-version=<v>] [--flutter-version=<v>]',
  );
}
