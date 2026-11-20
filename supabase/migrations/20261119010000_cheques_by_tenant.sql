-- Cheques belong to the tenant, so they can be planned before the lease
-- dates are set (the lease link is kept when there is one).

alter table public.cheques add column if not exists tenant_id bigint references public.tenants (id);
update public.cheques c set tenant_id = l.tenant_id
  from public.leases l
  where c.lease_id = l.id and c.tenant_id is null;
alter table public.cheques alter column lease_id drop not null;
create index if not exists cheques_tenant_id_idx on public.cheques (tenant_id);

-- Tenants: their own cheques, by tenant or by lease.
drop policy if exists "tenant: read own" on public.cheques;
create policy "tenant: read own" on public.cheques for select to authenticated
  using (
    tenant_id = (select private.my_tenant_id())
    or lease_id in (select l.id from public.leases l where l.tenant_id = (select private.my_tenant_id()))
  );

drop policy if exists "tenant: add cheque photo" on public.cheques;
create policy "tenant: add cheque photo" on public.cheques for update to authenticated
  using (
    tenant_id = (select private.my_tenant_id())
    or lease_id in (select l.id from public.leases l where l.tenant_id = (select private.my_tenant_id()))
  )
  with check (
    (tenant_id = (select private.my_tenant_id())
      or lease_id in (select l.id from public.leases l where l.tenant_id = (select private.my_tenant_id())))
    and photo_checked = false
  );
