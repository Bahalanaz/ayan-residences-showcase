-- Phone notifications: when something happens, the database asks the
-- send-push function to notify the right phones. The function reads the
-- row again itself and sends each event once (push_log).

create extension if not exists pg_net with schema extensions;

-- Events already sent (so nothing is sent twice). Only the server uses it.
create table if not exists public.push_log (
  key text primary key,
  created_at timestamptz not null default now()
);
alter table public.push_log enable row level security;
revoke all on public.push_log from anon, authenticated;
grant all on public.push_log to service_role;

create or replace function private.push_hook()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform net.http_post(
    url := 'https://YOUR-PROJECT.supabase.co/functions/v1/send-push',
    body := jsonb_build_object('table', tg_table_name, 'op', tg_op, 'record', to_jsonb(new)),
    -- The app's public (publishable) key: Supabase asks every call for it.
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', 'YOUR-PUBLISHABLE-KEY'
    )
  );
  return new;
exception when others then
  -- A notification must never stop the change itself from being saved.
  return new;
end
$$;
revoke execute on function private.push_hook() from public, anon, authenticated;

-- Notices (announcements and the app's automatic notices) â†’ the tenant.
drop trigger if exists push_notice on public.notice_recipients;
create trigger push_notice after insert on public.notice_recipients
  for each row execute function private.push_hook();

-- Chat â†’ the other side.
drop trigger if exists push_chat on public.chat_messages;
create trigger push_chat after insert on public.chat_messages
  for each row execute function private.push_hook();

-- Payment proofs â†’ admin; verified / not accepted â†’ the tenant.
drop trigger if exists push_payment_new on public.payments;
create trigger push_payment_new after insert on public.payments
  for each row execute function private.push_hook();
drop trigger if exists push_payment_status on public.payments;
create trigger push_payment_status after update of status on public.payments
  for each row when (old.status is distinct from new.status) execute function private.push_hook();

-- Reports â†’ admin; status changes and updates â†’ the tenant.
drop trigger if exists push_report_new on public.reports;
create trigger push_report_new after insert on public.reports
  for each row execute function private.push_hook();
drop trigger if exists push_report_status on public.reports;
create trigger push_report_status after update of status on public.reports
  for each row when (old.status is distinct from new.status) execute function private.push_hook();
drop trigger if exists push_report_update on public.report_updates;
create trigger push_report_update after insert on public.report_updates
  for each row execute function private.push_hook();

-- Complaints â†’ admin; the reply â†’ the tenant.
drop trigger if exists push_complaint_new on public.complaints;
create trigger push_complaint_new after insert on public.complaints
  for each row execute function private.push_hook();
drop trigger if exists push_complaint_reply on public.complaints;
create trigger push_complaint_reply after update of response on public.complaints
  for each row when (old.response is distinct from new.response) execute function private.push_hook();

-- Documents uploaded â†’ admin.
drop trigger if exists push_document_new on public.tenant_documents;
create trigger push_document_new after insert on public.tenant_documents
  for each row execute function private.push_hook();
drop trigger if exists push_document_again on public.tenant_documents;
create trigger push_document_again after update on public.tenant_documents
  for each row when (old.file_path is distinct from new.file_path or old.state is distinct from new.state)
  execute function private.push_hook();

-- Renewal / move-out requests â†’ admin.
drop trigger if exists push_request on public.lease_requests;
create trigger push_request after insert on public.lease_requests
  for each row execute function private.push_hook();
