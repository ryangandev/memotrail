-- One Entry editor now makes a Chapter and marks a First Time. save_entry drops its milestone
-- argument and takes two marks instead: whether the Entry is a Chapter (a named stretch of
-- time with a start and an optional end) and whether it is a First Time. One save turns an
-- Entry into a Chapter or back, and checks or unchecks First Time, keeping its tags, Location,
-- and photos. A Chapter needs a title, and may carry a Day, Month, or Year with an end.
--
-- editable_entry and entry_detail lose the milestone object; the marks arrive with the Entry
-- itself as item_subtype and is_first_time.

begin;

drop function public.save_entry(
  uuid, integer, text, text, jsonb, timestamptz, timestamptz, text, text, text, text[], jsonb, jsonb, jsonb
);

create function public.save_entry(
  p_entry_id uuid,
  p_expected_revision integer,
  p_title text,
  p_body text,
  p_body_rich jsonb,
  p_occurred_start timestamptz,
  p_occurred_end timestamptz,
  p_occurred_timezone text,
  p_occurred_label text,
  p_date_precision text,
  p_tag_names text[],
  p_primary_location jsonb,
  p_photo_location jsonb,
  p_is_chapter boolean,
  p_is_first_time boolean
)
returns table (entry_id uuid, revision integer)
language plpgsql
set search_path = ''
as $$
declare
  entry_owner_id uuid := auth.uid();
  saved_entry_id uuid;
  saved_revision integer;
  photo_attachment_id uuid;
  photo_latitude numeric;
  photo_longitude numeric;
  photo_location_id uuid;
