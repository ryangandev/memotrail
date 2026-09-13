-- Photo membership belongs to the same Entry history as writing.
-- Explicit RPC boundaries lock Entry before attachment; derivative workers and
-- restore_entry_version must not fire additional attachment-history triggers.
create table public.entry_photo_changes (
  entry_id uuid not null references public.entries(id) on delete cascade,
  from_revision integer not null check (from_revision > 0),
  attachment_id uuid not null,
  operation text not null check (operation in ('register','trash','restore')),
  primary key (entry_id,from_revision)
);
alter table public.entry_photo_changes enable row level security;
revoke all on public.entry_photo_changes from public,anon,authenticated;

create function public.archive_entry_photo_change(p_entry_id uuid,p_attachment_id uuid,p_operation text)
returns void language plpgsql security definer set search_path='' as $$
declare e public.entries;
begin
  select * into e from public.entries where id=p_entry_id and owner_id=auth.uid()
    and deleted_at is null for update;
  if not found then raise exception using errcode='42501',message='entry_unavailable'; end if;
  update public.entries set updated_at=clock_timestamp() where id=e.id;
  insert into public.entry_photo_changes values(e.id,e.revision,p_attachment_id,p_operation);
end;
$$;
revoke all on function public.archive_entry_photo_change(uuid,uuid,text) from public,anon,authenticated;

-- Safe only for writers which leave photo membership untouched.
-- A writing, organization, relationship, lifecycle or history-restore revision
-- creates a gap, so it can never be silently adopted by this reconciliation.
create function public.entry_writing_revision(p_entry_id uuid,p_expected_revision integer)
returns integer language plpgsql security definer set search_path='' as $$
declare current_revision integer; photo_count bigint;
begin
  if p_entry_id is null then return p_expected_revision; end if;
  select revision into current_revision from public.entries
    where id=p_entry_id and owner_id=auth.uid() and deleted_at is null;
  if current_revision is null or p_expected_revision is null or p_expected_revision<1
    or p_expected_revision>current_revision then return p_expected_revision; end if;
  select count(*) into photo_count from public.entry_photo_changes
    where entry_id=p_entry_id and from_revision>=p_expected_revision and from_revision<current_revision;
  if photo_count=current_revision-p_expected_revision then return current_revision; end if;
  return p_expected_revision;
end;
$$;
revoke all on function public.entry_writing_revision(uuid,integer) from public,anon;
grant execute on function public.entry_writing_revision(uuid,integer) to authenticated;

alter function public.register_entry_attachment(uuid,uuid,text,text,text,bigint,integer,integer)
  rename to register_entry_attachment_without_history;
revoke all on function public.register_entry_attachment_without_history(uuid,uuid,text,text,text,bigint,integer,integer)
  from public,anon,authenticated;

create function public.register_entry_attachment(
  p_entry_id uuid,p_attachment_id uuid,p_object_path text,p_original_filename text,
  p_mime_type text,p_byte_size bigint,p_pixel_width integer,p_pixel_height integer
) returns table(attachment_id uuid,entry_id uuid,object_path text)
language plpgsql security definer set search_path='' as $$
begin
  perform 1 from public.entries where id=p_entry_id and owner_id=auth.uid()
    and deleted_at is null for update;
  if not found then return; end if;
  -- Retries re-run the complete original identity validation, without a new version.
  if not exists(select 1 from public.attachments where id=p_attachment_id) then
    perform public.archive_entry_photo_change(p_entry_id,p_attachment_id,'register');
  end if;
  return query select * from public.register_entry_attachment_without_history(
    p_entry_id,p_attachment_id,p_object_path,p_original_filename,p_mime_type,
    p_byte_size,p_pixel_width,p_pixel_height);
end;
$$;
revoke all on function public.register_entry_attachment(uuid,uuid,text,text,text,bigint,integer,integer) from public,anon;
grant execute on function public.register_entry_attachment(uuid,uuid,text,text,text,bigint,integer,integer) to authenticated;

create or replace function public.register_first_time_attachment(
  p_entry_id uuid,p_attachment_id uuid,p_object_path text,p_original_filename text,
  p_mime_type text,p_byte_size bigint,p_pixel_width integer,p_pixel_height integer
) returns table(attachment_id uuid,entry_id uuid,object_path text)
language plpgsql security definer set search_path='' as $$
begin
  perform 1 from public.entries where id=p_entry_id and owner_id=auth.uid()
    and entry_type='first_time' and deleted_at is null for update;
  if not found then return; end if;
  return query select * from public.register_entry_attachment(
    p_entry_id,p_attachment_id,p_object_path,p_original_filename,p_mime_type,
    p_byte_size,p_pixel_width,p_pixel_height);
end;
$$;

create or replace function public.trash_entry_attachment(p_attachment_id uuid)
returns table(attachment_id uuid,entry_id uuid,deleted_at timestamptz)
language plpgsql security definer set search_path='' as $$
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
  perform public.archive_entry_photo_change(target_id,p_attachment_id,'trash');
  return query update public.attachments a set deleted_at=clock_timestamp()
    where a.id=p_attachment_id returning a.id,a.entry_id,a.deleted_at;
end;
$$;

create or replace function public.trash_first_time_attachment(p_attachment_id uuid)
returns table(attachment_id uuid,entry_id uuid,deleted_at timestamptz)
language plpgsql security definer set search_path='' as $$
begin
  perform 1 from public.entries e join public.attachments a on a.entry_id=e.id
    where a.id=p_attachment_id and e.owner_id=auth.uid() and a.owner_id=auth.uid()
      and e.entry_type='first_time' and e.deleted_at is null for update of e;
  if not found then return; end if;
  return query select * from public.trash_entry_attachment(p_attachment_id);
end;
$$;

alter function public.restore_trash_item(text,uuid,integer,timestamptz) rename to restore_trash_item_without_photo_history;
revoke all on function public.restore_trash_item_without_photo_history(text,uuid,integer,timestamptz) from public,anon,authenticated;
create function public.restore_trash_item(
  p_item_kind text,p_item_id uuid,p_expected_revision integer,p_expected_deleted_at timestamptz
) returns table(item_kind text,item_id uuid,revision integer)
language plpgsql security definer set search_path='' as $$
declare target_id uuid;
begin
  if p_item_kind='attachment' then
    if p_expected_revision is not null then
      raise exception using errcode='22023',message='unexpected_trash_revision';
    end if;
    select a.entry_id into target_id from public.attachments a
      where a.id=p_item_id and a.owner_id=auth.uid() and a.variant='original';
    perform 1 from public.entries where id=target_id and owner_id=auth.uid()
      and deleted_at is null for update;
    if not found then return; end if;
    perform 1 from public.attachments a where a.id=p_item_id and a.owner_id=auth.uid()
      and a.deleted_at=p_expected_deleted_at for update;
    if not found then return; end if;
    perform public.archive_entry_photo_change(target_id,p_item_id,'restore');
  end if;
  return query select * from public.restore_trash_item_without_photo_history(
    p_item_kind,p_item_id,p_expected_revision,p_expected_deleted_at);
end;
$$;
revoke all on function public.restore_trash_item(text,uuid,integer,timestamptz) from public,anon;
grant execute on function public.restore_trash_item(text,uuid,integer,timestamptz) to authenticated;
