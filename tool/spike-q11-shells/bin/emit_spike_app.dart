// Q11 spike transliterator.
//
// PURITY CONTRACT (verdict 3): this program reads exactly one input —
// ../input/design.json — and writes the golden tree. It contains no clock, no
// randomness, no environment reads, and no absolute paths in its output. Every
// collection is sorted before emission so a second run is byte-identical.
//
// It is a TRANSLITERATOR, not a designer: it invents no names, no ids and no
// structure. Everything it writes is a mechanical restatement of design.json
// through the Q8 manifest's path/name templates and the Q5 frontmatter order.

import 'dart:convert';
import 'dart:io';

const String _kIndent = '  ';

void main(List<String> args) {
  final Directory spikeRoot = Directory(
    Platform.script.resolve('..').toFilePath(),
  );
  final File input = File('${spikeRoot.path}input/design.json');
  // Optional out-dir. Verdict 3 emits into two throwaway directories and diffs
  // them against the committed tree; a probe must never re-emit over the tree
  // it is about to gate.
  final Directory golden = Directory(
    args.isNotEmpty ? args.first : '${spikeRoot.path}golden',
  );

  final Map<String, dynamic> design =
      json.decode(input.readAsStringSync()) as Map<String, dynamic>;

  final String app = design['app'] as String;
  final String pkg = 'appbox_kit_${app}_app';
  final List<String> factors =
      (design['factors'] as List).cast<String>().toList()..sort();

  final List<Map<String, dynamic>> shells =
      (design['shells'] as List).cast<Map<String, dynamic>>().toList()
        ..sort((a, b) =>
            (a['feature'] as String).compareTo(b['feature'] as String));

  _wipe(golden);

  final _Emitter e = _Emitter(golden, pkg, app, factors);

  e.write('pubspec.yaml', _pubspec(pkg));
  e.write('analysis_options.yaml', _analysisOptions());

  for (final Map<String, dynamic> shell in shells) {
    e.emitShell(shell);
    final List<Map<String, dynamic>> surfaces =
        ((shell['surfaces'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .toList()
          ..sort((a, b) =>
              (a['surface'] as String).compareTo(b['surface'] as String));
    for (final Map<String, dynamic> surface in surfaces) {
      e.emitSurface(shell, surface);
    }
  }

  stdout.writeln('emitted ${e.count} files under ${_rel(golden.path)}');
}

/// Deletes every emitted artifact but preserves the two gitignored pub
/// working-set entries, which are not part of the golden tree.
void _wipe(Directory golden) {
  if (!golden.existsSync()) {
    golden.createSync(recursive: true);
    return;
  }
  final List<FileSystemEntity> entries = golden.listSync()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final FileSystemEntity entity in entries) {
    final String base = entity.path.split(Platform.pathSeparator).last;
    if (base == '.dart_tool' || base == 'pubspec.lock') continue;
    entity.deleteSync(recursive: true);
  }
}

String _rel(String p) {
  final String marker = 'app-box${Platform.pathSeparator}';
  final int i = p.indexOf(marker);
  return i < 0 ? p : p.substring(i + marker.length);
}

// ---------------------------------------------------------------------------
// naming
// ---------------------------------------------------------------------------

String _pascal(String snake) => snake
    .split('_')
    .where((String s) => s.isNotEmpty)
    .map((String s) => s[0].toUpperCase() + s.substring(1))
    .join();

String _factorSuffix(String factor) => _pascal(factor);

// ---------------------------------------------------------------------------
// emitter
// ---------------------------------------------------------------------------

class _Emitter {
  _Emitter(this.golden, this.pkg, this.app, this.factors);

  final Directory golden;
  final String pkg;
  final String app;
  final List<String> factors;
  int count = 0;

  void write(String relPath, String body) {
    final File f = File('${golden.path}${Platform.pathSeparator}$relPath');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(body);
    count++;
  }

  // The identity carrier is NOT emitted. It is AppBoxKitInspectAttrs, imported
  // from kit core (registry v1.2.0, designVocabulary.inspectAttrs). Q11 emitted
  // its own copy because the shape had no ratified home; it has one now, and a
  // shape re-emitted per app is a shape that drifts per app.

  // -- shells ---------------------------------------------------------------

  void emitShell(Map<String, dynamic> shell) {
    final String feature = shell['feature'] as String;
    final String dir = 'lib/ui/views/${app}_${feature}_shell';
    final String stem = '${app}_${feature}_shell';
    final String cls = _pascal(stem);
    final String screenId = shell['screenId'] as String;
    final String surfaceId = 'surface.$feature.shell';
    // Shells are not surfaces in the design record, so there is no id to
    // copy. They stamp the view body every view stamps; surfaceId
    // ('surface.<feature>.shell') is what tells a shell from a leaf. Inventing
    // an 'anatomy:shell.frame' here would be vocabulary the registry never
    // ratified — registry v1.2.0 closes the set.
    const String anatomy = 'anatomy:view.body';

    // shell-view
    final String viewPath = '$dir/${stem}_view.dart';
    final StringBuffer b = StringBuffer();
    b.write(_frontmatterFull(
      intro: 'The views layer draws what the user sees and forwards the '
          "user's input. A view reads streams out and calls actions in; it "
          'holds no business logic of its own.',
      role: '${shell['intro']}',
      path: viewPath,
    ));
    b.writeln();
    b.writeln("import 'package:flutter/material.dart';");
    b.writeln("import 'package:responsive_builder/responsive_builder.dart';");
    b.writeln(
        "import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';");
    b.writeln();
    for (final String f in factors) {
      b.writeln("import 'package:$pkg/ui/views/$stem/${stem}_view.$f.dart';");
    }
    b.writeln("import 'package:$pkg/ui/views/$stem/${stem}_viewmodel.dart';");
    b.writeln();
    b.writeln('class ${cls}View extends StackedView<${cls}ViewModel> {');
    b.writeln('${_kIndent}const ${cls}View({super.key});');
    b.writeln();
    b.write(_inspectAttrsField(screenId, surfaceId, anatomy));
    b.writeln();
    b.writeln('$_kIndent@override');
    b.writeln('${_kIndent}Widget builder(');
    b.writeln('$_kIndent${_kIndent}BuildContext context,');
    b.writeln('$_kIndent$_kIndent${cls}ViewModel viewModel,');
    b.writeln('$_kIndent${_kIndent}Widget? child,');
    b.writeln('$_kIndent) {');
    b.writeln('$_kIndent${_kIndent}return ScreenTypeLayout.builder(');
    for (final String f in factors) {
      b.writeln(
          '$_kIndent$_kIndent$_kIndent$f: (_) => const ${cls}View${_factorSuffix(f)}(),');
    }
    b.writeln('$_kIndent$_kIndent);');
    b.writeln('$_kIndent}');
    b.writeln();
    b.writeln('$_kIndent@override');
    b.writeln('$_kIndent${cls}ViewModel viewModelBuilder(');
    b.writeln('$_kIndent${_kIndent}BuildContext context,');
    b.writeln('$_kIndent) =>');
    b.writeln('$_kIndent$_kIndent$_kIndent${cls}ViewModel();');
    b.writeln('}');
    write(viewPath, b.toString());

    // shell-view-factor
    for (final String f in factors) {
      final String fp = '$dir/${stem}_view.$f.dart';
      write(
        fp,
        _factorFile(
          path: fp,
          stem: stem,
          cls: cls,
          factor: f,
          screenId: screenId,
          surfaceId: surfaceId,
          anatomy: anatomy,
          role: 'The $f rendering of ${shell['label']}. It hosts the '
              'nested-router outlet the leaf renders through.',
          body: 'const NestedRouter()',
          needsMaterialOnly: false,
        ),
      );
    }

    // shell-viewmodel
    final String vmPath = '$dir/${stem}_viewmodel.dart';
    write(
      vmPath,
      _viewmodelFile(
        path: vmPath,
        cls: cls,
        role: 'The viewmodel behind ${shell['label']}. It is a passive anchor: '
            'the shell owns no state of its own, so it exposes no actions and '
            'no streams yet.',
      ),
    );
  }

  // -- surfaces -------------------------------------------------------------

  void emitSurface(Map<String, dynamic> shell, Map<String, dynamic> surface) {
    final String feature = shell['feature'] as String;
    final String surf = surface['surface'] as String;
    final String dir = 'lib/ui/views/${app}_${feature}_shell/${app}_$surf';
    final String stem = '${app}_$surf';
    final String cls = _pascal(stem);
    final String screenId = surface['screenId'] as String;
    final String surfaceId = surface['surfaceId'] as String;
    final String anatomy = surface['anatomyNodeId'] as String;
    final bool isSplash = surface['isSplash'] == true;

    final String viewPath = '$dir/${stem}_view.dart';
    final StringBuffer b = StringBuffer();
    b.write(_frontmatterFull(
      intro: 'The views layer draws what the user sees and forwards the '
          "user's input. A view reads streams out and calls actions in; it "
          'holds no business logic of its own.',
      role: '${surface['intro']}',
      path: viewPath,
    ));
    b.writeln();
    b.writeln("import 'package:flutter/material.dart';");
    b.writeln("import 'package:responsive_builder/responsive_builder.dart';");
    b.writeln(
        "import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';");
    b.writeln();
    for (final String f in factors) {
      b.writeln(
          "import 'package:$pkg/ui/views/${app}_${feature}_shell/$stem/${stem}_view.$f.dart';");
    }
    b.writeln(
        "import 'package:$pkg/ui/views/${app}_${feature}_shell/$stem/${stem}_viewmodel.dart';");
    b.writeln();
    b.writeln('class ${cls}View extends StackedView<${cls}ViewModel> {');
    b.writeln('${_kIndent}const ${cls}View({super.key});');
    b.writeln();
    b.write(_inspectAttrsField(screenId, surfaceId, anatomy));
    b.writeln();
    b.writeln('$_kIndent@override');
    b.writeln('${_kIndent}Widget builder(');
    b.writeln('$_kIndent${_kIndent}BuildContext context,');
    b.writeln('$_kIndent$_kIndent${cls}ViewModel viewModel,');
    b.writeln('$_kIndent${_kIndent}Widget? child,');
    b.writeln('$_kIndent) {');
    b.writeln('$_kIndent${_kIndent}return ScreenTypeLayout.builder(');
    for (final String f in factors) {
      b.writeln(
          '$_kIndent$_kIndent$_kIndent$f: (_) => const ${cls}View${_factorSuffix(f)}(),');
    }
    b.writeln('$_kIndent$_kIndent);');
    b.writeln('$_kIndent}');
    b.writeln();
    b.writeln('$_kIndent@override');
    b.writeln('$_kIndent${cls}ViewModel viewModelBuilder(');
    b.writeln('$_kIndent${_kIndent}BuildContext context,');
    b.writeln('$_kIndent) =>');
    b.writeln('$_kIndent$_kIndent$_kIndent${cls}ViewModel();');
    b.writeln('}');
    write(viewPath, b.toString());

    for (final String f in factors) {
      final String fp = '$dir/${stem}_view.$f.dart';
      write(
        fp,
        _factorFile(
          path: fp,
          stem: stem,
          cls: cls,
          factor: f,
          screenId: screenId,
          surfaceId: surfaceId,
          anatomy: anatomy,
          role: isSplash
              ? 'The $f rendering of the splash surface. Brand mark only: no '
                  'navigation, no copy, no controls.'
              : 'The $f rendering of ${surface['label']}.',
          body: isSplash
              ? "const Scaffold(body: Center(child: FlutterLogo(size: 96)))"
              : "const Scaffold(body: Center(child: Text('${surface['label']}')))",
          needsMaterialOnly: true,
        ),
      );
    }

    final String vmPath = '$dir/${stem}_viewmodel.dart';
    write(
      vmPath,
      _viewmodelFile(
        path: vmPath,
        cls: cls,
        role: 'The viewmodel behind ${surface['label']}. The scaffolder emits '
            'it empty; the builder fills the actions and streams the surface '
            'requires.',
      ),
    );
  }

  // -- shared file shapes ---------------------------------------------------

  String _factorFile({
    required String path,
    required String stem,
    required String cls,
    required String factor,
    required String screenId,
    required String surfaceId,
    required String anatomy,
    required String role,
    required String body,
    required bool needsMaterialOnly,
  }) {
    final String vmImport = path.substring(0, path.lastIndexOf('/'));
    final StringBuffer b = StringBuffer();
    b.write(_frontmatterFull(
      intro: 'The views layer draws what the user sees and forwards the '
          "user's input. A view-factor is one form factor's rendering of a "
          'single view; it shares the view\'s viewmodel and owns no state.',
      role: role,
      path: path,
    ));
    b.writeln();
    b.writeln("import 'package:flutter/material.dart';");
    b.writeln(
        "import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';");
    b.writeln();
    b.writeln(
        "import 'package:$pkg/${vmImport.substring('lib/'.length)}/${stem}_viewmodel.dart';");
    b.writeln();
    b.writeln('class ${cls}View${_factorSuffix(factor)}');
    b.writeln('$_kIndent${_kIndent}extends ViewModelWidget<${cls}ViewModel> {');
    b.writeln(
        '${_kIndent}const ${cls}View${_factorSuffix(factor)}({super.key});');
    b.writeln();
    b.write(_inspectAttrsField(screenId, surfaceId, anatomy));
    b.writeln();
    b.writeln('$_kIndent@override');
    b.writeln(
        '${_kIndent}Widget build(BuildContext context, ${cls}ViewModel viewModel) {');
    b.writeln('$_kIndent${_kIndent}return $body;');
    b.writeln('$_kIndent}');
    b.writeln('}');
    return b.toString();
  }

  String _viewmodelFile({
    required String path,
    required String cls,
    required String role,
  }) {
    final StringBuffer b = StringBuffer();
    b.write(_frontmatterFull(
      intro: 'The views layer draws what the user sees and forwards the '
          "user's input. A viewmodel holds the state a view renders and the "
          'actions a view calls; it never touches Flutter widgets.',
      role: role,
      path: path,
    ));
    b.writeln();
    b.writeln(
        "import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';");
    b.writeln();
    b.writeln('class ${cls}ViewModel extends BaseViewModel {}');
    return b.toString();
  }

  String _inspectAttrsField(
    String screenId,
    String surfaceId,
    String anatomy,
  ) {
    final StringBuffer b = StringBuffer();
    b.writeln('$_kIndent/// Identity stamped at emit time (Q12 triple).');
    b.writeln('${_kIndent}static const AppBoxKitInspectAttrs inspectAttrs = '
        'AppBoxKitInspectAttrs(');
    b.writeln("$_kIndent${_kIndent}screenId: '$screenId',");
    b.writeln("$_kIndent${_kIndent}surfaceId: '$surfaceId',");
    b.writeln("$_kIndent${_kIndent}anatomyNodeId: '$anatomy',");
    b.writeln('$_kIndent);');
    return b.toString();
  }
}

// ---------------------------------------------------------------------------
// Q5 frontmatter
// ---------------------------------------------------------------------------

String _frontmatterFull({
  required String intro,
  required String role,
  required String path,
}) {
  final StringBuffer b = StringBuffer();
  b.write(_wrap(intro));
  b.writeln('///');
  b.write(_wrap(role));
  b.writeln('///');
  b.writeln('/// Requirements:');
  b.writeln('/// 1. [Placeholder]');
  b.writeln('/// PLACEHOLDER(builder): the requirements body is user-owned. The');
  b.writeln('/// scaffolder emits the section and this marker only.');
  b.writeln('///');
  b.writeln('/// Relationships:');
  b.writeln('///');
  b.writeln('/// PLACEHOLDER(builder): the relationships diagram is user-owned.');
  b.writeln('/// The scaffolder emits the section and this marker only.');
  b.writeln('///');
  b.writeln(
      '/// History: git log --follow -- tool/spike-q11-shells/golden/$path');
  b.writeln('library;');
  return b.toString();
}

/// Deterministic greedy wrap at 76 columns of prose (plus the `/// ` prefix).
String _wrap(String prose) {
  final List<String> words = prose.split(RegExp(r'\s+'))
    ..removeWhere((String w) => w.isEmpty);
  final StringBuffer out = StringBuffer();
  final StringBuffer line = StringBuffer();
  for (final String w in words) {
    if (line.isEmpty) {
      line.write(w);
    } else if (line.length + 1 + w.length <= 72) {
      line.write(' ');
      line.write(w);
    } else {
      out.writeln('/// $line');
      line.clear();
      line.write(w);
    }
  }
  if (line.isNotEmpty) out.writeln('/// $line');
  return out.toString();
}

// ---------------------------------------------------------------------------
// non-dart artifacts
// ---------------------------------------------------------------------------

String _pubspec(String pkg) => '''
name: $pkg
description: Q11 spike golden app. Generated by tool/spike-q11-shells/bin/emit_spike_app.dart from the Q8 feature-recipe manifest. Do not hand-edit.
publish_to: 'none'
version: 0.1.0

environment:
  sdk: '>=3.0.3 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  # stacked / stacked_services / rxdart come via the kit barrel
  # (appbox_kit_ui_library re-exports them) — never declared here.
  appbox_kit_core:
    path: ../../../kit/core
  appbox_kit_ui_library:
    path: ../../../kit/ui_library
  appbox_kit_data:
    path: ../../../kit/data
  # SPIKE FINDING: the shell-view / surface-view artifact types are defined by
  # an exemplar that calls ScreenTypeLayout, but responsive_builder is declared
  # in NO manifest, playbook or skill — it is recoverable only by reading
  # kit/showcase_app/pubspec.yaml. Every view-factor emission needs it.
  responsive_builder: ^0.7.1

# appbox_kit_data's own dependency_overrides do NOT propagate to host apps
# (pub only honours the root package's overrides), so every scaffolded app must
# replicate them verbatim: appwrite's graph pins win32 5.x while
# appbox_kit_core -> talker_flutter -> share_plus 13 needs win32 ^6.
dependency_overrides:
  win32: ^6.0.1
  device_info_plus: ^13.0.0
  package_info_plus: ^10.0.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0
''';

String _analysisOptions() => '''
include: package:flutter_lints/flutter.yaml

# Mirrors kit/showcase_app/analysis_options.yaml. The showcase excludes
# lib/app/app.router.dart (stacked_generator output). The spike emits no
# generated router yet, so the exclude list is present but empty — the
# INCLUDE line is the part the exemplar contract actually pins.
analyzer:
  exclude:
''';
