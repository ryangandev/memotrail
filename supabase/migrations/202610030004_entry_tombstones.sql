-- Delete forever did not stop a client from creating the same Entry again. A capture
-- still queued on a device, because its insert response was lost or its photos were
-- still waiting, inserted its stable Entry ID again on the next sync, bringing back
-- an Entry the person had deleted forever. register_entry_attachment also answered
-- an Entry in Trash or deleted forever with an empty result, which clients retried
-- forever.
--
-- 1. Every hard delete of an Entry leaves an owner-scoped tombstone holding only its
--    ID and deletion time. Tombstones have no client access, are not exported, and
--    are removed with the account; account deletion records none.
-- 2. Inserting a tombstoned ID for the same owner fails with entry_deleted_forever.
--    Its SQLSTATE is 23505, like the duplicate key it replaces, so deployed clients
--    already treat it as a final refusal instead of retrying it.
-- 3. register_entry_attachment says why it cannot attach a photo to the owner's
--    Entry: entry_in_trash or entry_deleted_forever. Anyone else still receives an
--    empty result. Its signature is unchanged.

create table if not exists public.entry_tombstones (
  owner_id uuid not null references auth.users(id) on delete cascade,
  entry_id uuid not null,
  deleted_at timestamptz not null default clock_timestamp(),
  primary key (owner_id, entry_id)
);

comment on table public.entry_tombstones is
  'IDs of Entries deleted forever, so a delayed client write cannot create them again. Holds no content and is removed with the account.';

alter table public.entry_tombstones enable row level security;
revoke all on table public.entry_tombstones from public, anon, authenticated;

create or replace function public.record_entry_tombstone()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Account deletion removes the owner before its Entries, and nothing of the
  -- account may remain afterwards.
  if exists (select 1 from auth.users where users.id = old.owner_id) then
    insert into public.entry_tombstones (owner_id, entry_id)
    values (old.owner_id, old.id)
    on conflict (owner_id, entry_id) do nothing;
  end if;
  return old;
end;
$$;

revoke all on function public.record_entry_tombstone() from public, anon, authenticated;

create or replace trigger memotrail_entry_tombstone
after delete on public.entries
for each row execute function public.record_entry_tombstone();

create or replace function public.refuse_deleted_forever_entry()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- A Delete forever of this ID that has not committed yet still holds the row.
  -- Waiting for it makes its tombstone visible below; otherwise this insert would
  -- wait only at the primary key and then replace the deleted Entry.
  perform 1 from public.entries where entries.id = new.id for key share;
  if exists (
    select 1
    from public.entry_tombstones
    where entry_tombstones.owner_id = new.owner_id
      and entry_tombstones.entry_id = new.id
  ) then
    raise exception using errcode = '23505', message = 'entry_deleted_forever';
  end if;
  return new;
end;
$$;

revoke all on function public.refuse_deleted_forever_entry() from public, anon, authenticated;

create or replace trigger memotrail_refuse_deleted_forever_entry
before insert on public.entries
for each row execute function public.refuse_deleted_forever_entry();

create or replace function public.register_entry_attachment(
  p_entry_id uuid,
  p_attachment_id uuid,
  p_object_path text,
  p_original_filename text,
  p_mime_type text,
  p_byte_size bigint,
  p_pixel_width integer,
  p_pixel_height integer
)
returns table(attachment_id uuid, entry_id uuid, object_path text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  entry_deleted_at timestamptz;
begin
  select entries.deleted_at into entry_deleted_at
  from public.entries
  where entries.id = p_entry_id and entries.owner_id = auth.uid()
  for update;
  if not found then
    -- Only the owner learns that the Entry was deleted forever.
    if exists (
      select 1
      from public.entry_tombstones
      where entry_tombstones.owner_id = auth.uid()
        and entry_tombstones.entry_id = p_entry_id
    ) then
      raise exception using errcode = '23505', message = 'entry_deleted_forever';
    end if;
    return;
  end if;
  if entry_deleted_at is not null then
    raise exception using errcode = '22023', message = 'entry_in_trash';
  end if;
  -- Retries re-run the complete original identity validation, without a new version.
  if not exists(select 1 from public.attachments where id=p_attachment_id) then
    perform public.archive_entry_photo_change(p_entry_id,p_attachment_id,'register');
  end if;
  return query select * from public.register_entry_attachment_without_history(
    p_entry_id,p_attachment_id,p_object_path,p_original_filename,p_mime_type,
    p_byte_size,p_pixel_width,p_pixel_height);
end;
$$;

comment on function public.register_entry_attachment(uuid, uuid, text, text, text, bigint, integer, integer) is
  'Idempotently registers an uploaded private image against an owned Entry. Raises entry_in_trash or entry_deleted_forever for the owner''s Entry that cannot take photos.';
