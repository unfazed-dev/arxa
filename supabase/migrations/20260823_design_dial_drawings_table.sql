-- Design Dial drawings storage amendment (2026-08-23, operator decision):
-- drawings move from design_dial_pins.drawing (jsonb column, added by
-- 20260823_design_dial_drawings.sql) into their own table. The MODEL is
-- unchanged — a drawing still never exists standalone; it is a mandatory
-- 1:1 child of its pin (the pub.dev feedback package model, decision 14).
-- Only the STORAGE changes: relational rows instead of a column, keeping
-- the door open for per-stroke editing without another migration.

begin;

create table if not exists design_dial_drawings (
  pin_id     uuid primary key references design_dial_pins (id) on delete cascade,
  strokes    jsonb not null,
  created_at timestamptz not null default now()
);

-- Carry over any drawings written while they lived on the pin row.
insert into design_dial_drawings (pin_id, strokes)
select id, drawing from design_dial_pins where drawing is not null
on conflict (pin_id) do nothing;

alter table design_dial_pins drop column if exists drawing;

alter table design_dial_drawings enable row level security;
-- Zero policies, same posture as every dial table: service-role only.

-- Same cross-runtime rationale as pins/replies: the Publish slice can
-- subscribe without another schema change, and a drawing event covers the
-- pin-then-drawing insert race for realtime subscribers.
alter publication supabase_realtime add table design_dial_drawings;

commit;
