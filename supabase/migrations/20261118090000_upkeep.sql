-- Upkeep: a storage meter for the admin and a daily cleanup of old files.

-- The plan's file storage (MB), shown on the meter. 1 GB on the Free plan;
-- change it to 102400 after moving to Pro (100 GB).
alter table public.settings add column if not exists storage_limit_mb integer not null default 1024;
-- When the admin app last ran the cleanup (it runs at most once a day).
alter table public.settings add column if not exists last_cleanup_at timestamptz;

-- How much each storage area holds, in bytes (admin only).
create or replace function public.storage_usage()
returns table (bucket text, bytes bigint, files bigint)
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
    select o.bucket_id::text,
           coalesce(sum((o.metadata ->> 'size')::bigint), 0)::bigint,
           count(*)::bigint
    from storage.objects o
    group by o.bucket_id;
end
$$;
revoke execute on function public.storage_usage() from public, anon;
grant execute on function public.storage_usage() to authenticated;

-- The activity log keeps 2 years (nobody can delete from it directly).
create or replace function public.trim_activity_log()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  removed bigint;
begin
  if not (select private.is_admin()) then
    raise exception 'Admin only' using errcode = '42501';
  end if;
  delete from public.activity_log where created_at < now() - interval '2 years';
  get diagnostics removed = row_count;
  return removed;
end
$$;
revoke execute on function public.trim_activity_log() from public, anon;
grant execute on function public.trim_activity_log() to authenticated;
