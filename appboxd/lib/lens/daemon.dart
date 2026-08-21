// The lens daemon — one warm Chrome held across CLI invocations.
//
// There is no daemon PROCESS. Two pieces already existed and make one
// unnecessary: `CdpClient.connect(wsUrl)` attaches to a running browser, and
// on macOS headless `CdpClient.launch()` already detaches — it spawns Chrome
// via `open -g -n -a`, holds no child Process at all, and recovers the pid
// afterwards from the profile dir. So the daemon is a detached Chrome plus a
// state file, and CDP-over-WebSocket is the protocol. No supervisor, no wire
// format, no reconnect loop.
//
// Design and the constraints behind it: docs/plans/lens-daemon.md. The one
// that shapes every function here: **no CDP event reports full browser
// death.** A closed socket is the only signal, and it cannot tell "killed by
// an unrelated script" from "crashed". Everything below is therefore written
// to notice and rebuild, never to trust a recorded fact.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../cdp.dart'; // CdpClient + LensSession both live here

/// What the state file holds. Every field is a claim about the outside world
/// that may already be false — [LensDaemon.isAlive] re-checks before use.
class LensDaemonState {
  final String wsUrl;
  final String profileDir;
  final int browserPid;
  final String startedAt;
  final int shotsServed;

  /// Render mode is baked into Chrome's launch args (`--headless=new`,
  /// `--window-size`), so a daemon started headless CANNOT serve a `--visible`
  /// verb. Recorded so a mismatched verb bypasses the daemon instead of
  /// silently getting the wrong render mode back.
  final bool visible;

  const LensDaemonState({
    required this.wsUrl,
    required this.profileDir,
    required this.browserPid,
    required this.startedAt,
    required this.shotsServed,
    required this.visible,
  });

  Map<String, dynamic> toJson() => {
        'wsUrl': wsUrl,
        'profileDir': profileDir,
        'browserPid': browserPid,
        'startedAt': startedAt,
        'shotsServed': shotsServed,
        'visible': visible,
      };

  static LensDaemonState? fromJson(Map<String, dynamic> j) {
    final wsUrl = j['wsUrl'], dir = j['profileDir'], pid = j['browserPid'];
    if (wsUrl is! String || dir is! String || pid is! int) return null;
    return LensDaemonState(
      wsUrl: wsUrl,
      profileDir: dir,
      browserPid: pid,
      startedAt: j['startedAt'] as String? ?? '',
      shotsServed: j['shotsServed'] as int? ?? 0,
      visible: j['visible'] as bool? ?? false,
    );
  }

  LensDaemonState withShots(int n) => LensDaemonState(
      wsUrl: wsUrl,
      profileDir: profileDir,
      browserPid: browserPid,
      startedAt: startedAt,
      shotsServed: n,
      visible: visible);
}

class LensDaemon {
  /// Recycle after this many screenshots.
  ///
  /// From measurement, not from a blog post: the warm-Chrome depth probe ran
  /// 700 captures / 21m39s and 180 animated-page captures / ~900 shots with
  /// zero pixel drift and flat memory (max rise 4MB). 900 is the deepest point
  /// the evidence actually reaches, so it is where the policy sits — not a
  /// number chosen because nothing broke below it.
  static const recycleAfterShots = 900;

  /// In-process override, for tests. A machine-wide singleton state file would
  /// make concurrent tests fight each other and — worse — fight a daemon the
  /// developer is actually using. `Platform.environment` cannot be overridden
  /// in-process, so the env var alone would not have isolated anything.
  static String? statePathOverride;

  /// `APPBOX_LENS_DAEMON_STATE` overrides the path for subprocesses.
  static String statePath() {
    if (statePathOverride != null) return statePathOverride!;
    final override = Platform.environment['APPBOX_LENS_DAEMON_STATE'];
    if (override != null && override.isNotEmpty) return override;
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    return p.join(home, '.appbox', 'lens-daemon.json');
  }

  /// Only the `open -g` launch path detaches, and only headless takes it
  /// (`cdp.dart` sends visible mode down the direct-exec branch, whose child
  /// dies with its parent). Anywhere else, a "daemon" would be a Chrome that
  /// vanishes when the starting CLI exits — worse than no daemon, because the
  /// state file would then point at a corpse.
  static bool get supported => Platform.isMacOS;

  static LensDaemonState? read() {
    final f = File(statePath());
    if (!f.existsSync()) return null;
    try {
      final j = jsonDecode(f.readAsStringSync());
      return j is Map<String, dynamic> ? LensDaemonState.fromJson(j) : null;
    } catch (_) {
      return null; // a corrupt state file is a dead daemon, not a crash
    }
  }

