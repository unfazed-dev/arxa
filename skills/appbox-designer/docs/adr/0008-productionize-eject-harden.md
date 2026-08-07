# Productionize = eject + harden, keep the Repository seam

The Productionize command transforms an Artifact into a self-contained production-grade Hono app: own package.json, Runtime inlined, MVVM structure preserved, env-based config, baseline tests, README/deploy notes. The data layer stays behind the Repository seam — fixtures keep working; each Repository is the documented swap point for a real DB. Auth and DB provisioning are deliberately not generated (product decisions a design skill shouldn't guess). Considered and rejected: eject-only (no tests/config/deploy story — "production ready" in name only), full backend generation (schema + auth + deploy — a second product hiding inside a design skill).

## Amendment (Phase 5 — eject web productionization, 2026-08-06)

Auth and DB are no longer "deliberately not generated" when a kit provides
them — they arrive through the **kit facade seam**, the same MVVM Repository
interface the fixture readers implement. The eject step copies a maintained
facade per declared kit (supabase, stripe, maps) into the ejected tree, wired
to official npm SDKs (`@supabase/supabase-js`, `stripe`, `mapbox-gl`) and env
vars sourced from `config/credentials.catalog.json`. Design-time keeps fixture
facades — the designer never sees real credentials. CI pipelines remain out
of scope.
