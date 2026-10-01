-- History compares content, not the write bookkeeping of related rows.
-- Preserve stable IDs, restore inputs, metadata, and the version envelope.
create function public.normalize_entry_history_snapshot(p_snapshot jsonb)
returns jsonb
language plpgsql
immutable
strict
set search_path = ''
as $$
declare
  normalized jsonb := p_snapshot;
  field text;
  rows jsonb;
begin
  foreach field in array array['people', 'places', 'timeline_items', 'links', 'attachments'] loop
    if jsonb_typeof(normalized->field) = 'array' then
      select coalesce(jsonb_agg(
        case when field = 'attachments'
          then value - array['created_at', 'updated_at', 'deleted_at']
          else value - array['created_at', 'updated_at']
        end order by position
      ), '[]'::jsonb)
      into rows
      from jsonb_array_elements(normalized->field) with ordinality as relation(value, position);
      normalized := jsonb_set(normalized, array[field], rows);
    end if;
  end loop;
  foreach field in array array['home', 'vehicle', 'goal', 'place'] loop
    if jsonb_typeof(normalized->field) = 'object' then
      normalized := jsonb_set(normalized, array[field],
        (normalized->field) - array['created_at', 'updated_at']);
    end if;
  end loop;
  return normalized;
end;
$$;
revoke all on function public.normalize_entry_history_snapshot(jsonb) from public, anon, authenticated;

-- Newly archived snapshots use the same content contract; restore needs no timestamps.
CREATE OR REPLACE FUNCTION public.entry_history_snapshot(p_entry public.entries)
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
    'collections', coalesce((
      select jsonb_agg(jsonb_build_object('id', collection.id, 'name', collection.name) order by collection.name)
      from public.entry_collections as membership
      join public.collections as collection on collection.id = membership.collection_id
      where membership.entry_id = p_entry.id
    ), '[]'::jsonb),
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

-- Normalize both sides at read time so immutable pre-migration versions work.
create or replace function public.entry_history(
  p_entry_id uuid, p_limit integer default 20, p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  current_entry public.entries;
begin
  if p_limit is null or p_limit not between 1 and 20
    or p_offset is null or p_offset not between 0 and 100000
  then
    raise exception using errcode = '22023', message = 'invalid_history_page';
  end if;
  select * into current_entry
  from public.entries where id = p_entry_id and owner_id = auth.uid();
  if not found then return null; end if;
  return jsonb_build_object(
    'current', public.normalize_entry_history_snapshot(public.entry_history_snapshot(current_entry)) - 'embedding' - 'search_document',
    'total_count', (select count(*) from public.entry_versions where entry_id = p_entry_id),
    'versions', (
      select coalesce(jsonb_agg(
        to_jsonb(saved_version) || jsonb_build_object('snapshot',
          public.normalize_entry_history_snapshot(saved_version.snapshot) - 'embedding' - 'search_document')
        order by saved_version.version desc
      ), '[]'::jsonb)
      from (
        select version, operation, snapshot, created_at
        from public.entry_versions where entry_id = p_entry_id
        order by version desc limit p_limit offset p_offset
      ) as saved_version
    )
  );
end;
$$;

-- Keep existing validation, locks, revision checks, and ACLs intact.
-- Fail migration if a writer no longer has the exact expected fragment.
create function pg_temp.replace_history_writer_fragment(p_function regprocedure, p_old text, p_new text)
returns void language plpgsql as $$
declare
  definition text := pg_get_functiondef(p_function);
begin
  if length(definition) - length(replace(definition, p_old, '')) <> length(p_old) then
    raise exception 'History writer % changed unexpectedly', p_function;
  end if;
  execute replace(definition, p_old, p_new);
end;
$$;

-- Detail updates should advance updated_at only when their facts change.
select pg_temp.replace_history_writer_fragment(
  'public.save_home_entry_with_occurrence(text, text, timestamp with time zone, timestamp with time zone, text, text, text, uuid, text, text, text, text, text, numeric, numeric, text, text, text, text[], text[], uuid, integer)'::regprocedure,
$old$    move_out_reason = excluded.move_out_reason;$old$,
$new$    move_out_reason = excluded.move_out_reason
  where (homes.place_id, homes.move_in_reason, homes.move_out_reason)
    is distinct from (excluded.place_id, excluded.move_in_reason, excluded.move_out_reason);$new$
);

select pg_temp.replace_history_writer_fragment(
  'public.save_vehicle_entry_with_occurrence(text, text, timestamp with time zone, timestamp with time zone, text, text, text, text, text, integer, text, text[], text[], uuid, integer)'::regprocedure,
$old$    color = excluded.color;$old$,
$new$    color = excluded.color
  where (vehicles.make, vehicles.model, vehicles.model_year, vehicles.color)
    is distinct from (excluded.make, excluded.model, excluded.model_year, excluded.color);$new$
);

select pg_temp.replace_history_writer_fragment(
  'public.save_goal_entry(text, text, text, text, date, text[], text[], uuid[], uuid, integer)'::regprocedure,
$old$    target_date = excluded.target_date;$old$,
$new$    target_date = excluded.target_date
  where (goals.horizon, goals.status, goals.target_date)
    is distinct from (excluded.horizon, excluded.status, excluded.target_date);$new$
);

-- Keep the same Home Location link, including its original created_at.
select pg_temp.replace_history_writer_fragment(
  'public.save_home_entry_with_occurrence(text, text, timestamp with time zone, timestamp with time zone, text, text, text, uuid, text, text, text, text, text, numeric, numeric, text, text, text, text[], text[], uuid, integer)'::regprocedure,
$old$    and entry_places.relationship = 'home';$old$,
$new$    and entry_places.relationship = 'home'
    and entry_places.place_id is distinct from saved_place_id;$new$
);

select pg_temp.replace_history_writer_fragment(
  'public.save_home_entry_with_occurrence(text, text, timestamp with time zone, timestamp with time zone, text, text, text, uuid, text, text, text, text, text, numeric, numeric, text, text, text, text[], text[], uuid, integer)'::regprocedure,
$old$      'home'
    );$old$,
$new$      'home'
    ) on conflict on constraint entry_places_pkey do nothing;$new$
);

