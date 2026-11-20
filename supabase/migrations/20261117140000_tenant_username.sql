-- Tenants keep their username on their own record, so it is known before
-- their login is created (logins are made later by a server function).
-- Usernames are unique whatever the capitals ("Kelra" = "kelra").

alter table public.tenants add column if not exists username text;
create unique index if not exists tenants_username_key on public.tenants (lower(username));
