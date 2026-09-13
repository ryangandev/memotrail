-- One explicit Inbox save owns writing, occurrence and optional photo Place adoption.
-- Coordinate values are user-reviewed drafts, not claims verified by a geocoder.
create or replace function public.lock_photo_place_source(p_entry_id uuid,p_attachment_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
begin
  perform a.id from public.attachments a where a.id=p_attachment_id
    and a.owner_id=auth.uid() and a.entry_id=p_entry_id and a.deleted_at is null
    and a.variant='original' and a.bucket_id='entry-media'
    and exists(select 1 from public.entries e where e.id=p_entry_id and e.owner_id=auth.uid() and e.deleted_at is null)
    for share;
  return found;
end;
$$;
revoke all on function public.lock_photo_place_source(uuid,uuid) from public,anon;
grant execute on function public.lock_photo_place_source(uuid,uuid) to authenticated;

create or replace function public.review_entry_with_photo_place(
  p_entry_id uuid, p_expected_revision integer, p_title text, p_body text,
  p_entry_type text, p_occurred_start timestamptz, p_occurred_timezone text,
  p_collection_names text[], p_tag_names text[], p_mark_done boolean,
  p_occurred_end timestamptz, p_occurred_label text, p_date_precision text,
  p_photo_place jsonb default null
)
returns table(entry_id uuid, revision integer, inbox_status text)
language plpgsql security invoker set search_path='' as $$
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

  select * into reviewed from public.review_entry_with_occurrence(
    p_entry_id,p_expected_revision,p_title,p_body,p_entry_type,p_occurred_start,
    p_occurred_timezone,p_collection_names,p_tag_names,p_mark_done,p_occurred_end,
    p_occurred_label,p_date_precision);
  if reviewed.entry_id is null then return; end if;

  if source_id is not null then
    if not public.lock_photo_place_source(reviewed.entry_id,source_id)
    then raise exception using errcode='40001',message='photo_source_changed'; end if;
    if target is null then
      select s.place_id into target from public.save_place(
        name,null,null,null,null,latitude,longitude,null,array[reviewed.entry_id],null,null) s;
    elsif not exists(select 1 from public.entry_places ep
      where ep.entry_id=reviewed.entry_id and ep.place_id=target and ep.owner_id=owner) then
      -- Snapshot the independent Place's prior relationships before adding a link.
      update public.places p set notes=p.notes where p.id=target and p.owner_id=owner;
      insert into public.entry_places(entry_id,place_id,owner_id,relationship)
        values(reviewed.entry_id,target,owner,'related');
    end if;
  end if;
  return query select reviewed.entry_id,reviewed.revision,reviewed.inbox_status;
end;
$$;
revoke all on function public.review_entry_with_photo_place(uuid,integer,text,text,text,timestamptz,text,text[],text[],boolean,timestamptz,text,text,jsonb) from public,anon;
grant execute on function public.review_entry_with_photo_place(uuid,integer,text,text,text,timestamptz,text,text[],text[],boolean,timestamptz,text,text,jsonb) to authenticated;
