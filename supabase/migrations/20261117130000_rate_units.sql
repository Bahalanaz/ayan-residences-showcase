-- The app offers four rate units (per night, week, month or year); the first
-- migration only allowed night and month. Widen the check on both tables.

alter table public.units drop constraint units_rate_unit_check;
alter table public.units add constraint units_rate_unit_check
  check (rate_unit in ('night', 'week', 'month', 'year'));

alter table public.unit_templates drop constraint unit_templates_rate_unit_check;
alter table public.unit_templates add constraint unit_templates_rate_unit_check
  check (rate_unit in ('night', 'week', 'month', 'year'));
