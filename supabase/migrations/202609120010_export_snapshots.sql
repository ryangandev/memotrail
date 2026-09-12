-- Immutable, owner-scoped capture for complete portable exports.
-- The canonical allowlist deliberately excludes auth, secrets, storage credentials,
-- generated search indexes, and these temporary export tables themselves.
create table public.export_snapshots (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  schema_version integer not null default 1 check (schema_version = 1),
  captured_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null default (clock_timestamp() + interval '24 hours'),
  row_count bigint not null default 0,
  json_bytes bigint not null default 0,
  datasets jsonb not null default '{}'::jsonb,
  purged_at timestamptz,
  unique(id, owner_id)
);
create index export_snapshots_expiry on public.export_snapshots(expires_at);
create index export_snapshots_owner on public.export_snapshots(owner_id, captured_at desc);
create table public.export_snapshot_rows (
  snapshot_id uuid not null,
  owner_id uuid not null,
  position bigint not null check (position > 0),
  dataset text not null,
  value jsonb not null,
  primary key(snapshot_id, position),
  foreign key(snapshot_id, owner_id) references public.export_snapshots(id, owner_id) on delete cascade
);
alter table public.export_snapshots enable row level security;
alter table public.export_snapshot_rows enable row level security;
create policy export_snapshots_owner_read on public.export_snapshots for select to authenticated
  using(owner_id=(select auth.uid()) and expires_at>now());
create policy export_snapshot_rows_owner_read on public.export_snapshot_rows for select to authenticated
  using(owner_id=(select auth.uid()) and exists(select 1 from public.export_snapshots s where s.id=snapshot_id and s.expires_at>now()));
revoke all on public.export_snapshots, public.export_snapshot_rows from anon, authenticated;
grant select on public.export_snapshots, public.export_snapshot_rows to authenticated;
grant all on public.export_snapshots, public.export_snapshot_rows to service_role;

create or replace function public.export_dataset_names() returns text[]
language sql immutable set search_path='' as $$
  select array['profiles','entries','entry_versions','collections','tags','entry_collections','entry_tags',
    'places','people','entry_places','entry_people','timeline_tracks','timeline_items','homes','vehicles','goals',
    'habits','habit_occurrences','habit_versions','habit_occurrence_versions','attachments','entry_links',
    'person_versions','place_versions','ai_preferences','ai_usage','ai_suggestions','ai_exploration_turns','ai_exploration_saves','media_objects']::text[];
$$;

