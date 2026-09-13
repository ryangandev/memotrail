-- Originals remain canonical. Generated variants are private, replaceable display artifacts.
-- Clients may remove derivatives during explicit permanent deletion, but only the server writes them.
alter policy "Users can upload their own entry media" on storage.objects
with check(bucket_id='entry-media' and (storage.foldername(name))[1]=(select auth.uid())::text and split_part(name,'/',3)<>'derived');
alter policy "Users can update their own entry media" on storage.objects
using(bucket_id='entry-media' and (storage.foldername(name))[1]=(select auth.uid())::text and split_part(name,'/',3)<>'derived')
with check(bucket_id='entry-media' and (storage.foldername(name))[1]=(select auth.uid())::text and split_part(name,'/',3)<>'derived');
create or replace function public.media_source(p_owner_id uuid,p_attachment_id uuid,p_allow_trash boolean default false)
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object(
    'id',a.id,'owner_id',a.owner_id,'entry_id',a.entry_id,'object_path',a.object_path,
    'version',coalesce(o.version,o.updated_at::text),'etag',o.metadata->>'eTag',
    'byte_size',(o.metadata->>'size')::bigint,'mime_type',a.mime_type,
    'variants',coalesce((select jsonb_agg(jsonb_build_object('object_path',d.object_path,'variant',d.variant,'metadata',d.metadata))
      from public.attachments d where d.parent_attachment_id=a.id and d.owner_id=a.owner_id and d.variant in ('display','thumbnail')),'[]'::jsonb)
  ) from public.attachments a join public.entries e on e.id=a.entry_id and e.owner_id=a.owner_id
    join storage.objects o on o.bucket_id=a.bucket_id and o.name=a.object_path
  where a.id=p_attachment_id and a.owner_id=p_owner_id and a.variant='original' and a.bucket_id='entry-media'
    and split_part(a.object_path,'/',1)=p_owner_id::text
    and (p_allow_trash or (a.deleted_at is null and e.deleted_at is null));
$$;
revoke all on function public.media_source(uuid,uuid,boolean) from public,anon,authenticated;
grant execute on function public.media_source(uuid,uuid,boolean) to service_role;

create or replace function public.register_media_derivatives(p_owner_id uuid,p_attachment_id uuid,p_version text,p_sha256 text,p_variants jsonb)
returns boolean language plpgsql security definer set search_path='' as $$
declare source public.attachments%rowtype; current_version text; v jsonb; expected_prefix text;
begin
  select * into source from public.attachments where id=p_attachment_id and owner_id=p_owner_id and variant='original' for update;
  if not found then return false; end if;
  select coalesce(o.version,o.updated_at::text) into current_version from storage.objects o
    where o.bucket_id=source.bucket_id and o.name=source.object_path for share;
  if current_version is null or current_version is distinct from p_version then return false; end if;
  if p_sha256 is null or p_sha256 !~ '^[a-f0-9]{64}$' or jsonb_typeof(p_variants) is distinct from 'array' or jsonb_array_length(p_variants)<>2 then
    raise exception using errcode='22023',message='invalid_media_derivatives';
  end if;
  expected_prefix := p_owner_id::text || '/' || source.entry_id::text || '/derived/' || source.id::text || '/v1/' || p_sha256 || '/';
  if (select count(distinct item->>'variant') from jsonb_array_elements(p_variants) item where item->>'variant' in ('display','thumbnail'))<>2 then
    raise exception using errcode='22023',message='invalid_media_derivatives';
  end if;
  for v in select * from jsonb_array_elements(p_variants) loop
    if v->>'object_path' is distinct from expected_prefix || (v->>'variant') || '.webp'
      or coalesce(v->>'sha256','') !~ '^[a-f0-9]{64}$'
      or coalesce((v->>'byte_size')::bigint,0) not between 1 and 8388608
      or coalesce((v->>'width')::integer,0) not between 1 and (case v->>'variant' when 'display' then 1600 else 400 end)
      or coalesce((v->>'height')::integer,0) not between 1 and (case v->>'variant' when 'display' then 1600 else 400 end)
      or not exists(select 1 from storage.objects o where o.bucket_id='entry-media' and o.name=v->>'object_path' and (o.metadata->>'size')::bigint=(v->>'byte_size')::bigint)
    then raise exception using errcode='22023',message='invalid_media_derivative'; end if;
    insert into public.attachments(owner_id,entry_id,parent_attachment_id,variant,bucket_id,object_path,mime_type,byte_size,pixel_width,pixel_height,metadata)
    values(p_owner_id,source.entry_id,source.id,v->>'variant','entry-media',v->>'object_path','image/webp',(v->>'byte_size')::bigint,(v->>'width')::integer,(v->>'height')::integer,
      jsonb_build_object('pipeline','v1','source_version',p_version,'source_sha256',p_sha256,'sha256',v->>'sha256'))
    on conflict(bucket_id,object_path) do update set metadata=excluded.metadata
      where attachments.owner_id=p_owner_id and attachments.parent_attachment_id=p_attachment_id and attachments.variant=excluded.variant;
  end loop;
  return true;
