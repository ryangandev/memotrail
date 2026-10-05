-- Collections merge into tags.
-- Each active Collection becomes a tag with the same name, and its Entries gain that tag.
-- Trashed Collections are removed with the rest of the Collection data.
-- Tags now allow up to 70 names of up to 80 characters so every merged Entry stays valid.

create function public.valid_tag_names(p_tag_names text[])
returns boolean
language sql
immutable
set search_path = ''
as $$
  select cardinality(coalesce(p_tag_names, '{}'::text[])) <= 70
    and not exists (
      select 1
      from unnest(coalesce(p_tag_names, '{}'::text[])) as tag_name
      where nullif(btrim(tag_name), '') is null or length(btrim(tag_name)) > 80
    );
$$;

create function public.replace_entry_tags(p_entry_id uuid, p_tag_names text[])
returns void
language plpgsql
set search_path = ''
as $$
declare
  tag_owner_id uuid := auth.uid();
begin
  if tag_owner_id is null then
    return;
  end if;

  with normalized_names as (
    select distinct on (lower(btrim(tag_name))) btrim(tag_name) as name
    from unnest(coalesce(p_tag_names, '{}'::text[])) as tag_name
    order by lower(btrim(tag_name)), btrim(tag_name)
  )
  insert into public.tags (owner_id, name)
  select tag_owner_id, normalized_names.name
  from normalized_names
  where not exists (
    select 1
    from public.tags
    where owner_id = tag_owner_id and lower(name) = lower(normalized_names.name)
  )
  on conflict do nothing;

  delete from public.entry_tags as membership
  where membership.entry_id = p_entry_id and membership.owner_id = tag_owner_id;

  with normalized_names as (
    select distinct lower(btrim(tag_name)) as normalized_name
    from unnest(coalesce(p_tag_names, '{}'::text[])) as tag_name
  )
  insert into public.entry_tags (entry_id, tag_id, owner_id)
  select p_entry_id, tag.id, tag_owner_id
  from public.tags as tag
  join normalized_names on lower(tag.name) = normalized_names.normalized_name
  where tag.owner_id = tag_owner_id
  on conflict do nothing;
end;
$$;

revoke all on function public.valid_tag_names(text[]) from public, anon;
grant execute on function public.valid_tag_names(text[]) to authenticated;
revoke all on function public.replace_entry_tags(uuid, text[]) from public, anon;
grant execute on function public.replace_entry_tags(uuid, text[]) to authenticated;

insert into public.tags (owner_id, name)
select distinct on (collection.owner_id, lower(btrim(collection.name)))
  collection.owner_id, btrim(collection.name)
from public.collections as collection
where collection.archived_at is null
  and not exists (
    select 1
    from public.tags as tag
    where tag.owner_id = collection.owner_id and lower(tag.name) = lower(btrim(collection.name))
  )
order by collection.owner_id, lower(btrim(collection.name)), collection.created_at, collection.id;

create temporary table collection_tag_map as
select collection.id as collection_id, tag.id as tag_id, tag.name as tag_name
from public.collections as collection
join public.tags as tag
  on tag.owner_id = collection.owner_id and lower(tag.name) = lower(btrim(collection.name))
where collection.archived_at is null;

insert into public.entry_tags (entry_id, tag_id, owner_id)
select membership.entry_id, map.tag_id, membership.owner_id
from public.entry_collections as membership
join collection_tag_map as map on map.collection_id = membership.collection_id
on conflict do nothing;

-- History keeps each version's Collections as the tags they became.
update public.entry_versions as version
set snapshot = (version.snapshot - 'collections') || jsonb_build_object('tags', coalesce((
  select jsonb_agg(jsonb_build_object('id', merged.id, 'name', merged.name) order by merged.name, merged.id)
  from (
    select distinct on (candidate.id) candidate.id, candidate.name
    from (
      select (tag->>'id')::uuid as id, tag->>'name' as name, 0 as priority
      from jsonb_array_elements(coalesce(version.snapshot->'tags', '[]'::jsonb)) as tag
      union all
      select map.tag_id, map.tag_name, 1
      from jsonb_array_elements(coalesce(version.snapshot->'collections', '[]'::jsonb)) as collection
      join collection_tag_map as map on map.collection_id = (collection->>'id')::uuid
    ) as candidate
    order by candidate.id, candidate.priority
  ) as merged
), '[]'::jsonb))
where version.snapshot ? 'collections';

drop table collection_tag_map;

-- Pending AI suggestions only propose tags now.
update public.ai_suggestions
set suggestions = suggestions - 'collections'
where suggestions ? 'collections';

alter table public.ai_suggestions drop constraint ai_suggestions_entry_payload_check;
alter table public.ai_suggestions
  add constraint ai_suggestions_entry_payload_check
  check (jsonb_typeof(suggestions) = 'object'
    and not (suggestions ? 'entryType')
    and not (suggestions ? 'classification')
    and not (suggestions ? 'collections'));

drop function public.collection_wiki_items;
drop function public.collections_workspace;
drop function public.organization_workspace;
drop function public.save_organization;
drop function public.trash_collection;

drop table public.entry_collections;
drop table public.collections;

create function public.tags_workspace(p_query text default '', p_limit integer default 50, p_offset integer default 0)
returns table(id uuid, name text, revision integer, entry_count bigint, total_count bigint)
language plpgsql
stable
set search_path = ''
as $$
begin
  if auth.uid() is null then return; end if;
  if p_query is null or length(p_query) > 200
    or p_limit is null or p_limit < 1 or p_limit > 100 or p_offset is null or p_offset < 0 then
    raise exception using errcode='22023',message='invalid_tag_page';
  end if;
  return query select t.id,t.name,t.revision,
    (select count(*) from public.entry_tags et join public.entries e on e.id=et.entry_id and e.owner_id=et.owner_id
      where et.tag_id=t.id and et.owner_id=auth.uid() and e.deleted_at is null), count(*) over()
  from public.tags t where t.owner_id=auth.uid() and position(lower(btrim(p_query)) in lower(t.name)) > 0
  order by lower(t.name),t.id limit p_limit offset p_offset;
end;
$$;

create function public.save_tag(p_name text, p_id uuid default null, p_expected_revision integer default null)
returns uuid
language plpgsql
set search_path = ''
as $$
declare saved_id uuid; affected_id uuid; old_name text;
begin
  if auth.uid() is null then return null; end if;
  if nullif(btrim(p_name),'') is null or length(btrim(p_name)) > 80 then
    raise exception using errcode='22023',message='invalid_tag_details';
  end if;
  if (p_id is null and p_expected_revision is not null) or (p_id is not null and (p_expected_revision is null or p_expected_revision < 1)) then
    raise exception using errcode='22023',message='invalid_revision';
  end if;
  if p_id is null then
    insert into public.tags(owner_id,name) values(auth.uid(),btrim(p_name)) returning id into saved_id;
    return saved_id;
  end if;
  select name into old_name from public.tags where id=p_id and owner_id=auth.uid()
    and revision=p_expected_revision for no key update;
  if not found then return null; end if;
  -- Snapshot prior names and reject stale cross-device Entry reviews after a rename.
  if old_name <> btrim(p_name) then
    for affected_id in select e.id from public.entries e where e.owner_id=auth.uid()
      and exists(select 1 from public.entry_tags et where et.entry_id=e.id and et.tag_id=p_id and et.owner_id=auth.uid())
    order by e.id for update loop
      update public.entries set updated_at=clock_timestamp() where id=affected_id and owner_id=auth.uid();
    end loop;
  end if;
  update public.tags set name=btrim(p_name) where id=p_id and owner_id=auth.uid() returning id into saved_id;
  return saved_id;
end;
$$;

revoke all on function public.tags_workspace(text, integer, integer) from public, anon;
grant execute on function public.tags_workspace(text, integer, integer) to authenticated;
revoke all on function public.save_tag(text, uuid, integer) from public, anon;
grant execute on function public.save_tag(text, uuid, integer) to authenticated;

drop function public.review_wiki_item_with_occurrence_rich(p_entry_id uuid, p_expected_revision integer, p_title text, p_body text, p_item_kind text, p_item_subtype text, p_occurred_start timestamp with time zone, p_occurred_timezone text, p_collection_names text[], p_tag_names text[], p_mark_done boolean, p_occurred_end timestamp with time zone, p_occurred_label text, p_date_precision text, p_body_rich jsonb, p_preserve_rich_text boolean);
drop function public.review_wiki_item_with_photo_place_core(p_entry_id uuid, p_expected_revision integer, p_title text, p_body text, p_item_kind text, p_item_subtype text, p_occurred_start timestamp with time zone, p_occurred_timezone text, p_collection_names text[], p_tag_names text[], p_mark_done boolean, p_occurred_end timestamp with time zone, p_occurred_label text, p_date_precision text, p_photo_place jsonb, p_body_rich jsonb, p_preserve_rich_text boolean);
drop function public.review_wiki_item_with_photo_place(p_entry_id uuid, p_expected_revision integer, p_title text, p_body text, p_item_kind text, p_item_subtype text, p_occurred_start timestamp with time zone, p_occurred_timezone text, p_collection_names text[], p_tag_names text[], p_mark_done boolean, p_occurred_end timestamp with time zone, p_occurred_label text, p_date_precision text, p_photo_place jsonb);
drop function public.review_wiki_item_with_photo_place_rich(p_entry_id uuid, p_expected_revision integer, p_title text, p_body text, p_item_kind text, p_item_subtype text, p_occurred_start timestamp with time zone, p_occurred_timezone text, p_collection_names text[], p_tag_names text[], p_mark_done boolean, p_occurred_end timestamp with time zone, p_occurred_label text, p_date_precision text, p_photo_place jsonb, p_body_rich jsonb);
drop function public.review_wiki_item_with_location_rich(p_entry_id uuid, p_expected_revision integer, p_title text, p_body text, p_item_kind text, p_item_subtype text, p_occurred_start timestamp with time zone, p_occurred_timezone text, p_collection_names text[], p_tag_names text[], p_mark_done boolean, p_occurred_end timestamp with time zone, p_occurred_label text, p_date_precision text, p_photo_place jsonb, p_primary_location jsonb, p_body_rich jsonb);
drop function public.save_first_time_with_occurrence(p_title text, p_body text, p_occurred_start timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_collection_names text[], p_tag_names text[], p_entry_id uuid, p_expected_revision integer, p_occurred_end timestamp with time zone);
drop function public.save_home_entry_with_occurrence(p_title text, p_body text, p_occurred_start timestamp with time zone, p_occurred_end timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_place_id uuid, p_place_name text, p_address text, p_city text, p_region text, p_country text, p_latitude numeric, p_longitude numeric, p_place_notes text, p_move_in_reason text, p_move_out_reason text, p_collection_names text[], p_tag_names text[], p_entry_id uuid, p_expected_revision integer);
drop function public.save_home_entry(p_title text, p_body text, p_occurred_start timestamp with time zone, p_occurred_end timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_place_id uuid, p_place_name text, p_address text, p_city text, p_region text, p_country text, p_latitude numeric, p_longitude numeric, p_place_notes text, p_move_in_reason text, p_move_out_reason text, p_collection_names text[], p_tag_names text[], p_entry_id uuid, p_expected_revision integer);
drop function public.extract_capture_to_home(p_capture_id uuid, p_capture_revision integer, p_title text, p_body text, p_occurred_start timestamp with time zone, p_occurred_end timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_place_id uuid, p_place_name text, p_address text, p_city text, p_region text, p_country text, p_latitude numeric, p_longitude numeric, p_place_notes text, p_move_in_reason text, p_move_out_reason text, p_collection_names text[], p_tag_names text[]);
drop function public.save_vehicle_entry_with_occurrence(p_title text, p_body text, p_occurred_start timestamp with time zone, p_occurred_end timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_make text, p_model text, p_model_year integer, p_color text, p_collection_names text[], p_tag_names text[], p_entry_id uuid, p_expected_revision integer);
drop function public.save_vehicle_entry(p_title text, p_body text, p_occurred_start timestamp with time zone, p_occurred_end timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_make text, p_model text, p_model_year integer, p_color text, p_collection_names text[], p_tag_names text[], p_entry_id uuid, p_expected_revision integer);
drop function public.extract_capture_to_vehicle(p_capture_id uuid, p_capture_revision integer, p_title text, p_body text, p_occurred_start timestamp with time zone, p_occurred_end timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_make text, p_model text, p_model_year integer, p_color text, p_collection_names text[], p_tag_names text[]);
drop function public.save_goal_entry(p_title text, p_body text, p_horizon text, p_status text, p_target_date date, p_collection_names text[], p_tag_names text[], p_related_entry_ids uuid[], p_entry_id uuid, p_expected_revision integer);
drop function public.extract_capture_to_goal(p_capture_id uuid, p_capture_revision integer, p_title text, p_body text, p_horizon text, p_status text, p_target_date date, p_collection_names text[], p_tag_names text[], p_related_entry_ids uuid[]);
drop function public.archive_wiki_search_evidence(p_queries text[], p_item_classifications text[], p_collection_names text[], p_tag_names text[], p_date_from date, p_date_to date, p_before_latest_home boolean, p_order text, p_as_of date);
drop function public.first_times_workspace_with_occurrence();
drop function public.goals_workspace(p_limit integer, p_offset integer);
drop function public.home_resurfaced_memory(p_local_date date, p_timezone text);
drop function public.home_workspace(p_local_date date, p_timezone text, p_recent_limit integer);
drop function public.homes_workspace(p_limit integer, p_offset integer);
drop function public.save_timeline_entry_with_organization(p_track_id uuid, p_timeline_kind text, p_title text, p_body text, p_occurred_start timestamp with time zone, p_occurred_end timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_collection_names text[], p_tag_names text[], p_entry_id uuid, p_expected_revision integer);
drop function public.search_wiki_items(p_query text, p_item_classifications text[], p_collection_names text[], p_tag_names text[], p_date_from date, p_date_to date, p_limit integer, p_offset integer, p_order text);
drop function public.timeline_workspace_with_organization(p_include_hidden boolean);
drop function public.vehicles_workspace(p_limit integer, p_offset integer);

create function public.review_wiki_item_with_occurrence_rich(p_entry_id uuid, p_expected_revision integer, p_title text, p_body text, p_item_kind text, p_item_subtype text, p_occurred_start timestamp with time zone, p_occurred_timezone text, p_tag_names text[], p_mark_done boolean, p_occurred_end timestamp with time zone, p_occurred_label text, p_date_precision text, p_body_rich jsonb, p_preserve_rich_text boolean)
 RETURNS TABLE(entry_id uuid, revision integer, inbox_status text)
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  review_owner_id uuid := auth.uid();
  reviewed_entry_id uuid;
  reviewed_revision integer;
  reviewed_inbox_status text;
begin
  if review_owner_id is null then
    return;
  end if;
  if p_expected_revision is null or p_expected_revision < 1 then
    raise exception using errcode = '22023', message = 'invalid_revision';
  end if;
  if p_item_kind <> 'entry'
    or p_item_subtype is null
    or p_item_subtype !~ '^[a-z][a-z0-9_]{0,63}$'
    or p_item_subtype <> 'entry'
  then
    raise exception using errcode = '22023', message = 'invalid_item_classification';
  end if;

  p_title := nullif(btrim(p_title), '');
  p_body := btrim(coalesce(p_body, ''));
  if p_title is null and p_body = '' then
    raise exception using errcode = '22023', message = 'empty_entry';
  end if;
  if length(coalesce(p_title, '')) > 200 or length(p_body) > 50000 then
    raise exception using errcode = '22023', message = 'entry_content_too_long';
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
    or length(coalesce(p_occurred_label, '')) > 200
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

  if not public.valid_tag_names(p_tag_names) then
    raise exception using errcode = '22023', message = 'invalid_tags';
  end if;

  if exists (
    select 1
    from public.entries as item
    where item.id = p_entry_id
      and item.owner_id = review_owner_id
      and item.revision = p_expected_revision
      and item.deleted_at is null
      and item.item_kind = 'entry' and item.item_subtype = 'entry'
      
      and item.item_kind <> p_item_kind
  ) then
    raise exception using errcode = '22023', message = 'invalid_item_kind_transition';
  end if;

  update public.entries as item
  set
    title = p_title,
    body = p_body,
    metadata = case
      when p_preserve_rich_text then item.metadata
      when p_body_rich is null then item.metadata - 'body_rich'
      else jsonb_set(item.metadata, '{body_rich}', p_body_rich, true)
    end,
    item_kind = p_item_kind,
    item_subtype = p_item_subtype,
    inbox_status = case when p_mark_done then 'organized' else item.inbox_status end,
    occurred_start = p_occurred_start,
    occurred_end = p_occurred_end,
    occurred_label = p_occurred_label,
    date_precision = p_date_precision,
    occurred_timezone = btrim(p_occurred_timezone)
  where item.id = p_entry_id
    and item.owner_id = review_owner_id
    and item.revision = p_expected_revision
    and item.item_kind = 'entry' and item.item_subtype = 'entry'
    and item.deleted_at is null
  returning item.id, item.revision, item.inbox_status
  into reviewed_entry_id, reviewed_revision, reviewed_inbox_status;

  if reviewed_entry_id is null then
    return;
  end if;

  perform public.replace_entry_tags(reviewed_entry_id, p_tag_names);

  return query
  select reviewed_entry_id, reviewed_revision, reviewed_inbox_status;
end;
$function$;

create function public.review_wiki_item_with_photo_place_core(p_entry_id uuid, p_expected_revision integer, p_title text, p_body text, p_item_kind text, p_item_subtype text, p_occurred_start timestamp with time zone, p_occurred_timezone text, p_tag_names text[], p_mark_done boolean, p_occurred_end timestamp with time zone, p_occurred_label text, p_date_precision text, p_photo_place jsonb, p_body_rich jsonb, p_preserve_rich_text boolean)
 RETURNS TABLE(entry_id uuid, revision integer, inbox_status text)
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  review_owner_id uuid := auth.uid();
  reviewed record;
  target_place_id uuid;
  source_attachment_id uuid;
  target_revision integer;
  place_name text;
  latitude numeric;
  longitude numeric;