create or replace function public.create_export_snapshot(p_request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  owner uuid:=auth.uid(); existing public.export_snapshots; name text;
  pieces text[]:=array[]::text[]; source_sql text; counts jsonb;
begin
  if owner is null then raise exception using errcode='42501',message='authentication_required';end if;
  if p_request_id is null then raise exception using errcode='22023',message='invalid_export_request';end if;
  perform pg_advisory_xact_lock(hashtextextended('export:'||owner::text,0));
  select * into existing from public.export_snapshots where id=p_request_id;
  if found then
    if existing.owner_id<>owner then raise exception using errcode='22023',message='export_request_unavailable';end if;
    if existing.expires_at<=now() then raise exception using errcode='P0001',message='export_expired';end if;
    return to_jsonb(existing)-'owner_id';
  end if;
  if (select count(*) from public.export_snapshots where owner_id=owner and expires_at>now())>=2 then
    raise exception using errcode='P0001',message='export_limit_reached';
  end if;
  if (select count(*) from public.export_snapshots where owner_id=owner and captured_at>now()-interval '1 hour')>=10 then
    raise exception using errcode='P0001',message='export_rate_limit';
  end if;
  insert into public.export_snapshots(id,owner_id) values(p_request_id,owner);
  foreach name in array public.export_dataset_names() loop
    if name='media_objects' then continue;end if;
    pieces:=array_append(pieces,format('select %L::text as dataset,to_jsonb(t)%s as value from public.%I t where t.%I=$1',
      name,case when name='entries' then ' - ''search_document''' else '' end,name,case when name='profiles' then 'user_id' else 'owner_id' end));
  end loop;
  -- This is one INSERT/SELECT statement, so every source uses one MVCC snapshot.
  -- Storage metadata is captured only for owner-prefixed objects in the private media bucket.
  pieces:=array_append(pieces,$source$
    select 'media_objects'::text,jsonb_build_object(
      'attachment_id',a.id,'bucket_id',a.bucket_id,'object_path',a.object_path,'variant',a.variant,
      'storage_version',o.version,'byte_size',o.metadata->>'size','etag',o.metadata->>'eTag',
      'available',o.id is not null)
    from public.attachments a left join storage.objects o on o.bucket_id=a.bucket_id and o.name=a.object_path
      and a.bucket_id='entry-media' and split_part(a.object_path,'/',1)=$1::text
    where a.owner_id=$1
  $source$);
  source_sql:=array_to_string(pieces,' union all ');
  execute 'insert into public.export_snapshot_rows(snapshot_id,owner_id,position,dataset,value)
    select $2,$1,row_number() over(order by dataset,value::text),dataset,value from ('||source_sql||') captured'
    using owner,p_request_id;
  select jsonb_object_agg(n,coalesce(c.total,0)) into counts
    from unnest(public.export_dataset_names()) n left join
    (select dataset,count(*) total from public.export_snapshot_rows where snapshot_id=p_request_id group by dataset) c on c.dataset=n;
  update public.export_snapshots set datasets=counts,
    row_count=(select count(*) from public.export_snapshot_rows where snapshot_id=p_request_id),
    json_bytes=(select coalesce(sum(octet_length(value::text)),0) from public.export_snapshot_rows where snapshot_id=p_request_id)
    where id=p_request_id returning * into existing;
  return to_jsonb(existing)-'owner_id';
end;
$$;

create or replace function public.read_export_snapshot(p_snapshot_id uuid,p_after bigint default 0,p_limit integer default 100) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare snapshot public.export_snapshots; rows jsonb; last_position bigint;
begin
  if auth.uid() is null then raise exception using errcode='42501',message='authentication_required';end if;
  if p_snapshot_id is null or p_after is null or p_after<0 or p_limit is null or p_limit not between 1 and 250 then
    raise exception using errcode='22023',message='invalid_export_page';end if;
  select * into snapshot from public.export_snapshots where id=p_snapshot_id and owner_id=auth.uid();
  if not found then return null;end if;
  if snapshot.expires_at<=now() then raise exception using errcode='P0001',message='export_expired';end if;
  -- Cap ordinary pages at 1 MiB of JSON. An individual large record stays whole.
  with candidates as materialized (
    select position,dataset,value,sum(octet_length(value::text)) over(order by position) bytes,
      row_number() over(order by position) ordinal
    from public.export_snapshot_rows where snapshot_id=p_snapshot_id and position>p_after
    order by position limit p_limit
  ) select coalesce(jsonb_agg(jsonb_build_object('position',position,'dataset',dataset,'value',value) order by position),'[]'),max(position)
    into rows,last_position from candidates where bytes<=1048576 or ordinal=1;
  return jsonb_build_object('snapshot',to_jsonb(snapshot)-'owner_id','rows',rows,
    'next_cursor',coalesce(last_position,p_after),'has_more',coalesce(last_position,p_after)<snapshot.row_count);
end;
$$;

create or replace function public.discard_export_snapshot(p_snapshot_id uuid) returns boolean
language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is null then raise exception using errcode='42501',message='authentication_required';end if;
  perform pg_advisory_xact_lock(hashtextextended('export:'||auth.uid()::text,0));
  update public.export_snapshots set expires_at=least(expires_at,now()),purged_at=clock_timestamp(),datasets='{}',row_count=0,json_bytes=0
    where id=p_snapshot_id and owner_id=auth.uid();
  if not found then return false;end if;
  delete from public.export_snapshot_rows where snapshot_id=p_snapshot_id and owner_id=auth.uid();
  return true;
end;
$$;

create or replace function public.purge_expired_export_snapshots() returns bigint
language plpgsql security definer set search_path='' as $$
declare ids uuid[];
begin
  select array_agg(id) into ids from
    (select id from public.export_snapshots where expires_at<=now() and purged_at is null order by expires_at limit 100 for update skip locked) expired;
  delete from public.export_snapshot_rows where snapshot_id=any(ids);
  update public.export_snapshots set purged_at=clock_timestamp(),datasets='{}',row_count=0,json_bytes=0 where id=any(ids);
  return coalesce(cardinality(ids),0);
end;
$$;
revoke all on function public.export_dataset_names(),public.create_export_snapshot(uuid),public.read_export_snapshot(uuid,bigint,integer),public.discard_export_snapshot(uuid),public.purge_expired_export_snapshots() from public,anon,authenticated;
grant execute on function public.export_dataset_names(),public.create_export_snapshot(uuid),public.read_export_snapshot(uuid,bigint,integer),public.discard_export_snapshot(uuid) to authenticated;
grant execute on function public.purge_expired_export_snapshots() to service_role;

-- Snapshot content expires from reads after 24h and is physically purged hourly.
-- Minimal request tombstones prevent old retries from capturing a different archive.
-- This job touches export snapshots only, never canonical records or media.
create extension if not exists pg_cron with schema pg_catalog;
select cron.schedule('memotrail-expired-export-snapshots','17 * * * *','select public.purge_expired_export_snapshots()');
