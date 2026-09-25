-- Places was a default Timeline grouping, not the removed authored Place model.
-- Preserve its placements and restorable history under the remaining general track.
begin;

do $migration$
declare
  former_track record;
  historical record;
  placement jsonb;
  placements jsonb;
  normalized jsonb;
  revised_snapshot jsonb;
begin
  if exists (
    select 1
    from public.timeline_tracks as former
    where former.system_key = 'places'
      and not exists (
        select 1 from public.timeline_tracks as destination
        where destination.owner_id = former.owner_id
          and destination.system_key = 'other_events'
      )
  ) then
    raise exception 'A Places track has no general Timeline destination';
  end if;

  for former_track in
    select former.id, former.owner_id, destination.id as destination_id,
      destination.name as destination_name
    from public.timeline_tracks as former
    join public.timeline_tracks as destination
      on destination.owner_id = former.owner_id
      and destination.system_key = 'other_events'
    where former.system_key = 'places'
  loop
    insert into public.timeline_items (
      entry_id, track_id, owner_id, timeline_kind, sort_order, created_at
    )
    select item.entry_id, former_track.destination_id, item.owner_id,
      item.timeline_kind, item.sort_order, item.created_at
    from public.timeline_items as item
    where item.track_id = former_track.id
    on conflict (entry_id, track_id) do nothing;

    -- Historical snapshots carry track IDs. Remap them so restore stays usable.
    for historical in
      select id, snapshot
      from public.entry_versions
      where owner_id = former_track.owner_id
        and (
          snapshot->'timeline_items' @> jsonb_build_array(
            jsonb_build_object('track_id', former_track.id)
          )
          or snapshot->'timeline'->>'track_id' = former_track.id::text
        )
    loop
      revised_snapshot := historical.snapshot;
      if jsonb_typeof(revised_snapshot->'timeline_items') = 'array' then
        placements := revised_snapshot->'timeline_items';
        normalized := '[]'::jsonb;
        -- Prefer an existing placement on the destination when both exist.
        for placement in
          select value
          from jsonb_array_elements(placements)
          order by (value->>'track_id' = former_track.id::text)
        loop
          if placement->>'track_id' = former_track.id::text then
            placement := jsonb_set(
              jsonb_set(placement, '{track_id}', to_jsonb(former_track.destination_id)),
              '{track_name}', to_jsonb(former_track.destination_name)
            );
          end if;
          if not exists (
            select 1 from jsonb_array_elements(normalized) as existing(value)
            where existing.value->>'track_id' = placement->>'track_id'
          ) then
            normalized := normalized || jsonb_build_array(placement);
          end if;
        end loop;
        revised_snapshot := jsonb_set(revised_snapshot, '{timeline_items}', normalized);
      end if;
      if revised_snapshot->'timeline'->>'track_id' = former_track.id::text then
        revised_snapshot := jsonb_set(
          revised_snapshot, '{timeline}',
          revised_snapshot->'timeline'
            || jsonb_build_object(
              'track_id', former_track.destination_id,
              'track_name', former_track.destination_name,
              'track_system_key', 'other_events'
            )
        );
      end if;
      update public.entry_versions
      set snapshot = revised_snapshot
      where id = historical.id;
    end loop;

    delete from public.timeline_tracks where id = former_track.id;
  end loop;
end;
$migration$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (user_id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name'));

  insert into public.timeline_tracks (owner_id, name, system_key, sort_order)
  values
    (new.id, 'Education', 'education', 20),
    (new.id, 'Career', 'career', 30),
    (new.id, 'Homes', 'homes', 40),
    (new.id, 'Vehicles', 'vehicles', 50),
    (new.id, 'Relationships', 'relationships', 60),
    (new.id, 'Health', 'health', 70),
    (new.id, 'First Times', 'first_times', 80),
    (new.id, 'Other Events', 'other_events', 90);

  return new;
end;
$$;

commit;
