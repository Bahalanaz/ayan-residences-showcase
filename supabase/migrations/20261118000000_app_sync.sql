-- Ayan Residences: what the app needs on top of the first migrations, so
-- every screen can save to the database (part 4). Run after the earlier files.

-- ===================================================== tenants & leases

-- Lease history and an agreed renewal travel with the tenant (with their
-- contract files kept in storage), plus a few details the screens show.
alter table public.tenants add column if not exists past_leases jsonb not null default '[]'::jsonb;
alter table public.tenants add column if not exists next_lease jsonb;
alter table public.tenants add column if not exists deposit_note text;
alter table public.tenants add column if not exists end_reminded boolean not null default false;
alter table public.tenants add column if not exists balance numeric(12,2) not null default 0;

alter table public.leases add column if not exists paid_from date;
alter table public.leases add column if not exists contract_assigned_at timestamptz;

alter table public.move_outs add column if not exists inspection text not null default '';

-- ===================================================== reports & notices

alter table public.reports add column if not exists attachments smallint not null default 0;
alter table public.reports add column if not exists admin_note text not null default '';

-- A notice sent to one tenant only (null = an announcement).
alter table public.notices add column if not exists to_tenant_id bigint references public.tenants (id);
create index if not exists notices_to_tenant_id_idx on public.notices (to_tenant_id);

-- ===================================================== private messages

-- The older "Messages" screen (a category, a question, management's reply).
create table if not exists public.tenant_messages (
  id bigint generated always as identity primary key,
  tenant_id bigint not null references public.tenants (id),
  category text not null,
  body text not null,
  reply text,
  created_at timestamptz not null default now()
);
create index if not exists tenant_messages_tenant_id_idx on public.tenant_messages (tenant_id);

alter table public.tenant_messages enable row level security;
grant select, insert, update, delete on public.tenant_messages to authenticated;
grant all on public.tenant_messages to service_role;

drop policy if exists "admin: full access" on public.tenant_messages;
drop policy if exists "tenant: read own" on public.tenant_messages;
drop policy if exists "tenant: send" on public.tenant_messages;
create policy "admin: full access" on public.tenant_messages for all to authenticated
  using ((select private.is_admin())) with check ((select private.is_admin()));
create policy "tenant: read own" on public.tenant_messages for select to authenticated
  using (tenant_id = (select private.my_tenant_id()));
create policy "tenant: send" on public.tenant_messages for insert to authenticated
  with check (tenant_id = (select private.my_tenant_id()) and reply is null);

-- ===================================================== signing (until the server stamps it)

-- A tenant can sign a PDF of their own (it arrives already signed).
drop policy if exists "tenant: add own signed document" on public.documents_to_sign;
create policy "tenant: add own signed document" on public.documents_to_sign for insert to authenticated
  with check (tenant_id = (select private.my_tenant_id()) and status = 'signed');

-- Until a server function stamps the time and fingerprint, the app sends
-- them; allow those columns when a tenant signs.
drop trigger if exists documents_to_sign_tenant_columns on public.documents_to_sign;
create trigger documents_to_sign_tenant_columns before update on public.documents_to_sign
  for each row execute function private.tenant_may_only_change(
    'status', 'signature_path', 'signed_path', 'signed_device', 'signed_hash', 'signed_at');

-- ===================================================== reports filed by a tenant

-- A tenant can add a report for the unit of their lease whether it has
-- started or is about to (the first version required a started lease).
drop policy if exists "tenant: file report" on public.reports;
create policy "tenant: file report" on public.reports for insert to authenticated
  with check (
    tenant_id = (select private.my_tenant_id())
    and status = 'pending'
    and damage_kind is null
    and tenant_amount = 0
    and unit_id in (
      select l.unit_id from public.leases l
      where l.tenant_id = (select private.my_tenant_id()) and l.status in ('active', 'scheduled'))
  );

-- ===================================================== reports with no tenant account

-- A report the admin files for a condo guest (no account) keeps their name.
alter table public.reports add column if not exists reporter_name text;
