begin;

-- Guests (arc 2, 2026-08-26): a registered reviewer of one design. The email
-- is minted by the author BEFORE the link is sent; attribution on pins and
-- replies is by construction from the personal bearer link, never typed by
-- the guest. unique(design_id, email): the same person on two designs is two
-- rows, so closing one engagement deletes exactly that engagement's PII.
create table if not exists design_dial_guests (
  id           uuid primary key,
  design_id    uuid not null references design_dial_designs (id) on delete cascade,
  email        text not null check (email = lower(email) and char_length(email) <= 254),
  display_name text not null default '' check (char_length(display_name) <= 80),
  created_at   timestamptz not null default now(),
  unique (design_id, email)
);

-- Share links become personal: guest_id names whose link this is, design_id
-- rekeys the table off the artifact basename (two clients can both have an
-- artifact named 'design'). Both nullable: rows minted before arc 2 carry
-- neither and keep working until they expire.
alter table design_dial_share_links
  add column if not exists guest_id  uuid references design_dial_guests (id) on delete cascade,
  add column if not exists design_id uuid references design_dial_designs (id) on delete cascade;

-- Pins and replies: the attribution stamp. guest_id is the relation (set
-- null when the guest row is deleted so the feedback survives); guest_email
-- is the queryable copy ('everything this client ever said'), nulled by the
-- PII scrub. design_id rekeys both tables off the basename, same as links.
alter table design_dial_pins
  add column if not exists guest_id    uuid references design_dial_guests (id) on delete set null,
  add column if not exists guest_email text,
  add column if not exists design_id   uuid references design_dial_designs (id) on delete cascade;

alter table design_dial_replies
  add column if not exists guest_id    uuid references design_dial_guests (id) on delete set null,
  add column if not exists guest_email text,
  add column if not exists design_id   uuid references design_dial_designs (id) on delete cascade;

-- Backfill: every pre-arc-2 row keys to the design its artifact registered
-- (the designs table was created with the real registrations, so this join
-- is exact for all existing data). Replies have no artifact column — they
-- ride their pin.
update design_dial_pins p
   set design_id = d.id
  from design_dial_designs d
 where p.design_id is null and d.artifact = p.artifact;

update design_dial_replies r
   set design_id = p.design_id
  from design_dial_pins p
 where r.design_id is null and r.pin_id = p.id and p.design_id is not null;

update design_dial_share_links l
   set design_id = d.id
  from design_dial_designs d
 where l.design_id is null and d.artifact = l.artifact;

create index if not exists design_dial_guests_design on design_dial_guests (design_id);
create index if not exists design_dial_pins_design on design_dial_pins (design_id);
create index if not exists design_dial_pins_guest on design_dial_pins (guest_id);
create index if not exists design_dial_replies_design on design_dial_replies (design_id);
create index if not exists design_dial_replies_guest on design_dial_replies (guest_id);
create index if not exists design_dial_share_links_design on design_dial_share_links (design_id);
create index if not exists design_dial_share_links_guest on design_dial_share_links (guest_id);

-- RLS law of this store: enabled, zero policies, service-role only.
alter table design_dial_guests enable row level security;

commit;
