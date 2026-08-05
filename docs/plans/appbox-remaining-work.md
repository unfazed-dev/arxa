# appbox — remaining work (status 2026-08-05)

Everything from the reveal-drawer handoff, the scaffold audit, the payment
swap, the design-surface round, and the hosted-backend round is merged and
green (master `ed73ea3`). What is left, in dependency order.

## Ship-blockers (the pay-at-scaffold chain)

1. **Dev-key swap** (runbook §9 step 6): replace `Entitlement.publicKey` with
   the production hex `15b672f3…e768`, delete `mint --dev`, flip
   `appboxd/test/release_gate_test.dart`. After this, dogfooding goes through
   the live `/activate` (proven working 2026-08-05) — the dev JWT dies.
2. **Stripe** (runbook §5): products/prices per tier, webhook writing
   `subscriptions`/`entitlements`. The mock checkout in the studio design
   (workspace.plans, 5 kit-mirrored states) is the design target.
3. **`appbox login` + silent refresh** (runbook §4/§6): PKCE loopback against
   the live project, 48h refresh. Seeded users exist for testing
   (see `deploy/supabase/seed.sql` header for the dev password).
4. **OAuth providers** (runbook §10): create the Google Cloud OAuth client and
   Apple Services ID + key (paid Apple Developer account required), paste into
   the dashboard. Manual, external accounts.

## Enterprise tier (post-R1)

5. **Org-level seat policy** in `/activate` (cap is per-user today).
6. **Permission-matrix enforcement** in Edge Functions (documented as a
   comment matrix on `org_members`; RLS already reads own-org).
7. **Admin/business shell surfaces** in the studio design (clients, apps,
   tickets queue, support chat console) — decided product feature
   (Totem = first tenant), not yet in the registry.

## Design / docs debt

8. **Five brief surfaces marked "(not yet in registry)"** — `app.projects`,
   `app.pairing`, `app.notifications`, `app.remote`, `main.chrome`: declare
   them or drop the intent.
9. **Three pre-existing selftest failures**: prefs full-reload
   (`prefs_viewmodel.js:31`), `POST /design/widget/clear` unreachable from
   markup, icon glyphs in `design_viewer.html`.
10. **`.kimi-code/skills/appbox-designer/` is a stale mirror** of `skills/` —
    re-sync it (do not patch).
11. **Declared-but-undesigned shells** still `surface: null`: flows, ship,
    first, website (return when they have landing screens).

## Business (non-code)

12. **Holdco + operating Pty Ltd** with a Melbourne accountant (Holdco owns
    appbox + cairn IP; opco trades) — see the round-2 grilling decisions in
    `docs/plans/appbox-data-model-decisions.md`.
13. **Stripe account + products**, Apple Developer account (both feed above).
