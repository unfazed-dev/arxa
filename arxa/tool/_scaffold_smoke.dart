// Throwaway smoke driver: runs the Dart scaffold gate on an app-root arg and
// prints the summary + details. Compare against `bash scaffold.sh <root>`.
import 'package:arxa/gate_scaffold.dart';
import 'package:arxa/gates.dart';

void main(List<String> argv) {
  final root = argv[0];
  final ctx = GateContext(repoRoot: root, appRoot: root);
  final r = scaffoldGate(ctx);
  print('exit=${r.exitCode} passed=${r.passed}');
  print(r.summary);
  for (final d in r.details) {
    print(d);
  }
}
