-- Let each client hide deferred entity kinds without breaking older clients.
-- Existing callers keep the full People, Places, and Habits search by default.
drop function public.search_library_entities(text,integer,integer);

create function public.search_library_entities(
  p_query text,
  p_limit integer default 20,
  p_offset integer default 0,
  p_kinds text[] default array['person','place','habit']::text[]
)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare q text:=btrim(coalesce(p_query,'')); result jsonb;
begin
  if length(q)>200 or p_limit is null or p_limit<1 or p_limit>50
    or p_offset is null or p_offset<0 or p_offset>10000
    or p_kinds is null or cardinality(p_kinds)<1 or cardinality(p_kinds)>3
    or not (p_kinds <@ array['person','place','habit']::text[]) then
    raise exception using errcode='22023',message='invalid_library_search';
  end if;
  with candidates as (
    select p.id,'person'::text kind,p.name,coalesce(p.notes,'') notes,
      coalesce(p.relationship_label,'') details
    from public.people p
    where p.owner_id=auth.uid() and p.deleted_at is null and 'person'=any(p_kinds)
    union all
    select p.id,'place',p.name,coalesce(p.notes,''),
      concat_ws(' ',p.address,p.city,p.region,p.country,p.latitude::text,p.longitude::text)
    from public.places p
    where p.owner_id=auth.uid() and p.deleted_at is null and 'place'=any(p_kinds)
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
      and 'habit'=any(p_kinds)
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

revoke all on function public.search_library_entities(text,integer,integer,text[]) from public,anon;
grant execute on function public.search_library_entities(text,integer,integer,text[]) to authenticated;
