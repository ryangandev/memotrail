-- Inbox review is retired: a Capture is saved straight to Library.
-- Every Entry waiting in Inbox moves to Library without a new version, revision, or updated time,
-- so it keeps its place among recent Entries.
alter table public.entries disable trigger archive_entry_before_change;
update public.entries set inbox_status = 'organized' where inbox_status <> 'organized';
alter table public.entries enable trigger archive_entry_before_change;

-- History keeps no Inbox state either, so restoring an older version cannot return an Entry to Inbox.
update public.entry_versions
set snapshot = jsonb_set(snapshot, '{inbox_status}', '"organized"')
where snapshot->>'inbox_status' = 'unreviewed';

alter table public.entries alter column inbox_status set default 'organized';
alter table public.entries drop constraint entries_inbox_status_check;
alter table public.entries add constraint entries_inbox_status_check check (inbox_status = 'organized');

-- Clients that still save Captures to Inbox, such as a browser tab opened before this change or native iOS,
-- save them to Library instead of having them refused.
create function public.keep_entries_in_library()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.inbox_status := 'organized';
  return new;
end;
$$;
revoke all on function public.keep_entries_in_library() from public, anon, authenticated;
create trigger keep_entries_in_library
before insert or update of inbox_status on public.entries
for each row execute function public.keep_entries_in_library();

-- Without Inbox there is no Capture left to organize or to start a focused record from.
drop function public.organize_capture(uuid, integer, text, text);
drop function public.extract_capture_item(uuid, integer, text, text, text, text, timestamptz, timestamptz, text, text, text);
drop function public.capture_extraction_source(uuid);
drop function public.extract_capture_to_goal(uuid, integer, text, text, text, date, text[]);

-- The Home and Vehicle Location saves keep their signatures for deployed clients but refuse a Capture source.
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

  -- Inbox review is retired, so a Home no longer starts from a Capture.
  if p_source is not null and p_source <> 'null'::jsonb then
    raise exception using errcode = '22023', message = 'capture_handoff_retired';
  end if;

  select coalesce(array_agg(value), '{}'::text[]) into tag_names
  from jsonb_array_elements_text(p_input->'tagNames') as value;
  location_id := public.resolve_geoapify_location(p_provider_location);
  if location_id is null then
    raise exception using errcode = '22023', message = 'invalid_provider_location';
  end if;

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

  if saved is null then
    raise exception using errcode = '40001', message = 'home_changed';
  end if;
  return saved;
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

  -- Inbox review is retired, so a Vehicle no longer starts from a Capture.
  if p_source is not null and p_source <> 'null'::jsonb then
    raise exception using errcode = '22023', message = 'capture_handoff_retired';
  end if;

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

drop function public.extract_capture_to_home(uuid, integer, text, text, timestamptz, timestamptz, text, text, text, uuid, text, text, text, text, text, numeric, numeric, text, text, text, text[]);
drop function public.extract_capture_to_vehicle(uuid, integer, text, text, timestamptz, timestamptz, text, text, text, text, text, integer, text, text[]);

-- Library can list the Entries that still need organizing.
drop function public.wiki_items_workspace(text, text[], text[], integer, integer);
create function public.wiki_items_workspace(p_query text DEFAULT ''::text, p_item_kinds text[] DEFAULT ARRAY[]::text[], p_item_subtypes text[] DEFAULT ARRAY[]::text[], p_limit integer DEFAULT 50, p_offset integer DEFAULT 0, p_needs_organizing boolean DEFAULT false)
 RETURNS TABLE(record_source text, item_id uuid, canonical_item_id uuid, item_kind text, item_subtype text, title text, excerpt text, inbox_status text, occurred_start timestamp with time zone, occurred_end timestamp with time zone, updated_at timestamp with time zone, total_count bigint)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  workspace_owner_id uuid := auth.uid();
  normalized_query text := lower(btrim(coalesce(p_query, '')));