begin
  if review_owner_id is null then
    return;
  end if;
  if p_photo_place is not null and p_photo_place <> 'null'::jsonb then
    if jsonb_typeof(p_photo_place) <> 'object'
      or coalesce(p_photo_place->>'kind', '') not in ('new', 'existing')
      or coalesce(p_photo_place->>'attachmentId', '') !~* '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'
    then
      raise exception using errcode = '22023', message = 'invalid_photo_place';
    end if;
    source_attachment_id := (p_photo_place->>'attachmentId')::uuid;
    if p_photo_place->>'kind' = 'existing' then
      if coalesce(p_photo_place->>'placeId', '') !~* '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'
        or coalesce(p_photo_place->>'revision', '') !~ '^[1-9][0-9]{0,8}$'
      then
        raise exception using errcode = '22023', message = 'invalid_photo_place';
      end if;
      target_revision := (p_photo_place->>'revision')::integer;
      select place.id
      into target_place_id
      from public.locations as place
      where place.id = (p_photo_place->>'placeId')::uuid
        and place.owner_id = review_owner_id
        and place.deleted_at is null
        and place.revision = target_revision
      for update;
      if target_place_id is null then
        raise exception using errcode = '40001', message = 'photo_place_changed';
      end if;
    else
      place_name := nullif(btrim(p_photo_place->>'name'), '');
      if place_name is null or length(place_name) > 200
        or jsonb_typeof(p_photo_place->'name') is distinct from 'string'
        or jsonb_typeof(p_photo_place->'latitude') is distinct from 'number'
        or jsonb_typeof(p_photo_place->'longitude') is distinct from 'number'
      then
        raise exception using errcode = '22023', message = 'invalid_photo_place';
      end if;
      latitude := (p_photo_place->>'latitude')::numeric;
      longitude := (p_photo_place->>'longitude')::numeric;
      if latitude not between -90 and 90 or longitude not between -180 and 180 then
        raise exception using errcode = '22023', message = 'invalid_photo_place';
      end if;
    end if;
  end if;

  select *
  into reviewed
  from public.review_wiki_item_with_occurrence_rich(
    p_entry_id,
    p_expected_revision,
    p_title,
    p_body,
    p_item_kind,
    p_item_subtype,
    p_occurred_start,
    p_occurred_timezone,
    p_tag_names,
    p_mark_done,
    p_occurred_end,
    p_occurred_label,
    p_date_precision,
    p_body_rich,
    p_preserve_rich_text
  );
  if reviewed.entry_id is null then
    return;
  end if;

  if source_attachment_id is not null then
    if not public.lock_photo_place_source(reviewed.entry_id, source_attachment_id) then
      raise exception using errcode = '40001', message = 'photo_source_changed';
    end if;
    if target_place_id is null then
      select saved.place_id
      into target_place_id
      from public.save_location(
        place_name,
        null,
        null,
        null,
        null,
        latitude,
        longitude,
        null,
        array[reviewed.entry_id],
        null,
        null
      ) as saved;
      perform public.record_photo_location_source(
        target_place_id, reviewed.entry_id, source_attachment_id
      );
    elsif not exists (
      select 1
      from public.entry_places as link
      where link.entry_id = reviewed.entry_id
        and link.place_id = target_place_id
        and link.owner_id = review_owner_id
    ) then
      update public.locations as place
      set notes = place.notes
      where place.id = target_place_id and place.owner_id = review_owner_id;
      insert into public.entry_places (entry_id, place_id, owner_id, relationship)
      values (reviewed.entry_id, target_place_id, review_owner_id, 'related');
    end if;
  end if;

  return query
  select reviewed.entry_id, reviewed.revision, reviewed.inbox_status;
end;
$function$;

