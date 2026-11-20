-- A payment proof can be for charges (repairs, fees...) as well as rent
-- months: the charges it pays are kept with it, so verifying it clears them.
alter table public.payments add column if not exists charge_ids bigint[] not null default '{}';
