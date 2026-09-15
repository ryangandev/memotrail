-- Keep one atomic review path for plaintext, optional rich text, organization,
-- occurrence, and photo Place adoption. Existing clients preserve rich text.
create function public.review_entry_with_occurrence_rich(
  p_entry_id uuid,
  p_expected_revision integer,
  p_title text,
  p_body text,
  p_entry_type text,
  p_occurred_start timestamptz,
  p_occurred_timezone text,
  p_collection_names text[],
  p_tag_names text[],
  p_mark_done boolean,
  p_occurred_end timestamptz,
  p_occurred_label text,
  p_date_precision text,
  p_body_rich jsonb,
  p_preserve_rich_text boolean
)
returns table(entry_id uuid, revision integer, inbox_status text)
language plpgsql security invoker set search_path = '' as $$
declare
  review_owner_id uuid := auth.uid();
  reviewed_entry_id uuid;
  reviewed_revision integer;
  reviewed_inbox_status text;
begin
  if review_owner_id is null then return; end if;
  if p_expected_revision < 1 then
    raise exception using errcode = '22023', message = 'invalid_revision';
  end if;

  p_title := nullif(btrim(p_title), '');
  p_body := btrim(coalesce(p_body, ''));
  if p_title is null and p_body = '' then
    raise exception using errcode = '22023', message = 'empty_entry';
  end if;
  if length(coalesce(p_title, '')) > 200 or length(p_body) > 50000 then
    raise exception using errcode = '22023', message = 'entry_content_too_long';
  end if;
  if p_entry_type not in ('standard', 'first_time') then
    raise exception using errcode = '22023', message = 'unsupported_entry_type';
  end if;
  if p_entry_type = 'first_time' and p_title is null then
    raise exception using errcode = '22023', message = 'first_time_requires_title';
  end if;

  if p_preserve_rich_text is null then
    raise exception using errcode = '22023', message = 'invalid_rich_text';
  end if;
  if not p_preserve_rich_text and p_body_rich is not null and (
    jsonb_typeof(p_body_rich) is distinct from 'object'
    or p_body_rich->>'version' is distinct from '1'
    or jsonb_typeof(p_body_rich->'text') is distinct from 'string'
    or p_body_rich->>'text' is distinct from p_body
    or jsonb_typeof(p_body_rich->'document') is distinct from 'object'
    or octet_length(p_body_rich::text) > 300000
  ) then
    raise exception using errcode = '22023', message = 'invalid_rich_text';
  end if;

  p_occurred_label := nullif(btrim(p_occurred_label), '');
  if p_date_precision is null or p_date_precision not in ('exact','day','month','year','approximate','age','range','unknown')
    or p_occurred_timezone is null or length(p_occurred_timezone) > 100
    or not exists (select 1 from pg_catalog.pg_timezone_names where name = p_occurred_timezone)
    or length(coalesce(p_occurred_label,'')) > 200
    or (p_date_precision in ('exact','day','month','year','range') and p_occurred_start is null)
    or (p_date_precision = 'unknown' and (p_occurred_start is not null or p_occurred_end is not null))
    or (p_date_precision in ('age','approximate') and p_occurred_label is null)
    or (p_occurred_end is not null and (p_occurred_start is null or p_occurred_end < p_occurred_start))
    or (p_occurred_end is not null and p_date_precision not in ('range','approximate','age'))
    or (p_occurred_start is not null and not isfinite(p_occurred_start))
    or (p_occurred_end is not null and not isfinite(p_occurred_end))
  then
    raise exception using errcode = '22023', message = 'invalid_occurrence';
  end if;

  if cardinality(coalesce(p_collection_names, '{}'::text[])) > 20
    or exists (
      select 1 from unnest(coalesce(p_collection_names, '{}'::text[])) as collection_name
      where nullif(btrim(collection_name), '') is null or length(btrim(collection_name)) > 80
    )
  then
    raise exception using errcode = '22023', message = 'invalid_collections';
  end if;
  if cardinality(coalesce(p_tag_names, '{}'::text[])) > 50
    or exists (
      select 1 from unnest(coalesce(p_tag_names, '{}'::text[])) as tag_name
      where nullif(btrim(tag_name), '') is null or length(btrim(tag_name)) > 60
    )
  then
    raise exception using errcode = '22023', message = 'invalid_tags';
  end if;

  update public.entries as entry
  set
    title = p_title,
    body = p_body,
    metadata = case
      when p_preserve_rich_text then entry.metadata
      when p_body_rich is null then entry.metadata - 'body_rich'
      else jsonb_set(entry.metadata, '{body_rich}', p_body_rich, true)
    end,
    entry_type = p_entry_type,
    inbox_status = case when p_mark_done then 'organized' else entry.inbox_status end,
    occurred_start = p_occurred_start,
    occurred_end = p_occurred_end,
    occurred_label = p_occurred_label,
    date_precision = p_date_precision,
    occurred_timezone = btrim(p_occurred_timezone)
  where entry.id = p_entry_id
    and entry.owner_id = review_owner_id
    and entry.revision = p_expected_revision
    and entry.entry_type in ('standard','first_time')
    and entry.deleted_at is null
  returning entry.id, entry.revision, entry.inbox_status
  into reviewed_entry_id, reviewed_revision, reviewed_inbox_status;

  if reviewed_entry_id is null then return; end if;

  with normalized_names as (
    select distinct on (lower(btrim(collection_name))) btrim(collection_name) as name
    from unnest(coalesce(p_collection_names, '{}'::text[])) as collection_name
    order by lower(btrim(collection_name)), btrim(collection_name)
  )
  insert into public.collections (owner_id, name)
  select review_owner_id, normalized_names.name from normalized_names
  where not exists (
    select 1 from public.collections
    where owner_id = review_owner_id and lower(name) = lower(normalized_names.name)
      and archived_at is null
  )
  on conflict do nothing;

  delete from public.entry_collections as entry_collection
  where entry_collection.entry_id = reviewed_entry_id
    and entry_collection.owner_id = review_owner_id
    and exists (
      select 1 from public.collections c
      where c.id = entry_collection.collection_id and c.archived_at is null
    );

  with normalized_names as (
    select distinct lower(btrim(collection_name)) as normalized_name
    from unnest(coalesce(p_collection_names, '{}'::text[])) as collection_name
  )
  insert into public.entry_collections (entry_id, collection_id, owner_id)
  select reviewed_entry_id, collections.id, review_owner_id
  from public.collections as collections
  join normalized_names on lower(collections.name) = normalized_names.normalized_name
  where collections.owner_id = review_owner_id and collections.archived_at is null
  on conflict do nothing;

  with normalized_names as (
    select distinct on (lower(btrim(tag_name))) btrim(tag_name) as name
    from unnest(coalesce(p_tag_names, '{}'::text[])) as tag_name
    order by lower(btrim(tag_name)), btrim(tag_name)
  )
  insert into public.tags (owner_id, name)
  select review_owner_id, normalized_names.name from normalized_names
  where not exists (
    select 1 from public.tags
    where owner_id = review_owner_id and lower(name) = lower(normalized_names.name)
  )
  on conflict do nothing;

  delete from public.entry_tags as entry_tag
  where entry_tag.entry_id = reviewed_entry_id
    and entry_tag.owner_id = review_owner_id;

  with normalized_names as (
    select distinct lower(btrim(tag_name)) as normalized_name
    from unnest(coalesce(p_tag_names, '{}'::text[])) as tag_name
  )
  insert into public.entry_tags (entry_id, tag_id, owner_id)
  select reviewed_entry_id, tags.id, review_owner_id
  from public.tags as tags
  join normalized_names on lower(tags.name) = normalized_names.normalized_name
  where tags.owner_id = review_owner_id
  on conflict do nothing;

  return query select reviewed_entry_id, reviewed_revision, reviewed_inbox_status;
