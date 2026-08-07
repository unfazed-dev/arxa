/// Mutation tests for the W-gate (W1–W7).
///
/// The shape is one clean synthetic artifact tree that passes all seven rules,
/// then per-rule mutations of that same tree. Each mutation asserts BOTH
/// directions: the mutated rule fires, and the other six stay silent. A rule
/// that can only be shown to fire, never to be the *only* thing firing, is not
/// proven non-vacuous — that is the whole point of the exercise.
library;

import 'dart:io';

import 'package:appboxd/design_tools.dart' show LintFinding, designLint;
import 'package:appboxd/gate_design_widgets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// ══ fixture ═════════════════════════════════════════════════════════════

/// A minimal artifact that satisfies every rule, in the post-migration TSX
/// shape the studio itself uses:
///   - `_panel.tsx` (the W3 base) and two role panels in ui/common/widgets/,
///     each consumed by both shells. A role panel exports `Open` — the frame —
///     re-exported as default; a shell MOUNTS the role by rendering that
///     component.
///   - a shell widget used by two surfaces of main_shell.
///   - a surface widget used by exactly one surface.
///   - two shell views, each mounting header + main once.
///   - widgets.css holding the only pill radius.
///   - viewmodels writing only `<shell>.*` / `app.*` keys.
final _cleanTree = <String, String>{
  // ── the panel base: the ONLY file allowed to carry the skeleton classes.
  'ui/common/widgets/_panel.tsx': '''
export function Panel({ role, children }) {
  return (
    <section class="panel panel-frame panel-size-m">
      <div class="panel-top"></div>
      <div class="panel-side-start"></div>
      <div class="panel-body">{children}</div>
      <div class="panel-side-end"></div>
      <div class="panel-bottom"></div>
      <div class="panel-resize"></div>
    </section>
  );
}
''',
  // ── role panels: thin instantiations, consumed by both shells.
  'ui/common/widgets/header_panel.tsx': '''
import { Panel } from './_panel.tsx';
export function Open({ children }) {
  return <Panel role="header">{children}</Panel>;
}
export { Open as default };
''',
  'ui/common/widgets/main_panel.tsx': '''
import { Panel } from './_panel.tsx';
export function Open({ children }) {
  return <Panel role="main">{children}</Panel>;
}
export function PanelBar({ panel }) {
  return <nav class="panel-bar"></nav>;
}
export function View({ f }) {
  return <div class="panel-main"></div>;
}
export { Open as default };
''',
  // ── a genuinely cross-shell widget.
  'ui/common/widgets/chip.tsx': '''
export function Chip({ text }) {
  return <span class="chip">{text}</span>;
}
''',
  // ── main_shell: two surfaces share one widget.
  'ui/views/main_shell/shared/widgets/toolbar.tsx':
      'export default function Toolbar() { return <div class="toolbar">tools</div>; }\n',
  'ui/views/main_shell/main_shell_view.tsx': '''
import HeaderPanel from '../../common/widgets/header_panel.tsx';
import MainPanel from '../../common/widgets/main_panel.tsx';
export default function MainShellView() {
  return (
    <main>
      <HeaderPanel />
      <MainPanel />
    </main>
  );
}
''',
  'ui/views/main_shell/intake/brief/brief_view.tsx': '''
import Toolbar from '../../shared/widgets/toolbar.tsx';
import { Chip } from '../../../../common/widgets/chip.tsx';
import Row from './widgets/row.tsx';
export default function BriefView() {
  return <main><Toolbar /><Chip text="a" /><Row /></main>;
}
''',
  'ui/views/main_shell/intake/brief/widgets/row.tsx':
      'export default function Row() { return <div class="row"></div>; }\n',
  'ui/views/main_shell/design/chat/chat_view.tsx': '''
import Toolbar from '../../shared/widgets/toolbar.tsx';
export default function ChatView() {
  return <main><Toolbar /></main>;
}
''',
  'ui/views/main_shell/intake/brief/brief_viewmodel.js': '''
export const page = (c, h) => {
  h.session(c).data.main_shell = { step: 'brief' };
  h.session(c).data.app = { locale: 'en' };
};
''',
  // ── app_shell: the second consumer of the common widgets.
  'ui/views/app_shell/app_shell_view.tsx': '''
import HeaderPanel from '../../common/widgets/header_panel.tsx';
import MainPanel from '../../common/widgets/main_panel.tsx';
export default function AppShellView() {
  return (
    <main>
      <HeaderPanel />
      <MainPanel />
    </main>
  );
}
''',
  'ui/views/app_shell/auth/auth_view.tsx': '''
import { Chip } from '../../../common/widgets/chip.tsx';
export default function AuthView() {
  return <main><Chip text="b" /></main>;
}
''',
  'ui/views/app_shell/auth/auth_viewmodel.js': '''
export const page = (c, h) => {
  h.session(c).data['app_shell'] = { authed: false };
};
''',
  // ── the one legal home for the pill radius.
  'assets/css/widgets.css': '.chip { border-radius: 999px; }\n',
  'assets/css/app.css': '.card { border-radius: 8px; }\n'
      '.avatar { border-radius: 50%; }\n',
};

