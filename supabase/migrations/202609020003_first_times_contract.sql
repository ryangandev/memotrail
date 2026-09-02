alter table public.attachments
add column if not exists deleted_at timestamptz;

create index if not exists attachments_owner_entry_active_idx
  on public.attachments (owner_id, entry_id, created_at, id)
  where deleted_at is null;

revoke insert, update, delete on public.attachments from authenticated;

create or replace function public.first_times_workspace()
returns table (
  entry_id uuid,
  title text,
  body text,
  inbox_status text,
  occurred_start timestamptz,
  date_precision text,
  occurred_label text,
  occurred_timezone text,
  revision integer,
  updated_at timestamptz,
  collection_names text[],
  tag_names text[],
  attachments jsonb
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    entries.id,
    entries.title,
    entries.body,
    entries.inbox_status,
    entries.occurred_start,
    entries.date_precision,
    entries.occurred_label,
    entries.occurred_timezone,
    entries.revision,
    entries.updated_at,
    coalesce(
      (
        select array_agg(collections.name order by lower(collections.name), collections.id)
        from public.entry_collections
        join public.collections on collections.id = entry_collections.collection_id
        where entry_collections.entry_id = entries.id
          and entry_collections.owner_id = entries.owner_id
          and collections.archived_at is null
      ),
      '{}'::text[]
    ),
    coalesce(
      (
        select array_agg(tags.name order by lower(tags.name), tags.id)
        from public.entry_tags
        join public.tags on tags.id = entry_tags.tag_id
        where entry_tags.entry_id = entries.id
          and entry_tags.owner_id = entries.owner_id
      ),
      '{}'::text[]
    ),
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', media.id,
            'parentAttachmentId', media.parent_attachment_id,
            'variant', media.variant,
            'bucketId', media.bucket_id,
            'objectPath', media.object_path,
            'originalFilename', media.original_filename,
            'mimeType', media.mime_type,
            'byteSize', media.byte_size,
            'pixelWidth', media.pixel_width,
            'pixelHeight', media.pixel_height,
            'createdAt', media.created_at
          )
          order by media.created_at, media.id
        )
        from public.attachments as media
        where media.entry_id = entries.id
          and media.owner_id = entries.owner_id
          and media.deleted_at is null
      ),
      '[]'::jsonb
    )
  from public.entries
  where entries.owner_id = auth.uid()
    and entries.entry_type = 'first_time'
    and entries.deleted_at is null
  order by entries.occurred_start desc nulls last, entries.created_at desc, entries.id;
$$;

revoke all on function public.first_times_workspace() from public, anon;
grant execute on function public.first_times_workspace() to authenticated;

comment on function public.first_times_workspace() is
  'Returns the authenticated owner''s non-Trash First Times with organization and recoverable private attachment metadata.';

create or replace function public.save_first_time_entry(
  p_title text,
  p_body text,
  p_occurred_start timestamptz,
  p_date_precision text,
  p_occurred_label text,
  p_occurred_timezone text,
  p_collection_names text[],
  p_tag_names text[],
  p_entry_id uuid,
  p_expected_revision integer
)
returns table (
  entry_id uuid,
  revision integer,
  was_created boolean
)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  first_time_owner_id uuid := auth.uid();
  saved_entry_id uuid;
  saved_revision integer;
  normalized_title text := nullif(btrim(p_title), '');
  normalized_body text := btrim(coalesce(p_body, ''));
  normalized_label text := nullif(btrim(p_occurred_label), '');
  normalized_timezone text := nullif(btrim(p_occurred_timezone), '');
  created_entry boolean := p_entry_id is null;
