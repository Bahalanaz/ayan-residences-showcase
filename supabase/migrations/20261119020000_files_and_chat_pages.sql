-- 1. Files nothing points to any more (a removed cheque's photo, a replaced
--    document...). The admin app deletes them through the Storage API once
--    a day. Files newer than a day are left alone (they may still be
--    on their way to being saved).

create or replace function public.orphan_files()
returns table (bucket text, path text)
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
    with refs (bucket, path) as (
      select 'public-assets', u.photo_path from public.units u where u.photo_path is not null
      union all select 'public-assets', t.photo_path from public.unit_templates t where t.photo_path is not null
      union all select 'public-assets', a.qr_path from public.pay_accounts a where a.qr_path is not null
      union all select 'tenant-documents', d.file_path from public.tenant_documents d
      union all select 'payment-proofs', p.proof_path from public.payments p where p.proof_path is not null
      union all select 'cheque-photos', c.photo_path from public.cheques c where c.photo_path is not null
      union all select 'contracts', l.contract_path from public.leases l where l.contract_path is not null
      union all select 'contracts', l.signed_lease_path from public.leases l where l.signed_lease_path is not null
      union all select 'contracts', e ->> 'contract_path'
        from public.tenants t, jsonb_array_elements(t.past_leases) e
        where e ->> 'contract_path' is not null
      union all select 'contracts', t.next_lease ->> 'contract_path' from public.tenants t
        where t.next_lease ->> 'contract_path' is not null
      union all select 'chat-files', m.image_path from public.chat_messages m where m.image_path is not null
      union all select 'chat-files', m.file_path from public.chat_messages m where m.file_path is not null
      union all select 'chat-files', s.original_path from public.documents_to_sign s where s.original_path is not null
      union all select 'chat-files', s.signature_path from public.documents_to_sign s where s.signature_path is not null
      union all select 'chat-files', s.signed_path from public.documents_to_sign s where s.signed_path is not null
      union all select 'report-photos', r.file_path from public.report_photos r
      union all select 'guest-files', g.file_path from public.booking_files g
    )
    select o.bucket_id::text, o.name
    from storage.objects o
    where o.created_at < now() - interval '1 day'
      and o.name not like '%.emptyFolderPlaceholder'
      and not exists (select 1 from refs r where r.bucket = o.bucket_id and r.path = o.name);
end
$$;
revoke execute on function public.orphan_files() from public, anon;
grant execute on function public.orphan_files() to authenticated;

-- 2. Chat history in pages: the latest [p_limit] messages of each thread
--    the caller can see (security rules apply: a tenant gets their own).
create or replace function public.recent_chat(p_limit integer default 50)
returns setof public.chat_messages
language sql
stable
security invoker
set search_path = ''
as $$
  select m.id, m.tenant_id, m.sender, m.body, m.image_path, m.created_at, m.file_path, m.file_name
  from (
    select c.*, row_number() over (partition by c.tenant_id order by c.created_at desc) as n
    from public.chat_messages c
  ) m
  where m.n <= p_limit
  order by m.created_at;
$$;
revoke execute on function public.recent_chat(integer) from public, anon;
grant execute on function public.recent_chat(integer) to authenticated;