/// A third shell, for the cross-shell ownership cases. `settings/` holds its own
/// `*_view.tsx`, so it is a surface — never a hosted-shell namespace.
const _workspaceShell = <String, String>{
  'ui/views/workspace_shell/settings/settings_view.tsx':
      'export default function SettingsView() { return <main></main>; }\n',
};

/// Materialize [files] (plus [mutations], which overwrite or add) under a fresh
/// temp dir and return its path.
String _tree(Directory root, Map<String, String> mutations) {
  final dir = Directory(p.join(root.path, 'art'))..createSync(recursive: true);
  final files = {..._cleanTree, ...mutations};
  for (final entry in files.entries) {
    if (entry.value == _deleted) continue;
    final f = File(p.join(dir.path, p.joinAll(entry.key.split('/'))));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(entry.value);
  }
  return dir.path;
}

/// Sentinel: a mutation that removes a file from the clean tree.
const _deleted = '\x00deleted\x00';

/// Rule ids present in [findings], e.g. `{'W1'}`.
Set<String> _rules(List<LintFinding> findings) =>
    findings.map((f) => f.message.split(':').first.trim()).toSet();

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('w_gate_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  /// Assert the mutated tree fires exactly [rule] and nothing else, and that at
  /// least one message names the rule and reads like a fix instruction.
  void expectsOnly(String rule, Map<String, String> mutations,
      {String? messageContains}) {
    final notes = <LintFinding>[];
    final findings = gateDesignWidgets(_tree(tmp, mutations), notes: notes);
    expect(_rules(findings), {rule},
        reason: 'expected only $rule; got:\n${findings.join('\n')}');
    if (messageContains != null) {
      expect(findings.map((f) => f.message).join('\n'), contains(messageContains));
    }
  }

  group('clean tree', () {
    test('passes all seven rules', () {
      final notes = <LintFinding>[];
      final findings = gateDesignWidgets(_tree(tmp, const {}), notes: notes);
      expect(findings, isEmpty, reason: findings.join('\n'));
      // Every rule applies to this tree, so nothing should be skipped.
      expect(notes, isEmpty, reason: notes.join('\n'));
    });

    test('design lint reports the gate as clean alongside the JS lint', () {
      final r = designLint([_tree(tmp, const {})]);
      expect(r.exitCode, 0);
      expect(r.stdoutLines.join('\n'), contains('widget/panel gate clean'));
    });
  });

  group('W1 placement', () {
    test('common widget with a single-surface consumer set must demote', () {
      // Drop app_shell's use of chip: brief_view is now its only consumer, so
      // the law demands the surface home, not merely the shell home.
      expectsOnly('W1', {
        'ui/views/app_shell/auth/auth_view.tsx':
            'export default function AuthView() { return <main></main>; }\n',
      },
          messageContains:
              'ui/views/main_shell/intake/brief/widgets/chip.tsx');
    });

    test('common widget consumed by two surfaces of one shell demotes to shell',
        () {
      expectsOnly('W1', {
        'ui/views/app_shell/auth/auth_view.tsx':
            'export default function AuthView() { return <main></main>; }\n',
        'ui/views/main_shell/design/chat/chat_view.tsx': '''
import Toolbar from '../../shared/widgets/toolbar.tsx';
import { Chip } from '../../../../common/widgets/chip.tsx';
export default function ChatView() {
  return <main><Toolbar /><Chip text="c" /></main>;
}
''',
      },
          messageContains: 'ui/views/main_shell/shared/widgets/chip.tsx');
    });

    test('shell widget consumed by one surface only must demote to that surface',
        () {
      // chat_view stops using the toolbar → one consumer directory left.
      expectsOnly('W1', {
        'ui/views/main_shell/design/chat/chat_view.tsx':
            'export default function ChatView() { return <main></main>; }\n',
      }, messageContains: 'ui/views/main_shell/intake/brief/widgets/toolbar.tsx');
    });

    test('surface widget consumed from outside its surface must promote', () {
      // chat_view (a design surface) reaches into intake/brief's own widget.
      expectsOnly('W1', {
        'ui/views/main_shell/design/chat/chat_view.tsx': '''
import Toolbar from '../../shared/widgets/toolbar.tsx';
import Row from '../../intake/brief/widgets/row.tsx';
export default function ChatView() {
  return <main><Toolbar /><Row /></main>;
}
''',
      },
          messageContains:
              'ui/views/main_shell/shared/widgets/row.tsx');
    });

    test('a widget consumed only by a same-scope widget is correctly placed',
        () {
      // The doubled-path trap: the sole consumer is another shell-scoped widget
      // in the same folder, so the widget is already at the narrowest scope —
      // its consumer is itself shell-wide. Demanding `widgets/widgets/` here
      // would be reading the consumer's folder instead of its scope.
      final findings = gateDesignWidgets(_tree(tmp, {
        'ui/views/main_shell/shared/widgets/leaf.tsx':
            'export default function Leaf() { return <b></b>; }\n',
        'ui/views/main_shell/shared/widgets/toolbar.tsx': '''
import Leaf from './leaf.tsx';
export default function Toolbar() {
  return <div class="toolbar"><Leaf /></div>;
}
''',
      }));
      expect(findings, isEmpty, reason: findings.join('\n'));
    });

    test('two surfaces of one SECTION round up to the shell, not a section tier',
        () {
      // The four-tier trap: brief/ and direction/ are both under intake/, whose
      // common ancestor is `ui/views/main_shell/intake` — a section, not a
      // surface. The law names three homes, so the fix must be the shell home;
      // `intake/widgets/` is not a place the scaffolder would emit.
      final findings = gateDesignWidgets(_tree(tmp, {
        'ui/views/main_shell/design/chat/chat_view.tsx':
            'export default function ChatView() { return <main></main>; }\n',
        'ui/views/main_shell/intake/direction/direction_view.tsx': '''
import Toolbar from '../../shared/widgets/toolbar.tsx';
export default function DirectionView() {
  return <main><Toolbar /></main>;
}
''',
      }));
      expect(findings.map((f) => f.message).join('\n'), isNot(contains('intake/widgets')));
      expect(findings, isEmpty, reason: findings.join('\n'));
    });

    test('a section-level widgets/ dir is reported against the shell home', () {
      expectsOnly('W1', {
        'ui/views/main_shell/intake/widgets/section.tsx':
            'export default function Section() { return <b></b>; }\n',
        'ui/views/main_shell/intake/direction/direction_view.tsx': '''
import Section from '../widgets/section.tsx';
export default function DirectionView() {
  return <main><Section /></main>;
}
''',
        'ui/views/main_shell/intake/brief/brief_view.tsx': '''
import Toolbar from '../../shared/widgets/toolbar.tsx';
import { Chip } from '../../../../common/widgets/chip.tsx';
import Row from './widgets/row.tsx';
import Section from '../widgets/section.tsx';
export default function BriefView() {
  return <main><Toolbar /><Chip text="a" /><Row /><Section /></main>;
}
''',
      },
          messageContains:
              'ui/views/main_shell/shared/widgets/section.tsx');
    });

    test('the retired flat ui/widgets/ tier is named, not scope-measured', () {
      // Two shell consumers, so a scope reading would compute a legal-looking
      // "cross-shell" answer and say nothing about the tier. The failure must
      // name the retired tier instead — the fix is a migration, not a move
      // derived from consumer counts.
      final notes = <LintFinding>[];
      final findings = gateDesignWidgets(
          _tree(tmp, {
            'ui/widgets/components/_nav.tsx':
                'export default function Nav() { return <nav></nav>; }\n',
            'ui/views/main_shell/main_shell_view.tsx': '''
import HeaderPanel from '../../common/widgets/header_panel.tsx';
import MainPanel from '../../common/widgets/main_panel.tsx';
import Nav from '../../widgets/components/_nav.tsx';
export default function MainShellView() {
  return <main><HeaderPanel /><MainPanel /><Nav /></main>;
}
''',
            'ui/views/app_shell/app_shell_view.tsx': '''
import HeaderPanel from '../../common/widgets/header_panel.tsx';
import MainPanel from '../../common/widgets/main_panel.tsx';
import Nav from '../../widgets/components/_nav.tsx';
export default function AppShellView() {
  return <main><HeaderPanel /><MainPanel /><Nav /></main>;
}
''',
          }),
          notes: notes);
      expect(_rules(findings), {'W1'}, reason: findings.join('\n'));
      final msg = findings.single.message;
      expect(msg, contains('retired flat widget tier'));
      expect(msg, contains('ui/widgets/'));
      // The old behaviour: a surface home keyed `ui`, reported as a scope
      // problem. Neither phrase may come back.
      expect(msg, isNot(contains('narrowest scope')));
      expect(msg, isNot(contains('confined to')));
    });

    test('ui/dialogs/ and ui/bottomsheets/ are named too', () {
      // Neither holds a `widgets/` segment, so both are invisible to isWidget;
      // the placement pass admits them explicitly or the retired family is
      // enforced only where it happens to be spelled `widgets`.
      final findings = gateDesignWidgets(_tree(tmp, {
        'ui/dialogs/_confirm.tsx':
            'export default function Confirm() { return <dialog></dialog>; }\n',
        'ui/bottomsheets/_share.tsx':
            'export default function Share() { return <div></div>; }\n',
        'ui/views/main_shell/intake/brief/brief_view.tsx': '''
import Toolbar from '../../shared/widgets/toolbar.tsx';
import { Chip } from '../../../../common/widgets/chip.tsx';
import Row from './widgets/row.tsx';
import Confirm from '../../../../dialogs/_confirm.tsx';
import Share from '../../../../bottomsheets/_share.tsx';
export default function BriefView() {
  return <main><Toolbar /><Chip text="a" /><Row /><Confirm /><Share /></main>;
}
''',
      }));
      expect(_rules(findings), {'W1'}, reason: findings.join('\n'));
      final msgs = findings.map((f) => '${f.file}: ${f.message}').join('\n');
      expect(msgs, contains('ui/dialogs/'));
      expect(msgs, contains('ui/bottomsheets/'));
    });

    test('a bare <shell>/widgets/ directory is illegal', () {
      expectsOnly('W1', {
        'ui/views/main_shell/widgets/stray.tsx':
            'export default function Stray() { return <b></b>; }\n',
        'ui/views/main_shell/intake/brief/brief_view.tsx': '''
import Toolbar from '../../shared/widgets/toolbar.tsx';
import { Chip } from '../../../../common/widgets/chip.tsx';
import Row from './widgets/row.tsx';
import Stray from '../../widgets/stray.tsx';
export default function BriefView() {
  return <main><Toolbar /><Chip text="a" /><Row /><Stray /></main>;
}
''',
      }, messageContains: 'not a legal widget home');
    });
  });

  group('W2 dead widgets', () {
    test('a widget with zero importers fails', () {
      expectsOnly('W2', {
        'ui/common/widgets/ghost.tsx':
            'export default function Ghost() { return <i></i>; }\n',
      }, messageContains: 'zero importers');
    });
  });

  group('W3 panels instantiated, never re-implemented', () {
    test('skeleton classes outside _panel.tsx fail', () {
      expectsOnly('W3', {
        'ui/views/main_shell/shared/widgets/toolbar.tsx':
            'export default function Toolbar() { return <div class="panel-top panel-body">rolled my own</div>; }\n',
      }, messageContains: 'instantiate the base');
    });

    test('skeleton classes in a computed class string fail too', () {
      // hono/jsx class props are often backtick templates; quoting the attr is
      // not an escape from W3.
      expectsOnly('W3', {
        'ui/views/main_shell/shared/widgets/toolbar.tsx':
            'export default function Toolbar({ x }) { return <div class={`panel-top \${x}`}>rolled my own</div>; }\n',
      }, messageContains: 'instantiate the base');
    });

    test('role markers and innocuous descendants stay legal', () {
      final findings = gateDesignWidgets(_tree(tmp, {
        'ui/views/main_shell/shared/widgets/toolbar.tsx':
            'export default function Toolbar() { return <div class="panel-header panel-label panel-bar-item">ok</div>; }\n',
      }));
      expect(findings, isEmpty, reason: findings.join('\n'));
    });

    test('the base is found by name in ANY legal home, not just ui/common', () {
      // W1 places a widget by its consumers, so a base whose only consumers are
      // one shell's roles belongs in that shell. A path-pinned W3 would report
      // "no base" for a tree that has one, correctly placed — the two rules
      // would contradict each other over the same file.
      final notes = <LintFinding>[];
      final findings = gateDesignWidgets(
          _tree(tmp, {
            'ui/common/widgets/_panel.tsx': _deleted,
            'ui/views/main_shell/shared/widgets/_panel.tsx': '''
export default function Panel({ role, children }) {
  return (
    <section class="panel panel-frame">
      <div class="panel-body">{children}</div>
    </section>
  );
}
''',
            // The roles no longer import a base from ui/common.
            'ui/common/widgets/header_panel.tsx':
                'export default function HeaderPanel() { return <div class="panel-header">h</div>; }\n',
            'ui/common/widgets/main_panel.tsx':
                'export default function MainPanel() { return <div class="panel-main">m</div>; }\n',
            // The toolbar composes the relocated base, so it has a consumer.
            'ui/views/main_shell/shared/widgets/toolbar.tsx': '''
import BasePanel from './_panel.tsx';
export default function Toolbar() {
  return <BasePanel role="main"><span>tools</span></BasePanel>;
}
''',
          }),
          notes: notes);
      // No W3: the relocated base owns the skeleton, so its classes are legal
      // there and the rule is live rather than skipped.
      expect(_rules(findings), isEmpty, reason: findings.join('\n'));
      expect(notes.map((n) => n.message).join('\n'), isNot(contains('W3 skipped')));
    });

    test('reports skipped-with-note when the artifact has no panel base', () {
      final notes = <LintFinding>[];
      // Removing _panel.tsx would orphan its importers' W1/W2 story, so the
      // role panels drop the base import along with it.
      final findings = gateDesignWidgets(
          _tree(tmp, {
            'ui/common/widgets/_panel.tsx': _deleted,
            'ui/common/widgets/header_panel.tsx':
                'export default function HeaderPanel() { return <div class="panel-header">h</div>; }\n',
            'ui/common/widgets/main_panel.tsx':
                'export default function MainPanel() { return <div class="panel-main">m</div>; }\n',
          }),
          notes: notes);
      expect(_rules(findings), isEmpty, reason: findings.join('\n'));
      expect(notes.map((n) => n.message).join('\n'), contains('W3 skipped'));
    });
  });

  group('W4 shell composition', () {
    test('mounting a role panel twice fails', () {
      expectsOnly('W4', {
        'ui/views/main_shell/main_shell_view.tsx': '''
import HeaderPanel from '../../common/widgets/header_panel.tsx';
import MainPanel from '../../common/widgets/main_panel.tsx';
export default function MainShellView() {
  return (
    <main>
      <HeaderPanel />
      <MainPanel />
      <MainPanel />
    </main>
  );
}
''',
      }, messageContains: 'mounts the main panel 2 times');
    });

    test('a shell view is still checked even when it mounts only the header',
        () {
      expectsOnly('W4', {
        'ui/views/main_shell/main_shell_view.tsx': '''
import HeaderPanel from '../../common/widgets/header_panel.tsx';
import MainPanel from '../../common/widgets/main_panel.tsx';
export default function MainShellView() {
  return (
    <main>
      <HeaderPanel />
      <HeaderPanel />
      <MainPanel />
    </main>
  );
}
''',
      }, messageContains: 'mounts the header panel 2 times');
    });

    test('a mount via the named Open export counts the same as the default',
        () {
      // The studio's own spelling: `import { Open as MainOpen } …` then
      // `<MainOpen>…</MainOpen>`.
      expectsOnly('W4', {
        'ui/views/main_shell/main_shell_view.tsx': '''
import HeaderPanel from '../../common/widgets/header_panel.tsx';
import { Open as MainOpen } from '../../common/widgets/main_panel.tsx';
export default function MainShellView() {
  return (
    <main>
      <HeaderPanel />
      <MainOpen></MainOpen>
      <MainOpen></MainOpen>
    </main>
  );
}
''',
      }, messageContains: 'mounts the main panel 2 times');
    });

    test('helper components of a role panel are not mounts', () {
      // The macro-library trap, TSX form: main_panel.tsx exports the frame
      // plus PanelBar / View helpers, and a shell legitimately renders all
      // three. Counting every imported identifier would read ONE mounted main
      // panel as three.
      final findings = gateDesignWidgets(_tree(tmp, {
        'ui/views/main_shell/main_shell_view.tsx': '''
import HeaderPanel from '../../common/widgets/header_panel.tsx';
import MainPanel, { PanelBar, View as MainView } from '../../common/widgets/main_panel.tsx';
export default function MainShellView({ panel, f }) {
  return (
    <main>
      <HeaderPanel />
      <MainPanel>
        <PanelBar panel={panel} />
        <MainView f={f} />
      </MainPanel>
    </main>
  );
}
''',
      }));
      expect(findings, isEmpty, reason: findings.join('\n'));
    });

    test('a hosted-shell composition file is checked, double mount fails', () {
      // Role panels are mounted one tier down from the shell view, by the
      // hosted shell's own composition file. A shell-view-only sweep would open
      // main_shell_view.tsx, find nothing wrong, and pass while the real
      // composition went unmeasured.
      expectsOnly('W4', {
        'ui/views/main_shell/shared/widgets/activity_panel.tsx': '''
export function Open({ spec, children }) {
  return <aside class="panel-activity">{children}</aside>;
}
''',
        'ui/views/main_shell/design/_shared.tsx': '''
import { Open as ActivityOpen } from '../shared/widgets/activity_panel.tsx';
export function DesignShared({ spec }) {
  return (
    <section>
      <ActivityOpen spec={spec} />
      <ActivityOpen spec={spec} />
    </section>
  );
}
''',
      }, messageContains: 'mounts the activity panel 2 times');
    });

    test('one role mounted once each in two sibling files is not a double mount',
        () {
      // The studio's real shape: activity_panel is imported by both
      // design/_shared.tsx and design/prototype/prototype_view.tsx. Per-FILE
      // counting reads that as two layouts of one hosted shell, which is what
      // it is — a tree-wide count would call it a duplicate.
      final findings = gateDesignWidgets(_tree(tmp, {
        'ui/views/main_shell/shared/widgets/activity_panel.tsx': '''
export function Open({ spec, children }) {
  return <aside class="panel-activity">{children}</aside>;
}
''',
        'ui/views/main_shell/design/_shared.tsx': '''
import { Open as ActivityOpen } from '../shared/widgets/activity_panel.tsx';
export function DesignShared({ spec }) {
  return <ActivityOpen spec={spec} />;
}
''',
        'ui/views/main_shell/design/prototype/prototype_view.tsx': '''
import { Open as ActivityOpen } from '../../shared/widgets/activity_panel.tsx';
export default function PrototypeView({ spec }) {
  return <ActivityOpen spec={spec} />;
}
''',
      }));
      expect(findings, isEmpty, reason: findings.join('\n'));
    });

    test('an out-of-band section refresh is not a mount', () {
      // prototype_view.tsx imports the activity panel purely to re-feed its
      // top and bottom from a fragment route — section components of a panel
      // another file mounted. It sits in the hosted group, so it IS checked;
      // with no `Open` binding there is simply no mount to count.
      final findings = gateDesignWidgets(_tree(tmp, {
        'ui/views/main_shell/shared/widgets/activity_panel.tsx': '''
export function Open({ spec, children }) {
  return <aside class="panel-activity">{children}</aside>;
}
export function Top({ spec, oob }) {
  return <b>{spec.label}</b>;
}
export function Bottom({ spec, oob }) {
  return <i>{spec.label}</i>;
}
''',
        'ui/views/main_shell/design/_shared.tsx': '''
import { Open as ActivityOpen } from '../shared/widgets/activity_panel.tsx';
export function DesignShared({ spec }) {
  return <ActivityOpen spec={spec}>body</ActivityOpen>;
}
''',
        'ui/views/main_shell/design/prototype/prototype_view.tsx': '''
import { Top as ActivityTop, Bottom as ActivityBottom } from '../../shared/widgets/activity_panel.tsx';
export default function PrototypeView({ spec }) {
  return (
    <section>
      <ActivityTop spec={spec} oob={true} />
      <ActivityBottom spec={spec} oob={true} />
    </section>
  );
}
''',
      }));
      expect(findings, isEmpty, reason: findings.join('\n'));
    });

    test('a content widget composing a non-role panel is not a shell declaration',
        () {
      // design_viewer mounts mini_panel from shared/widgets/. That is content
      // composition, not a shell declaring its panel set, so the five-roles
      // rule must not reach it — `shared/` is an overlay, never a hosted shell.
      final findings = gateDesignWidgets(_tree(tmp, {
        'ui/views/main_shell/shared/widgets/mini_panel.tsx':
            'export default function MiniPanel() { return <div class="mini"></div>; }\n',
        'ui/views/main_shell/shared/widgets/toolbar.tsx': '''
import MiniPanel from './mini_panel.tsx';
export default function Toolbar() {
  return <div class="toolbar"><MiniPanel /></div>;
}
''',
      }));
      expect(findings, isEmpty, reason: findings.join('\n'));
    });

    test('mounting a non-role panel fails', () {
      expectsOnly('W4', {
        'ui/common/widgets/sidebar_panel.tsx':
            'export default function SidebarPanel() { return <aside></aside>; }\n',
        'ui/views/main_shell/main_shell_view.tsx': '''
import HeaderPanel from '../../common/widgets/header_panel.tsx';
import MainPanel from '../../common/widgets/main_panel.tsx';
import SidebarPanel from '../../common/widgets/sidebar_panel.tsx';
export default function MainShellView() {
  return <main><HeaderPanel /><MainPanel /><SidebarPanel /></main>;
}
''',
        'ui/views/app_shell/app_shell_view.tsx': '''
import HeaderPanel from '../../common/widgets/header_panel.tsx';
import MainPanel from '../../common/widgets/main_panel.tsx';
import SidebarPanel from '../../common/widgets/sidebar_panel.tsx';
export default function AppShellView() {
  return <main><HeaderPanel /><MainPanel /><SidebarPanel /></main>;
}
''',
      }, messageContains: 'not one of the five panel roles');
    });
  });

  group('W5 chip singularity', () {
    test('pill radius in a non-widgets stylesheet fails', () {
      expectsOnly('W5', {
        'assets/css/app.css': '.badge { border-radius: 9999px; }\n',
      }, messageContains: 'assets/css/widgets.css');
    });

    test('pill radius in an inline style fails', () {
      expectsOnly('W5', {
        'ui/views/main_shell/intake/brief/widgets/row.tsx':
            'export default function Row() { return <div style="border-radius: 999px">r</div>; }\n',
      }, messageContains: 'inline');
    });

    test('an annotated pill radius is exempt', () {
      final findings = gateDesignWidgets(_tree(tmp, {
        'assets/css/app.css':
            '.progress-track { border-radius: 999px; } /* w5:not-a-chip */\n',
      }));
      expect(findings, isEmpty, reason: findings.join('\n'));
    });

    test('the annotation exempts only its own line', () {
      // The escape is per-rule, not per-file: one annotated shape must not
      // license every other pill radius in the same stylesheet.
      final findings = gateDesignWidgets(_tree(tmp, {
        'assets/css/app.css': '.track { border-radius: 999px; } '
                '/* w5:not-a-chip */\n'
            '.badge { border-radius: 9999px; }\n',
      }));
      expect(_rules(findings), {'W5'}, reason: findings.join('\n'));
      // Line 2 is the badge; line 1 is annotated and must not be named.
      expect(findings.single.message, contains('at line 2'));
    });

    test('the annotation works on a multi-line declaration', () {
      final findings = gateDesignWidgets(_tree(tmp, {
        'assets/css/app.css': '.track {\n'
            '  border-radius:\n'
            '    999px; /* w5:not-a-chip */\n'
            '}\n',
      }));
      expect(findings, isEmpty, reason: findings.join('\n'));
    });

    test('an unannotated pill radius still fails', () {
      expectsOnly('W5', {
        'assets/css/app.css': '.badge { border-radius: 999px; }\n',
      }, messageContains: w5Exemption);
    });

    test('the annotation is harmless in the widgets CSS', () {
      final findings = gateDesignWidgets(_tree(tmp, {
        'assets/css/widgets.css': '.chip { border-radius: 999px; }\n'
            '.swatch { border-radius: 999px; } /* w5:not-a-chip */\n',
      }));
      expect(findings, isEmpty, reason: findings.join('\n'));
    });

    test('50% circles are exempt', () {
      final findings = gateDesignWidgets(_tree(tmp, {
        'assets/css/app.css': '.avatar { border-radius: 50%; }\n',
      }));
      expect(findings, isEmpty, reason: findings.join('\n'));
    });
  });

  group('W6 state namespacing', () {
    test('a viewmodel writing an unnamespaced session key fails', () {
      expectsOnly('W6', {
        'ui/views/main_shell/intake/brief/brief_viewmodel.js': '''
export const page = (c, h) => {
  h.session(c).data.draft = { text: '' };
};
''',
      }, messageContains: 'rename it to `main_shell.draft`');
    });

    test('an unrecognised root fails even when it looks namespaced', () {
      expectsOnly('W6', {
        'ui/views/app_shell/auth/auth_viewmodel.js': '''
export const page = (c, h) => {
  h.session(c).data['foo'] = { bogus: true };
};
''',
      }, messageContains: 'does not own');
    });

    test('a hosted-shell GROUP root passes (intake/ is a group, not a surface)',
        () {
      // The studio shape: main_shell hosts intake/design/build. Those dirs hold
      // no *_view.tsx of their own — their children do — so they are hosted
      // shells whose state legitimately lives under `intake.*`.
      final findings = gateDesignWidgets(_tree(tmp, {
        'ui/views/main_shell/intake/brief/brief_viewmodel.js': '''
export const page = (c, h) => {
  h.session(c).data.intake = { step: 'brief' };
};
''',
      }));
      expect(findings, isEmpty, reason: findings.join('\n'));
    });

    test('a surface dir name is NOT a namespace root', () {
      // brief/ holds brief_view.tsx, so it is a surface, not a hosted shell.
      expectsOnly('W6', {
        'ui/views/main_shell/intake/brief/brief_viewmodel.js': '''
export const page = (c, h) => {
  h.session(c).data.brief = { step: 1 };
};
''',
      }, messageContains: 'does not own');
    });

    test('`shared` is structure, not a namespace root', () {
      // Exercised from a viewmodel that actually sits under `shared/`, so the
      // overlay exclusion is what rejects it rather than mere path absence.
      expectsOnly('W6', {
        'ui/views/main_shell/shared/shared_viewmodel.js': '''
export const page = (c, h) => {
  h.session(c).data.shared = { x: 1 };
};
''',
      }, messageContains: 'does not own');
    });

    test('another shell\'s namespace fails even though it is a real shell', () {
      expectsOnly('W6', {
        ..._workspaceShell,
        'ui/views/workspace_shell/settings/settings_viewmodel.js': '''
export const page = (c, h) => {
  h.session(c).data['main_shell'] = { hijacked: true };
};
''',
      }, messageContains: 'app, workspace_shell');
    });

    test('a foreign hosted-shell group fails off its own path', () {
      // `intake` is a legitimate namespace under main_shell, and illegal here.
      expectsOnly('W6', {
        ..._workspaceShell,
        'ui/views/workspace_shell/settings/settings_viewmodel.js': '''
export const page = (c, h) => {
  h.session(c).data.intake = { step: 1 };
};
''',
      }, messageContains: 'does not own');
    });

    test('the host shell namespace passes from a hosted-shell viewmodel', () {
      // Ancestors count: panel-level state may live at the host tier.
      final findings = gateDesignWidgets(_tree(tmp, {
        'ui/views/main_shell/intake/brief/brief_viewmodel.js': '''
export const page = (c, h) => {
  h.session(c).data.main_shell = { panels: {} };
  h.session(c).data.intake = { step: 'brief' };
};
''',
      }));
      expect(findings, isEmpty, reason: findings.join('\n'));
    });

    test('a commented-out session write is not a violation', () {
      final findings = gateDesignWidgets(_tree(tmp, {
        'ui/views/main_shell/intake/brief/brief_viewmodel.js': '''
export const page = (c, h) => {
  // h.session(c).data.draft = { text: '' };
  /* h.session(c).data.scratch = 1; */
  h.session(c).data.main_shell = { step: 'brief' };
};
''',
      }));
      expect(findings, isEmpty, reason: findings.join('\n'));
    });

    test('app.* and <shell>.* keys pass in both write syntaxes', () {
      final findings = gateDesignWidgets(_tree(tmp, {
        'ui/views/main_shell/intake/brief/brief_viewmodel.js': '''
export const page = (c, h) => {
  const sd = h.session(c).data;
  h.session(c).data.main_shell ??= {};
  h.session(c).data['app'] = { locale: 'en' };
};
''',
      }));
      expect(findings, isEmpty, reason: findings.join('\n'));
    });
  });

  group('W7 anonymous text/interactive elements', () {
    test('a bare <span> with literal text in a surface view fails', () {
      expectsOnly('W7', {
        'ui/views/main_shell/intake/brief/brief_view.tsx': '''
import Toolbar from '../../shared/widgets/toolbar.tsx';
import { Chip } from '../../../../common/widgets/chip.tsx';
import Row from './widgets/row.tsx';
export default function BriefView() {
  return <main><Toolbar /><Chip text="a" /><Row /><span>Raw text</span></main>;
}
''',
      }, messageContains: 'wrap this <span>');
    });

    test('an interactive <button> without identity fails even with no text', () {
      expectsOnly('W7', {
        'ui/views/main_shell/intake/brief/brief_view.tsx': '''
import Toolbar from '../../shared/widgets/toolbar.tsx';
import { Chip } from '../../../../common/widgets/chip.tsx';
import Row from './widgets/row.tsx';
export default function BriefView() {
  return <main><Toolbar /><Chip text="a" /><Row /><button /></main>;
}
''',
      }, messageContains: 'wrap this <button>');
    });

    test('a library widget invocation (Capitalized tag) bearing text passes', () {
      final findings = gateDesignWidgets(_tree(tmp, {
        'ui/views/main_shell/intake/brief/brief_view.tsx': '''
import Toolbar from '../../shared/widgets/toolbar.tsx';
import { Chip } from '../../../../common/widgets/chip.tsx';
import Row from './widgets/row.tsx';
export default function BriefView() {
  return <main><Toolbar /><Chip text="a" /><Row /><Label>Raw text</Label></main>;
}
''',
      }));
      expect(findings, isEmpty, reason: findings.join('\n'));
    });

    test('a bare tag with data-el passes', () {
      final findings = gateDesignWidgets(_tree(tmp, {
        'ui/views/main_shell/intake/brief/brief_view.tsx': '''
import Toolbar from '../../shared/widgets/toolbar.tsx';
import { Chip } from '../../../../common/widgets/chip.tsx';
import Row from './widgets/row.tsx';
export default function BriefView() {
  return <main><Toolbar /><Chip text="a" /><Row /><span data-el="label">text</span></main>;
}
''',
      }));
      expect(findings, isEmpty, reason: findings.join('\n'));
    });

    test('a bare tag with inspectAttrs spread passes', () {
      final findings = gateDesignWidgets(_tree(tmp, {
        'ui/views/main_shell/intake/brief/brief_view.tsx': '''
import Toolbar from '../../shared/widgets/toolbar.tsx';
import { Chip } from '../../../../common/widgets/chip.tsx';
import Row from './widgets/row.tsx';
export default function BriefView() {
  return <main><Toolbar /><Chip text="a" /><Row /><span {...inspectAttrs('label', { role: 'label' })}>text</span></main>;
}
''',
      }));
      expect(findings, isEmpty, reason: findings.join('\n'));
    });

    test('widget-library dirs are exempt — raw text in a widget file is legal', () {
      // The same <span>Raw text</span> that fails in a surface view is legal
      // inside a widget-library dir: that is where the widgets are DEFINED.
      final findings = gateDesignWidgets(_tree(tmp, {
        'ui/views/main_shell/intake/brief/widgets/raw_label.tsx':
            'export default function RawLabel() { return <span>Raw text</span>; }\n',
        'ui/views/main_shell/intake/brief/brief_view.tsx': '''
import Toolbar from '../../shared/widgets/toolbar.tsx';
import { Chip } from '../../../../common/widgets/chip.tsx';
import Row from './widgets/row.tsx';
import RawLabel from './widgets/raw_label.tsx';
export default function BriefView() {
  return <main><Toolbar /><Chip text="a" /><Row /><RawLabel /></main>;
}
''',
      }));
      expect(_rules(findings), isNot(contains('W7')));
    });

    test('a bare <main> with only component children passes (no literal text)', () {
      // <main> itself is a lowercase HTML element, but it has no literal text
      // and is not interactive — so W7 does not fire.
      final findings = gateDesignWidgets(_tree(tmp, const {}));
      expect(_rules(findings), isNot(contains('W7')));
    });
  });

  group('import graph', () {
    test('records relative TSX imports as root-relative edges', () {
      final graph = buildIncludeGraph(_tree(tmp, const {}));
      expect(graph['ui/common/widgets/chip.tsx'],
          containsAll([
            'ui/views/main_shell/intake/brief/brief_view.tsx',
            'ui/views/app_shell/auth/auth_view.tsx',
          ]));
      expect(graph['ui/common/widgets/_panel.tsx'],
          containsAll([
            'ui/common/widgets/header_panel.tsx',
            'ui/common/widgets/main_panel.tsx',
          ]));
    });

    test('bare specifiers are not edges', () {
      // A package import ('hono/jsx') names no file in the tree; recording it
      // would read every hono component as a consumed widget.
      final graph = buildIncludeGraph(_tree(tmp, {
        'ui/common/widgets/chip.tsx': '''
import type { FC } from 'hono/jsx';
export function Chip({ text }) {
  return <span class="chip">{text}</span>;
}
''',
      }));
      expect(graph.keys.any((k) => k.contains('hono')), isFalse);
    });
  });
}
