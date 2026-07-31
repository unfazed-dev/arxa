/// Everything a [KitDeployTarget] needs to run one deployment.
class KitDeployConfig {
  const KitDeployConfig({
    required this.projectName,
    this.workingDirectory,
    this.releaseVersion,
    this.patchNumber,
    this.flutterVersion,
    this.dartDefines = const <String, String>{},
    this.environment = const <String, String>{},
  });

  /// Human/platform project identifier (e.g. Cloudflare Pages project name).
  final String projectName;

  /// Directory commands run in; null = current directory.
  final String? workingDirectory;

  /// Marketing version being released/patched (e.g. `1.2.0+45`).
  final String? releaseVersion;

  /// Shorebird patch number, when patching an existing release.
  final int? patchNumber;

  /// Pinned Flutter version for reproducible shorebird releases.
  final String? flutterVersion;

  /// Compile-time defines forwarded as `--dart-define=K=V`.
  final Map<String, String> dartDefines;

  /// Extra environment variables for the spawned processes
  /// (e.g. CLOUDFLARE_API_TOKEN).
  final Map<String, String> environment;

  /// `--dart-define` args in stable insertion order.
  List<String> get dartDefineArgs => [
        for (final entry in dartDefines.entries)
          '--dart-define=${entry.key}=${entry.value}',
      ];
}
