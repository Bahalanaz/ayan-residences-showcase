-- Tenants see repairs and maintenance scheduled in their own unit or their
-- building, so their calendar shows them (read only).

drop policy if exists "tenant: read work at own unit or building" on public.work_items;
create policy "tenant: read work at own unit or building" on public.work_items for select to authenticated
  using (
    unit_id in (
      select l.unit_id from public.leases l
      where l.tenant_id = (select private.my_tenant_id()) and l.status in ('active', 'scheduled')
      union
      select t.unit_id from public.tenants t
      where t.id = (select private.my_tenant_id()) and t.unit_id is not null)
    or property_id in (
      select u.property_id from public.units u
      where u.id in (
        select l.unit_id from public.leases l
        where l.tenant_id = (select private.my_tenant_id()) and l.status in ('active', 'scheduled')
        union
        select t.unit_id from public.tenants t
        where t.id = (select private.my_tenant_id()) and t.unit_id is not null))
  );
