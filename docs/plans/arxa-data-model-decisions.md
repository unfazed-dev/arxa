# arxa data-model decisions — round 2 (orgs, support, feedback, analytics, chat)

Status: **code-complete, not deployed** (2026-08-05). The schema lives in
`deploy/supabase/schema.sql` (round-2 section); it extends the round-1
entitlement tables (`docs/plans/entitlement-backend-runbook.md` §2) and was
verified against a scratch local Postgres — DDL applied clean and every RLS
policy was exercised with seeded orgs/users (member sees own org only, solo
user sees only own rows, `totem_staff` reads across orgs, client writes
denied). Applying it to a real Supabase project remains a §9 deploy step.

Locked decisions (do not re-litigate):

1. **Totem is the first tenant.** `org_members.totem_staff` flags Totem
   employees; `is_totem_staff()` gives them read access across orgs for
   support. The flag is service-role-set only, never self-service.
2. **Per-product projects.** Each product gets its own Supabase project; the
   schema is applied per project (same `supabase db push` path as round 1).
   No cross-product tables.
3. **Analytics is opt-in and metadata-only by law.** Collection is gated on
   `orgs.analytics_opt_in` / `user_prefs.analytics_opt_in` (default false).
   `analytics_events` carries event names, counts, durations and verdicts
   only — the boxed comment above the table forbids content columns (no
   prompt text, paths, free text, or jsonb payloads) forever.
4. **Totem-hosted LLM chat with human escalation.** `chat_conversations`
   carries the escalation state (`llm_attending → escalated →
   human_attending → resolved`) and links to a `tickets` row on escalation;
   `chat_messages.role` distinguishes `user` / `assistant` / `human`.

Shape notes:

- Tiers: **individual** (no org row, today's single-user path) and
  **enterprise** (org-backed). The round-1 tables keep their user-keyed
  primary keys and gain a **nullable `org_id`** — null on the individual
  path, so nothing existing breaks.
- Role matrix on `org_members`: owner / admin / billing / member, documented
  as a comment-block permission matrix above the table; enforcement lands in
  the Edge Functions, RLS stays read-own-org + service-role-writes.
- `ticket_messages.attachment_path` is a storage ref for the Flutter feedback
  kit's UI capture — a path, never a blob.

## Follow-up (flagged, not done in this slice)

`/activate`'s 3-seat cap (`deploy/supabase/functions/activate/index.ts`) is
**per-user**: it counts `machines` rows for one `user_id`. Enterprise orgs
need an **org-level seat policy** (pool seats across `org_members`, cap per
org, role-gated deactivation). This slice only added the nullable
`machines.org_id` linkage that such a policy would group by; `index.ts` is
deliberately untouched. Decide the enterprise seat model before the first
org-backed sale.
