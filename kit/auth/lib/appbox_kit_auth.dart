/// appbox_kit_auth — the API-first identity seam for appbox_kit apps.
///
/// Depend on [KitAuthService]; branch on the sealed [AuthResult]. The
/// in-memory default ([InMemoryKitAuthService]) is real enough to build the
/// full auth UI against; the Seed backend and native OAuth are later phases.
library;

// Models
export 'src/models/auth_credentials.dart';
export 'src/models/auth_failure.dart';
export 'src/models/auth_result.dart';
export 'src/models/auth_session.dart';
export 'src/models/auth_user.dart';

// Service (the port + implemented default backend)
export 'src/service/kit_auth_service.dart';
export 'src/service/in_memory_auth_service.dart';

// OAuth providers — port + stubs (phase-later)
export 'src/providers/kit_oauth_provider.dart';
export 'src/providers/apple/apple_sign_in_provider.dart';
export 'src/providers/google/google_sign_in_provider.dart';

// Seed backend seam — stub (phase-4)
export 'src/backends/seed_auth_backend.dart';

// Access policy — claims-based RBAC (role claim on AuthUser.metadata).
// Backend-agnostic; the host app resolves email→role. See CONTEXT.md.
export 'src/policy/kit_access_policy.dart';
export 'src/policy/kit_can.dart';
