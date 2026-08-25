-- The Design Dial's identity + axes plane (consolidation arc 1, grilled
-- 2026-08-25): every served design registers a stable identity (project +
-- artifact + author), and the dial's style/theme axes publish per design.
-- New state rides design ids; pins/share-links keep basename keys until
-- arc 2 (guest identity) reworks them.
--
-- RLS: enabled, zero policies — the service role bypasses; every other
-- role is denied by default (the 2026-08-23 amendment's law, unchanged).
--
-- Apply:  psql "$APPBOX_SUPABASE_DB_URL" -f 20260825_design_dial_designs_axes.sql
--   or    paste into the SQL editor of the operator project.

begin;

-- Designs (arc 1): the registry — one row per served artifact, keyed by
-- (project, artifact) so two clients sharing a dir basename never collide.
-- Author attaches from ~/.appbox/identity.json; nullable so a missing
-- identity never blocks a serve.
create table if not exists design_dial_designs (
  id           uuid primary key default gen_random_uuid(),
  project      text not null,
  artifact     text not null,
  author_email text,
  author_name  text,
  created_at   timestamptz not null default now(),
  unique (project, artifact)
);

-- Axes (arc 1): the published style/theme pick per design — one row,
-- upserted on every author flip. Guests never write here; their flips
-- ride per-request URL overrides (grilled 2026-08-25).
create table if not exists design_dial_axes (
  design_id  uuid primary key references design_dial_designs (id) on delete cascade,
  style      text not null check (style ~ '^[a-z0-9-]{1,40}$'),
  theme      text not null check (theme ~ '^[a-z0-9-]{1,40}$'),
  updated_at timestamptz not null default now()
);

alter table design_dial_designs enable row level security;
alter table design_dial_axes enable row level security;

commit;
