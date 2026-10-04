-- General links between Entries were removed from Web, and older Goals kept related links nothing shows.
-- Ryan chose to delete them, so only provenance and achievement links remain.
delete from public.entry_links
where relationship = 'related';

-- History drops them too, so restoring a version cannot bring one back.
update public.entry_versions
set snapshot = (snapshot - 'related_entry_ids') || jsonb_build_object(
  'links',
  coalesce((
    select jsonb_agg(link.value order by link.position)
    from jsonb_array_elements(snapshot->'links') with ordinality as link(value, position)
    where link.value->>'relationship' is distinct from 'related'
  ), '[]'::jsonb)
)
where jsonb_typeof(snapshot->'links') = 'array'
  and (
    snapshot ? 'related_entry_ids'
    or exists (
      select 1
      from jsonb_array_elements(snapshot->'links') as link(value)
      where link.value->>'relationship' = 'related'
    )
  );
update public.entry_versions
set snapshot = snapshot - 'related_entry_ids'
where snapshot ? 'related_entry_ids';

alter table public.entry_links
  alter column relationship drop default,
  add constraint entry_links_relationship_check
  check (relationship in ('achievement', 'derived', 'derived_from', 'exploration_conclusion', 'exploration_source'));

drop function public.set_entry_relation(uuid, uuid, integer, boolean);
drop function public.entry_relations(uuid, text, text, integer, integer);

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
    'attachments', coalesce((
      select jsonb_agg(to_jsonb(attachment) order by attachment.created_at, attachment.id)
      from public.attachments as attachment
      where attachment.entry_id = p_entry.id
        and attachment.deleted_at is null
        and attachment.variant = 'original'
    ), '[]'::jsonb)
  ));
$function$;
