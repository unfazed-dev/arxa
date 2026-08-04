// The probe registry — the one file every probe is listed in.
//
// Adding a probe is two edits and nothing else:
//   1. write `probe_<name>.dart` exporting a `const Probe`;
//   2. add its import and one entry to [kProbes] here, in run order.
//
// Deliberately a flat list rather than a discovery mechanism: the run order is
// the list order, it is reviewable in a diff, and two agents porting different
// probes in parallel touch one line each in this file and no line of each
// other's. Order matters because `probe all` runs it top to bottom — cheap and
// read-only probes first, so a broken server fails the suite in seconds rather
// than after the slow interaction-heavy ones.

import 'package:appboxd/probes/contract/probe_contract_chips.dart';
import 'package:appboxd/probes/contract/probe_contract_panels.dart';
import 'package:appboxd/probes/probe_base.dart';
import 'package:appboxd/probes/studio/probe_boost.dart';
import 'package:appboxd/probes/studio/probe_composer_draft.dart';
import 'package:appboxd/probes/studio/probe_context_sync.dart';
import 'package:appboxd/probes/studio/probe_explode.dart';
import 'package:appboxd/probes/studio/probe_flowwalk.dart';
import 'package:appboxd/probes/studio/probe_inspect.dart';
import 'package:appboxd/probes/studio/probe_no_reload.dart';
import 'package:appboxd/probes/studio/probe_panel_contract.dart';
import 'package:appboxd/probes/studio/probe_panel_resize.dart';
import 'package:appboxd/probes/studio/probe_reveal_drawer.dart';
import 'package:appboxd/probes/studio/probe_screen_composer.dart';
import 'package:appboxd/probes/studio/probe_scroll_ownership.dart';
import 'package:appboxd/probes/studio/probe_shell_chrome.dart';
import 'package:appboxd/probes/studio/probe_widget_logic.dart';
import 'package:appboxd/probes/studio/probe_widget_tools.dart';

/// Every probe, in `probe all` run order.
const List<Probe> kProbes = <Probe>[
  // Contract suite first: these assert the appbox opinion against ANY served
  // design, so a design that violates it fails here rather than deep inside a
  // studio-specific interaction. Same doctrine as kSuiteOrder.
  contractPanelsProbe,
  contractChipsProbe,
  // First studio probe: a read-mostly walk like the contract pair above it, so
  // a scroll-doctrine break fails before the interaction-heavy probes run.
  scrollOwnershipProbe,
  boostProbe,
  composerDraftProbe,
  contextSyncProbe,
  explodeProbe,
  flowwalkProbe,
  inspectProbe,
  noReloadProbe,
  panelContractProbe,
  panelResizeProbe,
  revealDrawerProbe,
  screenComposerProbe,
  shellChromeProbe,
  widgetLogicProbe,
  widgetToolsProbe,
];

/// Look up a probe by CLI name, or null if there is no such probe.
Probe? probeByName(String name) {
  for (final p in kProbes) {
    if (p.name == name) return p;
  }
  return null;
}
