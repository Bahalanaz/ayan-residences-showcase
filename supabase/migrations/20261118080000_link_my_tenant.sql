-- When a tenant logs in and their login is not linked to their tenant record
-- yet (the link step failed when the admin created it), the app calls this
-- to link it. It is safe: the username comes from the login's app_metadata,
-- which only the server can set, and usernames are unique among current
-- tenants. It never takes a record already linked to another login.

create or replace function public.link_my_tenant()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  claims jsonb := (select auth.jwt()) -> 'app_metadata';
  linked bigint;
begin
  if claims ->> 'role' is distinct from 'tenant' or coalesce(claims ->> 'username', '') = '' then
    return null;
  end if;
  update public.tenants
     set profile_id = (select auth.uid())
   where lower(username) = lower(claims ->> 'username')
     and status = 'active'
     and (profile_id is null or profile_id = (select auth.uid()))
  returning id into linked;
  return linked;
end
$$;

revoke execute on function public.link_my_tenant() from public, anon;
grant execute on function public.link_my_tenant() to authenticated;