begin
  if first_time_owner_id is null then
    return;
  end if;

  if normalized_title is null
    or length(normalized_title) > 200
    or length(normalized_body) > 50000
  then
    raise exception using errcode = '22023', message = 'invalid_first_time_content';
  end if;

  if p_date_precision not in (
    'exact',
    'day',
    'month',
    'year',
    'approximate',
    'age',
    'range',
    'unknown'
  ) then
    raise exception using errcode = '22023', message = 'invalid_date_precision';
  end if;

  if length(coalesce(normalized_label, '')) > 200 then
    raise exception using errcode = '22023', message = 'first_time_label_too_long';
  end if;

  if p_occurred_start is null then
    if p_date_precision not in ('approximate', 'age', 'unknown')
      or normalized_timezone is not null
    then
      raise exception using errcode = '22023', message = 'invalid_first_time_occurrence';
    end if;
  else
    if normalized_timezone is null or length(normalized_timezone) > 100 then
      raise exception using errcode = '22023', message = 'invalid_first_time_occurrence';
    end if;

    begin
      perform pg_catalog.timezone(normalized_timezone, p_occurred_start);
    exception
      when invalid_parameter_value then
        raise exception using errcode = '22023', message = 'invalid_first_time_timezone';
    end;
  end if;

  if cardinality(coalesce(p_collection_names, '{}'::text[])) > 20
    or exists (
      select 1
      from unnest(coalesce(p_collection_names, '{}'::text[])) as collection_name
      where nullif(btrim(collection_name), '') is null
        or length(btrim(collection_name)) > 80
    )
  then
    raise exception using errcode = '22023', message = 'invalid_collections';
  end if;

  if cardinality(coalesce(p_tag_names, '{}'::text[])) > 50
    or exists (
      select 1
      from unnest(coalesce(p_tag_names, '{}'::text[])) as tag_name
      where nullif(btrim(tag_name), '') is null
        or length(btrim(tag_name)) > 60
    )
  then
    raise exception using errcode = '22023', message = 'invalid_tags';
  end if;

  if created_entry then
    if p_expected_revision is not null then
      raise exception using errcode = '22023', message = 'unexpected_revision';
    end if;

    insert into public.entries (
      owner_id,
      title,
      body,
      entry_type,
      inbox_status,
      occurred_start,
      occurred_end,
      date_precision,
      occurred_label,
      occurred_timezone
    )
    values (
      first_time_owner_id,
      normalized_title,
      normalized_body,
      'first_time',
      'organized',
      p_occurred_start,
      null,
      p_date_precision,
      normalized_label,
      normalized_timezone
    )
    returning id, entries.revision into saved_entry_id, saved_revision;
  else
    if p_expected_revision is null or p_expected_revision < 1 then
      raise exception using errcode = '22023', message = 'invalid_revision';
    end if;

    update public.entries as entries
    set
      title = normalized_title,
      body = normalized_body,
      occurred_start = p_occurred_start,
      occurred_end = null,
      date_precision = p_date_precision,
      occurred_label = normalized_label,
      occurred_timezone = normalized_timezone
    where entries.id = p_entry_id
      and entries.owner_id = first_time_owner_id
      and entries.entry_type = 'first_time'
      and entries.revision = p_expected_revision
      and entries.deleted_at is null
    returning entries.id, entries.revision into saved_entry_id, saved_revision;

    if saved_entry_id is null then
      return;
    end if;
  end if;

  with normalized_names as (
    select distinct on (lower(btrim(collection_name)))
      btrim(collection_name) as name
    from unnest(coalesce(p_collection_names, '{}'::text[])) as collection_name
    order by lower(btrim(collection_name)), btrim(collection_name)
  )
  insert into public.collections (owner_id, name)
  select first_time_owner_id, normalized_names.name
  from normalized_names
  where not exists (
    select 1
    from public.collections
    where owner_id = first_time_owner_id
      and lower(name) = lower(normalized_names.name)
      and archived_at is null
  )
  on conflict do nothing;

  delete from public.entry_collections
  where entry_collections.entry_id = saved_entry_id
    and entry_collections.owner_id = first_time_owner_id;

  with normalized_names as (
    select distinct lower(btrim(collection_name)) as normalized_name
    from unnest(coalesce(p_collection_names, '{}'::text[])) as collection_name
  )
  insert into public.entry_collections (entry_id, collection_id, owner_id)
  select saved_entry_id, collections.id, first_time_owner_id
  from public.collections
  join normalized_names on lower(collections.name) = normalized_names.normalized_name
  where collections.owner_id = first_time_owner_id
    and collections.archived_at is null
  on conflict do nothing;

  with normalized_names as (
    select distinct on (lower(btrim(tag_name)))
      btrim(tag_name) as name
    from unnest(coalesce(p_tag_names, '{}'::text[])) as tag_name
    order by lower(btrim(tag_name)), btrim(tag_name)
  )
  insert into public.tags (owner_id, name)
  select first_time_owner_id, normalized_names.name
  from normalized_names
  where not exists (
    select 1
    from public.tags
    where owner_id = first_time_owner_id
      and lower(name) = lower(normalized_names.name)
  )
  on conflict do nothing;

  delete from public.entry_tags
  where entry_tags.entry_id = saved_entry_id
    and entry_tags.owner_id = first_time_owner_id;

  with normalized_names as (
    select distinct lower(btrim(tag_name)) as normalized_name
    from unnest(coalesce(p_tag_names, '{}'::text[])) as tag_name
  )
  insert into public.entry_tags (entry_id, tag_id, owner_id)
  select saved_entry_id, tags.id, first_time_owner_id
  from public.tags
  join normalized_names on lower(tags.name) = normalized_names.normalized_name
  where tags.owner_id = first_time_owner_id
  on conflict do nothing;

  return query select saved_entry_id, saved_revision, created_entry;
