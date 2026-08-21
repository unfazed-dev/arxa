// Child process for test/cdp_launch_failure_test.dart — runs the doomed
// launch under a private TMPDIR so the parent can assert "left nothing
// behind" on a directory nothing else writes to. In-process, the same
// assertion raced every concurrently running test file that launches Chrome.
import 'package:appboxd/cdp.dart';

Future<void> main() async {
  // Visible mode forces the direct-exec path on macOS, where chromePath is
  // exec'd as-is; /bin/echo exits instantly without printing a DevTools URL.
  LensSession.visible = true;
  try {
    final c = await CdpClient.launch(chromePath: '/bin/echo');
    await c.close();
    print('UNEXPECTED-SUCCESS');
  } catch (e) {
    print('THREW: $e');
  }
}
