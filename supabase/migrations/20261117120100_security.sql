-- Ayan Residences: who can see and change what (part 2 of 3).
-- Two roles: the shared admin login (sees everything) and tenants (only
-- their own data). The role lives in the login's app_metadata, which only
-- the server can set; user_metadata is never trusted.

-- ===================================================== helpers (not exposed)

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;

-- True for the admin login.
create or replace function private.is_admin()
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce(((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin', false)
$$;

-- The tenant record of the person logged in (null for the admin).
-- Security definer so policies can use it without looping through the
-- tenants table's own rules; it only ever returns the caller's own id.
create or replace function private.my_tenant_id()
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select t.id from public.tenants t where t.profile_id = (select auth.uid())
$$;

revoke execute on function private.is_admin() from public, anon;
revoke execute on function private.my_tenant_id() from public, anon;
grant execute on function private.is_admin() to authenticated;
grant execute on function private.my_tenant_id() to authenticated;

-- Blocks a tenant from changing anything except the listed columns (the
-- trigger arguments). The admin may change everything.
create or replace function private.tenant_may_only_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (select private.is_admin()) then
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

-- A profile row for every new login, from the server-set app_metadata.
create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, role, username)
  values (
    new.id,
    coalesce(new.raw_app_meta_data ->> 'role', 'tenant'),
    coalesce(new.raw_app_meta_data ->> 'username', split_part(new.email, '@', 1))
  );
  return new;
end
$$;
revoke execute on function private.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- ===================================================== grants
-- New tables are not exposed automatically, so access is granted here.
-- Logged-out visitors (anon) get nothing. Rows are then filtered by RLS.

revoke all on all tables in schema public from anon;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant all on all tables in schema public to service_role;
-- The activity log can be read and added to, never edited or deleted.
revoke update, delete on public.activity_log from authenticated;

-- ===================================================== RLS: admin

-- Every table locked, and the admin gets full access to each one.
do $$
declare
  t text;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t);
    execute format(
      'create policy "admin: full access" on public.%I for all to authenticated '
      'using ((select private.is_admin())) with check ((select private.is_admin()))', t);
  end loop;
end
$$;

-- ===================================================== RLS: tenants

-- Shared reference data any logged-in user may read.
create policy "everyone: read" on public.properties for select to authenticated using (true);
create policy "everyone: read" on public.units for select to authenticated using (true);
create policy "everyone: read" on public.house_rules for select to authenticated using (true);
create policy "everyone: read" on public.pay_accounts for select to authenticated using (true);
create policy "everyone: read" on public.settings for select to authenticated using (true);

-- Own login and tenant record.
create policy "tenant: own profile" on public.profiles for select to authenticated
  using (id = (select auth.uid()));

create policy "tenant: read own" on public.tenants for select to authenticated
  using (profile_id = (select auth.uid()));
create policy "tenant: update own contact details" on public.tenants for update to authenticated
  using (profile_id = (select auth.uid()))
  with check (profile_id = (select auth.uid()));
create trigger tenants_tenant_columns before update on public.tenants
  for each row execute function private.tenant_may_only_change('phone', 'email', 'emergency_contact', 'occupants');

-- Leases and what hangs off them.
create policy "tenant: read own" on public.leases for select to authenticated
  using (tenant_id = (select private.my_tenant_id()));

create policy "tenant: read own" on public.move_outs for select to authenticated
  using (lease_id in (select l.id from public.leases l where l.tenant_id = (select private.my_tenant_id())));

create policy "tenant: read own" on public.cheques for select to authenticated
  using (lease_id in (select l.id from public.leases l where l.tenant_id = (select private.my_tenant_id())));
-- Uploading a cheque photo only (it goes back to "not checked yet").
create policy "tenant: add cheque photo" on public.cheques for update to authenticated
  using (lease_id in (select l.id from public.leases l where l.tenant_id = (select private.my_tenant_id())))
  with check (
    lease_id in (select l.id from public.leases l where l.tenant_id = (select private.my_tenant_id()))
    and photo_checked = false
  );
create trigger cheques_tenant_columns before update on public.cheques
  for each row execute function private.tenant_may_only_change('photo_path', 'photo_uploaded_at', 'photo_checked');

-- Documents (ID, clearances, passport...): upload or replace own; a new
-- file always waits for the admin to check it.
create policy "tenant: read own" on public.tenant_documents for select to authenticated
  using (tenant_id = (select private.my_tenant_id()));
create policy "tenant: upload own" on public.tenant_documents for insert to authenticated
  with check (tenant_id = (select private.my_tenant_id()) and state = 'to_review');
create policy "tenant: replace own" on public.tenant_documents for update to authenticated
  using (tenant_id = (select private.my_tenant_id()))
  with check (tenant_id = (select private.my_tenant_id()) and state = 'to_review' and reject_reason is null);
create trigger tenant_documents_tenant_columns before update on public.tenant_documents
  for each row execute function private.tenant_may_only_change(
    'file_name', 'file_path', 'state', 'reject_reason', 'uploaded_at', 'reviewed_at');

create policy "tenant: read own" on public.lease_requests for select to authenticated
  using (tenant_id = (select private.my_tenant_id()));
create policy "tenant: send request" on public.lease_requests for insert to authenticated
  with check (tenant_id = (select private.my_tenant_id()) and status = 'pending');

-- Money: read own; a tenant can only send a payment proof, which always
-- waits for the admin to verify it.
create policy "tenant: read own" on public.charges for select to authenticated
  using (tenant_id = (select private.my_tenant_id()));

create policy "tenant: read own" on public.payments for select to authenticated
  using (tenant_id = (select private.my_tenant_id()));
create policy "tenant: send proof" on public.payments for insert to authenticated
  with check (
    tenant_id = (select private.my_tenant_id())
    and source = 'tenant_proof'
    and status = 'submitted'
    and verified_at is null
    and gateway_ref is null
  );

create policy "tenant: read own" on public.payment_allocations for select to authenticated
  using (payment_id in (select p.id from public.payments p where p.tenant_id = (select private.my_tenant_id())));

-- Reports and complaints: file and follow own.
create policy "tenant: read own" on public.reports for select to authenticated
  using (tenant_id = (select private.my_tenant_id()));
create policy "tenant: file report" on public.reports for insert to authenticated
  with check (
    tenant_id = (select private.my_tenant_id())
    and status = 'pending'
    and damage_kind is null
    and tenant_amount = 0
    and unit_id in (
      select l.unit_id from public.leases l
      where l.tenant_id = (select private.my_tenant_id()) and l.status = 'active')
  );

create policy "tenant: read own" on public.report_updates for select to authenticated
  using (report_id in (select r.id from public.reports r where r.tenant_id = (select private.my_tenant_id())));

create policy "tenant: read own" on public.report_photos for select to authenticated
  using (report_id in (select r.id from public.reports r where r.tenant_id = (select private.my_tenant_id())));
create policy "tenant: add photos" on public.report_photos for insert to authenticated
  with check (report_id in (select r.id from public.reports r where r.tenant_id = (select private.my_tenant_id())));

create policy "tenant: read own" on public.complaints for select to authenticated
  using (tenant_id = (select private.my_tenant_id()));
create policy "tenant: file complaint" on public.complaints for insert to authenticated
  with check (tenant_id = (select private.my_tenant_id()) and status = 'open' and response is null);

-- Notices: read the ones sent to you, mark them read.
create policy "tenant: read own" on public.notice_recipients for select to authenticated
  using (tenant_id = (select private.my_tenant_id()));
create policy "tenant: mark read" on public.notice_recipients for update to authenticated
  using (tenant_id = (select private.my_tenant_id()))
  with check (tenant_id = (select private.my_tenant_id()));
create trigger notice_recipients_tenant_columns before update on public.notice_recipients
  for each row execute function private.tenant_may_only_change('read_at');

create policy "tenant: read sent to me" on public.notices for select to authenticated
  using (id in (select nr.notice_id from public.notice_recipients nr where nr.tenant_id = (select private.my_tenant_id())));

-- Chat: own thread only.
create policy "tenant: read own thread" on public.chat_messages for select to authenticated
  using (tenant_id = (select private.my_tenant_id()));
create policy "tenant: send in own thread" on public.chat_messages for insert to authenticated
  with check (tenant_id = (select private.my_tenant_id()) and sender = 'tenant');

create policy "tenant: read own" on public.chat_reads for select to authenticated
  using (tenant_id = (select private.my_tenant_id()));
create policy "tenant: mark own read" on public.chat_reads for insert to authenticated
  with check (tenant_id = (select private.my_tenant_id()) and side = 'tenant');
create policy "tenant: update own read" on public.chat_reads for update to authenticated
  using (tenant_id = (select private.my_tenant_id()) and side = 'tenant')
  with check (tenant_id = (select private.my_tenant_id()) and side = 'tenant');

-- Documents to sign: read own; sign while it is waiting. The signing time
-- and the signed file's fingerprint are set by the server, not the phone.
create policy "tenant: read own" on public.documents_to_sign for select to authenticated
  using (tenant_id = (select private.my_tenant_id()));
create policy "tenant: sign own" on public.documents_to_sign for update to authenticated
  using (tenant_id = (select private.my_tenant_id()) and status = 'awaiting')
  with check (tenant_id = (select private.my_tenant_id()) and status = 'signed');
create trigger documents_to_sign_tenant_columns before update on public.documents_to_sign
  for each row execute function private.tenant_may_only_change(
    'status', 'signature_path', 'signed_path', 'signed_device');

-- Phone notification tokens: own only.
create policy "user: own push tokens" on public.push_tokens for all to authenticated
  using (profile_id = (select auth.uid()))
  with check (profile_id = (select auth.uid()));

-- Tables with no tenant policy (admin only): unit_templates, bookings,
-- booking_deductions, booking_files, work_items, unit_costs,
-- monthly_expenses, expense_templates, taxes, cost_types, charge_types,
-- activity_log, alert_prefs.
