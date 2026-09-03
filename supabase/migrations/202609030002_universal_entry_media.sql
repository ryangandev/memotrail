create or replace function public.register_entry_attachment(
  p_entry_id uuid,
  p_attachment_id uuid,
  p_object_path text,
  p_original_filename text,
  p_mime_type text,
  p_byte_size bigint,
  p_pixel_width integer,
  p_pixel_height integer
)
returns table (
  attachment_id uuid,
  entry_id uuid,
  object_path text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  attachment_owner_id uuid := auth.uid();
  normalized_path text := btrim(coalesce(p_object_path, ''));
  normalized_filename text := nullif(btrim(p_original_filename), '');
  normalized_mime_type text := lower(btrim(coalesce(p_mime_type, '')));
  expected_folders text[];
  object_filename text;
begin
  if attachment_owner_id is null then
    return;
  end if;

  if not exists (
    select 1
    from public.entries
    where entries.id = p_entry_id
      and entries.owner_id = attachment_owner_id
      and entries.deleted_at is null
  ) then
    return;
  end if;

  expected_folders := storage.foldername(normalized_path);
  object_filename := regexp_replace(normalized_path, '^.*/', '');

  if array_length(expected_folders, 1) <> 2
    or expected_folders[1] <> attachment_owner_id::text
    or expected_folders[2] <> p_entry_id::text
    or object_filename !~ ('^' || p_attachment_id::text || '(\.[A-Za-z0-9]{1,10})?$')
  then
    raise exception using errcode = '22023', message = 'invalid_attachment_path';
  end if;

  if normalized_mime_type not in (
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/heic',
    'image/heif'
  ) then
    raise exception using errcode = '22023', message = 'unsupported_attachment_type';
  end if;

  if p_byte_size is null or p_byte_size < 1 or p_byte_size > 52428800
    or (p_pixel_width is not null and p_pixel_width < 1)
    or (p_pixel_height is not null and p_pixel_height < 1)
    or length(coalesce(normalized_filename, '')) > 255
  then
    raise exception using errcode = '22023', message = 'invalid_attachment_metadata';
  end if;

  if exists (
    select 1
    from public.attachments
    where attachments.id = p_attachment_id
      and attachments.owner_id = attachment_owner_id
      and attachments.entry_id = p_entry_id
      and attachments.bucket_id = 'entry-media'
      and attachments.object_path = normalized_path
      and attachments.variant = 'original'
      and attachments.mime_type = normalized_mime_type
      and attachments.byte_size = p_byte_size
      and attachments.pixel_width is not distinct from p_pixel_width
      and attachments.pixel_height is not distinct from p_pixel_height
      and attachments.deleted_at is null
  ) then
    return query select p_attachment_id, p_entry_id, normalized_path;
    return;
  end if;

  if exists (
    select 1
    from public.attachments
    where attachments.id = p_attachment_id
      or (
        attachments.bucket_id = 'entry-media'
        and attachments.object_path = normalized_path
      )
  ) then
    raise exception using errcode = '23505', message = 'attachment_conflict';
  end if;

  if not exists (
    select 1
    from storage.objects
    where objects.bucket_id = 'entry-media'
      and objects.name = normalized_path
      and (storage.foldername(objects.name))[1] = attachment_owner_id::text
  ) then
    raise exception using errcode = '22023', message = 'attachment_object_missing';
  end if;

  insert into public.attachments (
    id,
    owner_id,
    entry_id,
    variant,
    bucket_id,
    object_path,
    original_filename,
    mime_type,
    byte_size,
    pixel_width,
    pixel_height
  )
  values (
    p_attachment_id,
    attachment_owner_id,
    p_entry_id,
    'original',
    'entry-media',
    normalized_path,
    normalized_filename,
    normalized_mime_type,
    p_byte_size,
    p_pixel_width,
    p_pixel_height
  );

  return query select p_attachment_id, p_entry_id, normalized_path;
end;
$$;

revoke all on function public.register_entry_attachment(
  uuid,
  uuid,
  text,
  text,
  text,
  bigint,
  integer,
  integer
) from public, anon;

grant execute on function public.register_entry_attachment(
  uuid,
  uuid,
  text,
  text,
  text,
  bigint,
  integer,
  integer
) to authenticated;

comment on function public.register_entry_attachment(
  uuid,
  uuid,
  text,
  text,
  text,
  bigint,
  integer,
  integer
) is 'Idempotently registers an uploaded private image against any owned non-Trash Entry after validating its Storage path and metadata.';

create or replace function public.trash_entry_attachment(
  p_attachment_id uuid
)
returns table (
  attachment_id uuid,
  entry_id uuid,
  deleted_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  attachment_owner_id uuid := auth.uid();
begin
  if attachment_owner_id is null then
    return;
  end if;

  return query
  update public.attachments
  set deleted_at = timezone('utc', now())
  where attachments.id = p_attachment_id
    and attachments.owner_id = attachment_owner_id
    and attachments.deleted_at is null
    and exists (
      select 1
      from public.entries
      where entries.id = attachments.entry_id
        and entries.owner_id = attachment_owner_id
        and entries.deleted_at is null
    )
  returning attachments.id, attachments.entry_id, attachments.deleted_at;
end;
$$;

revoke all on function public.trash_entry_attachment(uuid) from public, anon;
grant execute on function public.trash_entry_attachment(uuid) to authenticated;

comment on function public.trash_entry_attachment(uuid) is
  'Recoverably removes an owned image from any active Entry without deleting its private Storage object.';
