-- Preserve Done state during later edits; specialized structures keep their dedicated editors.
create function public.editable_entry(p_entry_id uuid) returns jsonb
language sql stable security invoker set search_path='' as $$
 select to_jsonb(e) || jsonb_build_object(
   'collection_names',coalesce((select jsonb_agg(c.name order by c.name) from public.entry_collections ec join public.collections c on c.id=ec.collection_id and c.owner_id=ec.owner_id where ec.entry_id=e.id and ec.owner_id=auth.uid() and c.archived_at is null),'[]'),
   'tag_names',coalesce((select jsonb_agg(t.name order by t.name) from public.entry_tags et join public.tags t on t.id=et.tag_id and t.owner_id=et.owner_id where et.entry_id=e.id and et.owner_id=auth.uid()),'[]'))
 from public.entries e where e.id=p_entry_id and e.owner_id=auth.uid()
 and e.deleted_at is null and e.entry_type in ('standard','first_time');
$$;
revoke all on function public.editable_entry(uuid) from public,anon;
grant execute on function public.editable_entry(uuid) to authenticated;
create or replace function public.review_entry_with_occurrence(
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
  p_date_precision text
)
returns table (
  entry_id uuid,
  revision integer,
  inbox_status text
)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  review_owner_id uuid := auth.uid();
  reviewed_entry_id uuid;
  reviewed_revision integer;
  reviewed_inbox_status text;
begin
  if review_owner_id is null then
    return;
  end if;

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

  update public.entries as entry
  set
    title = p_title,
    body = p_body,
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

  if reviewed_entry_id is null then
    return;
  end if;

  with normalized_names as (
    select distinct on (lower(btrim(collection_name)))
      btrim(collection_name) as name
    from unnest(coalesce(p_collection_names, '{}'::text[])) as collection_name
    order by lower(btrim(collection_name)), btrim(collection_name)
  )
  insert into public.collections (owner_id, name)
  select review_owner_id, normalized_names.name
  from normalized_names
  where not exists (
    select 1
    from public.collections
    where owner_id = review_owner_id
      and lower(name) = lower(normalized_names.name)
      and archived_at is null
  )
  on conflict do nothing;

  delete from public.entry_collections as entry_collection
  where entry_collection.entry_id = reviewed_entry_id
    and entry_collection.owner_id = review_owner_id
    and exists (select 1 from public.collections c where c.id = entry_collection.collection_id and c.archived_at is null);

  with normalized_names as (
    select distinct lower(btrim(collection_name)) as normalized_name
    from unnest(coalesce(p_collection_names, '{}'::text[])) as collection_name
  )
  insert into public.entry_collections (entry_id, collection_id, owner_id)
  select reviewed_entry_id, collections.id, review_owner_id
  from public.collections as collections
  join normalized_names
    on lower(collections.name) = normalized_names.normalized_name
  where collections.owner_id = review_owner_id
    and collections.archived_at is null
  on conflict do nothing;

  with normalized_names as (
    select distinct on (lower(btrim(tag_name)))
      btrim(tag_name) as name
    from unnest(coalesce(p_tag_names, '{}'::text[])) as tag_name
    order by lower(btrim(tag_name)), btrim(tag_name)
  )
  insert into public.tags (owner_id, name)
  select review_owner_id, normalized_names.name
  from normalized_names
  where not exists (
    select 1
    from public.tags
    where owner_id = review_owner_id
      and lower(name) = lower(normalized_names.name)
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
  join normalized_names
    on lower(tags.name) = normalized_names.normalized_name
  where tags.owner_id = review_owner_id
  on conflict do nothing;

  return query
  select reviewed_entry_id, reviewed_revision, reviewed_inbox_status;
end;
$$;

revoke all on function public.review_entry_with_occurrence(
  uuid,
  integer,
  text,
  text,
  text,
  timestamptz,
  text,
  text[],
  text[],
  boolean,
  timestamptz,
  text,
  text
) from public, anon;

grant execute on function public.review_entry_with_occurrence(
  uuid,
  integer,
  text,
  text,
  text,
  timestamptz,
  text,
  text[],
  text[],
  boolean,
  timestamptz,
  text,
  text
) to authenticated;

comment on function public.review_entry_with_occurrence(
  uuid,
  integer,
  text,
  text,
  text,
  timestamptz,
  text,
  text[],
  text[],
  boolean,
  timestamptz,
  text,
  text
) is 'Atomically edits an owned Standard or First Time Entry with full occurrence, organization, preserved Inbox state and revision protection. The original review_entry remains available to older clients.';
