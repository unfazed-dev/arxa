// contract-panels — the panel shape holds on every surface the design serves.
//
// The behavioural twin of the W3/W4 lint gates: those read the templates, this
// reads what the templates rendered. Two rules, both from the panel vocabulary
// (designs/arxa-studio/ui/common/_integration_panels.md, and the base at
// shared/widgets/_panel.html):
//
//   1. A role panel is mounted AT MOST ONCE per surface. `header`, `main`,
//      `activity`, `composer`, `footer` are ROLES, not positions — a shell has
//      one of each or none. Two `.panel-main` on a page is a composition bug
//      that still renders, and renders almost right, which is why nobody
//      catches it by looking.
//   2. A panel SECTION only appears inside a role panel. The five section
//      classes are the panel's skeleton; one outside a panel is a bordered
//      strip floating in the layout, and it is invisible in review because it
//      inherits the panel's own styling.
//
// A surface with zero panels is NOT a failure. Most designs have splash, auth
// and error surfaces with no shell at all, and this probe must pass against a
// design that has no panels anywhere (hello-hda is exactly that). The count is
// printed per surface so a pass that asserted about nothing says so out loud.

import 'package:arxa/probes/contract/surface_walk.dart';
import 'package:arxa/probes/probe_base.dart';

/// `arxa design probe contract-panels`.
const Probe contractPanelsProbe = Probe(
  name: 'contract-panels',
  summary:
      'every declared surface: each role panel mounted at most once, panel sections only inside a panel',
  suite: kSuiteContract,
  // Issues GETs and nothing else — no clicks, no POSTs. It is still marked as
  // mutating, on measured evidence rather than caution: a design may DECLARE a
  // state-changing GET, and this one does (`/build/chips/pin` and its unpin
  // sibling both answer 200 and change pinned state). Walking every declared
  // GET surface therefore leaves the served project changed. Same reasoning
  // the studio panel-contract probe records for itself. The mutation is the
  // design's; the guard is ours, and it costs a disposable project.
  mutates: true,
  body: _run,
);

/// The five roles. A ROLE is not a position — see the panel vocabulary.
const List<String> _roles = [
  'header',
  'main',
  'activity',
  'composer',
  'footer',
];

/// Read the panel census from one surface.
///
/// Main frame only — `querySelectorAll` does not descend into iframes, which
/// is what keeps a canvas of screen tiles from reporting one header per tile.
const String _read = '''
(() => {
  const roles = ['header','main','activity','composer','footer'];
  // A MOUNTED PANEL is what the panel base emits: `class="panel panel-<role>"`
  // (_panel.html). The bare `.panel-<role>` class alone is the layout SLOT the
  // card fills — the panel vocabulary says so of main explicitly ("the layout
  // slot; the card is what fills it"), and the served markup agrees: /design
  // carries `<div class="panel-main" id="panel-main">` (slot) wrapping
  // `<section class="panel panel-main panel-viewer">` (card), while /intake
  // and /build carry the slot with no card at all. Counting the bare class
  // would read that pair as two main panels and red a correct composition.
  const mount = (r) => '.panel.panel-' + r;
  // The five section classes, enumerated rather than matched as `panel-*`. A
  // prefix match would be wrong four ways: the base also emits
  // `panel-size-{s,m,l}`, `panel-overlay` and `panel-resize`, and `spec.class`
  // lets any caller add its own (`panel-viewer` is one). None is a section.
  const sections = ['panel-top','panel-side-start','panel-body','panel-side-end','panel-bottom'];
  const counts = {};
  let slots = 0;
  for (const r of roles) {
    counts[r] = document.querySelectorAll(mount(r)).length;
    // Slots are counted but never asserted on, so the gap between the two
    // numbers is visible rather than something the next reader rediscovers.
    slots += document.querySelectorAll('.panel-' + r + ':not(.panel)').length;
  }
  const orphans = [];
  let sectionTotal = 0;
  for (const s of sections) {
    for (const el of document.querySelectorAll('.' + s)) {
      sectionTotal++;
      // The legal shape: a section lives inside a role panel. `closest` walks
      // self-first, so it is asked of the PARENT — a role panel that also
      // carried a section class would otherwise vouch for itself.
      const host = el.parentElement && el.parentElement.closest(
        roles.map(mount).join(','));
      if (!host) orphans.push(s + (el.id ? '#' + el.id : ''));
    }
  }
  return { counts, orphans, sectionTotal, slots };
})()''';

Future<void> _run(ProbeContext ctx) async {
  final rep = ctx.report;
  final dupes = <String>[];
  final orphans = <String>[];
  var panelTotal = 0;
  var sectionTotal = 0;
  final withPanels = <String>[];

  rep.section('panel shape across every declared surface');
  final walk = await walkSurfaces(
    ctx,
    read: _read,
    onSurface: (path, data) {
      final d = data as Map<String, dynamic>;
      final counts = (d['counts'] as Map).cast<String, dynamic>();
      final here = <String>[];
      var onSurface = 0;
      for (final role in _roles) {
        final n = (counts[role] as num?)?.toInt() ?? 0;
        panelTotal += n;
        onSurface += n;
        if (n > 0) here.add('$role=$n');
        if (n > 1) dupes.add('$path: $role mounted $n times');
      }
      sectionTotal += ((d['sectionTotal'] as num?) ?? 0).toInt();
      for (final o in (d['orphans'] as List)) {
        orphans.add('$path: $o');
      }
      if (onSurface > 0) withPanels.add(path);
      // Per-surface counts, so a vacuous-looking pass is visibly explained.
      rep.out.writeln('  $path — panels: '
          '${here.isEmpty ? 'none' : here.join(' ')}'
          ' · sections: ${(d['sectionTotal'] as num?) ?? 0}'
          ' · slots: ${(d['slots'] as num?) ?? 0}');
    },
  );

  reportWalk(rep, walk);
  rep.out.writeln('  totals: $panelTotal role panel(s) and $sectionTotal'
      ' section(s) across ${walk.loaded.length} surface(s);'
      ' ${withPanels.length} surface(s) carry at least one panel');

  // Stated rather than asserted: a design with no panels at all is a design
  // this probe has nothing to say about, and it should say so instead of
  // reporting two passes as though it had checked something.
  if (panelTotal == 0) {
    rep.skip('this design mounts no role panels on any loadable surface —'
        ' both rules below are true of an empty set, and pass vacuously');
  }

  rep.check('each role panel is mounted at most once per surface', dupes.isEmpty,
      dupes.isEmpty ? '$panelTotal panel(s) seen' : dupes.join('; '));
  rep.check('panel sections appear only inside a role panel', orphans.isEmpty,
      orphans.isEmpty
          ? '$sectionTotal section(s) seen'
          : '${orphans.length} orphan(s): ${orphans.take(8).join('; ')}');
}
