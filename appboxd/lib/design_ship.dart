/// The Ship surface's confined git+gh channel (rework 2026-08-24, slice 5).
/// Operator law (Q5a): autopilot UP TO THE BUTTON — the dial automates
/// branch/commit/push/PR-open and WATCHES gates; every irreversible verb
/// (merge, close) is a one-tap operator action; conflicts are detected and
/// surfaced, never auto-resolved; no force-push exists anywhere in this
/// file. gh is authed (unfazed-dev, repo+workflow scopes, verified
/// 2026-08-24); the runner is injectable so tests capture argv verbatim.
library;

import 'dart:convert';
import 'dart:io';

/// One captured command outcome — the fake runner answers with these and
/// the production runner maps ProcessResult onto them.
class ShipProc {
  final int exit;
  final String out;
  final String err;
  const ShipProc(this.exit, [this.out = '', this.err = '']);
}

typedef ShipRunner = Future<ShipProc> Function(
    String cmd, List<String> args);

/// Production: run in [repoDir] with the server's own environment (HOME
/// included, so the gh keyring resolves).
ShipRunner ioRunner(String repoDir) => (cmd, args) async {
      final r = await Process.run(cmd, args, workingDirectory: repoDir);
      return ShipProc(r.exitCode, r.stdout.toString(), r.stderr.toString());
    };

class ShipRefusal implements Exception {
  final String message;
  const ShipRefusal(this.message);
  @override
  String toString() => message;
}

class DialShip {
  DialShip({required this.repoDir, required this.run});

  /// The git repo root (the client project).
  final String repoDir;
  final ShipRunner run;

  /// The operator-owned branch prefix — design dial PRs are identifiable
  /// and never collide with feature branches.
  static const branchPrefix = 'design/dial';

  Future<ShipProc> _git(List<String> args) => run('git', ['-C', repoDir, ...args]);
  Future<ShipProc> _gh(List<String> args) => run('gh', args);

