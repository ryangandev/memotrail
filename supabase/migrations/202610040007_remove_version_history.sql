-- Version history is retired: MemoTrail no longer keeps or restores earlier versions of an Entry.
-- Every stored version is deleted, Entry updates still advance the revision for conflict checks,
-- and photo changes no longer create Entry revisions, because they existed only for history.
-- Locations kept only for history are dropped, and prepared export snapshots held copies of
-- that history, so they are purged too.

create or replace function public.advance_entry_revision()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.revision := old.revision + 1;
  new.updated_at := now();
  return new;
end;
$$;
revoke all on function public.advance_entry_revision() from public, anon, authenticated;

drop trigger archive_entry_before_change on public.entries;
create trigger advance_entry_revision
before update on public.entries
for each row execute function public.advance_entry_revision();

CREATE OR REPLACE FUNCTION public.register_entry_attachment(p_entry_id uuid, p_attachment_id uuid, p_object_path text, p_original_filename text, p_mime_type text, p_byte_size bigint, p_pixel_width integer, p_pixel_height integer)
 RETURNS TABLE(attachment_id uuid, entry_id uuid, object_path text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  entry_deleted_at timestamptz;
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

  select entries.deleted_at into entry_deleted_at
  from public.entries
  where entries.id = p_entry_id and entries.owner_id = attachment_owner_id
  for update;
  if not found then
    -- Only the owner learns that the Entry was deleted forever.
    if exists (
      select 1
      from public.entry_tombstones
      where entry_tombstones.owner_id = attachment_owner_id
        and entry_tombstones.entry_id = p_entry_id
    ) then
      raise exception using errcode = '23505', message = 'entry_deleted_forever';
    end if;
    return;
  end if;
  if entry_deleted_at is not null then
    raise exception using errcode = '22023', message = 'entry_in_trash';
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
$function$;

CREATE OR REPLACE FUNCTION public.trash_entry_attachment(p_attachment_id uuid)
 RETURNS TABLE(attachment_id uuid, entry_id uuid, deleted_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare target_id uuid;
begin
  select a.entry_id into target_id from public.attachments a
    where a.id=p_attachment_id and a.owner_id=auth.uid() and a.variant='original';
  perform 1 from public.entries where id=target_id and owner_id=auth.uid()
    and entries.deleted_at is null for update;
  if not found then return; end if;
  perform 1 from public.attachments a where a.id=p_attachment_id
    and a.owner_id=auth.uid() and a.deleted_at is null for update;
  if not found then return; end if;
  return query update public.attachments a set deleted_at=clock_timestamp()
    where a.id=p_attachment_id returning a.id,a.entry_id,a.deleted_at;
end;
$function$;

CREATE OR REPLACE FUNCTION public.restore_trash_item(p_item_kind text, p_item_id uuid, p_expected_revision integer, p_expected_deleted_at timestamp with time zone)
 RETURNS TABLE(item_kind text, item_id uuid, revision integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  trash_owner_id uuid := auth.uid();
  target_id uuid;
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

    -- Lock the Entry before its photo, in the same order as Delete forever.
    select attachments.entry_id into target_id
    from public.attachments
    where attachments.id = p_item_id
      and attachments.owner_id = trash_owner_id
      and attachments.variant = 'original';
    perform 1 from public.entries
    where entries.id = target_id
      and entries.owner_id = trash_owner_id
      and entries.deleted_at is null
    for update;
    if not found then
      return;
    end if;

    return query
    update public.attachments
    set deleted_at = null
    where attachments.id = p_item_id
      and attachments.owner_id = trash_owner_id
      and attachments.deleted_at = p_expected_deleted_at
    returning 'attachment'::text, attachments.id, null::integer;
    return;
  end if;

  raise exception using errcode = '22023', message = 'invalid_trash_item_kind';
end;
$function$;

CREATE OR REPLACE FUNCTION public.trash_first_time_entry(p_entry_id uuid, p_expected_revision integer)
 RETURNS TABLE(entry_id uuid, revision integer)
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
    and entries.item_kind = 'entry' and entries.item_subtype = 'first_time'
    and entries.revision = p_expected_revision
    and entries.deleted_at is null
  returning entries.id, entries.revision;
end;
$function$;

CREATE OR REPLACE FUNCTION public.trash_goal_entry(p_entry_id uuid, p_expected_revision integer)
 RETURNS TABLE(entry_id uuid, revision integer)
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  goal_owner_id uuid := auth.uid();
begin
  if goal_owner_id is null or p_entry_id is null then
    return;
  end if;
  if p_expected_revision is null or p_expected_revision < 1 then
    raise exception using errcode = '22023', message = 'invalid_revision';
  end if;


  return query
  update public.entries
  set deleted_at = timezone('utc', now())
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
  returning entries.id, entries.revision;
end;
$function$;

CREATE OR REPLACE FUNCTION public.trash_home_entry(p_entry_id uuid, p_expected_revision integer)
 RETURNS TABLE(entry_id uuid, revision integer)
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  home_owner_id uuid := auth.uid();
begin
  if home_owner_id is null or p_entry_id is null then
    return;
  end if;

  if p_expected_revision is null or p_expected_revision < 1 then
    raise exception using errcode = '22023', message = 'invalid_revision';
  end if;


  return query
  update public.entries
  set deleted_at = timezone('utc', now())
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
  returning entries.id, entries.revision;
end;
$function$;

CREATE OR REPLACE FUNCTION public.trash_timeline_entry(p_entry_id uuid, p_expected_revision integer)
 RETURNS TABLE(entry_id uuid, revision integer)
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  timeline_owner_id uuid := auth.uid();
  trashed_entry_id uuid;
  trashed_revision integer;
begin
  if timeline_owner_id is null then
    return;
  end if;

  if p_expected_revision is null or p_expected_revision < 1 then
    raise exception using errcode = '22023', message = 'invalid_revision';
  end if;


  update public.entries as entries
  set deleted_at = timezone('utc', now())
  where entries.id = p_entry_id
    and entries.owner_id = timeline_owner_id
    and entries.revision = p_expected_revision
    and entries.deleted_at is null
    and exists (
      select 1
      from public.timeline_items as items
      where items.entry_id = entries.id
        and items.owner_id = timeline_owner_id
    )
  returning entries.id, entries.revision into trashed_entry_id, trashed_revision;

  if trashed_entry_id is null then
    return;
  end if;

  return query select trashed_entry_id, trashed_revision;
end;
$function$;

CREATE OR REPLACE FUNCTION public.trash_vehicle_entry(p_entry_id uuid, p_expected_revision integer)
 RETURNS TABLE(entry_id uuid, revision integer)
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  vehicle_owner_id uuid := auth.uid();
begin
  if vehicle_owner_id is null or p_entry_id is null then
    return;
  end if;

  if p_expected_revision is null or p_expected_revision < 1 then
    raise exception using errcode = '22023', message = 'invalid_revision';
  end if;


  return query
  update public.entries
  set deleted_at = timezone('utc', now())
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
  returning entries.id, entries.revision;
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
begin
  if goal_owner_id is null or p_goal_entry_id is null then
    return;
  end if;
  if p_expected_revision is null or p_expected_revision < 1 then
    raise exception using errcode = '22023', message = 'invalid_goal_achievement';
  end if;


  -- Touching the Goal advances its revision.
  update public.entries
  set updated_at = now()
  where entries.id = p_goal_entry_id
    and entries.owner_id = goal_owner_id
    and entries.revision = p_expected_revision
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

drop function public.register_entry_attachment_without_history(uuid, uuid, text, text, text, bigint, integer, integer);
drop function public.restore_trash_item_without_photo_history(text, uuid, integer, timestamptz);
drop function public.entry_writing_revision(uuid, integer);
drop function public.archive_entry_photo_change(uuid, uuid, text);
drop table public.entry_photo_changes;

drop function public.entry_history(uuid, integer, integer);
drop function public.entry_history_index(text, integer, integer);
drop function public.restore_entry_version(uuid, integer, integer);
drop function public.archive_entry_version();
drop function public.entry_history_snapshot(public.entries);
drop function public.normalize_entry_history_snapshot(jsonb);
drop table public.entry_versions;

-- The Item page reads an Entry's current content and its relationships.
create function public.entry_detail(p_entry_id uuid)
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
    'places', coalesce((
      select jsonb_agg(jsonb_build_object('place_id', link.place_id, 'relationship', link.relationship, 'name', place.name)
        order by link.place_id, link.relationship)
      from public.entry_places as link
      join public.locations as place on place.id = link.place_id
      where link.entry_id = entry.id
    ), '[]'::jsonb),
    'timeline_items', coalesce((
      select jsonb_agg(jsonb_build_object('track_id', placement.track_id, 'timeline_kind', placement.timeline_kind, 'track_name', track.name)
        order by placement.track_id)
      from public.timeline_items as placement
      join public.timeline_tracks as track on track.id = placement.track_id
      where placement.entry_id = entry.id
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
revoke all on function public.entry_detail(uuid) from public, anon;
grant execute on function public.entry_detail(uuid) to authenticated, service_role;

-- A Location belongs to the Entries that link to it. History kept a replaced or removed
-- Location so an earlier version could restore it; now it is dropped once nothing links to it.
-- The check runs at commit, so a save that relinks the same Location in the same transaction keeps it.
create function public.discard_unlinked_location()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.locations as location
  where location.id = old.place_id
    and location.owner_id = old.owner_id
    and not exists (select 1 from public.entry_places as link where link.place_id = old.place_id)
    and not exists (select 1 from public.homes as home where home.place_id = old.place_id);
  return null;
end;
$$;
revoke all on function public.discard_unlinked_location() from public, anon, authenticated;

create constraint trigger entry_places_discard_unlinked_location
after delete or update of place_id on public.entry_places
deferrable initially deferred
for each row execute function public.discard_unlinked_location();
create constraint trigger homes_discard_unlinked_location
after delete or update of place_id on public.homes
deferrable initially deferred
for each row execute function public.discard_unlinked_location();

delete from public.locations as location
where not exists (select 1 from public.entry_places as link where link.place_id = location.id)
  and not exists (select 1 from public.homes as home where home.place_id = location.id);

create or replace function public.export_dataset_names()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array[
    'profiles','entries','tags','entry_tags',
    'locations','entry_locations','timeline_tracks','timeline_items',
    'homes','vehicles','goals','attachments','entry_links',
    'ai_preferences','ai_usage','ai_suggestions','ai_exploration_turns','ai_exploration_saves','media_objects'
  ]::text[];
$$;

delete from public.export_snapshot_rows
where snapshot_id in (select id from public.export_snapshots where purged_at is null);
update public.export_snapshots
set purged_at = clock_timestamp(), datasets = '{}', row_count = 0, json_bytes = 0
where purged_at is null;
