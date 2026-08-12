/// Mutation tests for the W-gate (W1–W8).
///
/// The shape is one clean synthetic artifact tree that passes all eight rules,
/// then per-rule mutations of that same tree. Each mutation asserts BOTH
/// directions: the mutated rule fires, and the other seven stay silent. A rule
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
///   - `_panel.tsx` (the W3 base) and two role panels in `ui/widgets/common/panels/`,
///     each consumed by both shells. A role panel exports `Open` — the frame —
///     re-exported as default; a shell MOUNTS the role by rendering that
///     component.
///   - a feature widget (`ui/widgets/main_shell_widgets/`) used by two surfaces of main_shell.
///   - a feature widget used by exactly one surface.
///   - two shell views, each mounting header + main once.
///   - widgets.css holding the only pill radius.
///   - viewmodels writing only `<shell>.*` / `app.*` keys.
final _cleanTree = <String, String>{
  // ── the panel base: the ONLY file allowed to carry the skeleton classes.
  'ui/widgets/common/panels/_panel.tsx': '''
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
  'ui/widgets/common/panels/header_panel.tsx': '''
import { Panel } from './_panel.tsx';
export function Open({ children }) {
  return <Panel role="header">{children}</Panel>;
}
export { Open as default };
''',
  'ui/widgets/common/panels/main_panel.tsx': '''
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
  'ui/widgets/common/chips/chip.tsx': '''
export function Chip({ text }) {
  return <span class="chip">{text}</span>;
}
''',
  // ── main_shell: two surfaces share one widget.
  'ui/widgets/main_shell_widgets/toolbar.tsx':
      'export default function Toolbar() { return <div class="toolbar">tools</div>; }\n',
  'ui/views/main_shell/main_shell_view.tsx': '''
import HeaderPanel from '../../widgets/common/panels/header_panel.tsx';
import MainPanel from '../../widgets/common/panels/main_panel.tsx';
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
import Toolbar from '../../../../widgets/main_shell_widgets/toolbar.tsx';
import { Chip } from '../../../../widgets/common/chips/chip.tsx';
import Row from '../../../../widgets/main_brief_widgets/row.tsx';
export default function BriefView() {
  return <main><Toolbar /><Chip text="a" /><Row /></main>;
}
''',
  'ui/widgets/main_brief_widgets/row.tsx':
      'export default function Row() { return <div class="row"></div>; }\n',
  'ui/views/main_shell/design/chat/chat_view.tsx': '''
import Toolbar from '../../../../widgets/main_shell_widgets/toolbar.tsx';
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
  // ── brief is a stated view (has a viewmodel), so it carries the three
  //    factor variants (W8).
  'ui/views/main_shell/intake/brief/brief_view.desktop.tsx':
      'export default function BriefViewDesktop() { return <div class="rung rung--desktop"></div>; }\n',
  'ui/views/main_shell/intake/brief/brief_view.tablet.tsx':
      'export default function BriefViewTablet() { return <div class="rung rung--tablet"></div>; }\n',
  'ui/views/main_shell/intake/brief/brief_view.mobile.tsx':
      'export default function BriefViewMobile() { return <div class="rung rung--mobile"></div>; }\n',
  // ── app_shell: the second consumer of the common widgets.
  'ui/views/app_shell/app_shell_view.tsx': '''
import HeaderPanel from '../../widgets/common/panels/header_panel.tsx';
import MainPanel from '../../widgets/common/panels/main_panel.tsx';
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
import { Chip } from '../../../widgets/common/chips/chip.tsx';
export default function AuthView() {
  return <main><Chip text="b" /></main>;
}
''',
  'ui/views/app_shell/auth/auth_viewmodel.js': '''
export const page = (c, h) => {
  h.session(c).data['app_shell'] = { authed: false };
};
''',
  'ui/views/app_shell/auth/auth_view.desktop.tsx':
      'export default function AuthViewDesktop() { return <div class="rung rung--desktop"></div>; }\n',
  'ui/views/app_shell/auth/auth_view.tablet.tsx':
      'export default function AuthViewTablet() { return <div class="rung rung--tablet"></div>; }\n',
  'ui/views/app_shell/auth/auth_view.mobile.tsx':
      'export default function AuthViewMobile() { return <div class="rung rung--mobile"></div>; }\n',
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
  // Factor variants ride along so W6 mutations that hand settings a viewmodel
  // (making it a stated view) do not co-fire W8. Variants without a viewmodel
  // owe nothing — W8 checks one direction only.
  'ui/views/workspace_shell/settings/settings_view.desktop.tsx':
      'export default function SettingsViewDesktop() { return <div class="rung rung--desktop"></div>; }\n',
  'ui/views/workspace_shell/settings/settings_view.tablet.tsx':
      'export default function SettingsViewTablet() { return <div class="rung rung--tablet"></div>; }\n',
  'ui/views/workspace_shell/settings/settings_view.mobile.tsx':
      'export default function SettingsViewMobile() { return <div class="rung rung--mobile"></div>; }\n',
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
    test('passes all eight rules', () {
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
    test('a common widget consumed by one shell only must demote', () {
      // auth_view stops importing chip: every remaining consumer sits in
      // main_shell, so the common/ placement is no longer earned.
      expectsOnly('W1', {
        'ui/views/app_shell/auth/auth_view.tsx': '''
export default function AuthView() {
  return <main></main>;
}
''',
      }, messageContains: 'unearned');
    });

    test('a feature widget imported from a second shell earns promotion', () {
      expectsOnly('W1', {
        'ui/views/app_shell/auth/auth_view.tsx': '''
import { Chip } from '../../../widgets/common/chips/chip.tsx';
import Toolbar from '../../../widgets/main_shell_widgets/toolbar.tsx';
export default function AuthView() {
  return <main><Toolbar /><Chip text="b" /></main>;
}
''',
      }, messageContains: 'ui/widgets/common/<group>/toolbar.tsx');
    });

    test('a consumer in the ui/common base layer is cross-shell by construction',
        () {
      expectsOnly('W1', {
        'ui/common/base.tsx': '''
import Toolbar from '../widgets/main_shell_widgets/toolbar.tsx';
export default function Base() { return <Toolbar />; }
''',
      }, messageContains: 'cross-shell base layer');
    });

    test('a feature widget consumed only by a common widget promotes too', () {
      // chip is cross-shell by placement; toolbar inherits that reach.
      expectsOnly('W1', {
        'ui/widgets/common/chips/chip.tsx': '''
import Toolbar from '../../main_shell_widgets/toolbar.tsx';
export function Chip({ text }) {
  return <span class="chip">{text}<Toolbar /></span>;
}
''',
      }, messageContains: 'promotion');
    });

    test('a widget consumed only by a same-feature widget is correctly placed',
        () {
      final findings = gateDesignWidgets(_tree(tmp, {
        'ui/widgets/main_shell_widgets/leaf.tsx':
            'export default function Leaf() { return <i>leaf</i>; }\n',
        'ui/widgets/main_shell_widgets/toolbar.tsx': '''
import Leaf from './leaf.tsx';
export default function Toolbar() { return <div class="toolbar"><Leaf /></div>; }
''',
      }));
      expect(findings, isEmpty, reason: findings.join('\n'));
    });

    test('the retired three-tier homes are named, not scope-measured', () {
      // One retired home per spelling; each needs a live importer so W2 stays
      // out of the way. The message must name the tier, not measure scope.
      expectsOnly('W1', {
        'ui/views/main_shell/design/chat/widgets/nav.tsx':
            'export default function Nav() { return <nav></nav>; }\n',
        'ui/views/main_shell/design/chat/chat_view.tsx': '''
import Toolbar from '../../../../widgets/main_shell_widgets/toolbar.tsx';
import Nav from './widgets/nav.tsx';
export default function ChatView() {
  return <main><Toolbar /><Nav /></main>;
}
''',
      }, messageContains: 'retired widget tier');
    });

    test('ui/common/widgets/, ui/dialogs/ and ui/bottomsheets/ are named too',
        () {
      for (final retired in [
        'ui/common/widgets/nav.tsx',
        'ui/dialogs/nav.tsx',
        'ui/bottomsheets/nav.tsx',
      ]) {
        final art = _tree(
            Directory(tmp.path)..createSync(recursive: true), {
          retired: 'export default function Nav() { return <nav></nav>; }\n',
          'ui/views/main_shell/design/chat/chat_view.tsx': '''
import Toolbar from '../../../../widgets/main_shell_widgets/toolbar.tsx';
import Nav from '../../../../${retired.substring(3)}';
export default function ChatView() {
  return <main><Toolbar /><Nav /></main>;
}
''',
        });
        final findings = gateDesignWidgets(art);
        expect(_rules(findings), {'W1'},
            reason: '$retired:\n${findings.join('\n')}');
        expect(findings.map((f) => f.message).join('\n'),
            contains('retired widget tier'));
        Directory(art).deleteSync(recursive: true);
      }
    });

    test('a flat file directly in ui/widgets/ is illegal', () {
      expectsOnly('W1', {
        'ui/widgets/nav.tsx':
            'export default function Nav() { return <nav></nav>; }\n',
        'ui/views/main_shell/design/chat/chat_view.tsx': '''
import Toolbar from '../../../../widgets/main_shell_widgets/toolbar.tsx';
import Nav from '../../../../widgets/nav.tsx';
export default function ChatView() {
  return <main><Toolbar /><Nav /></main>;
}
''',
      }, messageContains: 'flat file directly in');
    });

    test('ui/widgets/common/ is grouped, never flat', () {
      expectsOnly('W1', {
        'ui/widgets/common/nav.tsx':
            'export default function Nav() { return <nav></nav>; }\n',
        'ui/views/main_shell/design/chat/chat_view.tsx': '''
import Toolbar from '../../../../widgets/main_shell_widgets/toolbar.tsx';
import Nav from '../../../../widgets/common/nav.tsx';
export default function ChatView() {
  return <main><Toolbar /><Nav /></main>;
}
''',
      }, messageContains: 'grouped, never flat');
    });

    test('an unnamed group is reported with the documented exception', () {
      expectsOnly('W1', {
        'ui/widgets/toolbox/nav.tsx':
            'export default function Nav() { return <nav></nav>; }\n',
        'ui/views/main_shell/design/chat/chat_view.tsx': '''
import Toolbar from '../../../../widgets/main_shell_widgets/toolbar.tsx';
import Nav from '../../../../widgets/toolbox/nav.tsx';
export default function ChatView() {
  return <main><Toolbar /><Nav /></main>;
}
''',
      }, messageContains: 'mouse_transforms');
    });
  });

  group('W2 dead widgets', () {
    test('a widget with zero importers fails', () {
      expectsOnly('W2', {
        'ui/widgets/common/panels/ghost.tsx':
            'export default function Ghost() { return <i></i>; }\n',
      }, messageContains: 'zero importers');
    });

    test(
        'the common/ root barrel is exempt: flat under common/ and '
        'unimported by design (anatomy §2)', () {
      final notes = <LintFinding>[];
      final findings = gateDesignWidgets(
          _tree(tmp, {
            'ui/widgets/common/widgets.tsx':
                "export * from './panels/_panel.tsx';\n"
                "export * from './chips/chip.tsx';\n",
          }),
          notes: notes);
      expect(findings, isEmpty,
          reason: 'the root barrel is a mandated fixture, not a widget:\n'
              '${findings.join('\n')}');
    });

    test('a flat non-barrel under common/ is still W1, not exempted', () {
      expectsOnly('W1', {
        'ui/widgets/common/util.tsx':
            'export default function Util() { return <i></i>; }\n',
        'ui/views/main_shell/design/chat/chat_view.tsx': '''
import Toolbar from '../../../../widgets/main_shell_widgets/toolbar.tsx';
import Util from '../../../../widgets/common/util.tsx';
export default function ChatView() {
  return <main><Toolbar /><Util /></main>;
}
''',
      }, messageContains: 'the one exception');
    });
  });

  group('W3 panels instantiated, never re-implemented', () {
    test('skeleton classes outside _panel.tsx fail', () {
      expectsOnly('W3', {
        'ui/widgets/main_shell_widgets/toolbar.tsx':
            'export default function Toolbar() { return <div class="panel-top panel-body">rolled my own</div>; }\n',
      }, messageContains: 'instantiate the base');
    });

    test('skeleton classes in a computed class string fail too', () {
      // hono/jsx class props are often backtick templates; quoting the attr is
      // not an escape from W3.
      expectsOnly('W3', {
        'ui/widgets/main_shell_widgets/toolbar.tsx':
            'export default function Toolbar({ x }) { return <div class={`panel-top \${x}`}>rolled my own</div>; }\n',
      }, messageContains: 'instantiate the base');
    });

    test('role markers and innocuous descendants stay legal', () {
      final findings = gateDesignWidgets(_tree(tmp, {
        'ui/widgets/main_shell_widgets/toolbar.tsx':
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
            'ui/widgets/common/panels/_panel.tsx': _deleted,
            'ui/widgets/main_shell_widgets/_panel.tsx': '''
export default function Panel({ role, children }) {
  return (
    <section class="panel panel-frame">
      <div class="panel-body">{children}</div>
    </section>
  );
}
''',
            // The roles no longer import a base from ui/common.
            'ui/widgets/common/panels/header_panel.tsx':
                'export default function HeaderPanel() { return <div class="panel-header">h</div>; }\n',
            'ui/widgets/common/panels/main_panel.tsx':
                'export default function MainPanel() { return <div class="panel-main">m</div>; }\n',
            // The toolbar composes the relocated base, so it has a consumer.
            'ui/widgets/main_shell_widgets/toolbar.tsx': '''
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
            'ui/widgets/common/panels/_panel.tsx': _deleted,
            'ui/widgets/common/panels/header_panel.tsx':
                'export default function HeaderPanel() { return <div class="panel-header">h</div>; }\n',
            'ui/widgets/common/panels/main_panel.tsx':
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
import HeaderPanel from '../../widgets/common/panels/header_panel.tsx';
import MainPanel from '../../widgets/common/panels/main_panel.tsx';
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
import HeaderPanel from '../../widgets/common/panels/header_panel.tsx';
import MainPanel from '../../widgets/common/panels/main_panel.tsx';
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
import HeaderPanel from '../../widgets/common/panels/header_panel.tsx';
import { Open as MainOpen } from '../../widgets/common/panels/main_panel.tsx';
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
import HeaderPanel from '../../widgets/common/panels/header_panel.tsx';
import MainPanel, { PanelBar, View as MainView } from '../../widgets/common/panels/main_panel.tsx';
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
        'ui/widgets/main_shell_widgets/activity_panel.tsx': '''
export function Open({ spec, children }) {
  return <aside class="panel-activity">{children}</aside>;
}
''',
        'ui/views/main_shell/design/_shared.tsx': '''
import { Open as ActivityOpen } from '../../../widgets/main_shell_widgets/activity_panel.tsx';
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
        'ui/widgets/main_shell_widgets/activity_panel.tsx': '''
export function Open({ spec, children }) {
  return <aside class="panel-activity">{children}</aside>;
}
''',
        'ui/views/main_shell/design/_shared.tsx': '''
import { Open as ActivityOpen } from '../../../widgets/main_shell_widgets/activity_panel.tsx';
export function DesignShared({ spec }) {
  return <ActivityOpen spec={spec} />;
}
''',
        'ui/views/main_shell/design/prototype/prototype_view.tsx': '''
import { Open as ActivityOpen } from '../../../../widgets/main_shell_widgets/activity_panel.tsx';
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
        'ui/widgets/main_shell_widgets/activity_panel.tsx': '''
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
import { Open as ActivityOpen } from '../../../widgets/main_shell_widgets/activity_panel.tsx';
export function DesignShared({ spec }) {
  return <ActivityOpen spec={spec}>body</ActivityOpen>;
}
''',
        'ui/views/main_shell/design/prototype/prototype_view.tsx': '''
import { Top as ActivityTop, Bottom as ActivityBottom } from '../../../../widgets/main_shell_widgets/activity_panel.tsx';
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
        'ui/widgets/main_shell_widgets/mini_panel.tsx':
            'export default function MiniPanel() { return <div class="mini"></div>; }\n',
        'ui/widgets/main_shell_widgets/toolbar.tsx': '''
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
        'ui/widgets/common/panels/sidebar_panel.tsx':
            'export default function SidebarPanel() { return <aside></aside>; }\n',
        'ui/views/main_shell/main_shell_view.tsx': '''
import HeaderPanel from '../../widgets/common/panels/header_panel.tsx';
import MainPanel from '../../widgets/common/panels/main_panel.tsx';
import SidebarPanel from '../../widgets/common/panels/sidebar_panel.tsx';
export default function MainShellView() {
  return <main><HeaderPanel /><MainPanel /><SidebarPanel /></main>;
}
''',
        'ui/views/app_shell/app_shell_view.tsx': '''
import HeaderPanel from '../../widgets/common/panels/header_panel.tsx';
import MainPanel from '../../widgets/common/panels/main_panel.tsx';
import SidebarPanel from '../../widgets/common/panels/sidebar_panel.tsx';
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
        'ui/widgets/main_brief_widgets/row.tsx':
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
import Toolbar from '../../../../widgets/main_shell_widgets/toolbar.tsx';
import { Chip } from '../../../../widgets/common/chips/chip.tsx';
import Row from '../../../../widgets/main_brief_widgets/row.tsx';
export default function BriefView() {
  return <main><Toolbar /><Chip text="a" /><Row /><span>Raw text</span></main>;
}
''',
      }, messageContains: 'author via Label/Heading/Txt');
    });

    test('an interactive <button> without identity fails even with no text', () {
      expectsOnly('W7', {
        'ui/views/main_shell/intake/brief/brief_view.tsx': '''
import Toolbar from '../../../../widgets/main_shell_widgets/toolbar.tsx';
import { Chip } from '../../../../widgets/common/chips/chip.tsx';
import Row from '../../../../widgets/main_brief_widgets/row.tsx';
export default function BriefView() {
  return <main><Toolbar /><Chip text="a" /><Row /><button /></main>;
}
''',
      }, messageContains: 'wrap this <button>');
    });

    test('a library widget invocation (Capitalized tag) bearing text passes', () {
      final findings = gateDesignWidgets(_tree(tmp, {
        'ui/views/main_shell/intake/brief/brief_view.tsx': '''
import Toolbar from '../../../../widgets/main_shell_widgets/toolbar.tsx';
import { Chip } from '../../../../widgets/common/chips/chip.tsx';
import Row from '../../../../widgets/main_brief_widgets/row.tsx';
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
import Toolbar from '../../../../widgets/main_shell_widgets/toolbar.tsx';
import { Chip } from '../../../../widgets/common/chips/chip.tsx';
import Row from '../../../../widgets/main_brief_widgets/row.tsx';
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
import Toolbar from '../../../../widgets/main_shell_widgets/toolbar.tsx';
import { Chip } from '../../../../widgets/common/chips/chip.tsx';
import Row from '../../../../widgets/main_brief_widgets/row.tsx';
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
        'ui/widgets/main_brief_widgets/raw_label.tsx':
            'export default function RawLabel() { return <span>Raw text</span>; }\n',
        'ui/views/main_shell/intake/brief/brief_view.tsx': '''
import Toolbar from '../../../../widgets/main_shell_widgets/toolbar.tsx';
import { Chip } from '../../../../widgets/common/chips/chip.tsx';
import Row from '../../../../widgets/main_brief_widgets/row.tsx';
import RawLabel from '../../../../widgets/main_brief_widgets/raw_label.tsx';
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

    test('direct text in a non-text-bearing role (card) fails', () {
      // A card has identity (data-el) and role "card", which is not a
      // text-bearing role. Text directly inside it is unreachable on inspect.
      expectsOnly('W7', {
        'ui/views/main_shell/intake/brief/brief_view.tsx': '''
import Toolbar from '../../../../widgets/main_shell_widgets/toolbar.tsx';
import { Chip } from '../../../../widgets/common/chips/chip.tsx';
import Row from '../../../../widgets/main_brief_widgets/row.tsx';
export default function BriefView() {
  return <main><Toolbar /><Chip text="a" /><Row /><div data-el="card:X" data-inspect-role="card">hello</div></main>;
}
''',
      }, messageContains: 'author via Label/Heading/Txt');
    });

    test('text in a container-role card via child span fails (span has no identity)', () {
      expectsOnly('W7', {
        'ui/views/main_shell/intake/brief/brief_view.tsx': '''
import Toolbar from '../../../../widgets/main_shell_widgets/toolbar.tsx';
import { Chip } from '../../../../widgets/common/chips/chip.tsx';
import Row from '../../../../widgets/main_brief_widgets/row.tsx';
export default function BriefView() {
  return <main><Toolbar /><Chip text="a" /><Row /><div data-el="card:X" data-inspect-role="card"><span>hello</span></div></main>;
}
''',
      }, messageContains: 'author via Label/Heading/Txt');
    });

    test('data-el with no data-inspect-role and direct text passes (role unknown)', () {
      // A bare data-el with no role metadata: the gate cannot determine the
      // role, so it is lenient — the author put identity on it.
      final findings = gateDesignWidgets(_tree(tmp, {
        'ui/views/main_shell/intake/brief/brief_view.tsx': '''
import Toolbar from '../../../../widgets/main_shell_widgets/toolbar.tsx';
import { Chip } from '../../../../widgets/common/chips/chip.tsx';
import Row from '../../../../widgets/main_brief_widgets/row.tsx';
export default function BriefView() {
  return <main><Toolbar /><Chip text="a" /><Row /><div data-el="label:X">text</div></main>;
}
''',
      }));
      expect(findings, isEmpty, reason: findings.join('\n'));
    });

    test('text in a text-bearing role (button with data-el) passes', () {
      final findings = gateDesignWidgets(_tree(tmp, {
        'ui/views/main_shell/intake/brief/brief_view.tsx': '''
import Toolbar from '../../../../widgets/main_shell_widgets/toolbar.tsx';
import { Chip } from '../../../../widgets/common/chips/chip.tsx';
import Row from '../../../../widgets/main_brief_widgets/row.tsx';
export default function BriefView() {
  return <main><Toolbar /><Chip text="a" /><Row /><button data-el="btn:go" data-inspect-role="button">Go</button></main>;
}
''',
      }));
      expect(findings, isEmpty, reason: findings.join('\n'));
    });
  });

  group('W8 factor variants', () {
    test('a stated view missing one variant fails', () {
      expectsOnly(
          'W8',
          {
            'ui/views/app_shell/auth/auth_view.tablet.tsx': _deleted,
          },
          messageContains: 'auth_view.tablet.tsx');
    });

    test('a stated view missing all three names every missing file', () {
      final findings = gateDesignWidgets(_tree(tmp, {
        'ui/views/main_shell/intake/brief/brief_view.desktop.tsx': _deleted,
        'ui/views/main_shell/intake/brief/brief_view.tablet.tsx': _deleted,
        'ui/views/main_shell/intake/brief/brief_view.mobile.tsx': _deleted,
      }));
      expect(_rules(findings), {'W8'}, reason: findings.join('\n'));
      final msg = findings.map((f) => f.message).join('\n');
      expect(msg, contains('brief_view.desktop.tsx'));
      expect(msg, contains('brief_view.tablet.tsx'));
      expect(msg, contains('brief_view.mobile.tsx'));
    });

    test('a view without a viewmodel is a static partial — no variants owed',
        () {
      final findings = gateDesignWidgets(_tree(tmp, {
        'ui/views/app_shell/legal/legal_view.tsx':
            'export default function LegalView() { return <main></main>; }\n',
      }));
      expect(findings, isEmpty, reason: findings.join('\n'));
    });
  });

  group('import graph', () {
    test('records relative TSX imports as root-relative edges', () {
      final graph = buildIncludeGraph(_tree(tmp, const {}));
      expect(graph['ui/widgets/common/chips/chip.tsx'],
          containsAll([
            'ui/views/main_shell/intake/brief/brief_view.tsx',
            'ui/views/app_shell/auth/auth_view.tsx',
          ]));
      expect(graph['ui/widgets/common/panels/_panel.tsx'],
          containsAll([
            'ui/widgets/common/panels/header_panel.tsx',
            'ui/widgets/common/panels/main_panel.tsx',
          ]));
    });

    test('bare specifiers are not edges', () {
      // A package import ('hono/jsx') names no file in the tree; recording it
      // would read every hono component as a consumed widget.
      final graph = buildIncludeGraph(_tree(tmp, {
        'ui/widgets/common/chips/chip.tsx': '''
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
