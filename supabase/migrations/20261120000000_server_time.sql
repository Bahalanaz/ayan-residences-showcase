-- The server's clock, for signing: the time written on a signed document
-- comes from here, not from the phone (a phone's clock can be changed by
-- whoever holds it). Read-only, returns nothing but the current time.

create or replace function public.server_now()
returns timestamptz
language sql
stable
security invoker
set search_path = ''
as $$
  select now()
$$;

revoke execute on function public.server_now() from public, anon;
grant execute on function public.server_now() to authenticated;
