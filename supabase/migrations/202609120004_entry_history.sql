-- Snapshot Entry-owned state. Shared entity definitions remain independently owned.
create function public.entry_history_snapshot(p_entry public.entries) returns jsonb
language sql stable security definer set search_path='' as $$
  select to_jsonb(p_entry) || jsonb_build_object(
    'history_schema',2,
    'home',(select to_jsonb(h) from public.homes h where h.entry_id=p_entry.id),
    'vehicle',(select to_jsonb(v) from public.vehicles v where v.entry_id=p_entry.id),
    'goal',(select to_jsonb(g) from public.goals g where g.entry_id=p_entry.id),
    'place',(select to_jsonb(p) from public.homes h join public.places p on p.id=h.place_id where h.entry_id=p_entry.id),
    'collections',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name) order by c.name) from public.entry_collections ec join public.collections c on c.id=ec.collection_id where ec.entry_id=p_entry.id),'[]'),
    'tags',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'name',t.name) order by t.name) from public.entry_tags et join public.tags t on t.id=et.tag_id where et.entry_id=p_entry.id),'[]'),
    'people',coalesce((select jsonb_agg(to_jsonb(ep)||jsonb_build_object('name',p.name) order by ep.person_id,ep.relationship) from public.entry_people ep join public.people p on p.id=ep.person_id where ep.entry_id=p_entry.id),'[]'),
    'places',coalesce((select jsonb_agg(to_jsonb(ep)||jsonb_build_object('name',p.name) order by ep.place_id,ep.relationship) from public.entry_places ep join public.places p on p.id=ep.place_id where ep.entry_id=p_entry.id),'[]'),
    'timeline_items',coalesce((select jsonb_agg(to_jsonb(ti)||jsonb_build_object('track_name',tt.name) order by ti.track_id) from public.timeline_items ti join public.timeline_tracks tt on tt.id=ti.track_id where ti.entry_id=p_entry.id),'[]'),
    'timeline',(select jsonb_build_object('track_id',tt.id,'track_name',tt.name,'track_system_key',tt.system_key,'timeline_kind',ti.timeline_kind) from public.timeline_items ti join public.timeline_tracks tt on tt.id=ti.track_id where ti.entry_id=p_entry.id order by (tt.system_key=case p_entry.entry_type when 'home' then 'homes' when 'vehicle' then 'vehicles' else '' end) desc,ti.created_at,tt.id limit 1),
    'links',coalesce((select jsonb_agg(to_jsonb(el) order by el.target_entry_id,el.relationship) from public.entry_links el where el.source_entry_id=p_entry.id),'[]'),
    'related_entry_ids',coalesce((select jsonb_agg(el.target_entry_id order by el.target_entry_id) from public.entry_links el where el.source_entry_id=p_entry.id and el.relationship='related'),'[]'),
    'attachments',coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at,a.id) from public.attachments a where a.entry_id=p_entry.id and a.deleted_at is null),'[]')
  );
$$;
revoke all on function public.entry_history_snapshot(public.entries) from public,anon,authenticated;

create or replace function public.archive_entry_version() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  insert into public.entry_versions(entry_id,owner_id,version,operation,changed_by,snapshot)
  values(old.id,old.owner_id,old.revision,lower(tg_op),auth.uid(),public.entry_history_snapshot(old));
  if tg_op='UPDATE' then new.revision=old.revision+1;new.updated_at=now();return new;end if;
  return old;
end;
$$;

create function public.entry_history_index(p_query text default '',p_limit integer default 50,p_offset integer default 0)
returns table(entry_id uuid,title text,excerpt text,entry_type text,revision integer,is_deleted boolean,version_count bigint,last_changed timestamptz,total_count bigint)
language plpgsql stable security definer set search_path='' as $$
begin
  if p_limit is null or p_limit not between 1 and 50 or p_offset is null or p_offset not between 0 and 100000 or length(coalesce(p_query,''))>200 then
    raise exception using errcode='22023',message='invalid_history_page';end if;
  return query
  select e.id,e.title,left(e.body,160),e.entry_type,e.revision,e.deleted_at is not null,count(v.id),e.updated_at,count(*) over()
  from public.entries e join public.entry_versions v on v.entry_id=e.id
  where e.owner_id=auth.uid() and (coalesce(btrim(p_query),'')='' or strpos(lower(coalesce(e.title,'')||' '||e.body),lower(btrim(p_query)))>0)
  group by e.id order by e.updated_at desc,e.id limit p_limit offset p_offset;
end;
$$;

