-- The private bucket that holds an import ZIP between upload and the end of the import.
-- The browser uploads straight to it with Storage's resumable protocol, because a Vercel
-- Function cannot take a request body over 4.5 MB.
--
-- The bucket sets no size limit of its own, so the project's global Storage limit applies. The
-- limit people see comes from the Web server setting IMPORT_MAX_ZIP_BYTES, which defaults to
-- the 50 MB the Supabase free plan allows; raising it needs the project's Storage limit raised too.
--
-- An object path is <owner>/<job>/source.zip, and writing to it needs an upload in progress for
-- that exact path, so the bucket cannot be used as general storage.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'import-staging',
  'import-staging',
  false,
  null,
  array['application/zip', 'application/x-zip-compressed', 'application/octet-stream']
)
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy "Users can view the private import staging bucket"
on storage.buckets for select
to authenticated
using (id = 'import-staging');

create policy "Users can read their own staged imports"
on storage.objects for select
to authenticated
using (
  bucket_id = 'import-staging'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy "Users can upload the ZIP of their own import"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'import-staging'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and exists (
    select 1
    from public.import_jobs as job
    where job.owner_id = (select auth.uid())
      and job.staging_path = name
      and job.status = 'uploading'
  )
);

create policy "Users can update the ZIP of their own import"
on storage.objects for update
to authenticated
using (
  bucket_id = 'import-staging'
  and (storage.foldername(name))[1] = (select auth.uid())::text
)
with check (
  bucket_id = 'import-staging'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and exists (
    select 1
    from public.import_jobs as job
    where job.owner_id = (select auth.uid())
      and job.staging_path = name
      and job.status = 'uploading'
  )
);

create policy "Users can delete their own staged imports"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'import-staging'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);
