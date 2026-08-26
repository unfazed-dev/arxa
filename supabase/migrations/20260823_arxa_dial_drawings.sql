-- Arxa Dial amendment 2026-08-23 (decision: drawings attach to pins —
-- the pub.dev feedback model). A pin may carry the strokes its author drew
-- while placing it: array of strokes, each stroke an array of [x,y] points
-- in page coordinates. Plain jsonb so stroke tooling evolves without DDL;
-- shape + caps are enforced app-side in DialApi (64 strokes, 2000 points per
-- stroke, 8000 total). No publication change: the table is already in
-- supabase_realtime.

begin;

alter table arxa_dial_pins add column if not exists drawing jsonb;

commit;
