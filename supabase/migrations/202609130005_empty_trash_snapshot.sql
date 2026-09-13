-- Preparation is read-only. Clients confirm this exact snapshot, then use the
-- existing revision/deleted_at-checked Storage and permanent-deletion boundary.
create function public.prepare_empty_trash()
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;
begin
  if auth.uid() is null then
    raise exception using errcode='42501',message='authentication_required';
  end if;
  with candidates as (
    select 'entry'::text item_kind,e.id item_id,e.deleted_at,e.revision
      from public.entries e where e.owner_id=auth.uid() and e.deleted_at is not null
    union all
    select 'attachment',a.id,a.deleted_at,null::integer
      from public.attachments a join public.entries e on e.id=a.entry_id and e.owner_id=a.owner_id
      where a.owner_id=auth.uid() and a.deleted_at is not null and e.deleted_at is null
    union all
    select 'habit',h.id,h.deleted_at,h.revision
      from public.habits h where h.owner_id=auth.uid() and h.deleted_at is not null
    union all
    select 'place',p.id,p.deleted_at,p.revision
      from public.places p where p.owner_id=auth.uid() and p.deleted_at is not null
    union all
    select 'person',p.id,p.deleted_at,p.revision
      from public.people p where p.owner_id=auth.uid() and p.deleted_at is not null
    union all
    select 'collection',c.id,c.archived_at,c.revision
      from public.collections c where c.owner_id=auth.uid() and c.archived_at is not null
  ), bounded as (
    select * from candidates order by
      case item_kind when 'entry' then 0 when 'attachment' then 1 else 2 end,
      item_kind,item_id limit 10001
  ) select coalesce(jsonb_agg(to_jsonb(bounded) order by
      case item_kind when 'entry' then 0 when 'attachment' then 1 else 2 end,
      item_kind,item_id),'[]'::jsonb) into result from bounded;
  if jsonb_array_length(result)>10000 then
    raise exception using errcode='54000',message='trash_snapshot_too_large';
  end if;
  return result;
end;
$$;
revoke all on function public.prepare_empty_trash() from public,anon;
grant execute on function public.prepare_empty_trash() to authenticated;
comment on function public.prepare_empty_trash() is
  'Read-only exact owner-scoped manifest across all Trash pages; no new content is included after confirmation, and each later deletion still checks revision and deletion timestamp.';
