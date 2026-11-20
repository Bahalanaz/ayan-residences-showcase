-- A username only has to be unique among current tenants, so the username
-- of someone who moved out (or was removed) can be given to a new tenant.

drop index if exists public.tenants_username_key;
create unique index tenants_username_key on public.tenants (lower(username)) where status = 'active';