begin
  if workspace_owner_id is null then return; end if;

  if p_query is null
    or length(p_query) > 200
    or p_item_kinds is null
    or cardinality(p_item_kinds) > 6
    or exists (
      select 1 from unnest(p_item_kinds) as kind
      where kind not in ('entry', 'entity', 'goal')
    )
    or p_item_subtypes is null
    or cardinality(p_item_subtypes) > 50
    or exists (
      select 1 from unnest(p_item_subtypes) as subtype
      where subtype !~ '^[a-z][a-z0-9_]{0,63}$'
    )
    or p_limit is null or p_limit < 1 or p_limit > 100
    or p_offset is null or p_offset < 0 or p_offset > 100000
    or p_needs_organizing is null
  then
    raise exception using errcode = '22023', message = 'invalid_wiki_items_page';
  end if;

  return query
  with wiki_items as (
    select
      'entry'::text as record_source,
      entry.id as item_id,
      entry.id as canonical_item_id,
      entry.item_kind,
      entry.item_subtype,
      coalesce(
        nullif(btrim(entry.title), ''),
        nullif(left(btrim(entry.body), 120), ''),
        'Untitled item'
      ) as title,
      left(btrim(entry.body), 240) as excerpt,
      entry.inbox_status,
      entry.occurred_start,
      entry.occurred_end,
      entry.updated_at,
      concat_ws(
        ' ', entry.title, entry.body, entry.item_kind, entry.item_subtype
      ) as searchable
    from public.entries as entry
    where entry.owner_id = workspace_owner_id
      and entry.deleted_at is null
      -- An Entry needs organizing while it has neither a title nor a tag, like a fresh Capture.
      and (
        not p_needs_organizing
        or (
          entry.item_kind = 'entry'
          and nullif(btrim(entry.title), '') is null
          and not exists (
            select 1 from public.entry_tags as tagged
            where tagged.entry_id = entry.id and tagged.owner_id = workspace_owner_id
          )
        )
      )
  ),
  matches as (
    select *
    from wiki_items
    where (cardinality(p_item_kinds) = 0 or wiki_items.item_kind = any(p_item_kinds))
      and (cardinality(p_item_subtypes) = 0 or wiki_items.item_subtype = any(p_item_subtypes))
      and (normalized_query = '' or strpos(lower(wiki_items.searchable), normalized_query) > 0)
  ),
  counted as (
    select matches.*, count(*) over () as total_count
    from matches
  )
  select
    counted.record_source, counted.item_id, counted.canonical_item_id,
    counted.item_kind, counted.item_subtype, counted.title, counted.excerpt,
    counted.inbox_status, counted.occurred_start, counted.occurred_end,
    counted.updated_at, counted.total_count
  from counted
  order by counted.updated_at desc, lower(counted.title), counted.record_source, counted.item_id
  limit p_limit offset p_offset;
end;
$function$;
revoke all on function public.wiki_items_workspace(text, text[], text[], integer, integer, boolean) from public, anon;
grant execute on function public.wiki_items_workspace(text, text[], text[], integer, integer, boolean) to authenticated;

-- Paused AI suggestions can still be requested for any active Entry, now that none waits in Inbox.
CREATE OR REPLACE FUNCTION public.claim_entry_ai_suggestion(p_owner_id uuid, p_entry_id uuid, p_revision integer, p_scope text, p_retry boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare suggestion public.ai_suggestions; inserted_id uuid;
begin
  if p_revision is null or p_revision < 1 or p_scope is null or (
    p_scope not in ('classification','tagging','classification_tagging') and
    p_scope !~ '^(classification|tagging|classification_tagging)_photos_[a-f0-9]{64}$'
  ) then
    raise exception using errcode='22023',message='invalid_suggestion_request';
  end if;
  perform 1 from public.entries where id=p_entry_id and owner_id=p_owner_id and revision=p_revision and deleted_at is null for share;
  if not found then raise exception using errcode='P0001',message='entry_changed'; end if;
  if strpos(p_scope,'_photos_') > 0 then
    perform 1 from public.ai_preferences where owner_id=p_owner_id and enabled and photo_analysis
      and (classification or tagging);
    if not found then raise exception using errcode='P0001',message='ai_disabled'; end if;
  end if;
  insert into public.ai_suggestions(owner_id,entry_id,entry_revision,request_scope,suggestions,status,started_at)
  values(p_owner_id,p_entry_id,p_revision,p_scope,'{}','generating',now())
  on conflict(entry_id,entry_revision,request_scope) where entry_revision>0 do nothing returning id into inserted_id;
  select * into suggestion from public.ai_suggestions where entry_id=p_entry_id and entry_revision=p_revision and request_scope=p_scope for update;
  if inserted_id is null and suggestion.status='generating' and suggestion.started_at < now()-interval '2 minutes' then
    update public.ai_suggestions set status='failed',resolved_at=now() where id=suggestion.id returning * into suggestion;
  end if;
  if inserted_id is null and p_retry and suggestion.status='failed' then
    update public.ai_suggestions set status='generating',started_at=now(),resolved_at=null where id=suggestion.id returning * into suggestion;
    inserted_id:=suggestion.id;
  end if;
  return jsonb_build_object('claimed',inserted_id is not null,'suggestion',to_jsonb(suggestion)-'owner_id');
end;
$function$;