begin
  if entry_owner_id is null then
    return;
  end if;
  if p_entry_id is null then
    raise exception using errcode = '22023', message = 'invalid_entry';
  end if;
  if p_expected_revision is not null and p_expected_revision < 1 then
    raise exception using errcode = '22023', message = 'invalid_revision';
  end if;
  if p_is_chapter is null or p_is_first_time is null then
    raise exception using errcode = '22023', message = 'invalid_entry_marks';
  end if;

  p_title := nullif(btrim(p_title), '');
  p_body := btrim(coalesce(p_body, ''));
  if p_is_chapter and p_title is null then
    raise exception using errcode = '22023', message = 'chapter_requires_title';
  end if;
  if p_title is null and p_body = '' then
    raise exception using errcode = '22023', message = 'empty_entry';
  end if;
  if length(coalesce(p_title, '')) > 200 or length(p_body) > 50000 then
    raise exception using errcode = '22023', message = 'entry_content_too_long';
  end if;
  if p_body_rich is not null and (
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
    or (
      p_occurred_end is not null
      and p_date_precision not in ('range','approximate','age')
      and not p_is_chapter
    )
    or (p_occurred_start is not null and not isfinite(p_occurred_start))
    or (p_occurred_end is not null and not isfinite(p_occurred_end))
  then
    raise exception using errcode = '22023', message = 'invalid_occurrence';
  end if;

  if not public.valid_tag_names(p_tag_names) then
    raise exception using errcode = '22023', message = 'invalid_tags';
  end if;

  if p_photo_location is not null and p_photo_location <> 'null'::jsonb then
    -- A new Entry has no photos yet.
    if p_expected_revision is null
      or jsonb_typeof(p_photo_location) <> 'object'
      or coalesce(p_photo_location->>'attachmentId', '') !~* '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'
      or jsonb_typeof(p_photo_location->'latitude') is distinct from 'number'
      or jsonb_typeof(p_photo_location->'longitude') is distinct from 'number'
    then
      raise exception using errcode = '22023', message = 'invalid_photo_location';
    end if;
    photo_attachment_id := (p_photo_location->>'attachmentId')::uuid;
    photo_latitude := (p_photo_location->>'latitude')::numeric;
    photo_longitude := (p_photo_location->>'longitude')::numeric;
    if photo_latitude not between -90 and 90 or photo_longitude not between -180 and 180 then
      raise exception using errcode = '22023', message = 'invalid_photo_location';
    end if;
  end if;

  if p_expected_revision is null then
    insert into public.entries (
      id, owner_id, title, body, metadata, item_kind, item_subtype, is_first_time,
      occurred_start, occurred_end, occurred_label, date_precision, occurred_timezone
    )
    values (
      p_entry_id,
      entry_owner_id,
      p_title,
      p_body,
      case when p_body_rich is null then '{}'::jsonb else jsonb_build_object('body_rich', p_body_rich) end,
      'entry',
      case when p_is_chapter then 'chapter' else 'entry' end,
      p_is_first_time,
      p_occurred_start,
      p_occurred_end,
      p_occurred_label,
      p_date_precision,
      btrim(p_occurred_timezone)
    )
    on conflict on constraint entries_pkey do nothing
    returning entries.id, entries.revision
    into saved_entry_id, saved_revision;
  else
    update public.entries as item
    set
      title = p_title,
      body = p_body,
      metadata = case
        when p_body_rich is null then item.metadata - 'body_rich'
        else jsonb_set(item.metadata, '{body_rich}', p_body_rich, true)
      end,
      item_subtype = case when p_is_chapter then 'chapter' else 'entry' end,
      is_first_time = p_is_first_time,
      occurred_start = p_occurred_start,
      occurred_end = p_occurred_end,
      occurred_label = p_occurred_label,
      date_precision = p_date_precision,
      occurred_timezone = btrim(p_occurred_timezone)
    where item.id = p_entry_id
      and item.owner_id = entry_owner_id
      and item.revision = p_expected_revision
      and item.item_kind = 'entry'
      and item.deleted_at is null
    returning item.id, item.revision
    into saved_entry_id, saved_revision;
  end if;

  if saved_entry_id is null then
    return;
  end if;

  perform public.replace_entry_tags(saved_entry_id, p_tag_names);
  perform public.replace_primary_location(saved_entry_id, p_primary_location);

  if photo_attachment_id is not null then
    if not public.lock_photo_place_source(saved_entry_id, photo_attachment_id) then
      raise exception using errcode = '40001', message = 'photo_source_changed';
    end if;
    insert into public.locations (owner_id, latitude, longitude)
    values (entry_owner_id, round(photo_latitude, 6), round(photo_longitude, 6))
    returning locations.id into photo_location_id;
    insert into public.entry_locations (entry_id, location_id, owner_id, relationship)
    values (saved_entry_id, photo_location_id, entry_owner_id, 'photo');
    perform public.record_photo_location_source(
      photo_location_id, saved_entry_id, photo_attachment_id
    );
  end if;

  return query
  select saved_entry_id, saved_revision;
end;
$$;

revoke all on function public.save_entry(
  uuid, integer, text, text, jsonb, timestamptz, timestamptz, text, text, text, text[], jsonb, jsonb, boolean, boolean
) from public, anon;
grant execute on function public.save_entry(
  uuid, integer, text, text, jsonb, timestamptz, timestamptz, text, text, text, text[], jsonb, jsonb, boolean, boolean
) to authenticated, service_role;

-- The marks arrive through to_jsonb(e) as item_subtype and is_first_time.
create or replace function public.editable_entry(p_entry_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
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
      from public.entry_locations as link
      join public.locations as location
        on location.id = link.location_id
        and location.owner_id = link.owner_id
      where link.entry_id = e.id
        and link.owner_id = auth.uid()
        and link.relationship = 'primary'
      order by link.created_at desc, location.id
      limit 1
    )
  )
  from public.entries e
  where e.id = p_entry_id
    and e.owner_id = auth.uid()
    and e.deleted_at is null
    and e.item_kind = 'entry';
$$;

create or replace function public.entry_detail(p_entry_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select (to_jsonb(entry) - 'embedding' - 'search_document') || jsonb_build_object(
    'tags', coalesce((
      select jsonb_agg(jsonb_build_object('id', tag.id, 'name', tag.name) order by tag.name)
      from public.entry_tags as membership
      join public.tags as tag on tag.id = membership.tag_id
      where membership.entry_id = entry.id
    ), '[]'::jsonb),
    'locations', coalesce((
      select jsonb_agg(jsonb_build_object(
          'location_id', link.location_id,
          'relationship', link.relationship,
          'formatted_address', location.formatted_address,
          'latitude', location.latitude,
          'longitude', location.longitude
        ) order by link.relationship, link.location_id)
      from public.entry_locations as link
      join public.locations as location on location.id = link.location_id
      where link.entry_id = entry.id
    ), '[]'::jsonb),
    'links', coalesce((
      select jsonb_agg(jsonb_build_object('target_entry_id', link.target_entry_id, 'relationship', link.relationship)
        order by link.target_entry_id, link.relationship)
      from public.entry_links as link
      where link.source_entry_id = entry.id
    ), '[]'::jsonb)
  )
  from public.entries as entry
  where entry.id = p_entry_id and entry.owner_id = auth.uid();
$$;

commit;
