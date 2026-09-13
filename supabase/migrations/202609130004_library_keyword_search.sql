-- Independent entities are searchable without manufacturing duplicate Entries
-- or requiring an AI provider. Entry-specific filters remain Entry-specific.
create function public.library_text_matches(p_text text,p_query text)
returns boolean language sql immutable security invoker set search_path='' as $$
  select length(btrim(coalesce(p_query,'')))>0 and (
    strpos(lower(coalesce(p_text,'')),lower(btrim(p_query)))>0 or
    case when p_query ~ '[[:alnum:]]' then
      to_tsvector('simple',coalesce(p_text,'')) @@ plainto_tsquery('simple',p_query)
    else false end
  );
$$;
revoke all on function public.library_text_matches(text,text) from public,anon;
grant execute on function public.library_text_matches(text,text) to authenticated;

create function public.search_library_entities(p_query text,p_limit integer default 20,p_offset integer default 0)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare q text:=btrim(coalesce(p_query,'')); result jsonb;
begin
  if length(q)>200 or p_limit is null or p_limit<1 or p_limit>50
    or p_offset is null or p_offset<0 or p_offset>10000 then
    raise exception using errcode='22023',message='invalid_library_search';
  end if;
  with candidates as (
    select p.id,'person'::text kind,p.name,coalesce(p.notes,'') notes,
      coalesce(p.relationship_label,'') details
    from public.people p where p.owner_id=auth.uid() and p.deleted_at is null
    union all
    select p.id,'place',p.name,coalesce(p.notes,''),
      concat_ws(' ',p.address,p.city,p.region,p.country,p.latitude::text,p.longitude::text)
    from public.places p where p.owner_id=auth.uid() and p.deleted_at is null
    union all
    select h.id,'habit',h.name,coalesce(note.note,''),
      concat_ws(' ',h.tracking_mode,h.measurement_unit,h.target_value::text)
    from public.habits h left join lateral (
      select o.note from public.habit_occurrences o where o.habit_id=h.id
        and o.owner_id=auth.uid() and o.note is not null
        and public.library_text_matches(concat_ws(' ',h.name,h.tracking_mode,h.measurement_unit,o.note),q)
      order by o.local_date desc,o.id limit 1
    ) note on true
    where h.owner_id=auth.uid() and h.deleted_at is null and h.archived_at is null
  ), matched as (
    select id,kind,name,left(concat_ws(' · ',nullif(details,''),nullif(notes,'')),280) excerpt,
      array_remove(array[
        case when public.library_text_matches(name,q) then 'Name' end,
        case when public.library_text_matches(notes,q) then case when kind='habit' then 'Check-in note' else 'Notes' end end,
        case when public.library_text_matches(details,q) then 'Details' end
      ],null) match_reasons,
      case when lower(name)=lower(q) then 0 when strpos(lower(name),lower(q))>0 then 1 else 2 end rank
    from candidates where public.library_text_matches(concat_ws(' ',name,notes,details),q)
  ) select jsonb_build_object('total_count',(select count(*) from matched),'items',coalesce((
    select jsonb_agg(to_jsonb(page)-'rank' order by page.rank,lower(page.name),page.kind,page.id)
    from (select * from matched order by rank,lower(name),kind,id limit p_limit offset p_offset) page
  ),'[]'::jsonb)) into result;
  return result;
end;
$$;
revoke all on function public.search_library_entities(text,integer,integer) from public,anon;
grant execute on function public.search_library_entities(text,integer,integer) to authenticated;

-- Exact Person deep links do not depend on the first 100 People being loaded.
create function public.person_record(p_person_id uuid)
returns table(id uuid,name text,relationship_label text,notes text,revision integer,linked_entries jsonb,total_count bigint)
language sql stable security invoker set search_path='' as $$
  select p.id,p.name,p.relationship_label,p.notes,p.revision,
    coalesce((select jsonb_agg(jsonb_build_object(
      'id',e.id,'title',e.title,'body',e.body,'entry_type',e.entry_type,'is_deleted',e.deleted_at is not null
    ) order by e.updated_at desc,e.id)
    from public.entry_people ep join public.entries e on e.id=ep.entry_id and e.owner_id=ep.owner_id
    where ep.person_id=p.id and ep.owner_id=auth.uid()),'[]'::jsonb),1::bigint
  from public.people p where p.id=p_person_id and p.owner_id=auth.uid() and p.deleted_at is null;
$$;
revoke all on function public.person_record(uuid) from public,anon;
grant execute on function public.person_record(uuid) to authenticated;