create function public.review_wiki_item_with_photo_place(p_entry_id uuid, p_expected_revision integer, p_title text, p_body text, p_item_kind text, p_item_subtype text, p_occurred_start timestamp with time zone, p_occurred_timezone text, p_tag_names text[], p_mark_done boolean, p_occurred_end timestamp with time zone, p_occurred_label text, p_date_precision text, p_photo_place jsonb)
 RETURNS TABLE(entry_id uuid, revision integer, inbox_status text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select *
  from public.review_wiki_item_with_photo_place_core(
    p_entry_id,
    p_expected_revision,
    p_title,
    p_body,
    p_item_kind,
    p_item_subtype,
    p_occurred_start,
    p_occurred_timezone,
    p_tag_names,
    p_mark_done,
    p_occurred_end,
    p_occurred_label,
    p_date_precision,
    p_photo_place,
    null,
    true
  );
$function$;

create function public.review_wiki_item_with_photo_place_rich(p_entry_id uuid, p_expected_revision integer, p_title text, p_body text, p_item_kind text, p_item_subtype text, p_occurred_start timestamp with time zone, p_occurred_timezone text, p_tag_names text[], p_mark_done boolean, p_occurred_end timestamp with time zone, p_occurred_label text, p_date_precision text, p_photo_place jsonb, p_body_rich jsonb)
 RETURNS TABLE(entry_id uuid, revision integer, inbox_status text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select *
  from public.review_wiki_item_with_photo_place_core(
    p_entry_id,
    p_expected_revision,
    p_title,
    p_body,
    p_item_kind,
    p_item_subtype,
    p_occurred_start,
    p_occurred_timezone,
    p_tag_names,
    p_mark_done,
    p_occurred_end,
    p_occurred_label,
    p_date_precision,
    p_photo_place,
    p_body_rich,
    false
  );
$function$;

create function public.review_wiki_item_with_location_rich(p_entry_id uuid, p_expected_revision integer, p_title text, p_body text, p_item_kind text, p_item_subtype text, p_occurred_start timestamp with time zone, p_occurred_timezone text, p_tag_names text[], p_mark_done boolean, p_occurred_end timestamp with time zone, p_occurred_label text, p_date_precision text, p_photo_place jsonb, p_primary_location jsonb, p_body_rich jsonb)
 RETURNS TABLE(entry_id uuid, revision integer, inbox_status text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  review_owner_id uuid := auth.uid();
  reviewed record;
  target_location_id uuid;
  selected_kind text;
  selected_revision integer;
  normalized_name text;
  normalized_formatted_address text;
  normalized_address text;
  normalized_city text;
  normalized_region text;
  normalized_postal_code text;
  normalized_country text;
  normalized_country_code text;
  normalized_timezone text;
  normalized_result_type text;
  provider_identity text;
  provider_confidence numeric;
  latitude numeric;
  longitude numeric;
begin
  if review_owner_id is null then return; end if;

  -- Reject a stale or inaccessible editor before a provider result can create
  -- an unattached Location. The row lock also protects the later review write.
  perform 1
  from public.entries as item
  where item.id = p_entry_id
    and item.owner_id = review_owner_id
    and item.revision = p_expected_revision
    and item.item_kind = 'entry' and item.item_subtype = 'entry'
    and item.deleted_at is null
  for update;
  if not found then return; end if;

  if p_primary_location is not null and p_primary_location <> 'null'::jsonb then
    if jsonb_typeof(p_primary_location) <> 'object' then
      raise exception using errcode = '22023', message = 'invalid_primary_location';
    end if;
    selected_kind := p_primary_location->>'kind';
    if selected_kind = 'existing' then
      if coalesce(p_primary_location->>'id', '') !~* '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'
        or coalesce(p_primary_location->>'revision', '') !~ '^[1-9][0-9]{0,8}$'
      then
        raise exception using errcode = '22023', message = 'invalid_primary_location';
      end if;
      selected_revision := (p_primary_location->>'revision')::integer;
      select location.id into target_location_id
      from public.locations as location
      where location.id = (p_primary_location->>'id')::uuid
        and location.owner_id = review_owner_id
        and location.revision = selected_revision
        and location.deleted_at is null;
      if target_location_id is null then
        raise exception using errcode = '40001', message = 'primary_location_changed';
      end if;
    elsif selected_kind = 'provider' then
      if p_primary_location->>'provider' <> 'geoapify'
        or jsonb_typeof(p_primary_location->'providerLocationId') is distinct from 'string'
        or jsonb_typeof(p_primary_location->'name') is distinct from 'string'
        or jsonb_typeof(p_primary_location->'formattedAddress') is distinct from 'string'
        or jsonb_typeof(p_primary_location->'latitude') is distinct from 'number'
        or jsonb_typeof(p_primary_location->'longitude') is distinct from 'number'
      then
        raise exception using errcode = '22023', message = 'invalid_primary_location';
      end if;
      if exists (
        select 1
        from unnest(array[
          'address','city','region','postalCode','country','countryCode',
          'timezone','resultType','matchType','dataSource'
        ]) as optional_key
        where p_primary_location ? optional_key
          and p_primary_location->optional_key is distinct from 'null'::jsonb
          and jsonb_typeof(p_primary_location->optional_key) <> 'string'
      )
        or (
          p_primary_location ? 'confidence'
          and p_primary_location->'confidence' is distinct from 'null'::jsonb
          and jsonb_typeof(p_primary_location->'confidence') <> 'number'
        )
      then
        raise exception using errcode = '22023', message = 'invalid_primary_location';
      end if;

      provider_identity := nullif(btrim(p_primary_location->>'providerLocationId'), '');
      normalized_name := nullif(btrim(p_primary_location->>'name'), '');
      normalized_formatted_address := nullif(btrim(p_primary_location->>'formattedAddress'), '');
      normalized_address := nullif(btrim(p_primary_location->>'address'), '');
      normalized_city := nullif(btrim(p_primary_location->>'city'), '');
      normalized_region := nullif(btrim(p_primary_location->>'region'), '');
      normalized_postal_code := nullif(btrim(p_primary_location->>'postalCode'), '');
      normalized_country := nullif(btrim(p_primary_location->>'country'), '');
      normalized_country_code := lower(nullif(btrim(p_primary_location->>'countryCode'), ''));
      normalized_timezone := nullif(btrim(p_primary_location->>'timezone'), '');
      normalized_result_type := nullif(btrim(p_primary_location->>'resultType'), '');
      latitude := (p_primary_location->>'latitude')::numeric;
      longitude := (p_primary_location->>'longitude')::numeric;
      provider_confidence := (p_primary_location->>'confidence')::numeric;

      if provider_identity is null or length(provider_identity) > 500
        or normalized_name is null or length(normalized_name) > 200
        or normalized_formatted_address is null or length(normalized_formatted_address) > 1000
        or length(coalesce(normalized_address, '')) > 500
        or length(coalesce(normalized_city, '')) > 200
        or length(coalesce(normalized_region, '')) > 200
        or length(coalesce(normalized_postal_code, '')) > 40
        or length(coalesce(normalized_country, '')) > 200
        or (normalized_country_code is not null and normalized_country_code !~ '^[a-z]{2}$')
        or length(coalesce(normalized_timezone, '')) > 100
        or length(coalesce(normalized_result_type, '')) > 100
        or latitude not between -90 and 90
        or longitude not between -180 and 180
        or provider_confidence not between 0 and 1
      then
        raise exception using errcode = '22023', message = 'invalid_primary_location';
      end if;

      target_location_id := public.resolve_geoapify_location(p_primary_location);
    else
      raise exception using errcode = '22023', message = 'invalid_primary_location';
    end if;
  end if;

  select * into reviewed
  from public.review_wiki_item_with_photo_place_core(
    p_entry_id,
    p_expected_revision,
    p_title,
    p_body,
    p_item_kind,
    p_item_subtype,
    p_occurred_start,
    p_occurred_timezone,
    p_tag_names,
    p_mark_done,
    p_occurred_end,
    p_occurred_label,
    p_date_precision,
    p_photo_place,
    p_body_rich,
    false
  );
  if reviewed.entry_id is null then return; end if;

  delete from public.entry_places as link
  where link.entry_id = reviewed.entry_id
    and link.owner_id = review_owner_id
    and link.relationship = 'primary'
    and link.place_id is distinct from target_location_id;

  if target_location_id is not null then
    insert into public.entry_places (entry_id, place_id, owner_id, relationship)
    values (reviewed.entry_id, target_location_id, review_owner_id, 'primary')
    on conflict on constraint entry_places_pkey do nothing;
  end if;

  return query
  select reviewed.entry_id, reviewed.revision, reviewed.inbox_status;
end;
$function$;

create function public.save_first_time_with_occurrence(p_title text, p_body text, p_occurred_start timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_tag_names text[], p_entry_id uuid, p_expected_revision integer, p_occurred_end timestamp with time zone)
 RETURNS TABLE(entry_id uuid, revision integer, was_created boolean)
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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

  if not public.valid_tag_names(p_tag_names) then
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
      item_kind,
      item_subtype,
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
      'entry',
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
      and entries.item_kind = 'entry' and entries.item_subtype = 'first_time'
      and entries.revision = p_expected_revision
      and entries.deleted_at is null
    returning entries.id, entries.revision into saved_entry_id, saved_revision;

    if saved_entry_id is null then
      return;
    end if;
  end if;

  perform public.replace_entry_tags(saved_entry_id, p_tag_names);

  return query select saved_entry_id, saved_revision, created_entry;
end;
$function$;

CREATE OR REPLACE FUNCTION public.save_first_time_with_location(p_input jsonb, p_location jsonb)
 RETURNS TABLE(entry_id uuid, revision integer, was_created boolean)
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  saved record;
  selected_location_id uuid;
  first_time_owner_id uuid := auth.uid();
begin
  if first_time_owner_id is null then return; end if;
  if jsonb_typeof(p_input) is distinct from 'object' then
    raise exception using errcode = '22023', message = 'invalid_first_time_input';
  end if;

  select * into saved
  from public.save_first_time_with_occurrence(
    p_input->>'title',
    p_input->>'body',
    (p_input->>'occurredStart')::timestamptz,
    p_input->>'datePrecision',
    p_input->>'occurredLabel',
    p_input->>'occurredTimezone',
    array(select jsonb_array_elements_text(coalesce(p_input->'tagNames', '[]'::jsonb))),
    (p_input->>'id')::uuid,
    (p_input->>'revision')::integer,
    (p_input->>'occurredEnd')::timestamptz
  );
  if saved.entry_id is null then return; end if;

  selected_location_id := public.resolve_selected_location(p_location);
  delete from public.entry_places as link
  where link.entry_id = saved.entry_id
    and link.owner_id = first_time_owner_id
    and link.relationship = 'primary'
    and link.place_id is distinct from selected_location_id;
  if selected_location_id is not null then
    insert into public.entry_places(entry_id, place_id, owner_id, relationship)
    values (saved.entry_id, selected_location_id, first_time_owner_id, 'primary')
    on conflict on constraint entry_places_pkey do nothing;
  end if;

  return query select saved.entry_id, saved.revision, saved.was_created;
end;
$function$;

create function public.save_home_entry_with_occurrence(p_title text, p_body text, p_occurred_start timestamp with time zone, p_occurred_end timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_place_id uuid, p_place_name text, p_address text, p_city text, p_region text, p_country text, p_latitude numeric, p_longitude numeric, p_place_notes text, p_move_in_reason text, p_move_out_reason text, p_tag_names text[], p_entry_id uuid, p_expected_revision integer)
 RETURNS TABLE(entry_id uuid, revision integer, place_id uuid, was_created boolean)
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  home_owner_id uuid := auth.uid();
  saved_entry_id uuid;
  saved_revision integer;
  saved_place_id uuid;
  home_track_id uuid;
  normalized_title text := nullif(btrim(p_title), '');
  normalized_body text := btrim(coalesce(p_body, ''));
  normalized_label text := nullif(btrim(p_occurred_label), '');
  normalized_timezone text := nullif(btrim(p_occurred_timezone), '');
  normalized_place_name text := nullif(btrim(p_place_name), '');
  normalized_address text := nullif(btrim(p_address), '');
  normalized_city text := nullif(btrim(p_city), '');
  normalized_region text := nullif(btrim(p_region), '');
  normalized_country text := nullif(btrim(p_country), '');
  normalized_place_notes text := nullif(btrim(p_place_notes), '');
  normalized_move_in_reason text := nullif(btrim(p_move_in_reason), '');
  normalized_move_out_reason text := nullif(btrim(p_move_out_reason), '');
begin
  if home_owner_id is null then
    return;
  end if;

  if normalized_title is null or length(normalized_title) > 200
    or length(normalized_body) > 50000
  then
    raise exception using errcode = '22023', message = 'invalid_home_content';
  end if;

  if length(coalesce(normalized_place_name, '')) > 200
    or length(coalesce(normalized_address, '')) > 500
    or length(coalesce(normalized_city, '')) > 200
    or length(coalesce(normalized_region, '')) > 200
    or length(coalesce(normalized_country, '')) > 200
    or length(coalesce(normalized_place_notes, '')) > 10000
    or length(coalesce(normalized_move_in_reason, '')) > 10000
    or length(coalesce(normalized_move_out_reason, '')) > 10000
  then
    raise exception using errcode = '22023', message = 'invalid_home_details';
  end if;

  if (p_occurred_start is not null and not isfinite(p_occurred_start))
    or (p_occurred_end is not null and not isfinite(p_occurred_end))
    or (p_date_precision in ('exact','day','month','year','range') and p_occurred_start is null)
    or (p_date_precision='unknown' and (p_occurred_start is not null or p_occurred_end is not null))
    or (p_date_precision in ('age','approximate') and normalized_label is null)
    or (p_occurred_end is not null and p_occurred_start is null)
  then raise exception using errcode='22023',message='invalid_home_occurrence'; end if;
  if p_occurred_start is null then normalized_timezone := null;
  else
    if normalized_timezone is null or length(normalized_timezone)>100 then
      raise exception using errcode='22023',message='invalid_home_occurrence';
    end if;
    begin perform pg_catalog.timezone(normalized_timezone,p_occurred_start);
    exception when invalid_parameter_value then
      raise exception using errcode='22023',message='invalid_home_timezone';
    end;
  end if;

  if p_occurred_end is not null and p_occurred_end < p_occurred_start then
    raise exception using errcode = '22023', message = 'invalid_home_range';
  end if;

  if normalized_move_out_reason is not null and p_occurred_end is null then
    raise exception using errcode = '22023', message = 'home_move_out_requires_date';
  end if;

  if p_date_precision is null or p_date_precision not in (
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
    raise exception using errcode = '22023', message = 'home_label_too_long';
  end if;

  if not public.valid_tag_names(p_tag_names) then
    raise exception using errcode = '22023', message = 'invalid_tags';
  end if;

  if (p_latitude is null) <> (p_longitude is null)
    or p_latitude not between -90 and 90
    or p_longitude not between -180 and 180
  then
    raise exception using errcode = '22023', message = 'invalid_home_coordinates';
  end if;

  if p_entry_id is null and p_expected_revision is not null then
    raise exception using errcode = '22023', message = 'unexpected_revision';
  end if;

  if p_entry_id is not null
    and (p_expected_revision is null or p_expected_revision < 1)
  then
    raise exception using errcode = '22023', message = 'invalid_revision';
  end if;

  if p_place_id is not null and not exists (
    select 1
    from public.locations
    where locations.id = p_place_id
      and locations.owner_id = home_owner_id
  ) then
    return;
  end if;

  if p_entry_id is null then
    insert into public.entries (
      owner_id,
      title,
      body,
      item_kind,
      item_subtype,
      inbox_status,
      occurred_start,
      occurred_end,
      date_precision,
      occurred_label,
      occurred_timezone
    )
    values (
      home_owner_id,
      normalized_title,
      normalized_body,
      'entity',
      'home',
      'organized',
      p_occurred_start,
      p_occurred_end,
      p_date_precision,
      normalized_label,
      normalized_timezone
    )
    returning entries.id, entries.revision into saved_entry_id, saved_revision;
  else
    update public.entries
    set
      title = normalized_title,
      body = normalized_body,
      item_kind = 'entity',
      item_subtype = 'home',
      inbox_status = 'organized',
      occurred_start = p_occurred_start,
      occurred_end = p_occurred_end,
      date_precision = p_date_precision,
      occurred_label = normalized_label,
      occurred_timezone = normalized_timezone
    where entries.id = p_entry_id
      and entries.owner_id = home_owner_id
      and entries.revision = p_expected_revision
      and entries.item_kind = 'entity' and entries.item_subtype = 'home'
      and entries.deleted_at is null
      and exists (
        select 1
        from public.homes
        where homes.entry_id = entries.id
          and homes.owner_id = home_owner_id
      )
    returning entries.id, entries.revision into saved_entry_id, saved_revision;

    if saved_entry_id is null then
      return;
    end if;
  end if;

  if p_place_id is not null
    or normalized_address is not null
    or normalized_city is not null
    or normalized_region is not null
    or normalized_country is not null
    or p_latitude is not null
  then
    select public.resolve_home_location_copy_on_write(
      p_place_id,
      normalized_place_name,
      normalized_address,
      normalized_city,
      normalized_region,
      normalized_country,
      p_latitude,
      p_longitude,
      normalized_place_notes
    ) into saved_place_id;
  else
    saved_place_id := null;
  end if;

  if saved_place_id is null and (
    p_place_id is not null or normalized_address is not null
    or normalized_city is not null or normalized_region is not null
    or normalized_country is not null or p_latitude is not null
  ) then
    raise exception using errcode = '22023', message = 'invalid_home_place';
  end if;

  insert into public.homes (
    entry_id,
    owner_id,
    place_id,
    move_in_reason,
    move_out_reason
  )
  values (
    saved_entry_id,
    home_owner_id,
    saved_place_id,
    normalized_move_in_reason,
    normalized_move_out_reason
  )
  on conflict on constraint homes_pkey do update
  set
    place_id = excluded.place_id,
    move_in_reason = excluded.move_in_reason,
    move_out_reason = excluded.move_out_reason
  where (homes.place_id, homes.move_in_reason, homes.move_out_reason)
    is distinct from (excluded.place_id, excluded.move_in_reason, excluded.move_out_reason);

  delete from public.entry_places
  where entry_places.entry_id = saved_entry_id
    and entry_places.owner_id = home_owner_id
    and entry_places.relationship = 'home'
    and entry_places.place_id is distinct from saved_place_id;

  if saved_place_id is not null then
    insert into public.entry_places (
      entry_id,
      place_id,
      owner_id,
      relationship
    ) values (
      saved_entry_id,
      saved_place_id,
      home_owner_id,
      'home'
    ) on conflict on constraint entry_places_pkey do nothing;
  end if;

  select timeline_tracks.id
  into home_track_id
  from public.timeline_tracks
  where timeline_tracks.owner_id = home_owner_id
    and timeline_tracks.system_key = 'homes'
  order by timeline_tracks.sort_order, timeline_tracks.id
  limit 1;

  if home_track_id is null then
    select timeline_tracks.id
    into home_track_id
    from public.timeline_tracks
    where timeline_tracks.owner_id = home_owner_id
      and lower(btrim(timeline_tracks.name)) = 'homes'
      and timeline_tracks.system_key is null
    order by timeline_tracks.sort_order, timeline_tracks.id
    limit 1;

    if home_track_id is not null then
      update public.timeline_tracks
      set system_key = 'homes'
      where timeline_tracks.id = home_track_id
        and timeline_tracks.owner_id = home_owner_id
        and timeline_tracks.system_key is null;
    end if;
  end if;

  if home_track_id is null then
    insert into public.timeline_tracks (
      owner_id,
      name,
      system_key,
      sort_order
    )
    values (
      home_owner_id,
      'Homes',
      'homes',
      40
    )
    returning timeline_tracks.id into home_track_id;
  end if;

  delete from public.timeline_items
  where timeline_items.entry_id = saved_entry_id
    and timeline_items.owner_id = home_owner_id
    and timeline_items.track_id is distinct from home_track_id;

  insert into public.timeline_items (
    entry_id,
    track_id,
    owner_id,
    timeline_kind
  )
  values (
    saved_entry_id,
    home_track_id,
    home_owner_id,
    'stage'
  )
  on conflict on constraint timeline_items_pkey do update
  set timeline_kind = excluded.timeline_kind
  where timeline_items.timeline_kind is distinct from excluded.timeline_kind;

  perform public.replace_entry_tags(saved_entry_id, p_tag_names);

  return query
  select saved_entry_id, saved_revision, saved_place_id, p_entry_id is null;
end;
$function$;

create function public.save_home_entry(p_title text, p_body text, p_occurred_start timestamp with time zone, p_occurred_end timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_place_id uuid, p_place_name text, p_address text, p_city text, p_region text, p_country text, p_latitude numeric, p_longitude numeric, p_place_notes text, p_move_in_reason text, p_move_out_reason text, p_tag_names text[], p_entry_id uuid, p_expected_revision integer)
 RETURNS TABLE(entry_id uuid, revision integer, place_id uuid, was_created boolean)
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null then return; end if;
  if exists(select 1 from public.entries e where e.id=p_entry_id and e.owner_id=auth.uid() and e.deleted_at is null and (e.occurred_start is null or e.date_precision='exact')) then
    raise exception using errcode='22023',message='home_requires_current_editor';
  end if;
  if p_occurred_start is null then raise exception using errcode='22023',message='invalid_home_occurrence'; end if;
  return query select * from public.save_home_entry_with_occurrence(p_title,p_body,p_occurred_start,p_occurred_end,p_date_precision,p_occurred_label,p_occurred_timezone,p_place_id,p_place_name,p_address,p_city,p_region,p_country,p_latitude,p_longitude,p_place_notes,p_move_in_reason,p_move_out_reason,p_tag_names,p_entry_id,p_expected_revision);
end;
$function$;

CREATE OR REPLACE FUNCTION public.save_home_entry_with_geoapify(p_input jsonb, p_source jsonb, p_provider_location jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  location_id uuid;
  saved jsonb;
  tag_names text[];
begin
  if auth.uid() is null then return null; end if;
  if jsonb_typeof(p_input) is distinct from 'object' then
    raise exception using errcode = '22023', message = 'invalid_home_input';
  end if;

  select coalesce(array_agg(value), '{}'::text[]) into tag_names
  from jsonb_array_elements_text(p_input->'tagNames') as value;
  location_id := public.resolve_geoapify_location(p_provider_location);
  if location_id is null then
    raise exception using errcode = '22023', message = 'invalid_provider_location';
  end if;

  if p_source is null or p_source = 'null'::jsonb then
    select to_jsonb(result) into saved
    from public.save_home_entry_with_occurrence(
      p_input->>'title', p_input->>'body',
      (p_input->>'occurredStart')::timestamptz,
      (p_input->>'occurredEnd')::timestamptz,
      p_input->>'datePrecision', p_input->>'occurredLabel',
      p_input->>'occurredTimezone', location_id,
      p_input->>'placeName', p_input->>'address', p_input->>'city',
      p_input->>'region', p_input->>'country',
      (p_input->>'latitude')::numeric, (p_input->>'longitude')::numeric,
      p_input->>'placeNotes', p_input->>'moveInReason',
      p_input->>'moveOutReason', tag_names,
      (p_input->>'id')::uuid, (p_input->>'revision')::integer
    ) as result;
  else
    select to_jsonb(result) into saved
    from public.extract_capture_to_home(
      (p_source->>'id')::uuid, (p_source->>'revision')::integer,
      p_input->>'title', p_input->>'body',
      (p_input->>'occurredStart')::timestamptz,
      (p_input->>'occurredEnd')::timestamptz,
      p_input->>'datePrecision', p_input->>'occurredLabel',
      p_input->>'occurredTimezone', location_id,
      p_input->>'placeName', p_input->>'address', p_input->>'city',
      p_input->>'region', p_input->>'country',
      (p_input->>'latitude')::numeric, (p_input->>'longitude')::numeric,
      p_input->>'placeNotes', p_input->>'moveInReason',
      p_input->>'moveOutReason', tag_names
    ) as result;
  end if;

  if saved is null then
    raise exception using errcode = '40001', message = 'home_changed';
  end if;
  return saved;
end;
$function$;

create function public.extract_capture_to_home(p_capture_id uuid, p_capture_revision integer, p_title text, p_body text, p_occurred_start timestamp with time zone, p_occurred_end timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_place_id uuid, p_place_name text, p_address text, p_city text, p_region text, p_country text, p_latitude numeric, p_longitude numeric, p_place_notes text, p_move_in_reason text, p_move_out_reason text, p_tag_names text[])
 RETURNS TABLE(capture_id uuid, capture_revision integer, home_entry_id uuid, home_revision integer, place_id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  extraction_owner_id uuid := auth.uid();
  source public.entries;
  saved_home record;
  existing_home record;
  next_capture_revision integer;
begin
  if extraction_owner_id is null then
    return;
  end if;

  if p_capture_id is null
    or p_capture_revision is null
    or p_capture_revision < 1
  then
    raise exception using errcode = '22023', message = 'invalid_capture_home_extraction';
  end if;

  -- A response may be lost after the transaction commits. Return the existing
  -- derived Home on retry instead of ever creating a duplicate.
  select
    target.id as entry_id,
    target.revision,
    home.place_id,
    capture.revision as source_revision
  into existing_home
  from public.entries as capture
  join public.entry_links as provenance
    on provenance.source_entry_id = capture.id
    and provenance.owner_id = capture.owner_id
    and provenance.relationship = 'derived'
  join public.entries as target
    on target.id = provenance.target_entry_id
    and target.owner_id = provenance.owner_id
    and target.item_kind = 'entity'
    and target.item_subtype = 'home'
    and target.deleted_at is null
  join public.homes as home
    on home.entry_id = target.id
    and home.owner_id = target.owner_id
  where capture.id = p_capture_id
    and capture.owner_id = extraction_owner_id
    and capture.item_kind = 'entry'
    and capture.item_subtype = 'source_capture'
    and capture.inbox_status = 'organized'
    and capture.deleted_at is null
  order by provenance.created_at
  limit 1;

  if found then
    return query select
      p_capture_id,
      existing_home.source_revision,
      existing_home.entry_id,
      existing_home.revision,
      existing_home.place_id;
    return;
  end if;

  select *
  into source
  from public.entries as entry
  where entry.id = p_capture_id
    and entry.owner_id = extraction_owner_id
    and entry.revision = p_capture_revision
    and entry.item_kind = 'entry'
    and entry.inbox_status = 'unreviewed'
    and entry.inbox_status = 'unreviewed'
    and entry.deleted_at is null
  for update;

  if not found then
    return;
  end if;

  select *
  into saved_home
  from public.save_home_entry_with_occurrence(
    p_title,
    p_body,
    p_occurred_start,
    p_occurred_end,
    p_date_precision,
    p_occurred_label,
    p_occurred_timezone,
    p_place_id,
    p_place_name,
    p_address,
    p_city,
    p_region,
    p_country,
    p_latitude,
    p_longitude,
    p_place_notes,
    p_move_in_reason,
    p_move_out_reason,
    p_tag_names,
    null,
    null
  );

  if saved_home.entry_id is null then
    return;
  end if;

  update public.entries as entry
  set
    item_subtype = 'source_capture',
    inbox_status = 'organized'
  where entry.id = source.id
    and entry.owner_id = extraction_owner_id
    and entry.revision = p_capture_revision
  returning entry.revision into next_capture_revision;

  if next_capture_revision is null then
    raise exception using errcode = '40001', message = 'capture_changed';
  end if;

  insert into public.entry_links (
    source_entry_id,
    target_entry_id,
    owner_id,
    relationship
  )
  values
    (source.id, saved_home.entry_id, extraction_owner_id, 'derived'),
    (saved_home.entry_id, source.id, extraction_owner_id, 'derived_from')
  on conflict do nothing;

  return query select
    source.id,
    next_capture_revision,
    saved_home.entry_id,
    saved_home.revision,
    saved_home.place_id;
end;
$function$;

create function public.save_vehicle_entry_with_occurrence(p_title text, p_body text, p_occurred_start timestamp with time zone, p_occurred_end timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_make text, p_model text, p_model_year integer, p_color text, p_tag_names text[], p_entry_id uuid, p_expected_revision integer)
 RETURNS TABLE(entry_id uuid, revision integer, was_created boolean)
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  vehicle_owner_id uuid := auth.uid();
  saved_entry_id uuid;
  saved_revision integer;
  vehicle_track_id uuid;
  normalized_title text := nullif(btrim(p_title), '');
  normalized_body text := btrim(coalesce(p_body, ''));
  normalized_label text := nullif(btrim(p_occurred_label), '');
  normalized_timezone text := nullif(btrim(p_occurred_timezone), '');
  normalized_make text := nullif(btrim(p_make), '');
  normalized_model text := nullif(btrim(p_model), '');
  normalized_color text := nullif(btrim(p_color), '');
begin
  if vehicle_owner_id is null then
    return;
  end if;

  if normalized_title is null or length(normalized_title) > 200
    or length(normalized_body) > 50000
  then
    raise exception using errcode = '22023', message = 'invalid_vehicle_content';
  end if;

  if length(coalesce(normalized_make, '')) > 120
    or length(coalesce(normalized_model, '')) > 120
    or length(coalesce(normalized_color, '')) > 80
    or (p_model_year is not null and p_model_year not between 1886 and 2200)
  then
    raise exception using errcode = '22023', message = 'invalid_vehicle_details';
  end if;

  if (p_occurred_start is not null and not isfinite(p_occurred_start))
    or (p_occurred_end is not null and not isfinite(p_occurred_end))
    or (p_date_precision in ('exact','day','month','year','range') and p_occurred_start is null)
    or (p_date_precision='unknown' and (p_occurred_start is not null or p_occurred_end is not null))
    or (p_date_precision in ('age','approximate') and normalized_label is null)
    or (p_occurred_end is not null and p_occurred_start is null)
  then raise exception using errcode='22023',message='invalid_vehicle_occurrence'; end if;
  if p_occurred_start is null then normalized_timezone := null;
  else
    if normalized_timezone is null or length(normalized_timezone)>100 then
      raise exception using errcode='22023',message='invalid_vehicle_occurrence';
    end if;
    begin perform pg_catalog.timezone(normalized_timezone,p_occurred_start);
    exception when invalid_parameter_value then
      raise exception using errcode='22023',message='invalid_vehicle_timezone';
    end;
  end if;

  if p_occurred_end is not null and p_occurred_end < p_occurred_start then
    raise exception using errcode = '22023', message = 'invalid_vehicle_range';
  end if;

  if p_date_precision is null or p_date_precision not in (
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
    raise exception using errcode = '22023', message = 'vehicle_label_too_long';
  end if;

  if not public.valid_tag_names(p_tag_names) then
    raise exception using errcode = '22023', message = 'invalid_tags';
  end if;

  if p_entry_id is null and p_expected_revision is not null then
    raise exception using errcode = '22023', message = 'unexpected_revision';
  end if;

  if p_entry_id is not null
    and (p_expected_revision is null or p_expected_revision < 1)
  then
    raise exception using errcode = '22023', message = 'invalid_revision';
  end if;

  if p_entry_id is null then
    insert into public.entries (
      owner_id,
      title,
      body,
      item_kind,
      item_subtype,
      inbox_status,
      occurred_start,
      occurred_end,
      date_precision,
      occurred_label,
      occurred_timezone
    )
    values (
      vehicle_owner_id,
      normalized_title,
      normalized_body,
      'entity',
      'vehicle',
      'organized',
      p_occurred_start,
      p_occurred_end,
      p_date_precision,
      normalized_label,
      normalized_timezone
    )
    returning entries.id, entries.revision into saved_entry_id, saved_revision;
  else
    update public.entries
    set
      title = normalized_title,
      body = normalized_body,
      item_kind = 'entity',
      item_subtype = 'vehicle',
      inbox_status = 'organized',
      occurred_start = p_occurred_start,
      occurred_end = p_occurred_end,
      date_precision = p_date_precision,
      occurred_label = normalized_label,
      occurred_timezone = normalized_timezone
    where entries.id = p_entry_id
      and entries.owner_id = vehicle_owner_id
      and entries.revision = p_expected_revision
      and entries.item_kind = 'entity' and entries.item_subtype = 'vehicle'
      and entries.deleted_at is null
      and exists (
        select 1
        from public.vehicles
        where vehicles.entry_id = entries.id
          and vehicles.owner_id = vehicle_owner_id
      )
    returning entries.id, entries.revision into saved_entry_id, saved_revision;

    if saved_entry_id is null then
      return;
    end if;
  end if;

  insert into public.vehicles (
    entry_id,
    owner_id,
    make,
    model,
    model_year,
    color
  )
  values (
    saved_entry_id,
    vehicle_owner_id,
    normalized_make,
    normalized_model,
    p_model_year,
    normalized_color
  )
  on conflict on constraint vehicles_pkey do update
  set
    make = excluded.make,
    model = excluded.model,
    model_year = excluded.model_year,
    color = excluded.color
  where (vehicles.make, vehicles.model, vehicles.model_year, vehicles.color)
    is distinct from (excluded.make, excluded.model, excluded.model_year, excluded.color);

  select timeline_tracks.id
  into vehicle_track_id
  from public.timeline_tracks
  where timeline_tracks.owner_id = vehicle_owner_id
    and timeline_tracks.system_key = 'vehicles'
  order by timeline_tracks.sort_order, timeline_tracks.id
  limit 1;

  if vehicle_track_id is null then
    select timeline_tracks.id
    into vehicle_track_id
    from public.timeline_tracks
    where timeline_tracks.owner_id = vehicle_owner_id
      and lower(btrim(timeline_tracks.name)) = 'vehicles'
      and timeline_tracks.system_key is null
    order by timeline_tracks.sort_order, timeline_tracks.id
    limit 1;

    if vehicle_track_id is not null then
      update public.timeline_tracks
      set system_key = 'vehicles'
      where timeline_tracks.id = vehicle_track_id
        and timeline_tracks.owner_id = vehicle_owner_id
        and timeline_tracks.system_key is null;
    end if;
  end if;

  if vehicle_track_id is null then
    insert into public.timeline_tracks (
      owner_id,
      name,
      system_key,
      sort_order
    )
    values (
      vehicle_owner_id,
      'Vehicles',
      'vehicles',
      50
    )
    returning timeline_tracks.id into vehicle_track_id;
  end if;

  delete from public.timeline_items
  where timeline_items.entry_id = saved_entry_id
    and timeline_items.owner_id = vehicle_owner_id
    and timeline_items.track_id is distinct from vehicle_track_id;

  insert into public.timeline_items (
    entry_id,
    track_id,
    owner_id,
    timeline_kind
  )
  values (
    saved_entry_id,
    vehicle_track_id,
    vehicle_owner_id,
    'stage'
  )
  on conflict on constraint timeline_items_pkey do update
  set timeline_kind = excluded.timeline_kind
  where timeline_items.timeline_kind is distinct from excluded.timeline_kind;

  perform public.replace_entry_tags(saved_entry_id, p_tag_names);

  return query
  select saved_entry_id, saved_revision, p_entry_id is null;
end;
$function$;

create function public.save_vehicle_entry(p_title text, p_body text, p_occurred_start timestamp with time zone, p_occurred_end timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_make text, p_model text, p_model_year integer, p_color text, p_tag_names text[], p_entry_id uuid, p_expected_revision integer)
 RETURNS TABLE(entry_id uuid, revision integer, was_created boolean)
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null then return; end if;
  if exists(select 1 from public.entries e where e.id=p_entry_id and e.owner_id=auth.uid() and e.deleted_at is null and (e.occurred_start is null or e.date_precision='exact')) then
    raise exception using errcode='22023',message='vehicle_requires_current_editor';
  end if;
  if p_occurred_start is null then raise exception using errcode='22023',message='invalid_vehicle_occurrence'; end if;
  return query select * from public.save_vehicle_entry_with_occurrence(p_title,p_body,p_occurred_start,p_occurred_end,p_date_precision,p_occurred_label,p_occurred_timezone,p_make,p_model,p_model_year,p_color,p_tag_names,p_entry_id,p_expected_revision);
end;
$function$;

CREATE OR REPLACE FUNCTION public.save_vehicle_with_location(p_input jsonb, p_source jsonb, p_location jsonb)
 RETURNS TABLE(entry_id uuid, revision integer, was_created boolean)
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  saved record;
  saved_entry_id uuid;
  saved_revision integer;
  created_vehicle boolean;
  selected_location_id uuid;
  vehicle_owner_id uuid := auth.uid();
  tag_names text[];
begin
  if vehicle_owner_id is null then return; end if;
  if jsonb_typeof(p_input) is distinct from 'object' then
    raise exception using errcode = '22023', message = 'invalid_vehicle_input';
  end if;

  tag_names := array(select jsonb_array_elements_text(coalesce(p_input->'tagNames', '[]'::jsonb)));

  if p_source is null or p_source = 'null'::jsonb then
    select * into saved
    from public.save_vehicle_entry_with_occurrence(
      p_input->>'title',
      p_input->>'body',
      (p_input->>'occurredStart')::timestamptz,
      (p_input->>'occurredEnd')::timestamptz,
      p_input->>'datePrecision',
      p_input->>'occurredLabel',
      p_input->>'occurredTimezone',
      p_input->>'make',
      p_input->>'model',
      (p_input->>'modelYear')::integer,
      p_input->>'color',
      tag_names,
      (p_input->>'id')::uuid,
      (p_input->>'revision')::integer
    );
    if saved.entry_id is null then return; end if;
    saved_entry_id := saved.entry_id;
    saved_revision := saved.revision;
    created_vehicle := saved.was_created;
  else
    if jsonb_typeof(p_source) is distinct from 'object'
      or p_input->>'id' is not null
    then
      raise exception using errcode = '22023', message = 'invalid_vehicle_source';
    end if;
    select * into saved
    from public.extract_capture_to_vehicle(
      (p_source->>'id')::uuid,
      (p_source->>'revision')::integer,
      p_input->>'title',
      p_input->>'body',
      (p_input->>'occurredStart')::timestamptz,
      (p_input->>'occurredEnd')::timestamptz,
      p_input->>'datePrecision',
      p_input->>'occurredLabel',
      p_input->>'occurredTimezone',
      p_input->>'make',
      p_input->>'model',
      (p_input->>'modelYear')::integer,
      p_input->>'color',
      tag_names
    );
    if saved.vehicle_entry_id is null then return; end if;
    saved_entry_id := saved.vehicle_entry_id;
    saved_revision := saved.vehicle_revision;
    created_vehicle := true;
  end if;

  selected_location_id := public.resolve_selected_location(p_location);
  delete from public.entry_places as link
  where link.entry_id = saved_entry_id
    and link.owner_id = vehicle_owner_id
    and link.relationship = 'primary'
    and link.place_id is distinct from selected_location_id;
  if selected_location_id is not null then
    insert into public.entry_places(entry_id, place_id, owner_id, relationship)
    values (saved_entry_id, selected_location_id, vehicle_owner_id, 'primary')
    on conflict on constraint entry_places_pkey do nothing;
  end if;

  return query select saved_entry_id, saved_revision, created_vehicle;
end;
$function$;

create function public.extract_capture_to_vehicle(p_capture_id uuid, p_capture_revision integer, p_title text, p_body text, p_occurred_start timestamp with time zone, p_occurred_end timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_make text, p_model text, p_model_year integer, p_color text, p_tag_names text[])
 RETURNS TABLE(capture_id uuid, capture_revision integer, vehicle_entry_id uuid, vehicle_revision integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  extraction_owner_id uuid := auth.uid();
  source public.entries;
  saved_vehicle record;
  existing_vehicle record;
  next_capture_revision integer;
begin
  if extraction_owner_id is null then
    return;
  end if;

  if p_capture_id is null
    or p_capture_revision is null
    or p_capture_revision < 1
  then
    raise exception using errcode = '22023', message = 'invalid_capture_vehicle_extraction';
  end if;

  select
    target.id as entry_id,
    target.revision,
    capture.revision as source_revision
  into existing_vehicle
  from public.entries as capture
  join public.entry_links as provenance
    on provenance.source_entry_id = capture.id
    and provenance.owner_id = capture.owner_id
    and provenance.relationship = 'derived'
  join public.entries as target
    on target.id = provenance.target_entry_id
    and target.owner_id = provenance.owner_id
    and target.item_kind = 'entity'
    and target.item_subtype = 'vehicle'
    and target.deleted_at is null
  join public.vehicles as vehicle
    on vehicle.entry_id = target.id
    and vehicle.owner_id = target.owner_id
  where capture.id = p_capture_id
    and capture.owner_id = extraction_owner_id
    and capture.item_kind = 'entry'
    and capture.item_subtype = 'source_capture'
    and capture.inbox_status = 'organized'
    and capture.deleted_at is null
  order by provenance.created_at
  limit 1;

  if found then
    return query select
      p_capture_id,
      existing_vehicle.source_revision,
      existing_vehicle.entry_id,
      existing_vehicle.revision;
    return;
  end if;

  select *
  into source
  from public.entries as entry
  where entry.id = p_capture_id
    and entry.owner_id = extraction_owner_id
    and entry.revision = p_capture_revision
    and entry.item_kind = 'entry'
    and entry.inbox_status = 'unreviewed'
    and entry.inbox_status = 'unreviewed'
    and entry.deleted_at is null
  for update;

  if not found then
    return;
  end if;

  select *
  into saved_vehicle
  from public.save_vehicle_entry_with_occurrence(
    p_title,
    p_body,
    p_occurred_start,
    p_occurred_end,
    p_date_precision,
    p_occurred_label,
    p_occurred_timezone,
    p_make,
    p_model,
    p_model_year,
    p_color,
    p_tag_names,
    null,
    null
  );

  if saved_vehicle.entry_id is null then
    return;
  end if;

  update public.entries as entry
  set
    item_subtype = 'source_capture',
    inbox_status = 'organized'
  where entry.id = source.id
    and entry.owner_id = extraction_owner_id
    and entry.revision = p_capture_revision
  returning entry.revision into next_capture_revision;

  if next_capture_revision is null then
    raise exception using errcode = '40001', message = 'capture_changed';
  end if;

  insert into public.entry_links (
    source_entry_id,
    target_entry_id,
    owner_id,
    relationship
  )
  values
    (source.id, saved_vehicle.entry_id, extraction_owner_id, 'derived'),
    (saved_vehicle.entry_id, source.id, extraction_owner_id, 'derived_from')
  on conflict do nothing;

  return query select
    source.id,
    next_capture_revision,
    saved_vehicle.entry_id,
    saved_vehicle.revision;
end;
$function$;

create function public.save_goal_entry(p_title text, p_body text, p_horizon text, p_status text, p_target_date date, p_tag_names text[], p_related_entry_ids uuid[], p_entry_id uuid, p_expected_revision integer)
 RETURNS TABLE(entry_id uuid, revision integer, was_created boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  goal_owner_id uuid := auth.uid();
  saved_entry_id uuid;
  saved_revision integer;
  normalized_title text := nullif(btrim(p_title), '');
  normalized_body text := btrim(coalesce(p_body, ''));
begin
  if goal_owner_id is null then
    return;
  end if;
  if normalized_title is null or length(normalized_title) > 200
    or length(normalized_body) > 50000
  then
    raise exception using errcode = '22023', message = 'invalid_goal_content';
  end if;
  if p_horizon not in ('short_term', 'long_term', 'someday') then
    raise exception using errcode = '22023', message = 'invalid_goal_horizon';
  end if;
  if p_status not in ('considering', 'active', 'paused', 'achieved', 'let_go') then
    raise exception using errcode = '22023', message = 'invalid_goal_status';
  end if;
  if not public.valid_tag_names(p_tag_names) then
    raise exception using errcode = '22023', message = 'invalid_tags';
  end if;
  if cardinality(coalesce(p_related_entry_ids, '{}'::uuid[])) > 100
    or exists (
      select 1
      from unnest(coalesce(p_related_entry_ids, '{}'::uuid[])) as related_entry_id
      where related_entry_id is null
    )
  then
    raise exception using errcode = '22023', message = 'invalid_related_entries';
  end if;
  if p_entry_id is null and p_expected_revision is not null then
    raise exception using errcode = '22023', message = 'unexpected_revision';
  end if;
  if p_entry_id is not null and (p_expected_revision is null or p_expected_revision < 1) then
    raise exception using errcode = '22023', message = 'invalid_revision';
  end if;

  if p_entry_id is null then
    insert into public.entries (
      owner_id,
      title,
      body,
      item_kind,
      item_subtype,
      inbox_status,
      date_precision
    )
    values (
      goal_owner_id,
      normalized_title,
      normalized_body,
      'goal',
      'goal',
      'organized',
      'unknown'
    )
    returning entries.id, entries.revision into saved_entry_id, saved_revision;
  else
    update public.entries
    set
      title = normalized_title,
      body = normalized_body,
      item_kind = 'goal',
      item_subtype = 'goal',
      inbox_status = 'organized'
    where entries.id = p_entry_id
      and entries.owner_id = goal_owner_id
      and entries.revision = p_expected_revision
      and entries.item_kind = 'goal'
      and entries.deleted_at is null
      and exists (
        select 1
        from public.goals
        where goals.entry_id = entries.id
          and goals.owner_id = goal_owner_id
      )
    returning entries.id, entries.revision into saved_entry_id, saved_revision;

    if saved_entry_id is null then
      return;
    end if;
  end if;

  if exists (
    select 1
    from unnest(coalesce(p_related_entry_ids, '{}'::uuid[])) as related_entry_id
    where related_entry_id = saved_entry_id
      or not exists (
        select 1
        from public.entries as related
        where related.id = related_entry_id
          and related.owner_id = goal_owner_id
          and related.deleted_at is null
      )
  ) then
    raise exception using errcode = '22023', message = 'invalid_related_entries';
  end if;

  insert into public.goals (entry_id, owner_id, horizon, status, target_date)
  values (saved_entry_id, goal_owner_id, p_horizon, p_status, p_target_date)
  on conflict on constraint goals_pkey do update
  set
    horizon = excluded.horizon,
    status = excluded.status,
    target_date = excluded.target_date
  where (goals.horizon, goals.status, goals.target_date)
    is distinct from (excluded.horizon, excluded.status, excluded.target_date);

  perform public.replace_entry_tags(saved_entry_id, p_tag_names);

  delete from public.entry_links
  where entry_links.source_entry_id = saved_entry_id
    and entry_links.owner_id = goal_owner_id
    and entry_links.relationship = 'related'
    and not (entry_links.target_entry_id = any(coalesce(p_related_entry_ids, '{}'::uuid[])))
    and exists (
      select 1 from public.entries target
      where target.id = entry_links.target_entry_id
        and target.owner_id = entry_links.owner_id
        and target.deleted_at is null
    );

  insert into public.entry_links (source_entry_id, target_entry_id, owner_id, relationship)
  select saved_entry_id, related_entry_id, goal_owner_id, 'related'
  from (
    select distinct related_entry_id
    from unnest(coalesce(p_related_entry_ids, '{}'::uuid[])) as related_entry_id
  ) as related_entries
  on conflict do nothing;

  return query select saved_entry_id, saved_revision, p_entry_id is null;
end;
$function$;

create function public.extract_capture_to_goal(p_capture_id uuid, p_capture_revision integer, p_title text, p_body text, p_horizon text, p_status text, p_target_date date, p_tag_names text[], p_related_entry_ids uuid[])
 RETURNS TABLE(capture_id uuid, capture_revision integer, goal_entry_id uuid, goal_revision integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  extraction_owner_id uuid := auth.uid();
  source public.entries;
  saved_goal record;
  existing_goal record;
  next_capture_revision integer;
begin
  if extraction_owner_id is null then
    return;
  end if;

  if p_capture_id is null
    or p_capture_revision is null
    or p_capture_revision < 1
  then
    raise exception using errcode = '22023', message = 'invalid_capture_goal_extraction';
  end if;

  select
    target.id as entry_id,
    target.revision,
    capture.revision as source_revision
  into existing_goal
  from public.entries as capture
  join public.entry_links as provenance
    on provenance.source_entry_id = capture.id
    and provenance.owner_id = capture.owner_id
    and provenance.relationship = 'derived'
  join public.entries as target
    on target.id = provenance.target_entry_id
    and target.owner_id = provenance.owner_id
    and target.item_kind = 'goal'
    and target.item_subtype = 'goal'
    and target.deleted_at is null
  join public.goals as goal
    on goal.entry_id = target.id
    and goal.owner_id = target.owner_id
  where capture.id = p_capture_id
    and capture.owner_id = extraction_owner_id
    and capture.item_kind = 'entry'
    and capture.item_subtype = 'source_capture'
    and capture.inbox_status = 'organized'
    and capture.deleted_at is null
  order by provenance.created_at
  limit 1;

  if found then
    return query select
      p_capture_id,
      existing_goal.source_revision,
      existing_goal.entry_id,
      existing_goal.revision;
    return;
  end if;

  select *
  into source
  from public.entries as entry
  where entry.id = p_capture_id
    and entry.owner_id = extraction_owner_id
    and entry.revision = p_capture_revision
    and entry.item_kind = 'entry'
    and entry.inbox_status = 'unreviewed'
    and entry.inbox_status = 'unreviewed'
    and entry.deleted_at is null
  for update;

  if not found then
    return;
  end if;

  select *
  into saved_goal
  from public.save_goal_entry(
    p_title,
    p_body,
    p_horizon,
    p_status,
    p_target_date,
    p_tag_names,
    p_related_entry_ids,
    null,
    null
  );

  if saved_goal.entry_id is null then
    return;
  end if;

  update public.entries as entry
  set
    item_subtype = 'source_capture',
    inbox_status = 'organized'
  where entry.id = source.id
    and entry.owner_id = extraction_owner_id
    and entry.revision = p_capture_revision
  returning entry.revision into next_capture_revision;

  if next_capture_revision is null then
    raise exception using errcode = '40001', message = 'capture_changed';
  end if;

  insert into public.entry_links (
    source_entry_id,
    target_entry_id,
    owner_id,
    relationship
  )
  values
    (source.id, saved_goal.entry_id, extraction_owner_id, 'derived'),
    (saved_goal.entry_id, source.id, extraction_owner_id, 'derived_from')
  on conflict do nothing;

  return query select
    source.id,
    next_capture_revision,
    saved_goal.entry_id,
    saved_goal.revision;
end;
$function$;

CREATE OR REPLACE FUNCTION public.achieve_goal_with_occurrence(p_goal_entry_id uuid, p_expected_revision integer, p_occurred_start timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_occurred_end timestamp with time zone)
 RETURNS TABLE(goal_entry_id uuid, goal_revision integer, first_time_entry_id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  goal_owner_id uuid := auth.uid();
  achieved_goal_title text;
  achieved_goal_revision integer;
  new_first_time_id uuid;
  normalized_label text := nullif(btrim(p_occurred_label), '');
  normalized_timezone text := nullif(btrim(p_occurred_timezone), '');
  reconciled_revision integer;
begin
  if goal_owner_id is null or p_goal_entry_id is null then
    return;
  end if;
  if p_expected_revision is null or p_expected_revision < 1 then
    raise exception using errcode = '22023', message = 'invalid_goal_achievement';
  end if;

  perform 1 from public.entries
  where entries.id = p_goal_entry_id
    and entries.owner_id = goal_owner_id
    and entries.deleted_at is null
  for update;
  reconciled_revision := public.entry_writing_revision(p_goal_entry_id, p_expected_revision);

  update public.entries
  set inbox_status = 'organized'
  where entries.id = p_goal_entry_id
    and entries.owner_id = goal_owner_id
    and entries.revision = reconciled_revision
    and entries.item_kind = 'goal'
    and entries.deleted_at is null
    and exists (
      select 1
      from public.goals
      where goals.entry_id = entries.id
        and goals.owner_id = goal_owner_id
        and goals.status <> 'achieved'
    )
  returning entries.title, entries.revision
  into achieved_goal_title, achieved_goal_revision;

  if achieved_goal_title is null then
    return;
  end if;

  update public.goals
  set status = 'achieved'
  where goals.entry_id = p_goal_entry_id
    and goals.owner_id = goal_owner_id;

  select entry_id into new_first_time_id from public.save_first_time_with_occurrence(
    achieved_goal_title, '', p_occurred_start, p_date_precision, normalized_label,
    case when p_occurred_start is null then null else normalized_timezone end,
    '{}', null, null, p_occurred_end
  );

  insert into public.entry_links (source_entry_id, target_entry_id, owner_id, relationship)
  values (p_goal_entry_id, new_first_time_id, goal_owner_id, 'achievement');

  return query
  select p_goal_entry_id, achieved_goal_revision, new_first_time_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.advance_organization_revision()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'UPDATE' then new.revision := old.revision + 1; end if;
  return new;
end;
$function$;

create function public.archive_wiki_search_evidence(p_queries text[] DEFAULT '{}'::text[], p_item_classifications text[] DEFAULT '{}'::text[], p_tag_names text[] DEFAULT '{}'::text[], p_date_from date DEFAULT NULL::date, p_date_to date DEFAULT NULL::date, p_before_latest_home boolean DEFAULT false, p_order text DEFAULT 'relevance'::text, p_as_of date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  evidence_owner_id uuid := auth.uid();
  normalized_queries text[];
  selected_ids uuid[] := '{}'::uuid[];
  candidate_count integer := 0;
  query_truncated boolean := false;
  latest_home_entry public.entries;
  latest_home_facts public.homes;
  latest_home_reference jsonb;
  reference_date date;
  effective_date_to date := p_date_to;
  reference_window_applied boolean := false;
  entry_evidence jsonb := '[]'::jsonb;
  people_evidence jsonb := '[]'::jsonb;
begin
  if evidence_owner_id is null then
    return null;
  end if;

  if p_order is null or p_order not in ('relevance', 'oldest', 'newest')
    or p_as_of is null or not isfinite(p_as_of)
    or cardinality(coalesce(p_queries, '{}'::text[])) > 6
    or exists (
      select 1
      from unnest(coalesce(p_queries, '{}'::text[])) as query
      where query is null or length(btrim(query)) > 200
    )
    or (p_date_from is not null and not isfinite(p_date_from))
    or (p_date_to is not null and not isfinite(p_date_to))
    or (p_date_from is not null and p_date_to is not null and p_date_from > p_date_to)
    or cardinality(coalesce(p_item_classifications, '{}'::text[])) > 20
    or not public.valid_tag_names(p_tag_names)
  then
    raise exception using errcode = '22023', message = 'invalid_evidence_request';
  end if;

  normalized_queries := array(
    select btrim(query)
    from unnest(coalesce(p_queries, '{}'::text[])) as query
  );
  if cardinality(normalized_queries) = 0 then
    normalized_queries := array['']::text[];
  end if;

  if p_before_latest_home then
    select item.*
    into latest_home_entry
    from public.entries as item
    join public.homes as home
      on home.entry_id = item.id and home.owner_id = item.owner_id
    where item.owner_id = evidence_owner_id
      and item.deleted_at is null
      and item.item_kind = 'entity'
      and item.item_subtype = 'home'
      and item.occurred_start is not null
      and public.entry_local_timestamp(item.occurred_start, item.occurred_timezone)::date <= p_as_of
    order by
      public.entry_local_timestamp(item.occurred_start, item.occurred_timezone)::date desc,
      item.id
    limit 1;

    if latest_home_entry.id is not null then
      select home.*
      into latest_home_facts
      from public.homes as home
      where home.entry_id = latest_home_entry.id
        and home.owner_id = evidence_owner_id;

      latest_home_reference := jsonb_build_object(
        'id', latest_home_entry.id,
        'title', latest_home_entry.title,
        'body', latest_home_entry.body,
        'item_kind', latest_home_entry.item_kind,
        'item_subtype', latest_home_entry.item_subtype,
        'date_precision', latest_home_entry.date_precision,
        'occurred_start', latest_home_entry.occurred_start,
        'occurred_end', latest_home_entry.occurred_end,
        'occurred_label', latest_home_entry.occurred_label,
        'occurred_timezone', latest_home_entry.occurred_timezone,
        'facts', jsonb_build_object('home', to_jsonb(latest_home_facts))
      );
    end if;

    if latest_home_entry.id is not null
      and latest_home_entry.date_precision in ('exact', 'day')
    then
      reference_date := public.entry_local_timestamp(
        latest_home_entry.occurred_start,
        latest_home_entry.occurred_timezone
      )::date;
      effective_date_to := least(coalesce(p_date_to, p_as_of), reference_date - 1);
      reference_window_applied := true;
    end if;
  end if;

  if p_date_from is null or effective_date_to is null or p_date_from <= effective_date_to then
    with hits as (
      select
        result.entry_id,
        max(result.match_rank) as match_rank,
        max(result.occurred_start) as occurred_start,
        max(result.updated_at) as updated_at,
        bool_or(result.total_count > 100) as query_truncated
      from unnest(normalized_queries) as query
      cross join lateral public.search_wiki_items(
        query,
        case
          when cardinality(coalesce(p_item_classifications, '{}'::text[])) = 0 and query = ''
            then array['entry', 'entity', 'goal']::text[]
          else p_item_classifications
        end,
        p_tag_names,
        p_date_from,
        effective_date_to,
        100,
        0,
        p_order
      ) as result
      group by result.entry_id
    ),
    selected as (
      select *
      from hits
      order by
        case when p_order = 'relevance' then hits.match_rank end desc nulls last,
        case when p_order = 'oldest' then hits.occurred_start end asc nulls last,
        case when p_order <> 'oldest' then coalesce(hits.occurred_start, hits.updated_at) end desc nulls last,
        hits.entry_id
      limit 36
    )
    select
      coalesce(array_agg(selected.entry_id order by
        case when p_order = 'relevance' then selected.match_rank end desc nulls last,
        case when p_order = 'oldest' then selected.occurred_start end asc nulls last,
        case when p_order <> 'oldest' then coalesce(selected.occurred_start, selected.updated_at) end desc nulls last,
        selected.entry_id
      ), '{}'::uuid[]),
      (select count(*)::integer from hits),
      coalesce((select bool_or(hits.query_truncated) from hits), false)
    into selected_ids, candidate_count, query_truncated
    from selected;
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', item.id,
      'title', item.title,
      'body', item.body,
      'item_kind', item.item_kind,
      'item_subtype', item.item_subtype,
      'inbox_status', item.inbox_status,
      'date_precision', item.date_precision,
      'occurred_start', item.occurred_start,
      'occurred_end', item.occurred_end,
      'occurred_label', item.occurred_label,
      'occurred_timezone', item.occurred_timezone,
      'tags', coalesce(tag_context.names, '[]'::jsonb),
      'facts', jsonb_strip_nulls(jsonb_build_object(
        'home', (select to_jsonb(home) from public.homes as home where home.entry_id = item.id),
        'vehicle', (select to_jsonb(vehicle) from public.vehicles as vehicle where vehicle.entry_id = item.id),
        'goal', (select to_jsonb(goal) from public.goals as goal where goal.entry_id = item.id),
        'person', (select to_jsonb(person) from public.people as person where person.id = item.id)
      )),
      'record_source', case
        when item.item_kind = 'entity' and item.item_subtype = 'person' then 'person'
        else 'entry'
      end,
      'record_id', item.id
    ) order by selected.ordinality
  ), '[]'::jsonb)
  into entry_evidence
  from unnest(selected_ids) with ordinality as selected(entry_id, ordinality)
  join public.entries as item
    on item.id = selected.entry_id and item.owner_id = evidence_owner_id
  left join lateral (
    select jsonb_agg(tag.name order by lower(tag.name), tag.id) as names
    from public.entry_tags as membership
    join public.tags as tag
      on tag.id = membership.tag_id and tag.owner_id = membership.owner_id
    where membership.entry_id = item.id and membership.owner_id = evidence_owner_id
  ) as tag_context on true;

  if cardinality(coalesce(p_tag_names, '{}'::text[])) = 0
    and p_date_from is null
    and p_date_to is null
    and not p_before_latest_home
  then
    if cardinality(coalesce(p_item_classifications, '{}'::text[])) = 0
      or p_item_classifications && array['entity', 'person']::text[]
    then
      select coalesce(jsonb_agg(to_jsonb(person) order by lower(person.name), person.id), '[]'::jsonb)
      into people_evidence
      from public.people as person
      where person.owner_id = evidence_owner_id
        and person.deleted_at is null
        and exists (
          select 1
          from unnest(normalized_queries) as query
          where query <> ''
            and strpos(lower(concat_ws(' ', person.name, person.relationship_label, person.notes)), lower(query)) > 0
        );
    end if;

  end if;

  return jsonb_build_object(
    'entries', entry_evidence,
    'people', people_evidence,
    'candidate_count', candidate_count,
    'query_truncated', query_truncated,
    'query_limit', 100,
    'source_limit', 36,
    'queries', normalized_queries,
    'effective_date_to', effective_date_to,
    'latest_home_reference', latest_home_reference,
    'reference_window_applied', reference_window_applied
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.capture_extraction_source(p_capture_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select jsonb_build_object(
    'id', entry.id,
    'title', entry.title,
    'body', entry.body,
    'metadata', entry.metadata,
    
    'item_kind', entry.item_kind,
    'item_subtype', entry.item_subtype,
    'inbox_status', entry.inbox_status,
    'created_at', entry.created_at,
    'occurred_start', entry.occurred_start,
    'occurred_end', entry.occurred_end,
    'occurred_label', entry.occurred_label,
    'date_precision', entry.date_precision,
    'occurred_timezone', entry.occurred_timezone,
    'revision', entry.revision,
    'tag_names', coalesce(
      (
        select jsonb_agg(tag.name order by tag.name)
        from public.entry_tags as membership
        join public.tags as tag
          on tag.id = membership.tag_id
          and tag.owner_id = membership.owner_id
        where membership.entry_id = entry.id
          and membership.owner_id = auth.uid()
      ),
      '[]'::jsonb
    )
  )
  from public.entries as entry
  where entry.id = p_capture_id
    and entry.owner_id = auth.uid()
    and entry.item_kind = 'entry'
    and entry.inbox_status = 'unreviewed'
    and entry.inbox_status = 'unreviewed'
    and entry.deleted_at is null;
$function$;

CREATE OR REPLACE FUNCTION public.delete_trash_item_forever(p_item_kind text, p_item_id uuid, p_expected_revision integer, p_expected_deleted_at timestamp with time zone)
 RETURNS TABLE(item_kind text, item_id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  trash_owner_id uuid := auth.uid();
begin
  if trash_owner_id is null or p_item_id is null or p_expected_deleted_at is null then return; end if;
  if p_item_kind = 'entry' then
    if p_expected_revision is null or p_expected_revision < 1 then
      raise exception using errcode='22023',message='invalid_trash_revision';
    end if;
    return query delete from public.entries
      where entries.id=p_item_id and entries.owner_id=trash_owner_id
        and entries.revision=p_expected_revision and entries.deleted_at=p_expected_deleted_at
      returning 'entry'::text,entries.id;
    return;
  end if;
  if p_item_kind = 'attachment' then
    if p_expected_revision is not null then
      raise exception using errcode='22023',message='unexpected_trash_revision';
    end if;
    return query delete from public.attachments
      where attachments.id=p_item_id and attachments.owner_id=trash_owner_id
        and attachments.deleted_at=p_expected_deleted_at
        and exists(select 1 from public.entries where entries.id=attachments.entry_id
          and entries.owner_id=trash_owner_id and entries.deleted_at is null)
      returning 'attachment'::text,attachments.id;
    return;
  end if;
  if p_item_kind = 'person' then
    if p_expected_revision is null or p_expected_revision < 1 then
      raise exception using errcode='22023',message='invalid_trash_revision';
    end if;
    return query delete from public.people
      where people.id=p_item_id and people.owner_id=trash_owner_id
        and people.revision=p_expected_revision and people.deleted_at=p_expected_deleted_at
        and not exists(select 1 from public.entry_people ep where ep.person_id=people.id)
      returning 'person'::text,people.id;
    return;
  end if;
  raise exception using errcode='22023',message='invalid_trash_item_kind';
end;
$function$;

CREATE OR REPLACE FUNCTION public.editable_entry(p_entry_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select to_jsonb(e) || jsonb_build_object(
    'tag_names', coalesce(
      (
        select jsonb_agg(t.name order by t.name)
        from public.entry_tags et
        join public.tags t
          on t.id = et.tag_id
          and t.owner_id = et.owner_id
        where et.entry_id = e.id
          and et.owner_id = auth.uid()
      ),
      '[]'::jsonb
    ),
    'primary_location', (
      select to_jsonb(location)
      from public.entry_places as link
      join public.locations as location
        on location.id = link.place_id
        and location.owner_id = link.owner_id
      where link.entry_id = e.id
        and link.owner_id = auth.uid()
        and link.relationship = 'primary'
        and location.deleted_at is null
      order by link.created_at desc, location.id
      limit 1
    )
  )
  from public.entries e
  where e.id = p_entry_id
    and e.owner_id = auth.uid()
    and e.deleted_at is null
    and e.item_kind = 'entry' and e.item_subtype in ('entry', 'source_capture');
$function$;

CREATE OR REPLACE FUNCTION public.entry_history_snapshot(p_entry entries)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select public.normalize_entry_history_snapshot(to_jsonb(p_entry) || jsonb_build_object(
    'history_schema', 3,
    'home', (select to_jsonb(home) from public.homes as home where home.entry_id = p_entry.id),
    'vehicle', (select to_jsonb(vehicle) from public.vehicles as vehicle where vehicle.entry_id = p_entry.id),
    'goal', (select to_jsonb(goal) from public.goals as goal where goal.entry_id = p_entry.id),
    'place', (
      select to_jsonb(place)
      from public.homes as home
      join public.locations as place on place.id = home.place_id
      where home.entry_id = p_entry.id
    ),
    'tags', coalesce((
      select jsonb_agg(jsonb_build_object('id', tag.id, 'name', tag.name) order by tag.name)
      from public.entry_tags as membership
      join public.tags as tag on tag.id = membership.tag_id
      where membership.entry_id = p_entry.id
    ), '[]'::jsonb),
    'people', coalesce((
      select jsonb_agg(to_jsonb(link) || jsonb_build_object('name', person.name) order by link.person_id, link.relationship)
      from public.entry_people as link
      join public.people as person on person.id = link.person_id
      where link.entry_id = p_entry.id
    ), '[]'::jsonb),
    'places', coalesce((
      select jsonb_agg(to_jsonb(link) || jsonb_build_object('name', place.name) order by link.place_id, link.relationship)
      from public.entry_places as link
      join public.locations as place on place.id = link.place_id
      where link.entry_id = p_entry.id
    ), '[]'::jsonb),
    'timeline_items', coalesce((
      select jsonb_agg(to_jsonb(placement) || jsonb_build_object('track_name', track.name) order by placement.track_id)
      from public.timeline_items as placement
      join public.timeline_tracks as track on track.id = placement.track_id
      where placement.entry_id = p_entry.id
    ), '[]'::jsonb),
    'timeline', (
      select jsonb_build_object(
        'track_id', track.id,
        'track_name', track.name,
        'track_system_key', track.system_key,
        'timeline_kind', placement.timeline_kind
      )
      from public.timeline_items as placement
      join public.timeline_tracks as track on track.id = placement.track_id
      where placement.entry_id = p_entry.id
      order by (
        track.system_key = case
          when p_entry.item_kind = 'entity' and p_entry.item_subtype = 'home' then 'homes'
          when p_entry.item_kind = 'entity' and p_entry.item_subtype = 'vehicle' then 'vehicles'
          else ''
        end
      ) desc, placement.created_at, track.id
      limit 1
    ),
    'links', coalesce((
      select jsonb_agg(to_jsonb(link) order by link.target_entry_id, link.relationship)
      from public.entry_links as link
      where link.source_entry_id = p_entry.id
    ), '[]'::jsonb),
    'related_entry_ids', coalesce((
      select jsonb_agg(link.target_entry_id order by link.target_entry_id)
      from public.entry_links as link
      where link.source_entry_id = p_entry.id and link.relationship = 'related'
    ), '[]'::jsonb),
    'attachments', coalesce((
      select jsonb_agg(to_jsonb(attachment) order by attachment.created_at, attachment.id)
      from public.attachments as attachment
      where attachment.entry_id = p_entry.id
        and attachment.deleted_at is null
        and attachment.variant = 'original'
    ), '[]'::jsonb)
  ));
$function$;

CREATE OR REPLACE FUNCTION public.export_dataset_names()
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select array[
    'profiles','entries','entry_versions','tags','entry_tags',
    'locations','people','entry_locations','entry_people','timeline_tracks','timeline_items',
    'homes','vehicles','goals','attachments','entry_links','person_versions',
    'ai_preferences','ai_usage','ai_suggestions','ai_exploration_turns','ai_exploration_saves','media_objects'
  ]::text[];
$function$;

create function public.first_times_workspace_with_occurrence()
 RETURNS TABLE(entry_id uuid, title text, body text, inbox_status text, occurred_start timestamp with time zone, occurred_end timestamp with time zone, date_precision text, occurred_label text, occurred_timezone text, revision integer, updated_at timestamp with time zone, tag_names text[], attachments jsonb)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
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
          and media.deleted_at is null and media.variant = 'original'
      ),
      '[]'::jsonb
    )
  from public.entries
  where entries.owner_id = auth.uid()
    and entries.item_kind = 'entry' and entries.item_subtype = 'first_time'
    and entries.deleted_at is null
  order by entries.occurred_start desc nulls last, entries.created_at desc, entries.id;
$function$;

create function public.goals_workspace(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS TABLE(entry_id uuid, title text, body text, revision integer, created_at timestamp with time zone, updated_at timestamp with time zone, horizon text, status text, target_date date, tag_names text[], related_entries jsonb, attachments jsonb, total_count bigint)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  goal_owner_id uuid := auth.uid();
begin
  if goal_owner_id is null then
    return;
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 100
    or p_offset is null or p_offset < 0 or p_offset > 10000
  then
    raise exception using errcode = '22023', message = 'invalid_goals_page';
  end if;

  return query
  with visible_goals as (
    select
      entries.id as entry_id,
      entries.title,
      entries.body,
      entries.revision,
      entries.created_at,
      entries.updated_at,
      goals.horizon,
      goals.status,
      goals.target_date,
      coalesce(
        (
          select array_agg(tags.name order by lower(tags.name), tags.id)
          from public.entry_tags
          join public.tags
            on tags.id = entry_tags.tag_id
            and tags.owner_id = entry_tags.owner_id
          where entry_tags.entry_id = entries.id
            and entry_tags.owner_id = goal_owner_id
        ),
        array[]::text[]
      ) as tag_names,
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', related.id,
              'title', related.title,
              'body', related.body,
              'item_kind', related.item_kind, 'item_subtype', related.item_subtype,
              'occurred_start', related.occurred_start,
              'occurred_label', related.occurred_label,
              'occurred_timezone', related.occurred_timezone,
              'revision', related.revision,
              'updated_at', related.updated_at,
              'relationship', entry_links.relationship
            )
            order by related.updated_at desc, related.id
          )
          from public.entry_links
          join public.entries as related
            on related.id = entry_links.target_entry_id
            and related.owner_id = entry_links.owner_id
          where entry_links.source_entry_id = entries.id
            and entry_links.owner_id = goal_owner_id
            and related.deleted_at is null
        ),
        '[]'::jsonb
      ) as related_entries,
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', attachments.id,
              'bucket_id', attachments.bucket_id,
              'object_path', attachments.object_path,
              'original_filename', attachments.original_filename,
              'mime_type', attachments.mime_type,
              'byte_size', attachments.byte_size,
              'pixel_width', attachments.pixel_width,
              'pixel_height', attachments.pixel_height,
              'created_at', attachments.created_at
            )
            order by attachments.created_at, attachments.id
          )
          from public.attachments
          where attachments.entry_id = entries.id
            and attachments.owner_id = goal_owner_id
            and attachments.deleted_at is null
            and attachments.variant = 'original'
        ),
        '[]'::jsonb
      ) as attachments
    from public.entries
    join public.goals
      on goals.entry_id = entries.id
      and goals.owner_id = entries.owner_id
    where entries.owner_id = goal_owner_id
      and entries.item_kind = 'goal'
      and entries.deleted_at is null
  ),
  counted_goals as (
    select visible_goals.*, count(*) over () as total_count
    from visible_goals
  )
  select counted_goals.*
  from counted_goals
  order by
    case counted_goals.status
      when 'active' then 10
      when 'considering' then 20
      when 'paused' then 30
      when 'achieved' then 40
      else 50
    end,
    counted_goals.target_date asc nulls last,
    counted_goals.updated_at desc,
    lower(counted_goals.title),
    counted_goals.entry_id
  limit p_limit
  offset p_offset;
end;
$function$;

create function public.home_resurfaced_memory(p_local_date date, p_timezone text)
 RETURNS TABLE(resurfacing_kind text, years_ago integer, entry_id uuid, title text, body text, item_kind text, item_subtype text, inbox_status text, occurred_start timestamp with time zone, occurred_end timestamp with time zone, date_precision text, occurred_label text, occurred_timezone text, revision integer, created_at timestamp with time zone, updated_at timestamp with time zone, tag_names jsonb, attachments jsonb)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  home_owner_id uuid := auth.uid();
  normalized_timezone text := nullif(btrim(p_timezone), '');
begin
  if home_owner_id is null then
    return;
  end if;
  if p_local_date is null then
    raise exception using errcode = '22023', message = 'invalid_home_date';
  end if;
  if normalized_timezone is null or length(normalized_timezone) > 100 then
    raise exception using errcode = '22023', message = 'invalid_home_timezone';
  end if;
  begin
    perform pg_catalog.timezone(normalized_timezone, p_local_date::timestamp);
  exception
    when invalid_parameter_value then
      raise exception using errcode = '22023', message = 'invalid_home_timezone';
  end;

  return query
  with eligible_items as (
    select
      item.*,
      pg_catalog.timezone(coalesce(timezone.name, 'UTC'), item.occurred_start)::date
        as local_occurred_date
    from public.entries as item
    left join pg_catalog.pg_timezone_names as timezone
      on timezone.name = item.occurred_timezone
    where item.owner_id = home_owner_id
      and item.deleted_at is null
      and item.inbox_status = 'organized'
      and item.occurred_start is not null
      and not (item.item_kind = 'entry' and item.item_subtype = 'period')
  ),
  anniversary_memory as (
    select
      eligible_items.*,
      'on_this_day'::text as selected_kind,
      extract(year from p_local_date)::integer
        - extract(year from eligible_items.local_occurred_date)::integer
        as selected_years_ago
    from eligible_items
    where extract(month from eligible_items.local_occurred_date) = extract(month from p_local_date)
      and extract(day from eligible_items.local_occurred_date) = extract(day from p_local_date)
      and extract(year from eligible_items.local_occurred_date) < extract(year from p_local_date)
    order by eligible_items.local_occurred_date desc, eligible_items.created_at desc, eligible_items.id
    limit 1
  ),
  archive_memories as (
    select
      eligible_items.*,
      row_number() over (order by eligible_items.local_occurred_date, eligible_items.id) as archive_position,
      count(*) over () as archive_count
    from eligible_items
    where eligible_items.local_occurred_date <= p_local_date - 30
      and not exists (select 1 from anniversary_memory)
  ),
  archive_memory as (
    select
      archive_memories.*,
      'from_your_archive'::text as selected_kind,
      null::integer as selected_years_ago
    from archive_memories
    where archive_memories.archive_position = (
      pg_catalog.mod(
        (p_local_date - date '2000-01-01')::bigint,
        archive_memories.archive_count
      ) + 1
    )
  ),
  selected_memory as (
    select
      anniversary_memory.selected_kind,
      anniversary_memory.selected_years_ago,
      anniversary_memory.id,
      anniversary_memory.title,
      anniversary_memory.body,
      anniversary_memory.item_kind,
      anniversary_memory.item_subtype,
      anniversary_memory.inbox_status,
      anniversary_memory.occurred_start,
      anniversary_memory.occurred_end,
      anniversary_memory.date_precision,
      anniversary_memory.occurred_label,
      anniversary_memory.occurred_timezone,
      anniversary_memory.revision,
      anniversary_memory.created_at,
      anniversary_memory.updated_at
    from anniversary_memory
    union all
    select
      archive_memory.selected_kind,
      archive_memory.selected_years_ago,
      archive_memory.id,
      archive_memory.title,
      archive_memory.body,
      archive_memory.item_kind,
      archive_memory.item_subtype,
      archive_memory.inbox_status,
      archive_memory.occurred_start,
      archive_memory.occurred_end,
      archive_memory.date_precision,
      archive_memory.occurred_label,
      archive_memory.occurred_timezone,
      archive_memory.revision,
      archive_memory.created_at,
      archive_memory.updated_at
    from archive_memory
  )
  select
    selected_memory.selected_kind,
    selected_memory.selected_years_ago,
    selected_memory.id,
    coalesce(
      nullif(btrim(selected_memory.title), ''),
      nullif(split_part(btrim(selected_memory.body), E'\n', 1), ''),
      'Untitled Entry'
    ),
    selected_memory.body,
    selected_memory.item_kind,
    selected_memory.item_subtype,
    selected_memory.inbox_status,
    selected_memory.occurred_start,
    selected_memory.occurred_end,
    selected_memory.date_precision,
    selected_memory.occurred_label,
    selected_memory.occurred_timezone,
    selected_memory.revision,
    selected_memory.created_at,
    selected_memory.updated_at,
    coalesce((
      select jsonb_agg(tag.name order by lower(tag.name), tag.id)
      from public.entry_tags as membership
      join public.tags as tag
        on tag.id = membership.tag_id
        and tag.owner_id = membership.owner_id
      where membership.entry_id = selected_memory.id
        and membership.owner_id = home_owner_id
    ), '[]'::jsonb),
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'attachment_id', attachment.id,
        'bucket_id', attachment.bucket_id,
        'object_path', attachment.object_path,
        'original_filename', attachment.original_filename,
        'mime_type', attachment.mime_type,
        'byte_size', attachment.byte_size,
        'pixel_width', attachment.pixel_width,
        'pixel_height', attachment.pixel_height
      ) order by attachment.created_at, attachment.id)
      from public.attachments as attachment
      where attachment.entry_id = selected_memory.id
        and attachment.owner_id = home_owner_id
        and attachment.deleted_at is null
        and attachment.variant = 'original'
    ), '[]'::jsonb)
  from selected_memory;
