-- 20260913b: font manifest column (the live-sync law, operator
-- 2026-09-13: "in sync and live at all times"). The design server pushes
-- the artifact's fonts.json here on every ingest/delete; deployed
-- workers merge this cell over their baked manifest so a choice created
-- mid-session applies live without a redeploy. Object-typed only -- the
-- id law is enforced by the design server and the worker resolver
-- (pg forbids subqueries in CHECK constraints; same carve-out as the
-- font column).
alter table arxa_dial_axes
  add column if not exists font_manifest jsonb not null default '{}'::jsonb;
