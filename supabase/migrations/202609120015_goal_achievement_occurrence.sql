create function public.achieve_goal_with_occurrence(
  p_goal_entry_id uuid,
  p_expected_revision integer,
  p_occurred_start timestamptz,
  p_date_precision text,
  p_occurred_label text,
  p_occurred_timezone text,
  p_occurred_end timestamptz
)
returns table (
  goal_entry_id uuid,
  goal_revision integer,
  first_time_entry_id uuid
)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  goal_owner_id uuid := auth.uid();
  achieved_goal_title text;
  achieved_goal_revision integer;
  new_first_time_id uuid;
  normalized_label text := nullif(btrim(p_occurred_label), '');
  normalized_timezone text := nullif(btrim(p_occurred_timezone), '');
begin
  if goal_owner_id is null or p_goal_entry_id is null then
    return;
  end if;
  if p_expected_revision is null or p_expected_revision < 1 then
    raise exception using errcode = '22023', message = 'invalid_goal_achievement';
  end if;
  update public.entries
  set inbox_status = 'organized'
  where entries.id = p_goal_entry_id
    and entries.owner_id = goal_owner_id
    and entries.revision = p_expected_revision
    and entries.entry_type = 'goal'
    and entries.deleted_at is null
    and exists (
      select 1
      from public.goals
      where goals.entry_id = entries.id
        and goals.owner_id = goal_owner_id
        and goals.status <> 'achieved'
    )
    and exists (
      select 1
      from public.entry_collections
      join public.collections
        on collections.id = entry_collections.collection_id
        and collections.owner_id = entry_collections.owner_id
      where entry_collections.entry_id = entries.id
        and entry_collections.owner_id = goal_owner_id
        and collections.archived_at is null
        and (collections.system_key = 'bucket_list' or lower(btrim(collections.name)) = 'bucket list')
    )
  returning entries.title, entries.revision
  into achieved_goal_title, achieved_goal_revision;

  if achieved_goal_title is null then
    return;
  end if;

  update public.goals
  set status = 'achieved'
  where goals.entry_id = p_goal_entry_id
    and goals.owner_id = goal_owner_id;

  select entry_id into new_first_time_id from public.save_first_time_with_occurrence(
    achieved_goal_title, '', p_occurred_start, p_date_precision, normalized_label,
    case when p_occurred_start is null then null else normalized_timezone end,
    '{}', '{}', null, null, p_occurred_end
  );

  insert into public.entry_links (source_entry_id, target_entry_id, owner_id, relationship)
  values (p_goal_entry_id, new_first_time_id, goal_owner_id, 'achievement');

  return query
  select p_goal_entry_id, achieved_goal_revision, new_first_time_id;
end;
$$;

revoke all on function public.achieve_goal_with_occurrence(uuid,integer,timestamptz,text,text,text,timestamptz) from public,anon;
grant execute on function public.achieve_goal_with_occurrence(uuid,integer,timestamptz,text,text,text,timestamptz) to authenticated;

-- Preserve legacy validation and signature, then use the same atomic operation.
create or replace function public.mark_goal_achieved_with_first_time(
  p_goal_entry_id uuid,p_expected_revision integer,p_occurred_start timestamptz,
  p_date_precision text,p_occurred_label text,p_occurred_timezone text
) returns table(goal_entry_id uuid,goal_revision integer,first_time_entry_id uuid)
language plpgsql security invoker set search_path='' as $$
begin
  if auth.uid() is null or p_goal_entry_id is null then return; end if;
  if p_expected_revision is null or p_expected_revision < 1 or p_occurred_start is null
    or nullif(btrim(p_occurred_timezone),'') is null or length(btrim(p_occurred_timezone)) > 100
  then raise exception using errcode='22023',message='invalid_goal_achievement'; end if;
  if p_date_precision is null or p_date_precision not in ('exact','day','month','year','approximate','age')
    or length(coalesce(btrim(p_occurred_label),'')) > 200
  then raise exception using errcode='22023',message='invalid_goal_achievement_date'; end if;
  begin perform pg_catalog.timezone(btrim(p_occurred_timezone),p_occurred_start);
  exception when invalid_parameter_value then
    raise exception using errcode='22023',message='invalid_goal_achievement_timezone';
  end;
  return query select * from public.achieve_goal_with_occurrence(
    p_goal_entry_id,p_expected_revision,p_occurred_start,p_date_precision,p_occurred_label,p_occurred_timezone,null);
end;
$$;
