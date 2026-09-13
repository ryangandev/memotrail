-- Generated Storage objects can exist before derivative registration finishes.
-- Serialize their creation with original deletion, without changing Storage data via SQL.
create or replace function public.guard_derived_media_source()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.bucket_id<>'entry-media' or split_part(new.name,'/',3)<>'derived' then return new; end if;
  -- Reject client writes before path/source validation can reveal privileged existence information.
  if current_setting('role',true) in ('anon','authenticated') or auth.role() in ('anon','authenticated') then
    raise exception using errcode='42501',message='derived_media_server_only';
  end if;
  if new.name !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/derived/[0-9a-f-]{36}/v[0-9]+/[a-f0-9]{64}/(display|thumbnail)\.webp$' then
    raise exception using errcode='22023',message='invalid_derived_media_path';
  end if;
  perform a.id from public.attachments a
    where a.id::text=split_part(new.name,'/',4) and a.owner_id::text=split_part(new.name,'/',1)
      and a.entry_id::text=split_part(new.name,'/',2) and a.variant='original' and a.bucket_id='entry-media'
    for key share;
  if not found then raise exception using errcode='23503',message='media_source_removed'; end if;
  return new;
end;
$$;
revoke all on function public.guard_derived_media_source() from public,anon,authenticated;
create or replace trigger memotrail_derived_media_source
before insert or update on storage.objects for each row execute function public.guard_derived_media_source();

create or replace function public.guard_original_media_cleanup()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if old.variant='original' and exists(
    select 1 from storage.objects o where o.bucket_id='entry-media'
      and starts_with(o.name,old.owner_id::text||'/'||old.entry_id::text||'/derived/'||old.id::text||'/')
  ) then
    raise exception using errcode='55000',message='media_cleanup_required';
  end if;
  return old;
end;
$$;
revoke all on function public.guard_original_media_cleanup() from public,anon,authenticated;
create or replace trigger memotrail_original_media_cleanup
before delete on public.attachments for each row execute function public.guard_original_media_cleanup();

create or replace function public.trash_item_storage_paths(p_item_kind text,p_item_id uuid,p_expected_revision integer,p_expected_deleted_at timestamptz)
returns table(object_path text) language plpgsql stable security invoker set search_path='' as $$
begin
  if auth.uid() is null or p_item_id is null or p_expected_deleted_at is null then return; end if;
  if p_item_kind='entry' then
    return query
      with target as (
        select e.id,e.owner_id from public.entries e where e.id=p_item_id and e.owner_id=auth.uid()
          and e.revision=p_expected_revision and e.deleted_at=p_expected_deleted_at
      )
      select a.object_path from target t join public.attachments a on a.entry_id=t.id and a.owner_id=t.owner_id where a.bucket_id='entry-media'
      union
      select o.name from target t join storage.objects o on o.bucket_id='entry-media'
        and starts_with(o.name,t.owner_id::text||'/'||t.id::text||'/derived/');
    return;
  end if;
  if p_item_kind='attachment' then
    return query
      with target as (
        select a.id,a.owner_id,a.entry_id from public.attachments a join public.entries e on e.id=a.entry_id and e.owner_id=a.owner_id
        where a.id=p_item_id and a.owner_id=auth.uid() and a.variant='original' and a.deleted_at=p_expected_deleted_at and e.deleted_at is null
      )
      select a.object_path from target t join public.attachments a on (a.id=t.id or a.parent_attachment_id=t.id) and a.owner_id=t.owner_id where a.bucket_id='entry-media'
      union
      select o.name from target t join storage.objects o on o.bucket_id='entry-media'
        and starts_with(o.name,t.owner_id::text||'/'||t.entry_id::text||'/derived/'||t.id::text||'/');
    return;
  end if;
  if p_item_kind in ('habit','place','person','collection') then return; end if;
  raise exception using errcode='22023',message='invalid_trash_item_kind';
end;
$$;
