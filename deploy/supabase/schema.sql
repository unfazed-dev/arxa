-- Entitlement backend schema (docs/plans/entitlement-backend-runbook.md §2, D18).
-- Apply once per Supabase project: `supabase db push` (as a migration) or paste
-- into the SQL editor. RLS: users read their own rows; ALL writes are
-- service-role-only (the /activate Edge Function and the Stripe webhook,
-- never the client) — the service role bypasses RLS.

-- Stripe mirror; the webhook is the only writer.
create table subscriptions (
  user_id              uuid primary key references auth.users,
  stripe_customer_id   text not null,
  stripe_subscription_id text not null,
  tier                 text not null check (tier in ('pro', 'scale')),
  status               text not null,  -- Stripe's, verbatim
  current_period_end   timestamptz not null,
  updated_at           timestamptz not null default now()
);

-- What the user may do. One row per (user, feature).
create table entitlements (
  user_id    uuid not null references auth.users,
  feature    text not null,            -- 'emit.scaffold' today
  status     text not null check (status in ('active', 'past_due', 'canceled')),
  expires_at timestamptz not null,
  primary key (user_id, feature)
);

-- Seat cap: 3 machines per user, self-service deactivation.
create table machines (
  user_id           uuid not null references auth.users,
  fingerprint_sha256 text not null,    -- the fpr claim; hashed, never raw
  platform          text not null,     -- 'macos' | 'windows' | 'linux'
  activated_at      timestamptz not null default now(),
  last_seen_at      timestamptz not null default now(),
  deactivated_at    timestamptz,       -- null = active seat
  primary key (user_id, fingerprint_sha256)
);

alter table subscriptions enable row level security;
alter table entitlements enable row level security;
alter table machines enable row level security;

-- Read-own-rows policies on all three; deliberately NO insert/update/delete
-- policies — writes go through the service role, which bypasses RLS.
create policy "users read own subscriptions" on subscriptions
  for select using (auth.uid() = user_id);
create policy "users read own entitlements" on entitlements
  for select using (auth.uid() = user_id);
create policy "users read own machines" on machines
  for select using (auth.uid() = user_id);


-- ── Round 2 (2026-08-05): orgs, support, feedback, analytics, audit, chat ──
-- Decisions: docs/plans/arxa-data-model-decisions.md. Same rules as above:
-- RLS read-own / read-own-org, ALL writes service-role-only (the Edge
-- Functions, never the client) — the service role bypasses RLS.

-- Enterprise tenants. Individual-tier users have NO org row: every org_id
-- below is nullable and stays null on that path, so today's single-user
-- shape is unchanged; enterprise links the same per-user rows to an org.
create table orgs (
  id               uuid primary key default gen_random_uuid(),
  name             text not null,
  slug             text not null unique,
  analytics_opt_in boolean not null default false,  -- metadata-only analytics, per-org opt-in
  created_at       timestamptz not null default now()
);

-- Permission matrix (documentation ONLY — enforcement lands in the Edge
-- Functions; the RLS below guarantees read-own-org + service-role writes):
--
--   capability                   owner  admin  billing  member
--   ---------------------------  -----  -----  -------  ------
--   manage org settings            ✓      ·       ·       ·
--   add / remove members           ✓      ✓       ·       ·
--   change roles                   ✓      ·       ·       ·
--   manage billing / subscription  ✓      ·       ✓       ·
--   manage seats / licences        ✓      ✓       ·       ·
--   view audit_log                 ✓      ✓       ·       ·
--   create / reply to tickets      ✓      ✓       ✓       ✓
--   use support chat               ✓      ✓       ✓       ✓
--
-- totem_staff is orthogonal to role: a Totem employee flagged on ANY org
-- membership gets read access across orgs for support (is_totem_staff()
-- below). Set by the service role only, never self-service.
create table org_members (
  org_id      uuid not null references orgs on delete cascade,
  user_id     uuid not null references auth.users,
  role        text not null check (role in ('owner', 'admin', 'billing', 'member')),
  totem_staff boolean not null default false,
  created_at  timestamptz not null default now(),
  primary key (org_id, user_id)
);

-- RLS helpers. SECURITY DEFINER so policies can consult org_members without
-- infinite recursion (a policy on org_members may not subquery org_members
-- directly); the function owner bypasses RLS.
create or replace function is_org_member(p_org_id uuid)
  returns boolean language sql stable security definer
  set search_path = public as
$$ select exists (
     select 1 from org_members
     where org_id = p_org_id and user_id = auth.uid()) $$;

create or replace function is_totem_staff()
  returns boolean language sql stable security definer
  set search_path = public as
$$ select exists (
     select 1 from org_members
     where user_id = auth.uid() and totem_staff) $$;

-- Individual-tier user preferences (orgs carry their own flags above).
create table user_prefs (
  user_id          uuid primary key references auth.users,
  analytics_opt_in boolean not null default false
);

-- Org linkage for the round-1 tables: nullable, individual path untouched;
-- enterprise sets it on the same per-user rows (keys stay user-keyed).
alter table subscriptions add column org_id uuid references orgs;
alter table entitlements  add column org_id uuid references orgs;
alter table machines      add column org_id uuid references orgs;

