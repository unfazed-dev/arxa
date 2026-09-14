// Pure tap→route decision (task-tap routing): the push class rides the
// collapse key — 'task:*' pushes land on the studio root, everything else
// keeps the approvals deep link. Pure so the choice is unit-testable.

enum TapRoute { studioRoot, approvals }

TapRoute routeForTap(String? collapseKey) =>
    (collapseKey ?? '').startsWith('task')
    ? TapRoute.studioRoot
    : TapRoute.approvals;