end;
$function$;

create function public.home_workspace(p_local_date date, p_timezone text, p_recent_limit integer DEFAULT 5)
 RETURNS TABLE(snapshot_date date, profile_display_name text, inbox_count bigint, entry_count bigint, first_time_count bigint, tag_count bigint, current_stage_count bigint, recent_entries jsonb, current_stages jsonb)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  home_owner_id uuid := auth.uid();
  normalized_timezone text := nullif(btrim(p_timezone), '');
  local_day_start timestamptz;
  local_day_end timestamptz;
begin
  if home_owner_id is null then
    return;
  end if;

  if p_local_date is null then
    raise exception using errcode = '22023', message = 'invalid_home_date';
  end if;

  if normalized_timezone is null or length(normalized_timezone) > 100 then
    raise exception using errcode = '22023', message = 'invalid_home_timezone';
  end if;

  if p_recent_limit is null or p_recent_limit < 1 or p_recent_limit > 10 then
    raise exception using errcode = '22023', message = 'invalid_home_recent_limit';
  end if;

  begin
    local_day_start := pg_catalog.timezone(normalized_timezone, p_local_date::timestamp);
    local_day_end := pg_catalog.timezone(
      normalized_timezone,
      (p_local_date + 1)::timestamp
    );
  exception
    when invalid_parameter_value then
      raise exception using errcode = '22023', message = 'invalid_home_timezone';
  end;

  return query
  with active_entries as (
    select entries.*
    from public.entries
    where entries.owner_id = home_owner_id
      and entries.deleted_at is null
  ),
  entry_stats as (
    select
      count(*) filter (where inbox_status = 'unreviewed') as inbox_count,
      count(*) filter (where inbox_status = 'organized') as entry_count,
      count(*) filter (where item_kind = 'entry' and item_subtype = 'first_time') as first_time_count
    from active_entries
  ),
  tag_stats as (
    select count(*) as tag_count
    from public.tags
    where tags.owner_id = home_owner_id
  ),

  visible_stages as (
    select
      entries.id as entry_id,
      entries.title,
      entries.body,
      entries.occurred_start,
      entries.occurred_end,
      entries.date_precision,
      entries.occurred_label,
      entries.occurred_timezone,
      tracks.id as track_id,
      tracks.name as track_name,
      tracks.sort_order as track_sort_order,
      items.sort_order as item_sort_order
    from public.timeline_items as items
    join active_entries as entries on entries.id = items.entry_id
    join public.timeline_tracks as tracks
      on tracks.id = items.track_id
      and tracks.owner_id = items.owner_id
    where items.owner_id = home_owner_id
      and items.timeline_kind = 'stage'
      and not tracks.is_hidden
      and entries.occurred_start < local_day_end
      and (entries.occurred_end is null or entries.occurred_end >= local_day_start)
  ),
  recent_entry_rows as (
    select
      entries.*,
      row_number() over (order by entries.created_at desc, entries.id) as recent_position
    from active_entries as entries
    where entries.inbox_status = 'organized'
    order by entries.created_at desc, entries.id
    limit p_recent_limit
  )
  select
    p_local_date,
    (
      select profiles.display_name
      from public.profiles
      where profiles.user_id = home_owner_id
    ),
    entry_stats.inbox_count,
    entry_stats.entry_count,
    entry_stats.first_time_count,
    tag_stats.tag_count,
    (select count(*) from visible_stages),
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'entry_id', recent_entries.id,
            'title', coalesce(
              nullif(btrim(recent_entries.title), ''),
              nullif(split_part(btrim(recent_entries.body), E'\n', 1), ''),
              'Untitled Entry'
            ),
            'body', recent_entries.body,
            'item_kind', recent_entries.item_kind, 'item_subtype', recent_entries.item_subtype,
            'inbox_status', recent_entries.inbox_status,
            'occurred_start', recent_entries.occurred_start,
            'occurred_end', recent_entries.occurred_end,
            'date_precision', recent_entries.date_precision,
            'occurred_label', recent_entries.occurred_label,
            'occurred_timezone', recent_entries.occurred_timezone,
            'revision', recent_entries.revision,
            'created_at', recent_entries.created_at,
            'updated_at', recent_entries.updated_at,
            'tag_names', coalesce(
              (
                select jsonb_agg(tags.name order by lower(tags.name), tags.id)
                from public.entry_tags
                join public.tags
                  on tags.id = entry_tags.tag_id
                  and tags.owner_id = entry_tags.owner_id
                where entry_tags.entry_id = recent_entries.id
                  and entry_tags.owner_id = home_owner_id
              ),
              '[]'::jsonb
            ),
            'attachments', coalesce(
              (
                select jsonb_agg(
                  jsonb_build_object(
                    'attachment_id', attachments.id,
                    'bucket_id', attachments.bucket_id,
                    'object_path', attachments.object_path,
                    'original_filename', attachments.original_filename,
                    'mime_type', attachments.mime_type,
                    'byte_size', attachments.byte_size,
                    'pixel_width', attachments.pixel_width,
                    'pixel_height', attachments.pixel_height
                  )
                  order by attachments.created_at, attachments.id
                )
                from public.attachments
                where attachments.entry_id = recent_entries.id
                  and attachments.owner_id = home_owner_id
                  and attachments.deleted_at is null
                  and attachments.variant = 'original'
              ),
              '[]'::jsonb
            )
          )
          order by recent_entries.recent_position
        )
        from recent_entry_rows as recent_entries
      ),
      '[]'::jsonb
    ),
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'entry_id', stages.entry_id,
            'title', stages.title,
            'body', stages.body,
            'track_id', stages.track_id,
            'track_name', stages.track_name,
            'occurred_start', stages.occurred_start,
            'occurred_end', stages.occurred_end,
            'date_precision', stages.date_precision,
            'occurred_label', stages.occurred_label,
            'occurred_timezone', stages.occurred_timezone
          )
          order by
            stages.track_sort_order,
            lower(stages.track_name),
            stages.occurred_start,
            stages.item_sort_order,
            stages.entry_id
        )
        from visible_stages as stages
      ),
      '[]'::jsonb
    )
  from entry_stats
  cross join tag_stats;
