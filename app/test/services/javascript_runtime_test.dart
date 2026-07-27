// Probe: confirm flutter_js on macOS binds JavaScriptCore, the synchronous
// `sendMessage` bridge works, and JSC drains `await` microtasks on
// executePendingJob (the crux for async POST handlers).
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_js/flutter_js.dart';

void main() {
  test('JSC: sync bridge + microtask drain', () {
    final rt = getJavascriptRuntime(xhr: false);
    addTearDown(rt.dispose);
    rt.setupBridge('readFile', (args) => 'HELLO-$args');
    final r1 = rt.evaluate("sendMessage('readFile', JSON.stringify('x.txt'))");
    expect(r1.stringResult, 'HELLO-x.txt');

    rt.evaluate(
      "globalThis.__r='pending'; (async()=>{ const v=await Promise.resolve(42); globalThis.__r='got:'+v; })();",
    );
    // JSC drains microtasks between evaluate() calls, so the awaited value is
    // already resolved by the time the next evaluate reads it.
    expect(rt.evaluate('globalThis.__r').stringResult, 'got:42');
    for (var i = 0; i < 5; i++) {
      rt.executePendingJob();
    }
    expect(rt.evaluate('globalThis.__r').stringResult, 'got:42');
  });
}
