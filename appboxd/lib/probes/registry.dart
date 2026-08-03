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

import 'package:appboxd/probes/probe_base.dart';
import 'package:appboxd/probes/probe_composer_draft.dart';

/// Every probe, in `probe all` run order.
const List<Probe> kProbes = <Probe>[
  composerDraftProbe,
];

/// Look up a probe by CLI name, or null if there is no such probe.
Probe? probeByName(String name) {
  for (final p in kProbes) {
    if (p.name == name) return p;
  }
  return null;
}
