// appbox-lens — macOS native capture (ScreenCaptureKit one-shot).
//
// Thin ProcessRunner wrappers over a single Swift helper CLI
// (native/lens_native.swift) that this file compiles on demand. The helper is
// an external binary spawned through the daemon-wide ProcessRunner seam
// (lib/process.dart); tests inject a scripted fake so NO real ScreenCaptureKit
// grant and NO real capture are ever required. Plan: appbox-lens-full-port.md,
// Task 10.

library;

import 'dart:io';

import '../../process.dart';
import 'adb.dart';

/// Default Swift helper source, relative to the appboxd package root.
const String kLensNativeSource = 'native/lens_native.swift';

/// Default cache path for the compiled helper binary (repo-local, gitignored).
const String kLensNativeCache = '.dart_tool/appboxd/lens_native';

/// Ensures the macOS helper binary exists, compiling it on demand.
///
/// If [cache] is missing or older than [source], preflights `swiftc` then runs
/// `swiftc -O <source> -o <cache>` through [runner]. Returns the cache path.
/// A missing `swiftc` raises [LensNativeException] with the Xcode CLT
/// remediation; so does a failed compile. [source] / [cache] default to the
/// repo-relative constants above but may be overridden (tests use temp paths).
Future<String> ensureLensNativeBinary({
  ProcessRunner? runner,
  String source = kLensNativeSource,
  String cache = kLensNativeCache,
}) async {
  final r = runner ?? const RealProcessRunner();
  // Fresh cache beats the source -> reuse, no toolchain needed.
  if (File(cache).existsSync() &&
      File(source).existsSync() &&
      File(cache).statSync().modified.compareTo(File(source).statSync().modified) >= 0) {
    return cache;
  }
  final which = await r.run('which', ['swiftc']);
  if (which.exitCode != 0 || which.stdout.trim().isEmpty) {
    throw LensNativeException(
        'swiftc not found — install Xcode Command Line Tools: xcode-select --install');
  }
  File(cache).parent.createSync(recursive: true);
  final compile = await r.run('swiftc', ['-O', source, '-o', cache]);
  if (compile.exitCode != 0) {
    throw LensNativeException('swiftc compile failed: ${compile.stderr}');
  }
  return cache;
}

/// macOS ScreenCaptureKit capture verbs over the [ProcessRunner] seam. The
/// helper binary is resolved lazily (and compiled on first use) per instance.
class LensSck {
  LensSck({ProcessRunner? runner, String? source, String? cache})
      : _runner = runner ?? const RealProcessRunner(),
        _source = source ?? kLensNativeSource,
        _cache = cache ?? kLensNativeCache;

  final ProcessRunner _runner;
  final String _source;
  final String _cache;
  String? _bin;

  Future<String> _binary() async {
    return _bin ??= await ensureLensNativeBinary(
        runner: _runner, source: _source, cache: _cache);
  }

  /// Preflights the Screen Recording grant WITHOUT prompting. True when the
  /// terminal already has it.
  Future<bool> tccOk() async {
    final bin = await _binary();
    final r = await _runner.run(bin, ['tcc-check']);
    return r.exitCode == 0;
  }

  /// One-shot SCScreenshotManager capture to [outPng]. Preflights the Screen
  /// Recording grant first; a denied grant (helper `tcc-check` rc 3) raises
  /// [LensNativeException] with remediation. Pass [windowId] to capture a
  /// specific window, otherwise the first display is captured.
  Future<void> shot(String outPng, {int? windowId}) async {
    final bin = await _binary();
    final tcc = await _runner.run(bin, ['tcc-check']);
    if (tcc.exitCode != 0) {
      throw LensNativeException(
          'Screen Recording permission denied — grant it to your terminal in '
          'System Settings → Privacy & Security → Screen Recording');
    }
    final args = ['shot', outPng];
    if (windowId != null) args.addAll(['--window-id', '$windowId']);
    final r = await _runner.run(bin, args);
    if (r.exitCode != 0) {
      throw LensNativeException('lens_macos shot failed: ${r.stderr}');
    }
  }
}