end;
$function$;

create function public.homes_workspace(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS TABLE(entry_id uuid, title text, body text, occurred_start timestamp with time zone, occurred_end timestamp with time zone, date_precision text, occurred_label text, occurred_timezone text, revision integer, updated_at timestamp with time zone, move_in_reason text, move_out_reason text, place_id uuid, place_name text, address text, city text, region text, country text, latitude numeric, longitude numeric, place_notes text, timeline_track_id uuid, timeline_track_name text, tag_names text[], attachments jsonb, total_count bigint)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  home_owner_id uuid := auth.uid();
begin
  if home_owner_id is null then
    return;
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 100
    or p_offset is null or p_offset < 0 or p_offset > 10000
  then
    raise exception using errcode = '22023', message = 'invalid_homes_page';
  end if;

  return query
  with visible_homes as (
    select
      entries.id as entry_id,
      entries.title,
      entries.body,
      entries.occurred_start,
      entries.occurred_end,
      entries.date_precision,
      entries.occurred_label,
      entries.occurred_timezone,
      entries.revision,
      entries.updated_at,
      homes.move_in_reason,
      homes.move_out_reason,
      locations.id as place_id,
      locations.name as place_name,
      locations.address,
      locations.city,
      locations.region,
      locations.country,
      locations.latitude,
      locations.longitude,
      locations.notes as place_notes,
      timeline_tracks.id as timeline_track_id,
      timeline_tracks.name as timeline_track_name,
      coalesce(
        (
          select array_agg(tags.name order by lower(tags.name), tags.id)
          from public.entry_tags
          join public.tags
            on tags.id = entry_tags.tag_id
            and tags.owner_id = entry_tags.owner_id
          where entry_tags.entry_id = entries.id
            and entry_tags.owner_id = home_owner_id
        ),
        array[]::text[]
      ) as tag_names,
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', attachments.id,
              'bucket_id', attachments.bucket_id,
              'object_path', attachments.object_path,
              'original_filename', attachments.original_filename,
              'mime_type', attachments.mime_type,
              'byte_size', attachments.byte_size,
              'pixel_width', attachments.pixel_width,
              'pixel_height', attachments.pixel_height,
              'created_at', attachments.created_at
            )
            order by attachments.created_at, attachments.id
          )
          from public.attachments
          where attachments.entry_id = entries.id
            and attachments.owner_id = home_owner_id
            and attachments.deleted_at is null
            and attachments.variant = 'original'
        ),
        '[]'::jsonb
      ) as attachments
    from public.entries
    join public.homes
      on homes.entry_id = entries.id
      and homes.owner_id = entries.owner_id
    left join public.locations
      on locations.id = homes.place_id
      and locations.owner_id = homes.owner_id
    left join public.timeline_items
      on timeline_items.entry_id = entries.id
      and timeline_items.owner_id = entries.owner_id
      and exists (
        select 1
        from public.timeline_tracks as home_tracks
        where home_tracks.id = timeline_items.track_id
          and home_tracks.owner_id = timeline_items.owner_id
          and home_tracks.system_key = 'homes'
      )
    left join public.timeline_tracks
      on timeline_tracks.id = timeline_items.track_id
      and timeline_tracks.owner_id = timeline_items.owner_id
      and timeline_tracks.system_key = 'homes'
    where entries.owner_id = home_owner_id
      and entries.item_kind = 'entity' and entries.item_subtype = 'home'
      and entries.deleted_at is null
  ),
  counted_homes as (
    select visible_homes.*, count(*) over () as total_count
    from visible_homes
  )
  select counted_homes.*
  from counted_homes
  order by
    (counted_homes.occurred_end is null) desc,
    counted_homes.occurred_start desc nulls last,
    lower(counted_homes.title),
    counted_homes.entry_id
  limit p_limit
  offset p_offset;
