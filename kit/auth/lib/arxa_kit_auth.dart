/// arxa_kit_auth — the API-first identity seam for arxa_kit apps.
///
/// Depend on [ArxaKitAuthService]; branch on the sealed [ArxaKitAuthResult]. The
/// in-memory default ([InMemoryArxaKitAuthService]) is real enough to build the
/// full auth UI against; [ArxaKitSeedAuthBackend] adds the deterministic seeded
/// accounts the showcase promises, and the Apple/Google [ArxaKitOAuthProvider]s
/// run the native OAuth flows.
library;

// Models
export 'src/models/arxa_kit_auth_credentials.dart';
export 'src/models/arxa_kit_auth_failure.dart';
export 'src/models/arxa_kit_auth_result.dart';
export 'src/models/arxa_kit_auth_session.dart';
export 'src/models/arxa_kit_auth_user.dart';

// Service (the port + implemented default backend)
export 'src/service/arxa_kit_auth_service.dart';
export 'src/service/arxa_kit_in_memory_auth_service.dart';

// OAuth providers — port + native implementations (Apple / Google)
export 'src/providers/arxa_kit_oauth_provider.dart';
export 'src/providers/apple/arxa_kit_apple_sign_in_provider.dart';
export 'src/providers/google/arxa_kit_google_sign_in_provider.dart';

// Seed backend — deterministic seeded accounts (port of the tier1 spec)
export 'src/backends/arxa_kit_seed_auth_backend.dart';

// Access policy — claims-based RBAC (role claim on ArxaKitAuthUser.metadata).
// Backend-agnostic; the host app resolves email→role. See CONTEXT.md.
export 'src/policy/arxa_kit_access_policy.dart';
export 'src/policy/arxa_kit_can.dart';
