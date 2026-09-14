-- The Arxa Dial's live Edit Overlay (edit-feature redesign, grilled
-- 2026-09-11, decisions 1-9): the author's text + image edits, stored per
-- design in Supabase, streamed live to every open client dial, and baked
-- into source at the next eject (decision 7). This migration overturns
-- design_draft.dart's decisions 5 (author-private drafts) and 11 (never in
-- Supabase) — the overlay IS the runtime truth for dial holders.
--
-- One row per design: patches jsonb (the dial's patch spelling: key ->
-- {text?, attrs?, was?, nth?, page?, locale?}), rev (the stale-guard — a
-- save from a surface that is behind is refused so it resyncs instead of
-- clobbering), updated_at.
--
-- Writes ONLY through save_overlay (security definer): the design's author
-- token hash (the publish_palette law, stricter — a guest ?dial= link is
-- rejected) or the service role (the local design server, key server-side).
-- Guests: SELECT-only (live view). Anonymous visitors without a link see
-- nothing — no dial, no overlay (Q9 of the palette plane, unchanged).
--
-- Realtime: the row rides the supabase_realtime publication — the
-- postgres_changes set becomes pins, replies, overlays (the drawings
-- channel retired with this change) on the dial's existing rails.
--
-- Apply:  /tmp/mcp_sql.sh (MCP execute_sql) or paste into the SQL editor
-- of the operator project. Idempotent.

begin;

create table if not exists arxa_dial_overlays (
  design_id  uuid primary key references arxa_dial_designs (id) on delete cascade,
  patches    jsonb not null default '{}'::jsonb
             check (jsonb_typeof(patches) = 'object')
             check (octet_length(patches::text) <= 262144), -- 256KB << 1MB pg_changes payload
  rev        integer not null default 0 check (rev >= 0),
  updated_at timestamptz not null default now()
);

alter table arxa_dial_overlays enable row level security;

-- Reads for every dial holder (author + guests boot-apply the overlay).
drop policy if exists "overlay reads" on arxa_dial_overlays;
create policy "overlay reads"
  on arxa_dial_overlays for select
  to anon, authenticated
  using (true);
-- No insert/update/delete policies: anon writes are denied by default;
-- the save_overlay security definer is the only write path.

-- The one write path. Author token (sha256 against the stored hash) or the
-- service role. Empty patches = revert-to-published (row deleted, everyone
-- snaps back to baked source). base_rev < current rev = stale refusal
-- carrying the fresh doc so the caller resyncs in one round trip.
create or replace function save_overlay(
  p_design_id  uuid,
  p_link_token text,
  p_base_rev   int,
  p_patches    jsonb
) returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_hash  text;
  v_rev   integer;
  v_keys  integer;
  v_k     text;
begin
  -- Authorization FIRST: the design's author token, or the service role
  -- (the local design server — its key never leaves the server).
  select author_token_hash into v_hash
    from arxa_dial_designs where id = p_design_id;
  if v_hash is null then
    return jsonb_build_object('ok', false, 'error', 'unknown design');
  end if;
  if coalesce(p_link_token, '') <> ''
     and encode(sha256(convert_to(p_link_token, 'UTF8')), 'hex') = v_hash then
    null; -- the author (deployed surface: raw token rides cfg.token)
  elsif auth.role() = 'service_role' then
    null; -- the local design server
  else
    return jsonb_build_object('ok', false, 'error', 'author only');
  end if;

  -- Shape guard (defense in depth; the dial enforces the same caps):
  if jsonb_typeof(p_patches) <> 'object' then
    return jsonb_build_object('ok', false, 'error', 'patches must be an object');
  end if;
  select count(*) into v_keys from jsonb_object_keys(p_patches);
  if v_keys > 128 then
    return jsonb_build_object('ok', false, 'error', 'too many patch keys');
  end if;
  for v_k in select key from jsonb_object_keys(p_patches) as key loop
    if v_k !~ '^(el:)?[a-zA-Z0-9][a-zA-Z0-9:_@.-]{0,99}$' then
      return jsonb_build_object('ok', false, 'error', 'bad patch key');
    end if;
  end loop;

  select rev into v_rev from arxa_dial_overlays
    where design_id = p_design_id for update;
  if v_rev is null then v_rev := 0; end if;

  if v_keys = 0 then
    -- Revert-to-published: the row dies, dial holders reapply nothing.
    delete from arxa_dial_overlays where design_id = p_design_id;
    return jsonb_build_object('ok', true, 'rev', 0);
  end if;

  if p_base_rev is null or p_base_rev < v_rev then
    return jsonb_build_object('ok', false, 'error', 'stale', 'rev', v_rev,
      'patches', coalesce((select patches from arxa_dial_overlays
        where design_id = p_design_id), '{}'::jsonb));
  end if;

  insert into arxa_dial_overlays (design_id, patches, rev, updated_at)
    values (p_design_id, p_patches, v_rev + 1, now())
    on conflict (design_id) do update
      set patches = excluded.patches,
          rev = arxa_dial_overlays.rev + 1,
          updated_at = now();
  return jsonb_build_object('ok', true, 'rev', v_rev + 1);
end;
$fn$;

-- Realtime: the frame-is-truth channel (the pins law's twin).
do $do$
begin
  alter publication supabase_realtime add table public.arxa_dial_overlays;
exception
  when duplicate_object then null; -- already in the publication
end $do$;

commit;
