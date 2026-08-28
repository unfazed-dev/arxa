# arxa-studio-mobile — review

This stage holds pre-release QC evidence: the deterministic contract
validator (arch_guard), the over-engineering review (ponytail-review), and
the manifest hash check.

What starts it: a built target (build/ is green). The `arxa-reviewer`
skill runs both reviews and emits a green/red verdict here. Red verdicts
name the file and the rule — fix the code, never the reviewer.