-- The focused forms own the selected track and kind, not presentation order.
select pg_temp.replace_history_writer_fragment(
  'public.save_home_entry_with_occurrence(text, text, timestamp with time zone, timestamp with time zone, text, text, text, uuid, text, text, text, text, text, numeric, numeric, text, text, text, text[], text[], uuid, integer)'::regprocedure,
$old$  delete from public.timeline_items
  where timeline_items.entry_id = saved_entry_id
    and timeline_items.owner_id = home_owner_id;$old$,
$new$  delete from public.timeline_items
  where timeline_items.entry_id = saved_entry_id
    and timeline_items.owner_id = home_owner_id
    and timeline_items.track_id is distinct from home_track_id;$new$
);

select pg_temp.replace_history_writer_fragment(
  'public.save_home_entry_with_occurrence(text, text, timestamp with time zone, timestamp with time zone, text, text, text, uuid, text, text, text, text, text, numeric, numeric, text, text, text, text[], text[], uuid, integer)'::regprocedure,
$old$    home_owner_id,
    'stage'
  );$old$,
$new$    home_owner_id,
    'stage'
  )
  on conflict on constraint timeline_items_pkey do update
  set timeline_kind = excluded.timeline_kind
  where timeline_items.timeline_kind is distinct from excluded.timeline_kind;$new$
);

select pg_temp.replace_history_writer_fragment(
  'public.save_vehicle_entry_with_occurrence(text, text, timestamp with time zone, timestamp with time zone, text, text, text, text, text, integer, text, text[], text[], uuid, integer)'::regprocedure,
$old$  delete from public.timeline_items
  where timeline_items.entry_id = saved_entry_id
    and timeline_items.owner_id = vehicle_owner_id;$old$,
$new$  delete from public.timeline_items
  where timeline_items.entry_id = saved_entry_id
    and timeline_items.owner_id = vehicle_owner_id
    and timeline_items.track_id is distinct from vehicle_track_id;$new$
);

select pg_temp.replace_history_writer_fragment(
  'public.save_vehicle_entry_with_occurrence(text, text, timestamp with time zone, timestamp with time zone, text, text, text, text, text, integer, text, text[], text[], uuid, integer)'::regprocedure,
$old$    vehicle_owner_id,
    'stage'
  );$old$,
$new$    vehicle_owner_id,
    'stage'
  )
  on conflict on constraint timeline_items_pkey do update
  set timeline_kind = excluded.timeline_kind
  where timeline_items.timeline_kind is distinct from excluded.timeline_kind;$new$
);

select pg_temp.replace_history_writer_fragment(
  'public.save_timeline_entry_with_occurrence(uuid, text, text, text, timestamp with time zone, timestamp with time zone, text, text, text, uuid, integer)'::regprocedure,
$old$  delete from public.timeline_items as items
  where items.entry_id = saved_entry_id
    and items.owner_id = timeline_owner_id;$old$,
$new$  delete from public.timeline_items as items
  where items.entry_id = saved_entry_id
    and items.owner_id = timeline_owner_id
    and items.track_id is distinct from p_track_id;$new$
);

select pg_temp.replace_history_writer_fragment(
  'public.save_timeline_entry_with_occurrence(uuid, text, text, text, timestamp with time zone, timestamp with time zone, text, text, text, uuid, integer)'::regprocedure,
$old$    timeline_owner_id,
    p_timeline_kind
  );$old$,
$new$    timeline_owner_id,
    p_timeline_kind
  )
  on conflict on constraint timeline_items_pkey do update
  set timeline_kind = excluded.timeline_kind
  where timeline_items.timeline_kind is distinct from excluded.timeline_kind;$new$
);

