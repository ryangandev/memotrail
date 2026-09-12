create or replace function public.first_times_workspace_with_occurrence()
returns table (
  entry_id uuid,
  title text,
  body text,
  inbox_status text,
  occurred_start timestamptz,
  occurred_end timestamptz,
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
    entries.occurred_end,
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



create or replace function public.save_first_time_with_occurrence(
  p_title text,
  p_body text,
  p_occurred_start timestamptz,
  p_date_precision text,
  p_occurred_label text,
  p_occurred_timezone text,
  p_collection_names text[],
  p_tag_names text[],
  p_entry_id uuid,
  p_expected_revision integer,
  p_occurred_end timestamptz
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

  if p_date_precision is null
    or (p_date_precision = 'unknown' and (p_occurred_start is not null or p_occurred_end is not null))
    or (p_date_precision in ('age','approximate') and normalized_label is null)
    or (p_occurred_end is not null and (p_occurred_start is null or p_occurred_end < p_occurred_start))
    or (p_occurred_end is not null and p_date_precision not in ('range','approximate','age'))
    or (p_occurred_start is not null and not isfinite(p_occurred_start))
    or (p_occurred_end is not null and not isfinite(p_occurred_end))
  then raise exception using errcode='22023',message='invalid_first_time_occurrence';end if;

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
      p_occurred_end,
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
      occurred_end = p_occurred_end,
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

revoke all on function public.first_times_workspace_with_occurrence() from public,anon;
grant execute on function public.first_times_workspace_with_occurrence() to authenticated;
revoke all on function public.save_first_time_with_occurrence(text,text,timestamptz,text,text,text,text[],text[],uuid,integer,timestamptz) from public,anon;
grant execute on function public.save_first_time_with_occurrence(text,text,timestamptz,text,text,text,text[],text[],uuid,integer,timestamptz) to authenticated;

-- Keep the old signature callable, but do not let an older editor erase dates it cannot represent.
create or replace function public.save_first_time_entry(
 p_title text,p_body text,p_occurred_start timestamptz,p_date_precision text,
 p_occurred_label text,p_occurred_timezone text,p_collection_names text[],p_tag_names text[],
 p_entry_id uuid,p_expected_revision integer
) returns table(entry_id uuid,revision integer,was_created boolean)
language plpgsql security invoker set search_path='' as $$
declare existing public.entries;
begin
 if auth.uid() is null then return;end if;
 if p_entry_id is not null then
   select * into existing from public.entries e where e.id=p_entry_id and e.owner_id=auth.uid()
     and e.entry_type='first_time' and e.deleted_at is null for update;
   if not found or existing.revision is distinct from p_expected_revision then return;end if;
   if existing.occurred_end is not null or
      (existing.date_precision in ('exact','range') and
       (p_date_precision is distinct from existing.date_precision or p_occurred_start is distinct from existing.occurred_start))
   then raise exception using errcode='22023',message='first_time_requires_current_editor';end if;
 end if;
 return query select * from public.save_first_time_with_occurrence(p_title,p_body,p_occurred_start,p_date_precision,
 p_occurred_label,p_occurred_timezone,p_collection_names,p_tag_names,p_entry_id,p_expected_revision,null);
end;$$;
