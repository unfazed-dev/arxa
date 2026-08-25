-- Design Dial pin context (research improvements slice, 2026-08-25).
-- The anchored element's text snapshot rides the pin row: a review
-- conversation then survives copy edits and element orphaning (Figma
-- design-context practice — comments bind to content, not coordinates).
-- Nullable: surface pins carry no text, and pins placed before this
-- column simply read back without one.

alter table design_dial_pins
  add column if not exists context_text text;

comment on column design_dial_pins.context_text is
  'Anchored element text at pin time (whitespace-collapsed, ≤600 chars,
   nullable) — review context that survives copy edits and orphaning.';