  // ── status ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> status() async {
    final repo = await _git(['remote', 'get-url', 'origin']);
    final branch = await _git(['rev-parse', '--abbrev-ref', 'HEAD']);
    final dirty = await _git(['status', '--porcelain']);
    final aheadBehind = await _git(
        ['rev-list', '--left-right', '--count', 'main...@{u}']);
    final log = await _git(['log', '--oneline', '-5']);
    final pr = await _gh([
      'pr', 'view', '--json',
      'number,title,state,mergeable,url,headRefName,statusCheckRollup'
    ]);
    return {
      'repo': _repoSlug(repo.out),
      'branch': branch.out.trim(),
      'dirty': dirty.exit == 0
          ? dirty.out.trim().split('\n').where((l) => l.isNotEmpty).length
          : 0,
      'aheadBehind': aheadBehind.exit == 0 ? aheadBehind.out.trim() : '',
      'log': log.exit == 0
          ? log.out.trim().split('\n').where((l) => l.isNotEmpty).take(5).toList()
          : <String>[],
      'pr': pr.exit == 0 && pr.out.trim().isNotEmpty
          ? _prFromJson(pr.out)
          : null,
    };
  }

  String _repoSlug(String remoteUrl) {
    final m = RegExp(r'github\.com[/:]([^/]+/[^\s]+?)(\.git)?$')
        .firstMatch(remoteUrl.trim());
    return m == null ? remoteUrl.trim() : m.group(1)!;
  }

  Map<String, dynamic> _prFromJson(String raw) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final rollup = (j['statusCheckRollup'] as List? ?? []);
    final checks = [
      for (final c in rollup)
        {
          'name': '${c['__name'] ?? c['name'] ?? c['context'] ?? 'check'}',
          'status': '${c['status'] ?? ''}',
          'conclusion': '${c['conclusion'] ?? ''}',
        }
    ];
    final failing = checks
        .where((c) => c['conclusion'] == 'FAILURE' || c['conclusion'] == 'TIMED_OUT')
        .length;
    final pending = checks.where((c) => c['conclusion'] == '' && c['status'] != '').length;
    return {
      'number': j['number'],
      'title': j['title'],
      'state': j['state'],
      'mergeable': j['mergeable'] == true,
      'url': j['url'],
      'head': j['headRefName'],
      'checks': checks,
      'failing': failing,
      'pending': pending,
      'green': failing == 0 && pending == 0 && checks.isNotEmpty,
    };
  }

  // ── branch + commit + push + PR (the automated prefix) ──────────────

  /// Stage the artifact subtree, commit on a design branch, push, open the
  /// PR. Refuses loudly when there is nothing to ship or the repo already
  /// sits on an open design branch (one PR per batch — merge or close it
  /// first). Never touches origin/main.
  Future<Map<String, dynamic>> commitAndPr({
    required String artifactDir,
    required String title,
    required String body,
  }) async {
    final dirty = await _git(['status', '--porcelain', artifactDir]);
    if (dirty.exit != 0) {
      throw const ShipRefusal('artifact dir is not inside this repo');
    }
    if (dirty.out.trim().isEmpty) {
      throw const ShipRefusal('nothing to ship — the artifact is clean');
    }
    final branch = await _git(['rev-parse', '--abbrev-ref', 'HEAD']);
    final onMain = branch.out.trim() == 'main';
    if (!onMain) {
      throw ShipRefusal(
          'repo sits on ${branch.out.trim()} — merge or close its PR first');
    }
    final name = '$branchPrefix-${DateTime.now().millisecondsSinceEpoch}';
    final co = await _git(['checkout', '-b', name]);
    if (co.exit != 0) {
      throw ShipRefusal('branch create failed: ${co.err.trim()}');
    }
    final add = await _git(['add', '--', artifactDir]);
    if (add.exit != 0) {
      throw ShipRefusal('stage failed: ${add.err.trim()}');
    }
    final commit = await _git([
      'commit', '-m', title, '-m', body,
    ]);
    if (commit.exit != 0) {
      await _git(['checkout', 'main']);
      throw ShipRefusal('commit failed: ${commit.err.trim()}');
    }
    final push = await _git(['push', '-u', 'origin', name]);
    if (push.exit != 0) {
      throw ShipRefusal('push failed: ${push.err.trim()}');
    }
    final pr = await _gh([
      'pr', 'create', '--title', title, '--body', body,
      '--base', 'main', '--head', name,
    ]);
    if (pr.exit != 0) {
      throw ShipRefusal('PR create failed: ${pr.err.trim()}');
    }
    return {'branch': name, 'url': pr.out.trim()};
  }

  // ── the one-tap irreversible verbs (operator's finger) ──────────────

  /// Squash-merge the open PR and delete its branch. DISABLED-BY-LAW until
  /// green: failing checks or pending checks or an unmergeable PR refuse
  /// here too — the island disables the button, but the server re-enforces.
  Future<Map<String, dynamic>> merge() async {
    final st = await status();
    final pr = st['pr'] as Map<String, dynamic>?;
    if (pr == null) throw const ShipRefusal('no open PR');
    if (pr['state'] != 'OPEN') {
      throw ShipRefusal('PR is ${pr['state']}');
    }
    if (pr['mergeable'] != true) {
      throw ShipRefusal(
          'PR is not mergeable — pull & rebase first, resolve by hand');
    }
    if (pr['failing'] != 0) {
      throw ShipRefusal('${pr['failing']} check(s) failing');
    }
    if (pr['pending'] != 0) {
      throw ShipRefusal('${pr['pending']} check(s) still running');
    }
    final n = '${pr['number']}';
    final m = await _gh(['pr', 'merge', n, '--squash', '--delete-branch']);
    if (m.exit != 0) {
      throw ShipRefusal('merge failed: ${m.err.trim()}');
    }
    return {'merged': n};
  }

  Future<Map<String, dynamic>> close() async {
    final st = await status();
    final pr = st['pr'] as Map<String, dynamic>?;
    if (pr == null) throw const ShipRefusal('no open PR');
    final n = '${pr['number']}';
    final c = await _gh(['pr', 'close', n, '--delete-branch']);
    if (c.exit != 0) {
      throw ShipRefusal('close failed: ${c.err.trim()}');
    }
    return {'closed': n};
  }

  /// Back to main, updated. A rebase that hits conflicts refuses loudly
  /// and leaves the repo exactly where it was — conflicts are resolved by
  /// a human in a terminal, never by this file.
  Future<Map<String, dynamic>> sync() async {
    final co = await _git(['checkout', 'main']);
    if (co.exit != 0) {
      throw ShipRefusal('checkout main failed: ${co.err.trim()}');
    }
    final pull = await _git(['pull', '--rebase', 'origin', 'main']);
    if (pull.exit != 0) {
      await _git(['rebase', '--abort']);
      await _git(['merge', '--abort']);
      throw const ShipRefusal(
          'rebase hit conflicts — aborted; resolve by hand in a terminal');
    }
    return {'synced': true};
  }
}