create function public.entry_history(p_entry_id uuid,p_limit integer default 20,p_offset integer default 0) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare current_entry public.entries;
begin
  if p_limit is null or p_limit not between 1 and 20 or p_offset is null or p_offset not between 0 and 100000 then
    raise exception using errcode='22023',message='invalid_history_page';end if;
  select * into current_entry from public.entries where id=p_entry_id and owner_id=auth.uid();
  if not found then return null;end if;
  return jsonb_build_object('current',public.entry_history_snapshot(current_entry)-'embedding'-'search_document',
    'total_count',(select count(*) from public.entry_versions where entry_id=p_entry_id),
    'versions',(select coalesce(jsonb_agg(to_jsonb(v)||jsonb_build_object('snapshot',v.snapshot-'embedding'-'search_document') order by v.version desc),'[]') from
      (select version,operation,snapshot,created_at from public.entry_versions where entry_id=p_entry_id order by version desc limit p_limit offset p_offset) v));
end;
$$;

create function public.restore_entry_version(p_entry_id uuid,p_version integer,p_expected_revision integer) returns integer
language plpgsql security definer set search_path='' as $$
declare e public.entries; s jsonb; result integer; item jsonb; track_items jsonb; home_record public.homes; vehicle_record public.vehicles; goal_record public.goals;
begin
  select * into e from public.entries where id=p_entry_id and owner_id=auth.uid() for update;
  if not found or e.revision is distinct from p_expected_revision or e.deleted_at is not null then return null;end if;
  select snapshot into s from public.entry_versions where entry_id=e.id and owner_id=e.owner_id and version=p_version;
  if s is null then return null;end if;
  -- All references must still be owned and available. Never silently drop historical relationships.
  for item in select value from jsonb_array_elements(coalesce(s->'collections','[]')) loop
    perform 1 from public.collections where id=(item->>'id')::uuid and owner_id=e.owner_id for share;
    if not found then raise exception using errcode='P0001',message='history_reference_unavailable';end if;
  end loop;
  for item in select value from jsonb_array_elements(coalesce(s->'tags','[]')) loop
    perform 1 from public.tags where id=(item->>'id')::uuid and owner_id=e.owner_id for share;
    if not found then raise exception using errcode='P0001',message='history_reference_unavailable';end if;
  end loop;
  for item in select value from jsonb_array_elements(coalesce(s->'people','[]')) loop
    perform 1 from public.people where id=(item->>'person_id')::uuid and owner_id=e.owner_id and deleted_at is null for share;
    if not found then raise exception using errcode='P0001',message='history_reference_unavailable';end if;
  end loop;
  for item in select value from jsonb_array_elements(coalesce(s->'places','[]')) loop
    perform 1 from public.places where id=(item->>'place_id')::uuid and owner_id=e.owner_id and deleted_at is null for share;
    if not found then raise exception using errcode='P0001',message='history_reference_unavailable';end if;
  end loop;
  track_items:=s->'timeline_items';
  if track_items is null and s?'timeline' then
    track_items:=case when s->'timeline'='null'::jsonb then '[]'::jsonb else jsonb_build_array(s->'timeline') end;
  end if;
  for item in select value from jsonb_array_elements(coalesce(track_items,'[]')) loop
    perform 1 from public.timeline_tracks where id=(item->>'track_id')::uuid and owner_id=e.owner_id for share;
    if not found then raise exception using errcode='P0001',message='history_reference_unavailable';end if;
  end loop;
  for item in select value from jsonb_array_elements(coalesce(s->'links','[]')) loop
    perform 1 from public.entries where id=(item->>'target_entry_id')::uuid and owner_id=e.owner_id and deleted_at is null for share;
    if not found then raise exception using errcode='P0001',message='history_reference_unavailable';end if;
  end loop;
  if s->'links' is null and s?'related_entry_ids' then
    for item in select value from jsonb_array_elements(s->'related_entry_ids') loop
      perform 1 from public.entries where id=(item#>>'{}')::uuid and owner_id=e.owner_id and deleted_at is null for share;
      if not found then raise exception using errcode='P0001',message='history_reference_unavailable';end if;
    end loop;
  end if;
  for item in select value from jsonb_array_elements(coalesce(s->'attachments','[]')) loop
    perform 1 from public.attachments a join storage.objects o on o.bucket_id=a.bucket_id and o.name=a.object_path
      where a.id=(item->>'id')::uuid and a.entry_id=e.id and a.owner_id=e.owner_id for share of a;
    if not found then raise exception using errcode='P0001',message='history_attachment_unavailable';end if;
  end loop;
  if s->>'entry_type'='home' then
    if s->'home' is null or s->'home'='null'::jsonb then raise exception using errcode='P0001',message='history_details_unavailable';end if;
    home_record:=jsonb_populate_record(null::public.homes,s->'home');
    if home_record.place_id is not null then
      perform 1 from public.places where id=home_record.place_id and owner_id=e.owner_id and deleted_at is null for share;
      if not found then raise exception using errcode='P0001',message='history_reference_unavailable';end if;
    end if;
  elsif s->>'entry_type'='vehicle' then
    if s->'vehicle' is null or s->'vehicle'='null'::jsonb then raise exception using errcode='P0001',message='history_details_unavailable';end if;
    vehicle_record:=jsonb_populate_record(null::public.vehicles,s->'vehicle');
  elsif s->>'entry_type'='goal' then
    if s->'goal' is null or s->'goal'='null'::jsonb then raise exception using errcode='P0001',message='history_details_unavailable';end if;
    goal_record:=jsonb_populate_record(null::public.goals,s->'goal');
  end if;
  -- The normal trigger saves today's state before applying the selected version.
  update public.entries set title=s->>'title',body=coalesce(s->>'body',''),entry_type=s->>'entry_type',inbox_status=s->>'inbox_status',
    occurred_start=(s->>'occurred_start')::timestamptz,occurred_end=(s->>'occurred_end')::timestamptz,
    date_precision=s->>'date_precision',occurred_label=s->>'occurred_label',occurred_timezone=s->>'occurred_timezone',
    source_language=s->>'source_language',metadata=coalesce(s->'metadata','{}'),embedding=null,embedding_model=null,embedding_updated_at=null
  where id=e.id returning revision into result;
  delete from public.homes where entry_id=e.id;
  delete from public.vehicles where entry_id=e.id;
  delete from public.goals where entry_id=e.id;
  if home_record.entry_id is not null then
    insert into public.homes(entry_id,owner_id,place_id,move_in_reason,move_out_reason) values(e.id,e.owner_id,home_record.place_id,home_record.move_in_reason,home_record.move_out_reason);
  elsif vehicle_record.entry_id is not null then
    insert into public.vehicles(entry_id,owner_id,make,model,model_year,color) values(e.id,e.owner_id,vehicle_record.make,vehicle_record.model,vehicle_record.model_year,vehicle_record.color);
  elsif goal_record.entry_id is not null then
    insert into public.goals(entry_id,owner_id,horizon,status,target_date) values(e.id,e.owner_id,goal_record.horizon,goal_record.status,goal_record.target_date);
  end if;
  if s?'collections' then
    delete from public.entry_collections where entry_id=e.id;
    insert into public.entry_collections(entry_id,owner_id,collection_id) select e.id,e.owner_id,(value->>'id')::uuid from jsonb_array_elements(s->'collections');
  end if;
  if s?'tags' then
    delete from public.entry_tags where entry_id=e.id;
    insert into public.entry_tags(entry_id,owner_id,tag_id) select e.id,e.owner_id,(value->>'id')::uuid from jsonb_array_elements(s->'tags');
  end if;
  if s?'people' then
    delete from public.entry_people where entry_id=e.id;
    insert into public.entry_people(entry_id,owner_id,person_id,relationship) select e.id,e.owner_id,(value->>'person_id')::uuid,value->>'relationship' from jsonb_array_elements(s->'people');
  end if;
  if s?'places' then
    delete from public.entry_places where entry_id=e.id;
    insert into public.entry_places(entry_id,owner_id,place_id,relationship) select e.id,e.owner_id,(value->>'place_id')::uuid,value->>'relationship' from jsonb_array_elements(s->'places');
  end if;
  if track_items is not null then
    delete from public.timeline_items where entry_id=e.id;
    insert into public.timeline_items(entry_id,owner_id,track_id,timeline_kind,sort_order) select e.id,e.owner_id,(value->>'track_id')::uuid,value->>'timeline_kind',coalesce((value->>'sort_order')::integer,0) from jsonb_array_elements(track_items);
  end if;
  if s?'links' then
    delete from public.entry_links where source_entry_id=e.id;
    insert into public.entry_links(source_entry_id,owner_id,target_entry_id,relationship) select e.id,e.owner_id,(value->>'target_entry_id')::uuid,value->>'relationship' from jsonb_array_elements(s->'links');
  elsif s?'related_entry_ids' then
    delete from public.entry_links where source_entry_id=e.id and relationship='related';
    insert into public.entry_links(source_entry_id,owner_id,target_entry_id,relationship) select e.id,e.owner_id,(value#>>'{}')::uuid,'related' from jsonb_array_elements(s->'related_entry_ids');
  end if;
  if s?'attachments' then
    update public.attachments set deleted_at=case when id in (select (value->>'id')::uuid from jsonb_array_elements(s->'attachments')) then null else coalesce(deleted_at,now()) end where entry_id=e.id;
  end if;
  return result;
end;
$$;
revoke all on function public.entry_history_index(text,integer,integer),public.entry_history(uuid,integer,integer),public.restore_entry_version(uuid,integer,integer) from public,anon,authenticated;
grant execute on function public.entry_history_index(text,integer,integer),public.entry_history(uuid,integer,integer),public.restore_entry_version(uuid,integer,integer) to authenticated;
