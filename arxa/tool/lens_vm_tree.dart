// lens driver: dump the attached Flutter app's widget/render tree.
// usage: dart run arxa/tool/lens_vm_tree.dart <vmUrl> widget|render|semantics
import 'dart:io';

import 'package:arxa/lens/native/flutter_vm.dart';

Future<void> main(List<String> args) async {
  final vm = await FlutterVm.connect(args[0]);
  switch (args[1]) {
    case 'widget':
      stdout.write(await vm.dumpWidgetTree());
    case 'render':
      stdout.write(await vm.dumpRenderTree());
    case 'semantics':
      stdout.write(await vm.dumpSemanticsTree());
    default:
      stderr.writeln('unknown tree kind: ${args[1]}');
      exit(2);
  }
  await vm.dispose();
}
