-- The Arxa Dial's central store (locked amendment 2026-08-23:
-- 'the feedback dial becomes the Arxa Dial', decisions 6/7/9/11).
--
-- One operator-owned Supabase project; every design server and deployed
-- preview Worker holds the SERVICE key and proxies — clients never see an
-- anon key, so RLS here is deliberately 'enabled, zero policies': the
-- service role bypasses RLS, and every other role is denied by default.
-- Do NOT add anon/authenticated policies without amending the amendment.
--
-- Apply:  psql "$ARXA_SUPABASE_DB_URL" -f 20260823_arxa_dial.sql
--   or    paste into the SQL editor of the operator project.

begin;

-- Pins (decision 6): anchored to W7 data-el identity when there is one,
-- rect snapshot ALWAYS stored so a removed element leaves an Orphaned Pin.
create table if not exists arxa_dial_pins (
  id          uuid primary key,
  artifact    text not null,
  route       text not null,
  viewport_w  integer not null check (viewport_w between 1 and 10000),
  viewport_h  integer not null check (viewport_h between 1 and 10000),
  anchor_el   text,
  rect        jsonb not null,
  status      text not null default 'open'
              check (status in ('open','triaged','in_progress','resolved','wont_do')),
  author_kind text not null check (author_kind in ('author','guest')),
  author_name text not null,
  body        text not null check (char_length(body) between 1 and 4000),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists arxa_dial_pins_artifact_route
  on arxa_dial_pins (artifact, route);

create table if not exists arxa_dial_replies (
  id          uuid primary key,
  pin_id      uuid not null references arxa_dial_pins (id) on delete cascade,
  author_kind text not null check (author_kind in ('author','guest')),
  author_name text not null,
  body        text not null check (char_length(body) between 1 and 4000),
  created_at  timestamptz not null default now()
);
create index if not exists arxa_dial_replies_pin on arxa_dial_replies (pin_id);

-- Share Links (decision 7): scoped, expiring, comment-level. The RAW token
-- is shown once at minting and never stored — only its sha256. A guest
-- arriving with a raw token is resolved by hashing and matching here.
create table if not exists arxa_dial_share_links (
  token_hash  text primary key,
  artifact    text not null,
  expires_at  timestamptz,
  created_at  timestamptz not null default now()
);
create index if not exists arxa_dial_share_links_artifact
  on arxa_dial_share_links (artifact);

alter table arxa_dial_pins enable row level security;
alter table arxa_dial_replies enable row level security;
alter table arxa_dial_share_links enable row level security;
-- No policies on purpose: service-role only. See the header comment.

-- Realtime publication so the Publish slice's cross-runtime delivery
-- (guest pins on the deployed Worker arriving in the local session) can
-- subscribe without a schema change.
alter publication supabase_realtime add table arxa_dial_pins;
alter publication supabase_realtime add table arxa_dial_replies;

commit;
