/// appbox_kit_auth — the API-first identity seam for appbox_kit apps.
///
/// Depend on [AppBoxKitAuthService]; branch on the sealed [AppBoxKitAuthResult]. The
/// in-memory default ([InMemoryAppBoxKitAuthService]) is real enough to build the
/// full auth UI against; [AppBoxKitSeedAuthBackend] adds the deterministic seeded
/// accounts the showcase promises, and the Apple/Google [AppBoxKitOAuthProvider]s
/// run the native OAuth flows.
library;

// Models
export 'src/models/appbox_kit_auth_credentials.dart';
export 'src/models/appbox_kit_auth_failure.dart';
export 'src/models/appbox_kit_auth_result.dart';
export 'src/models/appbox_kit_auth_session.dart';
export 'src/models/appbox_kit_auth_user.dart';

// Service (the port + implemented default backend)
export 'src/service/appbox_kit_auth_service.dart';
export 'src/service/appbox_kit_in_memory_auth_service.dart';

// OAuth providers — port + native implementations (Apple / Google)
export 'src/providers/appbox_kit_oauth_provider.dart';
export 'src/providers/apple/appbox_kit_apple_sign_in_provider.dart';
export 'src/providers/google/appbox_kit_google_sign_in_provider.dart';

// Seed backend — deterministic seeded accounts (port of the tier1 spec)
export 'src/backends/appbox_kit_seed_auth_backend.dart';

// Access policy — claims-based RBAC (role claim on AppBoxKitAuthUser.metadata).
// Backend-agnostic; the host app resolves email→role. See CONTEXT.md.
export 'src/policy/appbox_kit_access_policy.dart';
export 'src/policy/appbox_kit_can.dart';
