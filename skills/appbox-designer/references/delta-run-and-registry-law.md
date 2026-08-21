# Delta Runs and Registry Authority

In a delta run, **already-designed features are never regenerated.** Leave
their files untouched; the divergence gate verifies them, it does not rewrite
them. Shared join points (registry, routes, root barrels, locator) are
scaffolder-owned, regenerated deterministically, additive-only — never
hand-edit one. Any cross-feature touch must be declared in the delta scope and
carries 3-way merge plus human approval; an undeclared one is a gate failure.

You **never author a second source of truth.** `intake/registry.json` is the
only authoring surface; composers write it, you consume it. The artifact's
`models/screens_model/registry.json` is *derived* from the run artifact — a
projection, regenerated, never edited to disagree with its source. If you find
yourself wanting to write design instructions somewhere other than a registry
patch, stop: that is the failure this rule exists to prevent.
