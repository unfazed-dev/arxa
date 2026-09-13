-- The Arxa Dial's font plane (grilled 2026-09-13, seven decisions):
-- typography as a published axis, exactly the palette plane's law
-- (ADDENDUM 17) one seat over. Fonts ride PER-ROLE picks — the grilled
-- shape is independent per-role dropdowns, so the cell is an object
-- role -> choice-id (e.g. {"display":"playfair-display","body":"inter"}),
-- not one scalar. Roles and choices are declared by the artifact's
-- fonts.json; validation of membership happens design-server-side (and
-- worker-side against the baked manifest) — the column only enforces
-- shape: object, bounded keys/values, both url-lawful.
--
-- Writes: the SAME one-path law as palette — publish_font (security
-- definer) checks the design's author token OR a live guest share link
-- in SQL (grilled Q5: author + guests, palette parity). The local design
-- server writes with the service role directly, as it does for palette.
-- Reads: the axes row is already anon-readable (the public palette ear
-- law, ADDENDUM 17 law 5) — the font ear rides the same row, so the
-- ear's LEAST-CHANNEL law is untouched: still ONE postgres_changes
-- channel on arxa_dial_axes per public tab.
--
-- Apply:  psql "$ARXA_SUPABASE_DB_URL" -f 20260913_arxa_dial_font.sql
--   or    paste into the SQL editor of the operator project. Idempotent.

begin;

-- NOTE: no subquery CHECKs (pg forbids them in constraints) — the
-- object-type is the column floor; the key/value url-law is enforced by
-- publish_font below and by the design server (the only write paths).
alter table arxa_dial_axes
  add column if not exists font jsonb not null default '{}'::jsonb
  check (jsonb_typeof(font) = 'object');

-- The one anon write path (palette parity): publish one design's font
-- picks. p_font merges over the stored cell — a per-role dropdown
-- publishes its role alone and never blanks the other roles (the grilled
-- independent-dropdowns law). Authorization: the design's author token
-- (sha256 vs the stored hash) or a live guest link for this design.
create or replace function publish_font(
  p_design_id   uuid,
  p_link_token  text,
  p_font        jsonb
) returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_hash  text;
  v_font  jsonb;
begin
  -- Shape first (the column CHECKs are the floor; the RPC re-derives the
  -- same law so a bad call fails with a nameable error, not a CHECK blast).
  if jsonb_typeof(p_font) <> 'object' then
    return jsonb_build_object('ok', false, 'error', 'font must be an object');
  end if;
  if exists (select 1 from jsonb_object_keys(p_font) k
             where k !~ '^[a-z0-9-]{1,40}$'
                or p_font ->> k !~ '^[a-z0-9-]{1,40}$') then
    return jsonb_build_object('ok', false, 'error',
                              'font roles and choices must be lowercase url-safe ids');
  end if;

  -- Authorization FIRST (the save_overlay law): the design's author
  -- token, the service role (the local design server), or a live guest
  -- share link scoped to this design — the share link IS the
  -- authorization (palette Q9/Q10 parity, grilled Q5 2026-09-13).
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
  elsif coalesce(p_link_token, '') <> ''
     and exists (select 1 from arxa_dial_share_links
                 where design_id = p_design_id
                   and token_hash = encode(sha256(convert_to(p_link_token, 'UTF8')), 'hex')
                   and (expires_at is null or expires_at > now())) then
    null; -- a live guest link (grilled Q5: guests publish fonts too)
  else
    return jsonb_build_object('ok', false, 'error', 'not authorized');
  end if;

  -- Merge over the stored cell (per-role independence), then write.
  select coalesce(font, '{}'::jsonb) || p_font into v_font
    from arxa_dial_axes where design_id = p_design_id;
  if not found then
    insert into arxa_dial_axes (design_id, style, theme, font)
    values (p_design_id, 'site', 'system', p_font);
  else
    update arxa_dial_axes set font = v_font, updated_at = now()
      where design_id = p_design_id;
  end if;
  return jsonb_build_object('ok', true, 'font', v_font);
end;
$fn$;

-- The column must ride the realtime publication like the rest of the row
-- (the public font ear reads it; postgres_changes delivers whole-row
-- payloads, so no publication change is strictly required — kept explicit
-- for the record: nothing to do, the row is already published).

commit;
