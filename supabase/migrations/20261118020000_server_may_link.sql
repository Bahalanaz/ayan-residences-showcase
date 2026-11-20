-- The "tenant may only change their contact details" check also stopped the
-- server (the login function and the SQL Editor), so a new login could not
-- be linked to its tenant. Only tenants logged in to the app are limited.

create or replace function private.tenant_may_only_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- The server's own roles (service_role, postgres) and the admin may change
  -- everything.
  if current_user not in ('authenticated', 'anon') or (select private.is_admin()) then
    return new;
  end if;
  if (to_jsonb(new) - tg_argv::text[]) is distinct from (to_jsonb(old) - tg_argv::text[]) then
    raise exception 'You can''t change these details.' using errcode = '42501';
  end if;
  return new;
end
$$;
revoke execute on function private.tenant_may_only_change() from public, anon;
grant execute on function private.tenant_may_only_change() to authenticated;