end;
$$;

revoke all on function public.review_entry_with_occurrence_rich(uuid,integer,text,text,text,timestamptz,text,text[],text[],boolean,timestamptz,text,text,jsonb,boolean) from public,anon;
grant execute on function public.review_entry_with_occurrence_rich(uuid,integer,text,text,text,timestamptz,text,text[],text[],boolean,timestamptz,text,text,jsonb,boolean) to authenticated;

-- Older Web and iOS clients keep rich text when they edit fields they understand.
create or replace function public.review_entry_with_occurrence(
  p_entry_id uuid, p_expected_revision integer, p_title text, p_body text,
  p_entry_type text, p_occurred_start timestamptz, p_occurred_timezone text,
  p_collection_names text[], p_tag_names text[], p_mark_done boolean,
  p_occurred_end timestamptz, p_occurred_label text, p_date_precision text
)
returns table(entry_id uuid, revision integer, inbox_status text)
language sql security invoker set search_path = '' as $$
  select * from public.review_entry_with_occurrence_rich(
    p_entry_id,p_expected_revision,p_title,p_body,p_entry_type,p_occurred_start,
    p_occurred_timezone,p_collection_names,p_tag_names,p_mark_done,p_occurred_end,
    p_occurred_label,p_date_precision,null,true
  );
$$;

