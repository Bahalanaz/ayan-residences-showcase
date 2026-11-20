-- A tenant can be given a unit (with rent, deposit and due day) before the
-- lease dates are set. The lease row needs dates, so the assignment itself
-- is kept on the tenant.

alter table public.tenants add column if not exists unit_id bigint references public.units (id);
alter table public.tenants add column if not exists rent numeric(12,2) not null default 0 check (rent >= 0);
alter table public.tenants add column if not exists deposit numeric(12,2) not null default 0 check (deposit >= 0);
alter table public.tenants add column if not exists due_day smallint not null default 5 check (due_day between 1 and 31);
alter table public.tenants add column if not exists cheques_per_year smallint check (cheques_per_year between 1 and 4);
create index if not exists tenants_unit_id_idx on public.tenants (unit_id);