end;
$$;
revoke all on function public.register_media_derivatives(uuid,uuid,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.register_media_derivatives(uuid,uuid,text,text,jsonb) to service_role;

-- Display artifacts must not count as user photos or become prerequisites for restoring writing.
do $media_projections$
declare patch record; definition text;
begin
  for patch in select * from (values
    ('public.first_times_workspace()','and media.deleted_at is null','and media.deleted_at is null and media.variant = ''original'''),
    ('public.first_times_workspace_with_occurrence()','and media.deleted_at is null','and media.deleted_at is null and media.variant = ''original'''),
    ('public.entry_history_snapshot(public.entries)','a.entry_id=p_entry.id and a.deleted_at is null','a.entry_id=p_entry.id and a.deleted_at is null and a.variant=''original'''),
    ('public.restore_entry_version(uuid,integer,integer)','for item in select value from jsonb_array_elements(coalesce(s->''attachments'',''[]'')) loop','for item in select value from jsonb_array_elements(coalesce(s->''attachments'',''[]'')) where coalesce(value->>''variant'',''original'')=''original'' loop'),
    ('public.restore_entry_version(uuid,integer,integer)','end where entry_id=e.id;','end where entry_id=e.id and variant=''original'';'),
    ('public.trash_workspace(integer,integer)','and media.deleted_at is not null','and media.deleted_at is not null and media.variant = ''original''')
  ) as changes(signature,old_text,new_text)
  loop
    definition := pg_get_functiondef(patch.signature::regprocedure);
    if position(patch.new_text in definition)>0 then continue; end if;
    if position(patch.old_text in definition)=0 then raise exception 'Unexpected media projection: %',patch.signature; end if;
    execute replace(definition,patch.old_text,patch.new_text);
  end loop;
end;
$media_projections$;

-- Permanent removal of one original includes its generated family, not unrelated photos.
create or replace function public.trash_item_storage_paths(p_item_kind text,p_item_id uuid,p_expected_revision integer,p_expected_deleted_at timestamptz)
returns table(object_path text) language plpgsql stable security invoker set search_path='' as $$
begin
  if auth.uid() is null or p_item_id is null or p_expected_deleted_at is null then return; end if;
  if p_item_kind='entry' then
    return query select media.object_path from public.entries e join public.attachments media on media.entry_id=e.id and media.owner_id=e.owner_id
      where e.id=p_item_id and e.owner_id=auth.uid() and e.revision=p_expected_revision and e.deleted_at=p_expected_deleted_at and media.bucket_id='entry-media'
      order by media.created_at,media.id;
    return;
  end if;
  if p_item_kind='attachment' then
    return query select media.object_path from public.attachments original join public.entries e on e.id=original.entry_id and e.owner_id=original.owner_id
      join public.attachments media on (media.id=original.id or media.parent_attachment_id=original.id) and media.owner_id=original.owner_id
      where original.id=p_item_id and original.owner_id=auth.uid() and original.variant='original' and original.deleted_at=p_expected_deleted_at and e.deleted_at is null and media.bucket_id='entry-media';
    return;
  end if;
  if p_item_kind in ('habit','place','person','collection') then return; end if;
  raise exception using errcode='22023',message='invalid_trash_item_kind';
end;
$$;
