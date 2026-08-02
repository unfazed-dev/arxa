// CdpClient teardown — does close() actually end the browser it started?
//
// The bug this pins: on macOS headless, `launch` goes through `open -g`, which
// returns no Process. close() could therefore only ask Chrome to leave over CDP
// and then fire a `pkill -f <profile dir>`; neither reliably landed, and a
// 6-launch lens storm was measured leaving 2 Chromes resident (plus their temp
// profiles on disk).
//
// The assertions are deliberately zero-grace: they run the instant `close()`
// returns, with no polling and no retry. Any waiting belongs in production
// code, where the fix put it — `close()` returns only once the profile is
// genuinely unowned. That asymmetry IS the test: `Browser.close` returns on
// acknowledgement rather than exit, and pkill's default SIGTERM starts a
// graceful Chrome unwind of hundreds of ms, so the old path is still holding
// the profile at this exact instant.
//
// Asserting `close()` merely returns would prove nothing, which is why every
// check here is against `ps` and the filesystem.
import 'dart:io';

import 'package:appboxd/cdp.dart';
import 'package:test/test.dart';

/// Pids whose command line carries `--user-data-dir=[dir]`, helpers included.
///
/// Independent of the production scan on purpose — a test that called back into
/// the code under test could agree with it while both were wrong.
List<int> pidsOwning(String dir) {
  final ps = Process.runSync('ps', ['-eo', 'pid=,command=']);
  if (ps.exitCode != 0) return const [];
  final needle = '--user-data-dir=$dir';
  final out = <int>[];
  for (final line in (ps.stdout as String).split('\n')) {
    final at = line.indexOf(needle);
    if (at < 0) continue;
    final rest = line.substring(at + needle.length);
    if (rest.isNotEmpty && !rest.startsWith(' ')) continue;
    final pid = int.tryParse(line.trimLeft().split(RegExp(r'\s+')).first);
    if (pid != null) out.add(pid);
  }
  return out;
}

bool get _chromeOk => File(CdpClient.defaultChromePath()).existsSync();

void main() {
  group('CdpClient teardown', () {
    test('launch resolves a live pid that owns the profile dir', () async {
      final client = await CdpClient.launch();
      final dir = client.userDataDir!.path;
      try {
        expect(client.chromePid, isNotNull,
            reason: 'every launch path must yield a killable pid');
        expect(pidsOwning(dir), contains(client.chromePid),
            reason: 'the resolved pid must be the process holding OUR profile');
      } finally {
        await client.close();
      }
    });

    test('close leaves no process owning the profile, and no profile', () async {
      final client = await CdpClient.launch();
      final dir = client.userDataDir!.path;
      expect(pidsOwning(dir), isNotEmpty,
          reason: 'precondition: Chrome is up and holding the profile');

      await client.close();

      // Checked immediately — see the file header for why there is no grace.
      expect(pidsOwning(dir), isEmpty,
          reason: 'close() must not return while Chrome still holds $dir');
      expect(Directory(dir).existsSync(), isFalse,
          reason: 'a live process holding the profile is why delete failed');
    });
  }, skip: _chromeOk ? null : 'requires Chrome');
}