-- Location-aware Entry, First Time, and Vehicle saves share the same no-op rule.
select pg_temp.replace_history_writer_fragment(
  'public.review_wiki_item_with_location_rich(uuid, integer, text, text, text, text, timestamp with time zone, text, text[], text[], boolean, timestamp with time zone, text, text, jsonb, jsonb, jsonb)'::regprocedure,
$old$  delete from public.entry_places as link
  where link.entry_id = reviewed.entry_id
    and link.owner_id = review_owner_id
    and link.relationship = 'primary';$old$,
$new$  delete from public.entry_places as link
  where link.entry_id = reviewed.entry_id
    and link.owner_id = review_owner_id
    and link.relationship = 'primary'
    and link.place_id is distinct from target_location_id;$new$
);

select pg_temp.replace_history_writer_fragment(
  'public.review_wiki_item_with_location_rich(uuid, integer, text, text, text, text, timestamp with time zone, text, text[], text[], boolean, timestamp with time zone, text, text, jsonb, jsonb, jsonb)'::regprocedure,
$old$on conflict on constraint entry_places_pkey do update
    set relationship = excluded.relationship;$old$,
$new$on conflict on constraint entry_places_pkey do nothing;$new$
);

select pg_temp.replace_history_writer_fragment(
  'public.save_first_time_with_location(jsonb, jsonb)'::regprocedure,
$old$  delete from public.entry_places as link
  where link.entry_id = saved.entry_id
    and link.owner_id = first_time_owner_id
    and link.relationship = 'primary';$old$,
$new$  delete from public.entry_places as link
  where link.entry_id = saved.entry_id
    and link.owner_id = first_time_owner_id
    and link.relationship = 'primary'
    and link.place_id is distinct from selected_location_id;$new$
);

select pg_temp.replace_history_writer_fragment(
  'public.save_first_time_with_location(jsonb, jsonb)'::regprocedure,
$old$    values (saved.entry_id, selected_location_id, first_time_owner_id, 'primary');$old$,
$new$    values (saved.entry_id, selected_location_id, first_time_owner_id, 'primary')
    on conflict on constraint entry_places_pkey do nothing;$new$
);

select pg_temp.replace_history_writer_fragment(
  'public.save_vehicle_with_location(jsonb, jsonb, jsonb)'::regprocedure,
$old$  delete from public.entry_places as link
  where link.entry_id = saved_entry_id
    and link.owner_id = vehicle_owner_id
    and link.relationship = 'primary';$old$,
$new$  delete from public.entry_places as link
  where link.entry_id = saved_entry_id
    and link.owner_id = vehicle_owner_id
    and link.relationship = 'primary'
    and link.place_id is distinct from selected_location_id;$new$
);

select pg_temp.replace_history_writer_fragment(
  'public.save_vehicle_with_location(jsonb, jsonb, jsonb)'::regprocedure,
$old$    values (saved_entry_id, selected_location_id, vehicle_owner_id, 'primary');$old$,
$new$    values (saved_entry_id, selected_location_id, vehicle_owner_id, 'primary')
    on conflict on constraint entry_places_pkey do nothing;$new$
);

-- Goal links and Person memberships also retain unchanged relationship rows.
select pg_temp.replace_history_writer_fragment(
  'public.save_goal_entry(text, text, text, text, date, text[], text[], uuid[], uuid, integer)'::regprocedure,
$old$    and entry_links.relationship = 'related'
    and exists ($old$,
$new$    and entry_links.relationship = 'related'
    and not (entry_links.target_entry_id = any(coalesce(p_related_entry_ids, '{}'::uuid[])))
    and exists ($new$
);

select pg_temp.replace_history_writer_fragment(
  'public.save_person(text, text, text, uuid[], uuid, integer)'::regprocedure,
$old$  delete from public.entry_people ep where ep.person_id = saved_id and ep.owner_id = auth.uid();$old$,
$new$  delete from public.entry_people ep
  where ep.person_id = saved_id and ep.owner_id = auth.uid()
    and (not (ep.entry_id = any(p_related_entry_ids)) or ep.relationship <> 'related');$new$
);

select pg_temp.replace_history_writer_fragment(
  'public.save_person(text, text, text, uuid[], uuid, integer)'::regprocedure,
$old$    select distinct eid, saved_id, auth.uid() from unnest(p_related_entry_ids) eid;$old$,
$new$    select distinct eid, saved_id, auth.uid() from unnest(p_related_entry_ids) eid
    on conflict on constraint entry_people_pkey do nothing;$new$
);

-- Collections/tags already snapshot only {id, name}; First Time occurrence
-- saves do not rewrite other compared relationships. set_entry_relation exits
-- on a no-op, and save_location removes old links only for a new Location ID.
-- Restore intentionally rebuilds selected state; normalization makes its
-- bookkeeping invisible while preserving all required restore inputs.
drop function pg_temp.replace_history_writer_fragment(regprocedure, text, text);