-- Support queue. org_id null = individual-tier reporter.
create table tickets (
  id         uuid primary key default gen_random_uuid(),
  org_id     uuid references orgs,
  user_id    uuid not null references auth.users,  -- reporter
  subject    text not null,
  status     text not null default 'open'
             check (status in ('open', 'pending', 'resolved', 'closed')),
  priority   text not null default 'normal'
             check (priority in ('low', 'normal', 'high', 'urgent')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table ticket_messages (
  id              uuid primary key default gen_random_uuid(),
  ticket_id       uuid not null references tickets on delete cascade,
  author_id       uuid references auth.users,   -- null = system-generated
  body            text not null,
  attachment_path text,   -- storage ref for the Flutter feedback kit's UI
                          -- capture; a path, NEVER a blob
  created_at      timestamptz not null default now()
);

-- In-product feedback: thumbs / comments / NPS, keyed by surface id.
create table feedback (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users,
  org_id     uuid references orgs,
  surface    text not null,     -- surface id the feedback came from
  locale     text not null,
  kind       text not null check (kind in ('thumbs_up', 'thumbs_down', 'comment', 'nps')),
  score      integer check (score between 0 and 10),  -- NPS only; null otherwise
  comment    text,
  created_at timestamptz not null default now()
);

-- ╔══════════════════════════════════════════════════════════════════╗
-- ║ METADATA-ONLY BY LAW. This table may NEVER gain content columns: ║
-- ║ no prompt text, no file names or paths, no document bodies, no   ║
-- ║ free text, no jsonb payloads. Event names, counts, durations and ║
-- ║ verdicts only. Collection is opt-in (orgs.analytics_opt_in /     ║
-- ║ user_prefs.analytics_opt_in) — writers MUST check the flag.      ║
-- ╚══════════════════════════════════════════════════════════════════╝
create table analytics_events (
  id          bigint generated always as identity primary key,
  org_id      uuid references orgs,             -- null = individual-tier user
  user_id     uuid references auth.users,
  event       text not null,   -- event name, from a fixed client-side vocabulary
  count       integer,         -- occurrences, if the event aggregates
  duration_ms integer,         -- runtime, if the event is timed
  verdict     text,            -- e.g. 'valid' | 'grace' | 'expired' | 'invalid'
  occurred_at timestamptz not null default now()
);

-- Org-scoped who/what/when: members, licences, seats, ticket actions.
create table audit_log (
  id          bigint generated always as identity primary key,
  org_id      uuid not null references orgs,
  actor_id    uuid references auth.users,  -- who; null = service role / system
  action      text not null,   -- e.g. 'member.added', 'seat.activated', 'ticket.escalated'
  target_type text not null,   -- 'member' | 'licence' | 'seat' | 'ticket'
  target_id   text not null,
  created_at  timestamptz not null default now()
);

-- LLM-first support chat; escalates to a human and links a ticket.
create table chat_conversations (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users,
  org_id     uuid references orgs,
  state      text not null default 'llm_attending'
             check (state in ('llm_attending', 'escalated', 'human_attending', 'resolved')),
  ticket_id  uuid references tickets,  -- set when state leaves 'llm_attending'
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table chat_messages (
  id              bigint generated always as identity primary key,
  conversation_id uuid not null references chat_conversations on delete cascade,
  role            text not null check (role in ('user', 'assistant', 'human')),
  body            text not null,
  created_at      timestamptz not null default now()
);

alter table orgs               enable row level security;
alter table org_members        enable row level security;
alter table user_prefs         enable row level security;
alter table tickets            enable row level security;
alter table ticket_messages    enable row level security;
alter table feedback           enable row level security;
alter table analytics_events   enable row level security;
alter table audit_log          enable row level security;
alter table chat_conversations enable row level security;
alter table chat_messages      enable row level security;

-- Read policies only; deliberately NO insert/update/delete policies — writes
-- go through the service role, which bypasses RLS. The round-1 tables keep
-- their read-own-rows policies above; enterprise org reads of subscriptions /
-- entitlements / machines happen server-side via the service role, not RLS.
create policy "members read own org" on orgs
  for select using (is_org_member(id) or is_totem_staff());
create policy "members read own org members" on org_members
  for select using (is_org_member(org_id) or is_totem_staff());
create policy "users read own prefs" on user_prefs
  for select using (auth.uid() = user_id);
create policy "users read own org tickets" on tickets
  for select using (user_id = auth.uid() or is_org_member(org_id)
                    or is_totem_staff());
create policy "users read own org ticket messages" on ticket_messages
  for select using (exists (
    select 1 from tickets t
    where t.id = ticket_id
      and (t.user_id = auth.uid() or is_org_member(t.org_id)
           or is_totem_staff())));
create policy "users read own feedback" on feedback
  for select using (user_id = auth.uid() or is_totem_staff());
create policy "users read own analytics" on analytics_events
  for select using (user_id = auth.uid() or is_org_member(org_id)
                    or is_totem_staff());
create policy "members read own org audit log" on audit_log
  for select using (is_org_member(org_id) or is_totem_staff());
create policy "users read own org conversations" on chat_conversations
  for select using (user_id = auth.uid() or is_org_member(org_id)
                    or is_totem_staff());
create policy "users read own org chat messages" on chat_messages
  for select using (exists (
    select 1 from chat_conversations c
    where c.id = conversation_id
      and (c.user_id = auth.uid() or is_org_member(c.org_id)
           or is_totem_staff())));
