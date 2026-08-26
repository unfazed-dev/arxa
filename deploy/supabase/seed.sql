-- Seed data for the arxa Supabase project (dev/dogfood only — NEVER prod).
-- Persona-shaped: Totem Labs org (Evan owner+staff, support admin+staff,
-- billing, member) exercising the full role matrix; Michelle as an
-- individual-tier buyer. Placeholder emails, one shared dev password.
--
--   ALL seed users sign in with password:  Arxa-Seed-2026!
--
-- Apply: paste into the SQL editor, or `psql ... -f seed.sql`, or the MCP
-- execute_sql. Idempotent: seed rows are deleted by id/email first.

begin;

-- ── auth users ──────────────────────────────────────────────────────────────
delete from auth.identities where provider = 'email' and provider_id in
  ('evan@totemlabs.dev', 'support@totemlabs.dev', 'billing@totemlabs.dev',
   'dev@totemlabs.dev', 'michelle@buyer.dev');
delete from auth.users where email in
  ('evan@totemlabs.dev', 'support@totemlabs.dev', 'billing@totemlabs.dev',
   'dev@totemlabs.dev', 'michelle@buyer.dev');

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
select
  u.id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
  u.email, crypt('Arxa-Seed-2026!', gen_salt('bf')),
  now(), now(), now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  jsonb_build_object('full_name', u.full_name),
  '', '', '', ''
from (values
  ('11111111-1111-1111-1111-111111111101'::uuid, 'evan@totemlabs.dev',    'Evan Founder'),
  ('11111111-1111-1111-1111-111111111102'::uuid, 'support@totemlabs.dev', 'Sam Support'),
  ('11111111-1111-1111-1111-111111111103'::uuid, 'billing@totemlabs.dev', 'Bill Billing'),
  ('11111111-1111-1111-1111-111111111104'::uuid, 'dev@totemlabs.dev',     'Dana Dev'),
  ('22222222-2222-2222-2222-222222222201'::uuid, 'michelle@buyer.dev',    'Michelle Buyer')
) as u(id, email, full_name);

insert into auth.identities (
  id, user_id, provider_id, provider, identity_data, created_at, updated_at
)
select
  u.ident_id, u.id, u.email, 'email',
  jsonb_build_object('sub', u.id::text, 'email', u.email),
  now(), now()
from (values
  ('11111111-1111-1111-1111-111111111101'::uuid, 'aaaaaaaa-0000-0000-0000-000000000101'::uuid, 'evan@totemlabs.dev'),
  ('11111111-1111-1111-1111-111111111102'::uuid, 'aaaaaaaa-0000-0000-0000-000000000102'::uuid, 'support@totemlabs.dev'),
  ('11111111-1111-1111-1111-111111111103'::uuid, 'aaaaaaaa-0000-0000-0000-000000000103'::uuid, 'billing@totemlabs.dev'),
  ('11111111-1111-1111-1111-111111111104'::uuid, 'aaaaaaaa-0000-0000-0000-000000000104'::uuid, 'dev@totemlabs.dev'),
  ('22222222-2222-2222-2222-222222222201'::uuid, 'aaaaaaaa-0000-0000-0000-000000000201'::uuid, 'michelle@buyer.dev')
) as u(id, ident_id, email);

-- ── org + members (full role matrix; Totem = first tenant, staff flagged) ──
delete from orgs where id = 'bbbbbbbb-0000-0000-0000-000000000001';

insert into orgs (id, name, slug, analytics_opt_in) values
  ('bbbbbbbb-0000-0000-0000-000000000001', 'Totem Labs', 'totem-labs', true);
  -- analytics_opt_in true: Totem dogfoods its own metadata-only analytics.

insert into org_members (org_id, user_id, role, totem_staff) values
  ('bbbbbbbb-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111101', 'owner',   true),
  ('bbbbbbbb-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111102', 'admin',   true),
  ('bbbbbbbb-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111103', 'billing', false),
  ('bbbbbbbb-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111104', 'member',  false);

-- ── billing + entitlement + seats ───────────────────────────────────────────
insert into subscriptions (user_id, org_id, stripe_customer_id, stripe_subscription_id, tier, status, current_period_end) values
  ('11111111-1111-1111-1111-111111111101', 'bbbbbbbb-0000-0000-0000-000000000001',
   'cus_seed_totem', 'sub_seed_totem', 'scale', 'active', now() + interval '1 year'),
  ('22222222-2222-2222-2222-222222222201', null,
   'cus_seed_michelle', 'sub_seed_michelle', 'pro', 'active', now() + interval '1 year');

