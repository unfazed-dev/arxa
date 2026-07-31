import 'package:flutter/widgets.dart';

import '../models/auth_user.dart';
import 'kit_access_policy.dart';

/// Hides or replaces its [child] based on the [KitAccessPolicy]. This is the
/// UI-affordance layer (C14): admin-only edit buttons wrap their content in
/// [KitCan] so they simply don't render for customers. It is DECORATIVE
/// enforcement — the authoritative check is [KitAccessPolicy.enforce] in the
/// facade (C15). Never rely on this alone for security.
///
/// Pure widget by design: the host passes the current [user] (from its auth
/// stream) and the [policy]. No locator coupling, no side effects — fully
/// testable in isolation.
class KitCan extends StatelessWidget {
  const KitCan({
    super.key,
    required this.action,
    required this.policy,
    required this.user,
    required this.child,
    this.fallback,
  });

  /// The action id to check against [KitAccessPolicy.actions].
  final String action;

  final KitAccessPolicy policy;

  /// The current user, or null if signed out.
  final AuthUser? user;

  /// Rendered when the user MAY perform [action].
  final Widget child;

  /// Rendered when denied. Defaults to nothing ([SizedBox.shrink]).
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    return policy.can(action, user) ? child : (fallback ?? const SizedBox.shrink());
  }
}
