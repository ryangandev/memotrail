-- Ordinary Entry links reuse Goal progress relationships without changing protected system links.
create index if not exists entry_links_owner_target_relationship_idx
  on public.entry_links(owner_id,target_entry_id,relationship,source_entry_id);

create function public.entry_relations(p_entry_id uuid,p_mode text default 'outgoing',p_query text default '',p_limit integer default 20,p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare source public.entries; result jsonb;
begin
  if p_mode is null or p_mode not in ('outgoing','incoming','candidates') or p_query is null or length(p_query)>200
    or p_limit is null or p_limit not between 1 and 50 or p_offset is null or p_offset not between 0 and 100000 then
    raise exception using errcode='22023',message='invalid_relation_page';
  end if;
  select * into source from public.entries where id=p_entry_id and owner_id=auth.uid() and deleted_at is null;
  if not found then return null; end if;
  with matches as (
    select e.id entry_id,e.title,left(e.body,160) excerpt,e.entry_type,e.deleted_at is not null is_deleted
    from public.entries e
    where e.owner_id=source.owner_id and e.id<>source.id
      and (btrim(p_query)='' or strpos(lower(coalesce(e.title,'')||' '||e.body),lower(btrim(p_query)))>0)
      and case p_mode
        when 'outgoing' then exists(select 1 from public.entry_links l where l.owner_id=source.owner_id and l.source_entry_id=source.id and l.target_entry_id=e.id and l.relationship='related')
        when 'incoming' then exists(select 1 from public.entry_links l where l.owner_id=source.owner_id and l.source_entry_id=e.id and l.target_entry_id=source.id and l.relationship='related')
        else e.deleted_at is null and not exists(select 1 from public.entry_links l where l.owner_id=source.owner_id and l.source_entry_id=source.id and l.target_entry_id=e.id and l.relationship='related')
      end
  ), page as (
    select * from matches order by lower(coalesce(nullif(btrim(title),''),nullif(excerpt,''),'Untitled Entry')),entry_id limit p_limit offset p_offset
  )
  select jsonb_build_object('revision',source.revision,'items',coalesce((select jsonb_agg(to_jsonb(page) order by lower(coalesce(nullif(btrim(title),''),nullif(excerpt,''),'Untitled Entry')),entry_id) from page),'[]'),
    'total_count',(select count(*) from matches)) into result;
  return result;
end;
$$;

create function public.set_entry_relation(p_entry_id uuid,p_target_id uuid,p_expected_revision integer,p_linked boolean)
returns integer language plpgsql security definer set search_path='' as $$
declare source public.entries; target public.entries; exists_link boolean; new_revision integer;
begin
  if p_entry_id is null or p_target_id is null or p_entry_id=p_target_id or p_expected_revision is null or p_expected_revision<1 or p_linked is null then
    raise exception using errcode='22023',message='invalid_relation_request';
  end if;
  -- Lock in stable order, including the target lifecycle, for competing two-way edits.
  perform 1 from public.entries where id in (p_entry_id,p_target_id) and owner_id=auth.uid() order by id for update;
  select * into source from public.entries where id=p_entry_id and owner_id=auth.uid();
  select * into target from public.entries where id=p_target_id and owner_id=auth.uid();
  if source.id is null or target.id is null or source.deleted_at is not null or source.revision<>p_expected_revision
    or (p_linked and target.deleted_at is not null) then return null; end if;
  select exists(select 1 from public.entry_links where owner_id=source.owner_id and source_entry_id=source.id and target_entry_id=target.id and relationship='related') into exists_link;
  if exists_link=p_linked then return source.revision; end if;
  if p_linked and (select count(*) from public.entry_links where owner_id=source.owner_id and source_entry_id=source.id and relationship='related')>=100 then
    raise exception using errcode='22023',message='relation_limit';
  end if;
  -- Archive the complete old relationship state before mutating it. No writing or dates change.
  update public.entries set updated_at=now() where id=source.id returning revision into new_revision;
  if p_linked then
    insert into public.entry_links(source_entry_id,target_entry_id,owner_id,relationship) values(source.id,target.id,source.owner_id,'related');
  else
    delete from public.entry_links where owner_id=source.owner_id and source_entry_id=source.id and target_entry_id=target.id and relationship='related';
  end if;
  return new_revision;
end;
$$;
revoke all on function public.entry_relations(uuid,text,text,integer,integer),public.set_entry_relation(uuid,uuid,integer,boolean) from public,anon;
grant execute on function public.entry_relations(uuid,text,text,integer,integer),public.set_entry_relation(uuid,uuid,integer,boolean) to authenticated;
