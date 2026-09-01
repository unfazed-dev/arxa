// probe: raw screenshot error on this VM
import 'dart:io';

import 'package:arxa/lens/native/flutter_vm.dart';

Future<void> main(List<String> args) async {
  final vm = await FlutterVm.connect(args[0]);
  try {
    final r = await vm.rpc('screenshot', {'silent': true});
    stdout.writeln('OK keys=' + r.keys.toList().join(','));
  } catch (e) {
    stdout.writeln('FAIL: ' + e.toString());
  }
  try {
    final vm0 = await vm.rpc('getVM');
    stdout.writeln('isolate0=' +
        ((vm0['isolates'] as List).first as Map)['id'].toString());
  } catch (e) {
    stdout.writeln('getVM FAIL: ' + e.toString());
  }
  await vm.dispose();
}
