// lens driver: burst-capture the attached Flutter app over the VM service.
// usage: dart run arxa/tool/lens_vm_burst.dart <vmUrl> <outDir> [count] [intervalMs]
import 'dart:async';
import 'dart:io';

import 'package:arxa/lens/native/flutter_vm.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln('usage: dart run arxa/tool/lens_vm_burst.dart <vmUrl> <outDir> [count] [intervalMs]');
    exit(2);
  }
  final vm = await FlutterVm.connect(args[0]);
  final out = Directory(args[1])..createSync(recursive: true);
  final count = args.length > 2 ? int.parse(args[2]) : 30;
  final interval = Duration(milliseconds: args.length > 3 ? int.parse(args[3]) : 100);
  var ok = 0;
  for (var i = 0; i < count; i++) {
    try {
      final png = await vm.arxaShot();
      File('${out.path}/frame-${i.toString().padLeft(3, '0')}.png')
          .writeAsBytesSync(png);
      stdout.writeln('frame $i: ${png.length} bytes');
      ok++;
    } catch (e) {
      stdout.writeln('frame $i failed: $e');
    }
    await Future<void>.delayed(interval);
  }
  await vm.dispose();
  stdout.writeln('captured $ok/$count frames into ${out.path}');
}