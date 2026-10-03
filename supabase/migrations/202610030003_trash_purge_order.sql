-- Delete forever used to remove an item's original photos from Storage before the
-- database delete. A preview finishing in between (media_cleanup_required), a lost
-- response, or a Restore from another device left a restorable Entry or photo whose
-- originals were gone, and Restore never checked Storage.
--
-- The database delete is now the commit point, and the order is enforced here:
-- 1. Deleting an attachment row records its remaining Storage objects in
--    media_purges in the same transaction, so a deleted item cannot be restored and
--    its files are never forgotten. This replaces the media_cleanup_required guard,
--    which now applies only to account deletion, where nothing could remove them later.
-- 2. Clients remove only recorded objects, then confirm with complete_media_purges.
--    An interrupted removal stays recorded and is retried on the next attempt.
-- 3. Storage refuses a client delete of a registered original, so an original can
--    only be removed after its record is permanently deleted.
-- 4. Every restore requires the originals it makes visible to still exist.
-- trash_item_storage_paths and delete_trash_item_forever keep their signatures. A
-- deployed client's old sequence now removes nothing early and still deletes safely.

create table if not exists public.media_purges (
  bucket_id text not null,
  object_name text not null,
  owner_id uuid not null references auth.users(id) on delete cascade,
  recorded_at timestamptz not null default clock_timestamp(),
  primary key (bucket_id, object_name)
);

comment on table public.media_purges is
  'Storage objects of permanently deleted attachments, kept until the Storage API confirms their removal.';

create index if not exists media_purges_owner_recorded_idx
  on public.media_purges (owner_id, recorded_at, object_name);

alter table public.media_purges enable row level security;
revoke all on table public.media_purges from public, anon, authenticated;

create or replace function public.record_deleted_media()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Account deletion removes the owner before its rows, and nothing can remove Storage
  -- objects as that owner afterwards. Its previews must still be removed first.
  if not exists (select 1 from auth.users where users.id = old.owner_id) then
    if old.variant = 'original' and exists (
      select 1
      from storage.objects
      where objects.bucket_id = old.bucket_id
        and starts_with(
          objects.name,
          old.owner_id::text || '/' || old.entry_id::text || '/derived/' || old.id::text || '/'
        )
    ) then
      raise exception using errcode = '55000', message = 'media_cleanup_required';
    end if;
    return old;
  end if;

  -- Storage is outside this transaction. A derived upload holds a key-share lock on
  -- its original until it commits, so this sees every object that can still appear.
  insert into public.media_purges (bucket_id, object_name, owner_id)
  select objects.bucket_id, objects.name, old.owner_id
  from storage.objects
  where objects.bucket_id = old.bucket_id
    and (
      objects.name = old.object_path
      or (
        old.variant = 'original'
        and starts_with(
          objects.name,
          old.owner_id::text || '/' || old.entry_id::text || '/derived/' || old.id::text || '/'
        )
      )
    )
  on conflict (bucket_id, object_name) do nothing;
  return old;
end;
$$;

revoke all on function public.record_deleted_media() from public, anon, authenticated;

create or replace trigger memotrail_original_media_cleanup
before delete on public.attachments
for each row execute function public.record_deleted_media();

drop function if exists public.guard_original_media_cleanup();

-- Derived objects stay removable; they are caches the server can regenerate.
alter policy "Users can delete their own entry media" on storage.objects
using (
  bucket_id = 'entry-media'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and not exists (
    select 1
    from public.attachments as attachment
    where attachment.bucket_id = objects.bucket_id
      and attachment.object_path = objects.name
      and attachment.variant = 'original'
  )
);

create or replace function public.pending_media_purge_paths(p_limit integer default 100)
returns table(object_path text)
language sql
stable
security definer
set search_path = ''
as $$
  select purge.object_name
  from public.media_purges as purge
  join storage.objects as object
    on object.bucket_id = purge.bucket_id and object.name = purge.object_name
  where purge.owner_id = auth.uid()
    and purge.bucket_id = 'entry-media'
    and split_part(purge.object_name, '/', 1) = auth.uid()::text
    and not exists (
      select 1
      from public.attachments as attachment
      where attachment.bucket_id = purge.bucket_id
        and attachment.object_path = purge.object_name
    )
  order by purge.recorded_at, purge.object_name
  limit greatest(1, least(coalesce(p_limit, 100), 1000));