revoke all on function public.review_entry_with_occurrence(uuid,integer,text,text,text,timestamptz,text,text[],text[],boolean,timestamptz,text,text) from public,anon;
grant execute on function public.review_entry_with_occurrence(uuid,integer,text,text,text,timestamptz,text,text[],text[],boolean,timestamptz,text,text) to authenticated;

create function public.review_entry_with_photo_place_rich(
  p_entry_id uuid, p_expected_revision integer, p_title text, p_body text,
  p_entry_type text, p_occurred_start timestamptz, p_occurred_timezone text,
  p_collection_names text[], p_tag_names text[], p_mark_done boolean,
  p_occurred_end timestamptz, p_occurred_label text, p_date_precision text,
  p_photo_place jsonb, p_body_rich jsonb
)
returns table(entry_id uuid, revision integer, inbox_status text)
language plpgsql security invoker set search_path = '' as $$
declare
  owner uuid := auth.uid();
  reviewed record;
  target uuid;
  source_id uuid;
  target_revision integer;
  name text;
  latitude numeric;
  longitude numeric;
begin
  if owner is null then return; end if;
  if p_photo_place is not null and p_photo_place <> 'null'::jsonb then
    if jsonb_typeof(p_photo_place) <> 'object'
      or coalesce(p_photo_place->>'kind','') not in ('new','existing')
      or coalesce(p_photo_place->>'attachmentId','') !~* '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'
    then raise exception using errcode='22023',message='invalid_photo_place'; end if;
    source_id := (p_photo_place->>'attachmentId')::uuid;
    if p_photo_place->>'kind' = 'existing' then
      if coalesce(p_photo_place->>'placeId','') !~* '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'
        or coalesce(p_photo_place->>'revision','') !~ '^[1-9][0-9]{0,8}$'
      then raise exception using errcode='22023',message='invalid_photo_place'; end if;
      target_revision := (p_photo_place->>'revision')::integer;
      select p.id into target from public.places p
      where p.id=(p_photo_place->>'placeId')::uuid and p.owner_id=owner
        and p.deleted_at is null and p.revision=target_revision for update;
      if target is null then raise exception using errcode='40001',message='photo_place_changed'; end if;
    else
      name := nullif(btrim(p_photo_place->>'name'),'');
      if name is null or length(name)>200 or jsonb_typeof(p_photo_place->'name') is distinct from 'string'
        or jsonb_typeof(p_photo_place->'latitude') is distinct from 'number'
        or jsonb_typeof(p_photo_place->'longitude') is distinct from 'number'
      then raise exception using errcode='22023',message='invalid_photo_place'; end if;
      latitude := (p_photo_place->>'latitude')::numeric;
      longitude := (p_photo_place->>'longitude')::numeric;
      if latitude not between -90 and 90 or longitude not between -180 and 180
      then raise exception using errcode='22023',message='invalid_photo_place'; end if;
    end if;
  end if;

  select * into reviewed from public.review_entry_with_occurrence_rich(
    p_entry_id,p_expected_revision,p_title,p_body,p_entry_type,p_occurred_start,
    p_occurred_timezone,p_collection_names,p_tag_names,p_mark_done,p_occurred_end,
    p_occurred_label,p_date_precision,p_body_rich,false
  );
  if reviewed.entry_id is null then return; end if;

  if source_id is not null then
    if not public.lock_photo_place_source(reviewed.entry_id,source_id)
    then raise exception using errcode='40001',message='photo_source_changed'; end if;
    if target is null then
      select s.place_id into target from public.save_place(
        name,null,null,null,null,latitude,longitude,null,array[reviewed.entry_id],null,null
      ) s;
    elsif not exists(
      select 1 from public.entry_places ep
      where ep.entry_id=reviewed.entry_id and ep.place_id=target and ep.owner_id=owner
    ) then
      update public.places p set notes=p.notes where p.id=target and p.owner_id=owner;
      insert into public.entry_places(entry_id,place_id,owner_id,relationship)
      values(reviewed.entry_id,target,owner,'related');
    end if;
  end if;
  return query select reviewed.entry_id,reviewed.revision,reviewed.inbox_status;
end;
$$;

revoke all on function public.review_entry_with_photo_place_rich(uuid,integer,text,text,text,timestamptz,text,text[],text[],boolean,timestamptz,text,text,jsonb,jsonb) from public,anon;
grant execute on function public.review_entry_with_photo_place_rich(uuid,integer,text,text,text,timestamptz,text,text[],text[],boolean,timestamptz,text,text,jsonb,jsonb) to authenticated;

comment on function public.review_entry_with_photo_place_rich(uuid,integer,text,text,text,timestamptz,text,text[],text[],boolean,timestamptz,text,text,jsonb,jsonb) is
  'Atomically reviews an Entry while preserving canonical plaintext and validated optional rich text metadata.';