end;
$function$;

CREATE OR REPLACE FUNCTION public.prepare_empty_trash()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  result jsonb;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;

  with candidates as (
    select 'entry'::text as item_kind, entry.id as item_id, entry.deleted_at, entry.revision
    from public.entries as entry
    where entry.owner_id = auth.uid()
      and entry.deleted_at is not null
      and not exists (
        select 1 from public.people as person
        where person.id = entry.id and person.owner_id = entry.owner_id
      )

    union all

    select 'attachment', attachment.id, attachment.deleted_at, null::integer
    from public.attachments as attachment
    join public.entries as entry
      on entry.id = attachment.entry_id and entry.owner_id = attachment.owner_id
    where attachment.owner_id = auth.uid()
      and attachment.deleted_at is not null
      and entry.deleted_at is null


    union all

    select 'person', person.id, person.deleted_at, person.revision
    from public.people as person
    where person.owner_id = auth.uid() and person.deleted_at is not null
  ),
  bounded as (
    select *
    from candidates
    order by
      case item_kind when 'entry' then 0 when 'attachment' then 1 else 2 end,
      item_kind,
      item_id
    limit 10001
  )
  select coalesce(
    jsonb_agg(
      to_jsonb(bounded)
      order by
        case item_kind when 'entry' then 0 when 'attachment' then 1 else 2 end,
        item_kind,
        item_id
    ),
    '[]'::jsonb
  )
  into result
  from bounded;

  if jsonb_array_length(result) > 10000 then
    raise exception using errcode = '54000', message = 'trash_snapshot_too_large';
  end if;

  return result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.restore_entry_version(p_entry_id uuid, p_version integer, p_expected_revision integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  item_record public.entries;
  snapshot jsonb;
  restored_revision integer;
  relation jsonb;
  timeline_items jsonb;
  home_record public.homes;
  vehicle_record public.vehicles;
  goal_record public.goals;
begin
  select *
  into item_record
  from public.entries
  where id = p_entry_id and owner_id = auth.uid()
  for update;
  if not found
    or item_record.revision is distinct from p_expected_revision
    or item_record.deleted_at is not null
  then
    return null;
  end if;

  select version.snapshot
  into snapshot
  from public.entry_versions as version
  where version.entry_id = item_record.id
    and version.owner_id = item_record.owner_id
    and version.version = p_version;
  if snapshot is null then
    return null;
  end if;
  if coalesce((snapshot->>'history_schema')::integer, 0) <> 3
    or snapshot->>'item_kind' not in ('capture', 'writing', 'event', 'story', 'entry', 'entity', 'goal')
    or coalesce(snapshot->>'item_subtype', '') !~ '^[a-z][a-z0-9_]{0,63}$'
  then
    raise exception using errcode = 'P0001', message = 'history_schema_unsupported';
  end if;

  for relation in select value from jsonb_array_elements(coalesce(snapshot->'tags', '[]')) loop
    perform 1
    from public.tags
    where id = (relation->>'id')::uuid and owner_id = item_record.owner_id
    for share;
    if not found then
      raise exception using errcode = 'P0001', message = 'history_reference_unavailable';
    end if;
  end loop;
  for relation in select value from jsonb_array_elements(coalesce(snapshot->'people', '[]')) loop
    perform 1
    from public.people
    where id = (relation->>'person_id')::uuid
      and owner_id = item_record.owner_id
      and deleted_at is null
    for share;
    if not found then
      raise exception using errcode = 'P0001', message = 'history_reference_unavailable';
    end if;
  end loop;
  for relation in select value from jsonb_array_elements(coalesce(snapshot->'places', '[]')) loop
    perform 1
    from public.locations
    where id = (relation->>'place_id')::uuid
      and owner_id = item_record.owner_id
      and deleted_at is null
    for share;
    if not found then
      raise exception using errcode = 'P0001', message = 'history_reference_unavailable';
    end if;
  end loop;

  timeline_items := snapshot->'timeline_items';
  if timeline_items is null and snapshot ? 'timeline' then
    timeline_items := case
      when snapshot->'timeline' = 'null'::jsonb then '[]'::jsonb
      else jsonb_build_array(snapshot->'timeline')
    end;
  end if;
  for relation in select value from jsonb_array_elements(coalesce(timeline_items, '[]')) loop
    perform 1
    from public.timeline_tracks
    where id = (relation->>'track_id')::uuid and owner_id = item_record.owner_id
    for share;
    if not found then
      raise exception using errcode = 'P0001', message = 'history_reference_unavailable';
    end if;
  end loop;
  for relation in select value from jsonb_array_elements(coalesce(snapshot->'links', '[]')) loop
    perform 1
    from public.entries
    where id = (relation->>'target_entry_id')::uuid
      and owner_id = item_record.owner_id
      and deleted_at is null
    for share;
    if not found then
      raise exception using errcode = 'P0001', message = 'history_reference_unavailable';
    end if;
  end loop;
  for relation in
    select value
    from jsonb_array_elements(coalesce(snapshot->'attachments', '[]'))
    where coalesce(value->>'variant', 'original') = 'original'
  loop
    perform 1
    from public.attachments as attachment
    join storage.objects as object
      on object.bucket_id = attachment.bucket_id and object.name = attachment.object_path
    where attachment.id = (relation->>'id')::uuid
      and attachment.entry_id = item_record.id
      and attachment.owner_id = item_record.owner_id
    for share of attachment;
    if not found then
      raise exception using errcode = 'P0001', message = 'history_attachment_unavailable';
    end if;
  end loop;

  if snapshot->>'item_kind' = 'entity' and snapshot->>'item_subtype' = 'home' then
    if snapshot->'home' is null or snapshot->'home' = 'null'::jsonb then
      raise exception using errcode = 'P0001', message = 'history_details_unavailable';
    end if;
    home_record := jsonb_populate_record(null::public.homes, snapshot->'home');
    if home_record.place_id is not null then
      perform 1
      from public.locations
      where id = home_record.place_id
        and owner_id = item_record.owner_id
        and deleted_at is null
      for share;
      if not found then
        raise exception using errcode = 'P0001', message = 'history_reference_unavailable';
      end if;
    end if;
  elsif snapshot->>'item_kind' = 'entity' and snapshot->>'item_subtype' = 'vehicle' then
    if snapshot->'vehicle' is null or snapshot->'vehicle' = 'null'::jsonb then
      raise exception using errcode = 'P0001', message = 'history_details_unavailable';
    end if;
    vehicle_record := jsonb_populate_record(null::public.vehicles, snapshot->'vehicle');
  elsif snapshot->>'item_kind' = 'goal' then
    if snapshot->'goal' is null or snapshot->'goal' = 'null'::jsonb then
      raise exception using errcode = 'P0001', message = 'history_details_unavailable';
    end if;
    goal_record := jsonb_populate_record(null::public.goals, snapshot->'goal');
  end if;

  update public.entries
  set
    title = snapshot->>'title',
    body = coalesce(snapshot->>'body', ''),
    item_kind = case when snapshot->>'item_kind' in ('capture', 'writing', 'event', 'story') then 'entry' else snapshot->>'item_kind' end,
    item_subtype = case when snapshot->>'item_kind' in ('capture', 'writing', 'event', 'story') then case snapshot->>'item_subtype' when 'first_time' then 'first_time' when 'life_stage' then 'period' when 'source_capture' then 'source_capture' when 'other' then case when exists (select 1 from jsonb_array_elements(coalesce(timeline_items, '[]'::jsonb)) as placement where placement->>'timeline_kind' = 'event') then 'moment' else 'entry' end else 'entry' end else snapshot->>'item_subtype' end,
    inbox_status = snapshot->>'inbox_status',
    occurred_start = (snapshot->>'occurred_start')::timestamptz,
    occurred_end = (snapshot->>'occurred_end')::timestamptz,
    date_precision = snapshot->>'date_precision',
    occurred_label = snapshot->>'occurred_label',
    occurred_timezone = snapshot->>'occurred_timezone',
    source_language = snapshot->>'source_language',
    metadata = coalesce(snapshot->'metadata', '{}'),
    embedding = null,
    embedding_model = null,
    embedding_updated_at = null
  where id = item_record.id
  returning revision into restored_revision;

  delete from public.homes where entry_id = item_record.id;
  delete from public.vehicles where entry_id = item_record.id;
  delete from public.goals where entry_id = item_record.id;
  if home_record.entry_id is not null then
    insert into public.homes (entry_id, owner_id, place_id, move_in_reason, move_out_reason)
    values (item_record.id, item_record.owner_id, home_record.place_id, home_record.move_in_reason, home_record.move_out_reason);
  elsif vehicle_record.entry_id is not null then
    insert into public.vehicles (entry_id, owner_id, make, model, model_year, color)
    values (item_record.id, item_record.owner_id, vehicle_record.make, vehicle_record.model, vehicle_record.model_year, vehicle_record.color);
  elsif goal_record.entry_id is not null then
    insert into public.goals (entry_id, owner_id, horizon, status, target_date)
    values (item_record.id, item_record.owner_id, goal_record.horizon, goal_record.status, goal_record.target_date);
  end if;

  delete from public.entry_tags where entry_id = item_record.id;
  insert into public.entry_tags (entry_id, owner_id, tag_id)
  select item_record.id, item_record.owner_id, (value->>'id')::uuid
  from jsonb_array_elements(coalesce(snapshot->'tags', '[]'));
  delete from public.entry_people where entry_id = item_record.id;
  insert into public.entry_people (entry_id, owner_id, person_id, relationship)
  select item_record.id, item_record.owner_id, (value->>'person_id')::uuid, value->>'relationship'
  from jsonb_array_elements(coalesce(snapshot->'people', '[]'));
  delete from public.entry_places where entry_id = item_record.id;
  insert into public.entry_places (entry_id, owner_id, place_id, relationship)
  select item_record.id, item_record.owner_id, (value->>'place_id')::uuid, value->>'relationship'
  from jsonb_array_elements(coalesce(snapshot->'places', '[]'));
  delete from public.timeline_items where entry_id = item_record.id;
  insert into public.timeline_items (entry_id, owner_id, track_id, timeline_kind, sort_order)
  select
    item_record.id,
    item_record.owner_id,
    (value->>'track_id')::uuid,
    value->>'timeline_kind',
    coalesce((value->>'sort_order')::integer, 0)
  from jsonb_array_elements(coalesce(timeline_items, '[]'));
  delete from public.entry_links where source_entry_id = item_record.id;
  insert into public.entry_links (source_entry_id, owner_id, target_entry_id, relationship)
  select item_record.id, item_record.owner_id, (value->>'target_entry_id')::uuid, value->>'relationship'
  from jsonb_array_elements(coalesce(snapshot->'links', '[]'));
  update public.attachments
  set deleted_at = case
    when id in (
      select (value->>'id')::uuid
      from jsonb_array_elements(coalesce(snapshot->'attachments', '[]'))
    ) then null
    else coalesce(deleted_at, now())
  end
  where entry_id = item_record.id and variant = 'original';

  return restored_revision;
end;
$function$;

CREATE OR REPLACE FUNCTION public.restore_trash_item_without_photo_history(p_item_kind text, p_item_id uuid, p_expected_revision integer, p_expected_deleted_at timestamp with time zone)
 RETURNS TABLE(item_kind text, item_id uuid, revision integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  trash_owner_id uuid := auth.uid();
begin
  if trash_owner_id is null or p_item_id is null or p_expected_deleted_at is null then
    return;
  end if;

  if p_item_kind = 'entry' then
    if p_expected_revision is null or p_expected_revision < 1 then
      raise exception using errcode = '22023', message = 'invalid_trash_revision';
    end if;

    return query
    update public.entries
    set deleted_at = null
    where entries.id = p_item_id
      and entries.owner_id = trash_owner_id
      and entries.revision = p_expected_revision
      and entries.deleted_at = p_expected_deleted_at
    returning 'entry'::text, entries.id, entries.revision;
    return;
  end if;

  if p_item_kind = 'attachment' then
    if p_expected_revision is not null then
      raise exception using errcode = '22023', message = 'unexpected_trash_revision';
    end if;

    return query
    update public.attachments
    set deleted_at = null
    where attachments.id = p_item_id
      and attachments.owner_id = trash_owner_id
      and attachments.deleted_at = p_expected_deleted_at
      and exists (
        select 1
        from public.entries
        where entries.id = attachments.entry_id
          and entries.owner_id = trash_owner_id
          and entries.deleted_at is null
      )
    returning 'attachment'::text, attachments.id, null::integer;
    return;
  end if;

  if p_item_kind = 'person' then
    if p_expected_revision is null or p_expected_revision < 1 then
      raise exception using errcode = '22023', message = 'invalid_trash_revision';
    end if;
    return query update public.people set deleted_at = null
      where people.id = p_item_id and people.owner_id = trash_owner_id
        and people.revision = p_expected_revision and people.deleted_at = p_expected_deleted_at
      returning 'person'::text, people.id, people.revision;
    return;
  end if;

  raise exception using errcode = '22023', message = 'invalid_trash_item_kind';
end;
$function$;

create function public.save_timeline_entry_with_organization(p_track_id uuid, p_timeline_kind text, p_title text, p_body text, p_occurred_start timestamp with time zone, p_occurred_end timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_tag_names text[], p_entry_id uuid, p_expected_revision integer)
 RETURNS TABLE(entry_id uuid, revision integer, was_created boolean)
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  timeline_owner_id uuid := auth.uid();
  saved_entry_id uuid;
  saved_revision integer;
  created boolean;
begin
  if timeline_owner_id is null then
    return;
  end if;

  if not public.valid_tag_names(p_tag_names) then
    raise exception using errcode = '22023', message = 'invalid_tags';
  end if;

  select saved.entry_id, saved.revision, saved.was_created
  into saved_entry_id, saved_revision, created
  from public.save_timeline_entry_with_occurrence(
    p_track_id,
    p_timeline_kind,
    p_title,
    p_body,
    p_occurred_start,
    p_occurred_end,
    p_date_precision,
    p_occurred_label,
    p_occurred_timezone,
    p_entry_id,
    p_expected_revision
  ) as saved;

  if saved_entry_id is null then
    return;
  end if;

  perform public.replace_entry_tags(saved_entry_id, p_tag_names);

  return query select saved_entry_id, saved_revision, created;
end;
$function$;

create function public.search_wiki_items(p_query text DEFAULT ''::text, p_item_classifications text[] DEFAULT '{}'::text[], p_tag_names text[] DEFAULT '{}'::text[], p_date_from date DEFAULT NULL::date, p_date_to date DEFAULT NULL::date, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0, p_order text DEFAULT 'relevance'::text)
 RETURNS TABLE(entry_id uuid, title text, body text, inbox_status text, occurred_start timestamp with time zone, occurred_end timestamp with time zone, occurred_label text, occurred_timezone text, revision integer, updated_at timestamp with time zone, tag_names text[], match_reasons text[], match_rank double precision, total_count bigint, date_precision text, item_kind text, item_subtype text, record_source text, record_id uuid)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  search_owner_id uuid := auth.uid();
  normalized_query text;
  normalized_classifications text[];
  normalized_tag_names text[];
  search_query tsquery;
  has_query boolean;
  has_filters boolean;
begin
  if search_owner_id is null then
    return;
  end if;
  if p_order is null or p_order not in ('relevance', 'oldest', 'newest') then
    raise exception using errcode = '22023', message = 'invalid_search_order';
  end if;
  if length(coalesce(p_query, '')) > 200 then
    raise exception using errcode = '22023', message = 'query_too_long';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 100
    or p_offset is null or p_offset < 0 or p_offset > 10000
  then
    raise exception using errcode = '22023', message = 'invalid_pagination';
  end if;
  if (p_date_from is not null and not isfinite(p_date_from))
    or (p_date_to is not null and not isfinite(p_date_to))
    or (p_date_from is not null and p_date_to is not null and p_date_from > p_date_to)
  then
    raise exception using errcode = '22023', message = 'invalid_date_range';
  end if;
  if cardinality(coalesce(p_item_classifications, '{}'::text[])) > 20
    or exists (
      select 1
      from unnest(coalesce(p_item_classifications, '{}'::text[])) as classification
      where nullif(btrim(classification), '') is null
        or length(btrim(classification)) > 64
    )
  then
    raise exception using errcode = '22023', message = 'invalid_item_classifications';
  end if;
  if not public.valid_tag_names(p_tag_names) then
    raise exception using errcode = '22023', message = 'invalid_tags';
  end if;

  normalized_query := lower(btrim(coalesce(p_query, '')));
  normalized_classifications := array(
    select distinct lower(btrim(classification))
    from unnest(coalesce(p_item_classifications, '{}'::text[])) as classification
    order by lower(btrim(classification))
  );
  normalized_tag_names := array(
    select distinct lower(btrim(tag_name))
    from unnest(coalesce(p_tag_names, '{}'::text[])) as tag_name
    order by lower(btrim(tag_name))
  );
  has_query := normalized_query <> '';
  search_query := case
    when has_query then websearch_to_tsquery('simple', normalized_query)
    else null::tsquery
  end;
  has_filters := cardinality(normalized_classifications) > 0
    or cardinality(normalized_tag_names) > 0
    or p_date_from is not null
    or p_date_to is not null;

  if not has_query and not has_filters then
    return;
  end if;

  return query
  with owned_items as (
    select item.*
    from public.entries as item
    where item.owner_id = search_owner_id
      and item.deleted_at is null
      and (
        cardinality(normalized_classifications) = 0
        or item.item_kind = any(normalized_classifications)
        or item.item_subtype = any(normalized_classifications)
      )
      and (
        cardinality(normalized_tag_names) = 0
        or exists (
          select 1
          from public.entry_tags as membership
          join public.tags as tag
            on tag.id = membership.tag_id
            and tag.owner_id = membership.owner_id
          where membership.entry_id = item.id
            and membership.owner_id = search_owner_id
            and lower(tag.name) = any(normalized_tag_names)
        )
      )
      and (
        (p_date_from is null and p_date_to is null)
        or public.wiki_item_occurrence_window(
          item.occurred_start,
          item.occurred_end,
          item.date_precision,
          item.occurred_timezone,
          item.item_kind,
          item.item_subtype
        ) && daterange(p_date_from, p_date_to, '[]')
      )
  ),
  enriched as (
    select
      item.*,
      tag_context.tag_names,
      tag_context.tag_text,
      concat_ws(
        ' ',
        item.occurred_label,
        public.entry_occurrence_date_text(
          item.occurred_start,
          item.date_precision,
          item.occurred_timezone
        ),
        public.entry_occurrence_date_text(
          item.occurred_end,
          item.date_precision,
          item.occurred_timezone
        )
      ) as date_text,
      concat_ws(
        ' ',
        replace(item.item_kind, '_', ' '),
        replace(item.item_subtype, '_', ' '),
        item.metadata::text,
        person.name,
        person.relationship_label,
        person.notes,
        home.move_in_reason,
        home.move_out_reason,
        vehicle.make,
        vehicle.model,
        vehicle.model_year::text,
        vehicle.color,
        goal.horizon,
        goal.status,
        goal.target_date::text,
        timeline_context.timeline_text,
        related_place_context.place_text,
        related_person_context.person_text,
        attachment_context.filename_text
      ) as structured_text
    from owned_items as item
    left join public.people as person
      on person.id = item.id and person.owner_id = search_owner_id
    left join public.homes as home
      on home.entry_id = item.id and home.owner_id = search_owner_id
    left join public.vehicles as vehicle
      on vehicle.entry_id = item.id and vehicle.owner_id = search_owner_id
    left join public.goals as goal
      on goal.entry_id = item.id and goal.owner_id = search_owner_id
    left join lateral (
      select
        coalesce(array_agg(tag.name order by lower(tag.name), tag.name), '{}'::text[]) as tag_names,
        coalesce(string_agg(tag.name, ' '), '') as tag_text
      from public.entry_tags as membership
      join public.tags as tag
        on tag.id = membership.tag_id
        and tag.owner_id = membership.owner_id
      where membership.entry_id = item.id
        and membership.owner_id = search_owner_id
    ) as tag_context on true
    left join lateral (
      select string_agg(concat_ws(' ', track.name, timeline_item.timeline_kind), ' ') as timeline_text
      from public.timeline_items as timeline_item
      join public.timeline_tracks as track
        on track.id = timeline_item.track_id
        and track.owner_id = timeline_item.owner_id
      where timeline_item.entry_id = item.id
        and timeline_item.owner_id = search_owner_id
    ) as timeline_context on true
    left join lateral (
      select string_agg(concat_ws(' ', related.name, related.address, related.city, related.region, related.country, related.notes, link.relationship), ' ') as place_text
      from public.entry_places as link
      join public.locations as related
        on related.id = link.place_id and related.owner_id = link.owner_id
      where link.entry_id = item.id and link.owner_id = search_owner_id
    ) as related_place_context on true
    left join lateral (
      select string_agg(concat_ws(' ', related.name, related.relationship_label, related.notes, link.relationship), ' ') as person_text
      from public.entry_people as link
      join public.people as related
        on related.id = link.person_id and related.owner_id = link.owner_id
      where link.entry_id = item.id and link.owner_id = search_owner_id
    ) as related_person_context on true
    left join lateral (
      select string_agg(attachment.original_filename, ' ') as filename_text
      from public.attachments as attachment
      where attachment.entry_id = item.id and attachment.owner_id = search_owner_id
    ) as attachment_context on true
  ),
  evaluated as (
    select
      enriched.*,
      has_query and (
        position(normalized_query in lower(coalesce(enriched.title, ''))) > 0
        or to_tsvector('simple', coalesce(enriched.title, '')) @@ search_query
      ) as title_matches,
      has_query and (
        position(normalized_query in lower(enriched.body)) > 0
        or to_tsvector('simple', enriched.body) @@ search_query
      ) as body_matches,
      has_query and (
        position(normalized_query in lower(enriched.tag_text)) > 0
        or to_tsvector('simple', enriched.tag_text) @@ search_query
      ) as tag_matches,
      has_query and (
        position(normalized_query in lower(enriched.date_text)) > 0
        or to_tsvector('simple', enriched.date_text) @@ search_query
      ) as date_matches,
      has_query and (
        position(normalized_query in lower(enriched.structured_text)) > 0
        or to_tsvector('simple', enriched.structured_text) @@ search_query
      ) as structured_matches
    from enriched
  ),
  matched as (
    select
      evaluated.*,
      case
        when not has_query then array['Filters']::text[]
        else array_remove(array[
          case when evaluated.title_matches then 'Title' end,
          case when evaluated.body_matches then 'Body' end,
          case when evaluated.tag_matches then 'Tag' end,
          case when evaluated.date_matches then 'Date' end,
          case when evaluated.structured_matches then 'Details' end
        ], null)
      end as computed_match_reasons,
      (
        case when evaluated.title_matches then 8 else 0 end
        + case when evaluated.body_matches then 4 else 0 end
        + case when evaluated.tag_matches then 3 else 0 end
        + case when evaluated.date_matches then 2 else 0 end
        + case when evaluated.structured_matches then 1 else 0 end
        + coalesce(ts_rank_cd(evaluated.search_document, search_query)::double precision, 0)
      ) as computed_match_rank
    from evaluated
    where not has_query
      or evaluated.title_matches
      or evaluated.body_matches
      or evaluated.tag_matches
      or evaluated.date_matches
      or evaluated.structured_matches
  )
  select
    matched.id,
    matched.title,
    matched.body,
    matched.inbox_status,
    matched.occurred_start,
    matched.occurred_end,
    matched.occurred_label,
    matched.occurred_timezone,
    matched.revision,
    matched.updated_at,
    matched.tag_names,
    matched.computed_match_reasons,
    matched.computed_match_rank,
    count(*) over (),
    matched.date_precision,
    matched.item_kind,
    matched.item_subtype,
    case
      when matched.item_kind = 'entity' and matched.item_subtype = 'person' then 'person'
      else 'entry'
    end,
    matched.id
  from matched
  order by
    case when p_order = 'relevance' then matched.computed_match_rank end desc nulls last,
    case when p_order = 'oldest' then matched.occurred_start end asc nulls last,
    case when p_order <> 'oldest' then coalesce(matched.occurred_start, matched.updated_at) end desc nulls last,
    matched.id
  limit p_limit
  offset p_offset;
end;
$function$;

create function public.timeline_workspace_with_organization(p_include_hidden boolean DEFAULT false)
 RETURNS TABLE(track_id uuid, track_name text, track_system_key text, track_sort_order integer, track_is_hidden boolean, entry_id uuid, title text, body text, item_kind text, item_subtype text, timeline_kind text, item_sort_order integer, occurred_start timestamp with time zone, occurred_end timestamp with time zone, date_precision text, occurred_label text, occurred_timezone text, revision integer, updated_at timestamp with time zone, tag_names text[])
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  timeline_owner_id uuid := auth.uid();
begin
  if timeline_owner_id is null or p_include_hidden is null then
    return;
  end if;

  return query
  with owned_tracks as (
    select track.*
    from public.timeline_tracks as track
    where track.owner_id = timeline_owner_id
      and (p_include_hidden or not track.is_hidden)
  ),
  visible_items as (
    select
      placement.track_id,
      placement.timeline_kind,
      placement.sort_order,
      item.*
    from public.timeline_items as placement
    join public.entries as item
      on item.id = placement.entry_id
      and item.owner_id = placement.owner_id
    where placement.owner_id = timeline_owner_id
      and item.deleted_at is null
  )
  select
    track.id,
    track.name,
    track.system_key,
    track.sort_order,
    track.is_hidden,
    item.id,
    item.title,
    item.body,
    item.item_kind,
    item.item_subtype,
    item.timeline_kind,
    item.sort_order,
    item.occurred_start,
    item.occurred_end,
    item.date_precision,
    item.occurred_label,
    item.occurred_timezone,
    item.revision,
    item.updated_at,
    coalesce((
      select array_agg(tag.name order by lower(tag.name), tag.id)
      from public.entry_tags as membership
      join public.tags as tag
        on tag.id = membership.tag_id
        and tag.owner_id = membership.owner_id
      where membership.entry_id = item.id
        and membership.owner_id = timeline_owner_id
    ), '{}'::text[])
  from owned_tracks as track
  left join visible_items as item on item.track_id = track.id
  order by
    track.sort_order,
    lower(track.name),
    item.occurred_start nulls last,
    item.sort_order,
    item.id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.trash_item_storage_paths(p_item_kind text, p_item_id uuid, p_expected_revision integer, p_expected_deleted_at timestamp with time zone)
 RETURNS TABLE(object_path text)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or p_item_id is null or p_expected_deleted_at is null then return; end if;
  -- Deployed clients remove these paths before delete_trash_item_forever. Nothing
  -- may be removed before the record is deleted, so the manifest is always empty.
  if p_item_kind in ('entry', 'attachment', 'place', 'person') then return; end if;
  raise exception using errcode = '22023', message = 'invalid_trash_item_kind';
end;
$function$;

CREATE OR REPLACE FUNCTION public.trash_workspace(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS TABLE(item_kind text, item_id uuid, title text, detail text, deleted_at timestamp with time zone, expires_at timestamp with time zone, revision integer, wiki_item_kind text, wiki_item_subtype text, parent_entry_id uuid, storage_paths text[], total_count bigint)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null then
    return;
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 100
    or p_offset is null or p_offset < 0 or p_offset > 10000
  then
    raise exception using errcode = '22023', message = 'invalid_trash_page';
  end if;

  return query
  with trash_items as (
    select
      'entry'::text as item_kind,
      item.id as item_id,
      coalesce(
        nullif(btrim(item.title), ''),
        nullif(left(btrim(regexp_replace(item.body, '\s+', ' ', 'g')), 120), ''),
        'Untitled Entry'
      ) as title,
      nullif(left(btrim(regexp_replace(item.body, '\s+', ' ', 'g')), 240), '') as detail,
      item.deleted_at,
      item.deleted_at + interval '30 days' as expires_at,
      item.revision,
      item.item_kind as wiki_item_kind,
      item.item_subtype as wiki_item_subtype,
      null::uuid as parent_entry_id,
      coalesce((
        select array_agg(media.object_path order by media.created_at, media.id)
        from public.attachments as media
        where media.owner_id = item.owner_id
          and media.entry_id = item.id
          and media.bucket_id = 'entry-media'
      ), '{}'::text[]) as storage_paths
    from public.entries as item
    where item.owner_id = auth.uid()
      and item.deleted_at is not null
      and not exists (
        select 1 from public.people as person
        where person.id = item.id and person.owner_id = item.owner_id
      )

    union all

    select
      'attachment'::text,
      media.id,
      coalesce(nullif(btrim(media.original_filename), ''), 'Removed photo'),
      concat('Photo from ', coalesce(
        nullif(btrim(item.title), ''),
        nullif(left(btrim(regexp_replace(item.body, '\s+', ' ', 'g')), 80), ''),
        'Untitled Entry'
      )),
      media.deleted_at,
      media.deleted_at + interval '30 days',
      null::integer,
      null::text,
      null::text,
      item.id,
      array[media.object_path]::text[]
    from public.attachments as media
    join public.entries as item
      on item.id = media.entry_id and item.owner_id = media.owner_id
    where media.owner_id = auth.uid()
      and media.deleted_at is not null
      and media.variant = 'original'
      and item.deleted_at is null


    union all

    select
      'person'::text,
      person.id,
      person.name,
      person.relationship_label,
      person.deleted_at,
      person.deleted_at + interval '30 days',
      person.revision,
      'entity'::text,
      'person'::text,
      null::uuid,
      '{}'::text[]
    from public.people as person
    where person.owner_id = auth.uid() and person.deleted_at is not null
  ),
  counted as (
    select trash_items.*, count(*) over () as total_count
    from trash_items
  )
  select counted.*
  from counted
  order by counted.deleted_at desc, counted.item_kind, counted.item_id
  limit p_limit
  offset p_offset;
end;
$function$;

create function public.vehicles_workspace(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS TABLE(entry_id uuid, title text, body text, occurred_start timestamp with time zone, occurred_end timestamp with time zone, date_precision text, occurred_label text, occurred_timezone text, revision integer, updated_at timestamp with time zone, make text, model text, model_year integer, color text, timeline_track_id uuid, timeline_track_name text, tag_names text[], attachments jsonb, total_count bigint)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  vehicle_owner_id uuid := auth.uid();
begin
  if vehicle_owner_id is null then
    return;
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 100
    or p_offset is null or p_offset < 0 or p_offset > 10000
  then
    raise exception using errcode = '22023', message = 'invalid_vehicles_page';
  end if;

  return query
  with visible_vehicles as (
    select
      entries.id as entry_id,
      entries.title,
      entries.body,
      entries.occurred_start,
      entries.occurred_end,
      entries.date_precision,
      entries.occurred_label,
      entries.occurred_timezone,
      entries.revision,
      entries.updated_at,
      vehicles.make,
      vehicles.model,
      vehicles.model_year,
      vehicles.color,
      timeline_tracks.id as timeline_track_id,
      timeline_tracks.name as timeline_track_name,
      coalesce(
        (
          select array_agg(tags.name order by lower(tags.name), tags.id)
          from public.entry_tags
          join public.tags
            on tags.id = entry_tags.tag_id
            and tags.owner_id = entry_tags.owner_id
          where entry_tags.entry_id = entries.id
            and entry_tags.owner_id = vehicle_owner_id
        ),
        array[]::text[]
      ) as tag_names,
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', attachments.id,
              'bucket_id', attachments.bucket_id,
              'object_path', attachments.object_path,
              'original_filename', attachments.original_filename,
              'mime_type', attachments.mime_type,
              'byte_size', attachments.byte_size,
              'pixel_width', attachments.pixel_width,
              'pixel_height', attachments.pixel_height,
              'created_at', attachments.created_at
            )
            order by attachments.created_at, attachments.id
          )
          from public.attachments
          where attachments.entry_id = entries.id
            and attachments.owner_id = vehicle_owner_id
            and attachments.deleted_at is null
            and attachments.variant = 'original'
        ),
        '[]'::jsonb
      ) as attachments
    from public.entries
    join public.vehicles
      on vehicles.entry_id = entries.id
      and vehicles.owner_id = entries.owner_id
    left join public.timeline_items
      on timeline_items.entry_id = entries.id
      and timeline_items.owner_id = entries.owner_id
      and exists (
        select 1
        from public.timeline_tracks as vehicle_tracks
        where vehicle_tracks.id = timeline_items.track_id
          and vehicle_tracks.owner_id = timeline_items.owner_id
          and vehicle_tracks.system_key = 'vehicles'
      )
    left join public.timeline_tracks
      on timeline_tracks.id = timeline_items.track_id
      and timeline_tracks.owner_id = timeline_items.owner_id
      and timeline_tracks.system_key = 'vehicles'
    where entries.owner_id = vehicle_owner_id
      and entries.item_kind = 'entity' and entries.item_subtype = 'vehicle'
      and entries.deleted_at is null
  ),
  counted_vehicles as (
    select visible_vehicles.*, count(*) over () as total_count
    from visible_vehicles
  )
  select counted_vehicles.*
  from counted_vehicles
  order by
    (counted_vehicles.occurred_end is null) desc,
    counted_vehicles.occurred_start desc nulls last,
    lower(counted_vehicles.title),
    counted_vehicles.entry_id
  limit p_limit
  offset p_offset;