insert into entitlements (user_id, org_id, feature, status, expires_at) values
  ('11111111-1111-1111-1111-111111111101', 'bbbbbbbb-0000-0000-0000-000000000001', 'emit.scaffold', 'active', now() + interval '1 year'),
  ('22222222-2222-2222-2222-222222222201', null, 'emit.scaffold', 'active', now() + interval '1 year');

insert into machines (user_id, org_id, fingerprint_sha256, platform) values
  ('11111111-1111-1111-1111-111111111101', 'bbbbbbbb-0000-0000-0000-000000000001',
   repeat('e1', 32), 'macos'),
  ('11111111-1111-1111-1111-111111111101', 'bbbbbbbb-0000-0000-0000-000000000001',
   repeat('e2', 32), 'macos'),
  ('22222222-2222-2222-2222-222222222201', null,
   repeat('m1', 32), 'macos');

insert into user_prefs (user_id, analytics_opt_in) values
  ('22222222-2222-2222-2222-222222222201', false);

-- ── support tickets (+ one chat escalation) ─────────────────────────────────
delete from tickets where id in
  ('cccccccc-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000002');

insert into tickets (id, org_id, user_id, subject, status, priority) values
  ('cccccccc-0000-0000-0000-000000000001', null,
   '22222222-2222-2222-2222-222222222201',
   'Checkout declined my card', 'open', 'high'),
  ('cccccccc-0000-0000-0000-000000000002', null,
   '22222222-2222-2222-2222-222222222201',
   'Scaffold emit fails on Windows paths', 'pending', 'normal');

insert into ticket_messages (ticket_id, author_id, body, attachment_path) values
  ('cccccccc-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222201',
   'Card declines at the plans checkout — screenshot attached.',
   'ticket-attachments/seed/capture-01.png'),
  ('cccccccc-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111102',
   'Looking into it — can you confirm the decline code on the plans page?', null),
  ('cccccccc-0000-0000-0000-000000000002', null,
   'Escalated from support chat (conversation dddddddd-…-02).', null);

-- ── feedback ────────────────────────────────────────────────────────────────
insert into feedback (user_id, org_id, surface, locale, kind, score, comment) values
  ('11111111-1111-1111-1111-111111111101', 'bbbbbbbb-0000-0000-0000-000000000001',
   'scaffold.picker', 'en', 'nps', 9, null),
  ('22222222-2222-2222-2222-222222222201', null,
   'workspace.plans', 'en', 'thumbs_down', null, 'Could not tell checkout was seeded.'),
  ('11111111-1111-1111-1111-111111111104', 'bbbbbbbb-0000-0000-0000-000000000001',
   'build.loop', 'en', 'thumbs_up', null, null);

-- ── analytics (Totem org only — the only opted-in entity) ──────────────────
insert into analytics_events (org_id, user_id, event, count, duration_ms, verdict) values
  ('bbbbbbbb-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111101',
   'gate.scaffold.run', 3, 41200, 'pass'),
  ('bbbbbbbb-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111101',
   'entitlement.verify', 12, 4, 'valid'),
  ('bbbbbbbb-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111104',
   'emit.scaffold.run', 1, 98000, 'pass');

-- ── audit log (Totem org) ───────────────────────────────────────────────────
insert into audit_log (org_id, actor_id, action, target_type, target_id) values
  ('bbbbbbbb-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111101',
   'member.added', 'member', '11111111-1111-1111-1111-111111111104'),
  ('bbbbbbbb-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111101',
   'seat.activated', 'seat', repeat('e2', 32)),
  ('bbbbbbbb-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111102',
   'ticket.escalated', 'ticket', 'cccccccc-0000-0000-0000-000000000002');

-- ── support chat (one attending, one escalated → ticket) ───────────────────
delete from chat_conversations where id in
  ('dddddddd-0000-0000-0000-000000000001', 'dddddddd-0000-0000-0000-000000000002');

insert into chat_conversations (id, user_id, org_id, state, ticket_id) values
  ('dddddddd-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222201',
   null, 'llm_attending', null),
  ('dddddddd-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222201',
   null, 'escalated', 'cccccccc-0000-0000-0000-000000000002');

insert into chat_messages (conversation_id, role, body) values
  ('dddddddd-0000-0000-0000-000000000001', 'user',
   'Where do I find my machine seats?'),
  ('dddddddd-0000-0000-0000-000000000001', 'assistant',
   'Plans → your plan badge lists active seats. You have 1 of 3 in use.'),
  ('dddddddd-0000-0000-0000-000000000002', 'user',
   'emit scaffold fails on my Windows machine with a path error.'),
  ('dddddddd-0000-0000-0000-000000000002', 'assistant',
   'I am not confident I can resolve this one — handing you to the team.'),
  ('dddddddd-0000-0000-0000-000000000002', 'human',
   'Picked up — we will reproduce on a Windows runner and follow up on the ticket.');

commit;
