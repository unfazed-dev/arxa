// probe: what screenshot-capable RPCs does this VM/DDS expose?
import 'dart:io';

import 'package:arxa/lens/native/flutter_vm.dart';

Future<void> main(List<String> args) async {
  final vm = await FlutterVm.connect(args[0]);
  for (final method in ['screenshot', 'getVM', '_screenshot']) {
    try {
      final r = await vm.rpc(method,
          method == 'getVM' ? null : {'silent': true});
      final b64 = r['screenshot'] as String?;
      stdout.writeln(method + ' OK type=' + (r['type'] ?? '?').toString() +
          ' keys=' + r.keys.toList().join(',') +
          ' b64len=' + (b64?.length.toString() ?? 'null'));
    } catch (e) {
      stdout.writeln(method + ' FAIL: ' + e.toString());
    }
  }
  await vm.dispose();
}