end;
$$;

revoke all on function public.save_first_time_entry(
  text,
  text,
  timestamptz,
  text,
  text,
  text,
  text[],
  text[],
  uuid,
  integer
) from public, anon;

grant execute on function public.save_first_time_entry(
  text,
  text,
  timestamptz,
  text,
  text,
  text,
  text[],
  text[],
  uuid,
  integer
) to authenticated;

comment on function public.save_first_time_entry(
  text,
  text,
  timestamptz,
  text,
  text,
  text,
  text[],
  text[],
  uuid,
  integer
) is 'Creates or revision-safely updates an owned First Time and atomically replaces its Collections and tags.';

create or replace function public.register_first_time_attachment(
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
      and entries.entry_type = 'first_time'
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

revoke all on function public.register_first_time_attachment(
  uuid,
  uuid,
  text,
  text,
  text,
  bigint,
  integer,
  integer
) from public, anon;

grant execute on function public.register_first_time_attachment(
  uuid,
  uuid,
  text,
  text,
  text,
  bigint,
  integer,
  integer
) to authenticated;

comment on function public.register_first_time_attachment(
  uuid,
  uuid,
  text,
  text,
  text,
  bigint,
  integer,
  integer
) is 'Idempotently registers an uploaded private image against an owned non-Trash First Time after validating its Storage path and metadata.';

create or replace function public.trash_first_time_attachment(
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
        and entries.entry_type = 'first_time'
        and entries.deleted_at is null
    )
  returning attachments.id, attachments.entry_id, attachments.deleted_at;
end;
$$;

revoke all on function public.trash_first_time_attachment(uuid) from public, anon;
grant execute on function public.trash_first_time_attachment(uuid) to authenticated;

comment on function public.trash_first_time_attachment(uuid) is
  'Recoverably removes an owned First Time image from active views without deleting its private Storage object.';

create or replace function public.trash_first_time_entry(
  p_entry_id uuid,
  p_expected_revision integer
)
returns table (
  entry_id uuid,
  revision integer
)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  first_time_owner_id uuid := auth.uid();
begin
  if first_time_owner_id is null then
    return;
  end if;

  if p_expected_revision is null or p_expected_revision < 1 then
    raise exception using errcode = '22023', message = 'invalid_revision';
  end if;

  return query
  update public.entries
  set deleted_at = timezone('utc', now())
  where entries.id = p_entry_id
    and entries.owner_id = first_time_owner_id
    and entries.entry_type = 'first_time'
    and entries.revision = p_expected_revision
    and entries.deleted_at is null
  returning entries.id, entries.revision;
end;
$$;

revoke all on function public.trash_first_time_entry(uuid, integer) from public, anon;
grant execute on function public.trash_first_time_entry(uuid, integer) to authenticated;

comment on function public.trash_first_time_entry(uuid, integer) is
  'Revision-safely moves an owned First Time to Trash while preserving Entry history and private media.';
