-- The admin can see a tenant's password again (to resend it). Supabase
-- only keeps logins' passwords scrambled, so a copy is kept encrypted in
-- Supabase Vault, one secret per tenant ("tenant-password-<id>"). Only the
-- admin login can save or read them (tenants never can).

create or replace function public.save_tenant_password(p_tenant_id bigint, p_password text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  secret_name text := 'tenant-password-' || p_tenant_id;
  existing uuid;
begin
  if not (select private.is_admin()) then
    raise exception 'Admin only' using errcode = '42501';
  end if;
  select s.id into existing from vault.secrets s where s.name = secret_name;
  if existing is null then
    perform vault.create_secret(p_password, secret_name, 'Ayan tenant login password');
  else
    perform vault.update_secret(existing, p_password);
  end if;
end
$$;

-- Every saved tenant password (admin only).
create or replace function public.tenant_passwords()
returns table (tenant_id bigint, password text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (select private.is_admin()) then
    raise exception 'Admin only' using errcode = '42501';
  end if;
  return query
    select substring(d.name from 'tenant-password-(\d+)$')::bigint, d.decrypted_secret
    from vault.decrypted_secrets d
    where d.name like 'tenant-password-%';
end
$$;

-- Removes a tenant's saved password (when their login is removed).
create or replace function public.forget_tenant_password(p_tenant_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (select private.is_admin()) then
    raise exception 'Admin only' using errcode = '42501';
  end if;
  delete from vault.secrets where name = 'tenant-password-' || p_tenant_id;
end
$$;

revoke execute on function public.save_tenant_password(bigint, text) from public, anon;
revoke execute on function public.tenant_passwords() from public, anon;
revoke execute on function public.forget_tenant_password(bigint) from public, anon;
grant execute on function public.save_tenant_password(bigint, text) to authenticated;
grant execute on function public.tenant_passwords() to authenticated;
grant execute on function public.forget_tenant_password(bigint) to authenticated;
