/// arxa_kit_cairn — the cairn backend for arxa_kit apps.
///
/// One-stop import for the kit's public surface:
/// ```dart
/// import 'package:arxa_kit_cairn/arxa_kit_cairn.dart';
/// ```
///
/// This package OWNS the `cairn_flutter` import: apps (and other kits) never
/// depend on cairn directly. Everything cairn-flavoured reaches consumers
/// through kit types only — [ArxaKitCairnConfig] for configuration and the
/// `ArxaKitBackendPlugin` seam in `arxa_kit_data` for wiring.
///
/// Modes ([ArxaKitCairnMode]):
/// - `localOnly` — zero server, zero env; `CairnDatabase.local` under the hood.
/// - `sync` — against a self-hosted cairn server (`ARXA_CAIRN_URL`), host-supplied
///   token provider.
/// - `supabaseBridge` — Supabase JWT bridge; session tokens come from kit/data's
///   auth service, never from the environment.
library;

// Nothing from cairn_flutter is re-exported except through kit types.
export 'arxa_kit_cairn_backend.dart';
export 'auth/arxa_kit_cairn_auth_service.dart';
export 'config/arxa_kit_cairn_config.dart';
export 'emitters/cairn_schema_emitter.dart';
export 'repositories/arxa_kit_crdt_capable.dart';
export 'repositories/cairn_kit_repository.dart';
