-- D31 (arxa-studio grill): unify tier vocabulary across the one
-- billing family (D15). 'pro'/'scale' remain arxa's tiers; 'agency'
-- is arxa studio's paid tier (D8/D9). Idempotent.

alter table subscriptions
  drop constraint if exists subscriptions_tier_check;

alter table subscriptions
  add constraint subscriptions_tier_check
  check (tier in ('pro', 'scale', 'agency'));

comment on column subscriptions.tier is
  'Unified family tiers (D15/D31): pro | scale (arxa), agency (arxa studio).';