$$;

comment on function public.pending_media_purge_paths(integer) is
  'Owned Storage paths of permanently deleted media that the client must remove through the Storage API.';

revoke all on function public.pending_media_purge_paths(integer) from public, anon;
grant execute on function public.pending_media_purge_paths(integer) to authenticated;

create or replace function public.complete_media_purges()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  purge_owner_id uuid := auth.uid();
  remaining integer;
begin
  if purge_owner_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;

  -- A path registered again is live media again, never something to remove.
  delete from public.media_purges as purge
  where purge.owner_id = purge_owner_id
    and (
      not exists (
        select 1
        from storage.objects as object
        where object.bucket_id = purge.bucket_id
          and object.name = purge.object_name
      )
      or exists (
        select 1
        from public.attachments as attachment
        where attachment.bucket_id = purge.bucket_id
          and attachment.object_path = purge.object_name
      )
    );

  select count(*)::integer into remaining
  from public.media_purges
  where media_purges.owner_id = purge_owner_id;
  return remaining;
end;
$$;

comment on function public.complete_media_purges() is
  'Forgets recorded media whose Storage objects are gone and returns how many still need removal.';

revoke all on function public.complete_media_purges() from public, anon;
grant execute on function public.complete_media_purges() to authenticated;

create or replace function public.trash_item_storage_paths(
  p_item_kind text,
  p_item_id uuid,
  p_expected_revision integer,
  p_expected_deleted_at timestamptz
)
returns table(object_path text)
language plpgsql
stable
set search_path = ''
as $$
begin
  if auth.uid() is null or p_item_id is null or p_expected_deleted_at is null then return; end if;
  -- Deployed clients remove these paths before delete_trash_item_forever. Nothing
  -- may be removed before the record is deleted, so the manifest is always empty.
  if p_item_kind in ('entry', 'attachment', 'place', 'person', 'collection') then return; end if;
  raise exception using errcode = '22023', message = 'invalid_trash_item_kind';
end;
$$;

comment on function public.trash_item_storage_paths(text, uuid, integer, timestamptz) is
  'Kept for deployed clients and always empty: Delete forever removes the record first, then pending_media_purge_paths lists its Storage objects.';

comment on function public.delete_trash_item_forever(text, uuid, integer, timestamptz) is
  'Permanently deletes one owned Trash item and records its private Storage objects for removal through pending_media_purge_paths.';

create or replace function public.require_entry_originals_on_restore()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.attachments as attachment
    where attachment.entry_id = new.id
      and attachment.owner_id = new.owner_id
      and attachment.variant = 'original'
      and attachment.deleted_at is null
      and not exists (
        select 1
        from storage.objects as object
        where object.bucket_id = attachment.bucket_id
          and object.name = attachment.object_path
      )
  ) then
    raise exception using errcode = 'P0001', message = 'trash_media_unavailable';
  end if;
  return new;
end;
$$;

revoke all on function public.require_entry_originals_on_restore() from public, anon, authenticated;

create or replace trigger memotrail_restore_requires_originals
before update of deleted_at on public.entries
for each row
when (old.deleted_at is not null and new.deleted_at is null)
execute function public.require_entry_originals_on_restore();

create or replace function public.require_attachment_original_on_restore()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from storage.objects as object
    where object.bucket_id = new.bucket_id
      and object.name = new.object_path
  ) then
    raise exception using errcode = 'P0001', message = 'trash_media_unavailable';
  end if;
  return new;
end;
$$;

revoke all on function public.require_attachment_original_on_restore() from public, anon, authenticated;

create or replace trigger memotrail_restore_requires_original
before update of deleted_at on public.attachments
for each row
when (old.variant = 'original' and old.deleted_at is not null and new.deleted_at is null)
execute function public.require_attachment_original_on_restore();