end;
$function$;

revoke all on function public.review_wiki_item_with_occurrence_rich(p_entry_id uuid, p_expected_revision integer, p_title text, p_body text, p_item_kind text, p_item_subtype text, p_occurred_start timestamp with time zone, p_occurred_timezone text, p_tag_names text[], p_mark_done boolean, p_occurred_end timestamp with time zone, p_occurred_label text, p_date_precision text, p_body_rich jsonb, p_preserve_rich_text boolean) from public, anon, authenticated;
revoke all on function public.review_wiki_item_with_photo_place_core(p_entry_id uuid, p_expected_revision integer, p_title text, p_body text, p_item_kind text, p_item_subtype text, p_occurred_start timestamp with time zone, p_occurred_timezone text, p_tag_names text[], p_mark_done boolean, p_occurred_end timestamp with time zone, p_occurred_label text, p_date_precision text, p_photo_place jsonb, p_body_rich jsonb, p_preserve_rich_text boolean) from public, anon, authenticated;
revoke all on function public.review_wiki_item_with_photo_place(p_entry_id uuid, p_expected_revision integer, p_title text, p_body text, p_item_kind text, p_item_subtype text, p_occurred_start timestamp with time zone, p_occurred_timezone text, p_tag_names text[], p_mark_done boolean, p_occurred_end timestamp with time zone, p_occurred_label text, p_date_precision text, p_photo_place jsonb) from public, anon;
grant execute on function public.review_wiki_item_with_photo_place(p_entry_id uuid, p_expected_revision integer, p_title text, p_body text, p_item_kind text, p_item_subtype text, p_occurred_start timestamp with time zone, p_occurred_timezone text, p_tag_names text[], p_mark_done boolean, p_occurred_end timestamp with time zone, p_occurred_label text, p_date_precision text, p_photo_place jsonb) to authenticated;
revoke all on function public.review_wiki_item_with_photo_place_rich(p_entry_id uuid, p_expected_revision integer, p_title text, p_body text, p_item_kind text, p_item_subtype text, p_occurred_start timestamp with time zone, p_occurred_timezone text, p_tag_names text[], p_mark_done boolean, p_occurred_end timestamp with time zone, p_occurred_label text, p_date_precision text, p_photo_place jsonb, p_body_rich jsonb) from public, anon;
grant execute on function public.review_wiki_item_with_photo_place_rich(p_entry_id uuid, p_expected_revision integer, p_title text, p_body text, p_item_kind text, p_item_subtype text, p_occurred_start timestamp with time zone, p_occurred_timezone text, p_tag_names text[], p_mark_done boolean, p_occurred_end timestamp with time zone, p_occurred_label text, p_date_precision text, p_photo_place jsonb, p_body_rich jsonb) to authenticated;
revoke all on function public.review_wiki_item_with_location_rich(p_entry_id uuid, p_expected_revision integer, p_title text, p_body text, p_item_kind text, p_item_subtype text, p_occurred_start timestamp with time zone, p_occurred_timezone text, p_tag_names text[], p_mark_done boolean, p_occurred_end timestamp with time zone, p_occurred_label text, p_date_precision text, p_photo_place jsonb, p_primary_location jsonb, p_body_rich jsonb) from public, anon;
grant execute on function public.review_wiki_item_with_location_rich(p_entry_id uuid, p_expected_revision integer, p_title text, p_body text, p_item_kind text, p_item_subtype text, p_occurred_start timestamp with time zone, p_occurred_timezone text, p_tag_names text[], p_mark_done boolean, p_occurred_end timestamp with time zone, p_occurred_label text, p_date_precision text, p_photo_place jsonb, p_primary_location jsonb, p_body_rich jsonb) to authenticated;
revoke all on function public.save_first_time_with_occurrence(p_title text, p_body text, p_occurred_start timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_tag_names text[], p_entry_id uuid, p_expected_revision integer, p_occurred_end timestamp with time zone) from public, anon;
grant execute on function public.save_first_time_with_occurrence(p_title text, p_body text, p_occurred_start timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_tag_names text[], p_entry_id uuid, p_expected_revision integer, p_occurred_end timestamp with time zone) to authenticated;
revoke all on function public.save_home_entry_with_occurrence(p_title text, p_body text, p_occurred_start timestamp with time zone, p_occurred_end timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_place_id uuid, p_place_name text, p_address text, p_city text, p_region text, p_country text, p_latitude numeric, p_longitude numeric, p_place_notes text, p_move_in_reason text, p_move_out_reason text, p_tag_names text[], p_entry_id uuid, p_expected_revision integer) from public, anon;
grant execute on function public.save_home_entry_with_occurrence(p_title text, p_body text, p_occurred_start timestamp with time zone, p_occurred_end timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_place_id uuid, p_place_name text, p_address text, p_city text, p_region text, p_country text, p_latitude numeric, p_longitude numeric, p_place_notes text, p_move_in_reason text, p_move_out_reason text, p_tag_names text[], p_entry_id uuid, p_expected_revision integer) to authenticated;
revoke all on function public.save_home_entry(p_title text, p_body text, p_occurred_start timestamp with time zone, p_occurred_end timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_place_id uuid, p_place_name text, p_address text, p_city text, p_region text, p_country text, p_latitude numeric, p_longitude numeric, p_place_notes text, p_move_in_reason text, p_move_out_reason text, p_tag_names text[], p_entry_id uuid, p_expected_revision integer) from public, anon;
grant execute on function public.save_home_entry(p_title text, p_body text, p_occurred_start timestamp with time zone, p_occurred_end timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_place_id uuid, p_place_name text, p_address text, p_city text, p_region text, p_country text, p_latitude numeric, p_longitude numeric, p_place_notes text, p_move_in_reason text, p_move_out_reason text, p_tag_names text[], p_entry_id uuid, p_expected_revision integer) to authenticated;
revoke all on function public.extract_capture_to_home(p_capture_id uuid, p_capture_revision integer, p_title text, p_body text, p_occurred_start timestamp with time zone, p_occurred_end timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_place_id uuid, p_place_name text, p_address text, p_city text, p_region text, p_country text, p_latitude numeric, p_longitude numeric, p_place_notes text, p_move_in_reason text, p_move_out_reason text, p_tag_names text[]) from public, anon;
grant execute on function public.extract_capture_to_home(p_capture_id uuid, p_capture_revision integer, p_title text, p_body text, p_occurred_start timestamp with time zone, p_occurred_end timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_place_id uuid, p_place_name text, p_address text, p_city text, p_region text, p_country text, p_latitude numeric, p_longitude numeric, p_place_notes text, p_move_in_reason text, p_move_out_reason text, p_tag_names text[]) to authenticated;
revoke all on function public.save_vehicle_entry_with_occurrence(p_title text, p_body text, p_occurred_start timestamp with time zone, p_occurred_end timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_make text, p_model text, p_model_year integer, p_color text, p_tag_names text[], p_entry_id uuid, p_expected_revision integer) from public, anon;
grant execute on function public.save_vehicle_entry_with_occurrence(p_title text, p_body text, p_occurred_start timestamp with time zone, p_occurred_end timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_make text, p_model text, p_model_year integer, p_color text, p_tag_names text[], p_entry_id uuid, p_expected_revision integer) to authenticated;
revoke all on function public.save_vehicle_entry(p_title text, p_body text, p_occurred_start timestamp with time zone, p_occurred_end timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_make text, p_model text, p_model_year integer, p_color text, p_tag_names text[], p_entry_id uuid, p_expected_revision integer) from public, anon;
grant execute on function public.save_vehicle_entry(p_title text, p_body text, p_occurred_start timestamp with time zone, p_occurred_end timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_make text, p_model text, p_model_year integer, p_color text, p_tag_names text[], p_entry_id uuid, p_expected_revision integer) to authenticated;
revoke all on function public.extract_capture_to_vehicle(p_capture_id uuid, p_capture_revision integer, p_title text, p_body text, p_occurred_start timestamp with time zone, p_occurred_end timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_make text, p_model text, p_model_year integer, p_color text, p_tag_names text[]) from public, anon;
grant execute on function public.extract_capture_to_vehicle(p_capture_id uuid, p_capture_revision integer, p_title text, p_body text, p_occurred_start timestamp with time zone, p_occurred_end timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_make text, p_model text, p_model_year integer, p_color text, p_tag_names text[]) to authenticated;
revoke all on function public.save_goal_entry(p_title text, p_body text, p_horizon text, p_status text, p_target_date date, p_tag_names text[], p_related_entry_ids uuid[], p_entry_id uuid, p_expected_revision integer) from public, anon;
grant execute on function public.save_goal_entry(p_title text, p_body text, p_horizon text, p_status text, p_target_date date, p_tag_names text[], p_related_entry_ids uuid[], p_entry_id uuid, p_expected_revision integer) to authenticated;
revoke all on function public.extract_capture_to_goal(p_capture_id uuid, p_capture_revision integer, p_title text, p_body text, p_horizon text, p_status text, p_target_date date, p_tag_names text[], p_related_entry_ids uuid[]) from public, anon;
grant execute on function public.extract_capture_to_goal(p_capture_id uuid, p_capture_revision integer, p_title text, p_body text, p_horizon text, p_status text, p_target_date date, p_tag_names text[], p_related_entry_ids uuid[]) to authenticated;
revoke all on function public.archive_wiki_search_evidence(p_queries text[], p_item_classifications text[], p_tag_names text[], p_date_from date, p_date_to date, p_before_latest_home boolean, p_order text, p_as_of date) from public, anon;
grant execute on function public.archive_wiki_search_evidence(p_queries text[], p_item_classifications text[], p_tag_names text[], p_date_from date, p_date_to date, p_before_latest_home boolean, p_order text, p_as_of date) to authenticated;
revoke all on function public.first_times_workspace_with_occurrence() from public, anon;
grant execute on function public.first_times_workspace_with_occurrence() to authenticated;
revoke all on function public.goals_workspace(p_limit integer, p_offset integer) from public, anon;
grant execute on function public.goals_workspace(p_limit integer, p_offset integer) to authenticated;
revoke all on function public.home_resurfaced_memory(p_local_date date, p_timezone text) from public, anon;
grant execute on function public.home_resurfaced_memory(p_local_date date, p_timezone text) to authenticated;
revoke all on function public.home_workspace(p_local_date date, p_timezone text, p_recent_limit integer) from public, anon;
grant execute on function public.home_workspace(p_local_date date, p_timezone text, p_recent_limit integer) to authenticated;
revoke all on function public.homes_workspace(p_limit integer, p_offset integer) from public, anon;
grant execute on function public.homes_workspace(p_limit integer, p_offset integer) to authenticated;
revoke all on function public.save_timeline_entry_with_organization(p_track_id uuid, p_timeline_kind text, p_title text, p_body text, p_occurred_start timestamp with time zone, p_occurred_end timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_tag_names text[], p_entry_id uuid, p_expected_revision integer) from public, anon;
grant execute on function public.save_timeline_entry_with_organization(p_track_id uuid, p_timeline_kind text, p_title text, p_body text, p_occurred_start timestamp with time zone, p_occurred_end timestamp with time zone, p_date_precision text, p_occurred_label text, p_occurred_timezone text, p_tag_names text[], p_entry_id uuid, p_expected_revision integer) to authenticated;
revoke all on function public.search_wiki_items(p_query text, p_item_classifications text[], p_tag_names text[], p_date_from date, p_date_to date, p_limit integer, p_offset integer, p_order text) from public, anon;
grant execute on function public.search_wiki_items(p_query text, p_item_classifications text[], p_tag_names text[], p_date_from date, p_date_to date, p_limit integer, p_offset integer, p_order text) to authenticated;
revoke all on function public.timeline_workspace_with_organization(p_include_hidden boolean) from public, anon;
grant execute on function public.timeline_workspace_with_organization(p_include_hidden boolean) to authenticated;
revoke all on function public.vehicles_workspace(p_limit integer, p_offset integer) from public, anon;
grant execute on function public.vehicles_workspace(p_limit integer, p_offset integer) to authenticated;
