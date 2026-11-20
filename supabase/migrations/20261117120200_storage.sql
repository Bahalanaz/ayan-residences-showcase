-- Ayan Residences: file storage (part 3 of 3).
-- All buckets are private: files are opened with short-lived signed links.
-- Tenant files go under a folder named after the tenant's id, e.g.
-- "tenant-documents/12/passport.jpg", so a tenant can only reach folder 12.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('tenant-documents', 'tenant-documents', false, 10485760, array['image/jpeg', 'image/png', 'image/webp', 'application/pdf']),
  ('payment-proofs',   'payment-proofs',   false, 10485760, array['image/jpeg', 'image/png', 'image/webp', 'application/pdf']),
  ('cheque-photos',    'cheque-photos',    false, 10485760, array['image/jpeg', 'image/png', 'image/webp']),
  ('contracts',        'contracts',        false, 20971520, array['application/pdf', 'image/jpeg', 'image/png']),
  ('chat-files',       'chat-files',       false, 20971520, array['image/jpeg', 'image/png', 'image/webp', 'application/pdf']),
  ('report-photos',    'report-photos',    false, 20971520, array['image/jpeg', 'image/png', 'image/webp', 'video/mp4']),
  ('guest-files',      'guest-files',      false, 10485760, array['image/jpeg', 'image/png', 'image/webp', 'application/pdf']),
  ('public-assets',    'public-assets',    false, 10485760, array['image/jpeg', 'image/png', 'image/webp']);

-- The admin can do everything in every bucket.
create policy "admin: all files" on storage.objects for all to authenticated
  using ((select private.is_admin()))
  with check ((select private.is_admin()));

-- Unit photos and payment QR codes: any logged-in user can view.
create policy "everyone: view public assets" on storage.objects for select to authenticated
  using (bucket_id = 'public-assets');

-- Tenants: view files in their own folder of the tenant buckets.
create policy "tenant: view own files" on storage.objects for select to authenticated
  using (
    bucket_id in ('tenant-documents', 'payment-proofs', 'cheque-photos', 'contracts', 'chat-files', 'report-photos')
    and (storage.foldername(name))[1] = (select private.my_tenant_id())::text
  );

-- Tenants: upload into their own folder (documents, payment proofs, cheque
-- photos, chat photos and signatures, report photos). Contracts and signed
-- copies are written by the admin or the server.
create policy "tenant: upload own files" on storage.objects for insert to authenticated
  with check (
    bucket_id in ('tenant-documents', 'payment-proofs', 'cheque-photos', 'chat-files', 'report-photos')
    and (storage.foldername(name))[1] = (select private.my_tenant_id())::text
  );

-- Replacing a file (e.g. a new passport photo) needs update too.
create policy "tenant: replace own files" on storage.objects for update to authenticated
  using (
    bucket_id in ('tenant-documents', 'cheque-photos')
    and (storage.foldername(name))[1] = (select private.my_tenant_id())::text
  )
  with check (
    bucket_id in ('tenant-documents', 'cheque-photos')
    and (storage.foldername(name))[1] = (select private.my_tenant_id())::text
  );

-- guest-files has no tenant policy: condo guest IDs are admin only.
