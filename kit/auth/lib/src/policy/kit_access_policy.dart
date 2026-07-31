import '../models/auth_user.dart';

/// Claims-based RBAC for a appbox_kit app — one declarative object consumed by
/// three enforcement layers (route guard, UI affordance gating, facade
/// Authority). See CONTEXT.md (Oracle App & Surfaces): Role, Access Policy,
/// Authority.
///
/// Deliberately NOT: a permissions engine, role hierarchy, ABAC, or
/// runtime-editable. Ownership rules ("edit *my* order") are facade domain
/// logic, not entries here.
///
/// Default asymmetry (load-bearing):
///   - [actions] is DENY-by-default: an unlisted action is denied to everyone.
///     Mutations must be explicit.
///   - [routes] is ALLOW-by-default: an unlisted route is open. Only
///     role-gated routes (e.g. admin) are listed.
/// A signed-out user (null) is denied every action and every listed route.
class KitAccessPolicy {
  const KitAccessPolicy({
    required this.roles,
    required this.defaultRole,
    this.routes = const {},
    this.actions = const {},
    this.roleMetadataKey = 'role',
  });

  /// Every role the app recognises. A user whose claim isn't in this set
  /// falls back to [defaultRole].
  final Set<String> roles;

  /// Role assigned to a signed-in user with no valid claim. The least-
  /// privileged real role (e.g. `customer`). Signed-OUT users are never
  /// assigned this — they get no role and are denied listed routes/actions.
  final String defaultRole;

  /// Route name → roles allowed to navigate to it. Unlisted = open.
  final Map<String, Set<String>> routes;

  /// Action id → roles allowed to perform it. Unlisted = denied.
  /// e.g. `{'product.update': {'admin'}}`.
  final Map<String, Set<String>> actions;

  /// The [AuthUser.metadata] key holding the role claim.
  final String roleMetadataKey;

  /// The role a user acts under, or [defaultRole] if their claim is absent or
  /// unrecognised. Returns `null` for a signed-out user — callers treat null
  /// as "no role, deny listed things."
  String? roleOf(AuthUser? user) {
    if (user == null) return null;
    final claim = user.metadata[roleMetadataKey];
    if (claim is String && roles.contains(claim)) return claim;
    return defaultRole;
  }

  /// May [user] perform [action]? Deny-by-default; signed-out always false.
  bool can(String action, AuthUser? user) {
    final allowed = actions[action];
    if (allowed == null) return false;
    final role = roleOf(user);
    return role != null && allowed.contains(role);
  }

  /// May [user] navigate to [routeName]? Allow-by-default; signed-out blocked
  /// only from explicitly listed routes.
  bool canRoute(String routeName, AuthUser? user) {
    final allowed = routes[routeName];
    if (allowed == null) return true;
    final role = roleOf(user);
    return role != null && allowed.contains(role);
  }

  /// Authority: throw [KitAccessDeniedError] if [user] may not perform
  /// [action]. Facades call this on every mutating op so a bypassed UI still
  /// fails — the C15 bypass test proves it.
  void enforce(String action, AuthUser? user) {
    if (!can(action, user)) {
      throw KitAccessDeniedError(action: action, role: roleOf(user));
    }
  }
}

/// Typed denial from [KitAccessPolicy.enforce]. Facades let this propagate or
/// map it onto [KitFeedback] (CONTEXT.md) — never swallow it silently.
class KitAccessDeniedError implements Exception {
  final String action;
  final String? role;
  const KitAccessDeniedError({required this.action, required this.role});

  @override
  String toString() =>
      role == null
          ? 'KitAccessDeniedError: signed-out user cannot perform "$action"'
          : 'KitAccessDeniedError: role "$role" cannot perform "$action"';
}