  static void write(LensDaemonState s) {
    final f = File(statePath());
    f.parent.createSync(recursive: true);
    f.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(s.toJson())}\n');
  }

  static void clearState() {
    final f = File(statePath());
    if (f.existsSync()) f.deleteSync();
  }

  /// Is the recorded browser still there?
  ///
  /// The pid ALONE is not enough: pids are recycled, and an unrelated process
  /// inheriting that number would read as a live daemon. Ownership of the
  /// exact profile dir is the check — which is also why the profile dir is
  /// recorded rather than derived.
  static bool isAlive(LensDaemonState s) =>
      CdpClient.pidsOwningProfile(s.profileDir, browserOnly: true)
          .contains(s.browserPid);

  /// Attach to a live, compatible daemon — or null, which every caller must
  /// treat as "launch your own", never as an error.
  ///
  /// Returns null when: unsupported platform, no state file, the browser is
  /// gone, the render mode does not match, or the socket refuses. The last one
  /// matters most: a state file that says "alive" and a socket that will not
  /// open is exactly the case no CDP event can announce.
  static Future<CdpClient?> attach() async {
    if (!supported) return null;
    final s = read();
    if (s == null) return null;
    if (s.visible != LensSession.visible) return null;
    if (!isAlive(s)) {
      // Attributable: log which profile the corpse owned before erasing the
      // only record of it.
      stderr.writeln('lens: daemon in ${statePath()} is dead '
          '(pid ${s.browserPid} no longer owns ${s.profileDir}) — reaping');
      reap(s);
      return null;
    }
    if (s.shotsServed >= recycleAfterShots) {
      stderr.writeln('lens: daemon reached ${s.shotsServed} screenshots '
          '(policy $recycleAfterShots) — recycling');
      await stop();
      return null;
    }
    try {
      final client = await CdpClient.connect(s.wsUrl);
      client.onGuestClose = _bankShots;
      return client;
    } catch (e) {
      stderr.writeln('lens: daemon socket ${s.wsUrl} refused ($e) — reaping');
      reap(s);
      return null;
    }
  }

  /// The whole integration surface: a daemon guest if one is usable, else a
  /// fresh browser exactly as before. Callers keep calling `close()`; a guest
  /// close leaves the browser up (see `CdpClient._ownsBrowser`), so nothing
  /// downstream changes.
  static Future<CdpClient> acquire() async =>
      await attach() ?? await CdpClient.launch();

  /// Start a daemon, replacing any existing one.
  static Future<LensDaemonState> start() async {
    if (!supported) {
      throw StateError('the lens daemon needs the detaching launch path '
          '(macOS headless); on ${Platform.operatingSystem} every verb '
          'launches its own Chrome, which is the existing behaviour');
    }
    await stop(); // never leave the previous one orphaned and unrecorded
    final client = await CdpClient.launch();
    final dir = client.userDataDir?.path;
    final pid = client.chromePid;
    final ws = client.wsUrl;
    if (dir == null || pid == null || ws == null) {
      // Refuse rather than record a daemon that cannot later be found or
      // killed — an unattributable orphan is the worst outcome here.
      await client.close();
      throw StateError('launch did not yield a profile dir, pid and wsUrl '
          '(dir=$dir pid=$pid ws=$ws) — refusing to record an unreapable '
          'daemon');
    }
    final state = LensDaemonState(
      wsUrl: ws,
      profileDir: dir,
      browserPid: pid,
      startedAt: DateTime.now().toIso8601String(),
      shotsServed: 0,
      visible: LensSession.visible,
    );
    write(state);
    // Drop OUR handle without killing the browser: the client owns it, and
    // close() would tear it down. Detaching the ownership flag is what leaves
    // Chrome running while this process exits.
    client.disownBrowser();
    await client.close();
    return state;
  }

  static Future<void> stop() async {
    final s = read();
    if (s == null) return;
    reap(s);
  }

  /// Kill the recorded browser and delete its profile — scoped to the exact
  /// `--user-data-dir`, never a prefix match. A dir with no owning pid is a
  /// true orphan and safe to delete alone.
  static void reap(LensDaemonState s) {
    for (final pid in CdpClient.pidsOwningProfile(s.profileDir)) {
      try {
        Process.killPid(pid, ProcessSignal.sigkill);
      } catch (_) {}
    }
    try {
      final d = Directory(s.profileDir);
      if (d.existsSync() && CdpClient.pidsOwningProfile(s.profileDir).isEmpty) {
        d.deleteSync(recursive: true);
      }
    } catch (_) {}
    clearState();
  }

  /// Add a finished guest's screenshots to the running total.
  ///
  /// Read-modify-write, so two concurrent verbs can lose an increment. That is
  /// deliberate and the failure is benign: a lost count delays recycling
  /// slightly, and the drift is bounded by how many verbs run at once. Locking
  /// would buy exactness in a number whose threshold came from a measurement
  /// with far wider error bars than that.
  static void _bankShots(int n) {
    if (n <= 0) return;
    final s = read();
    if (s == null) return;
    write(s.withShots(s.shotsServed + n));
  }
}
