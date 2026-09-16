-- A Goal is a distinct Life Wiki item. Creating one from existing material
-- preserves the source and records provenance instead of changing its Kind.

create function public.extract_goal_from_item(
  p_source_entry_id uuid,
  p_source_revision integer,
  p_goal_id uuid,
  p_title text,
  p_horizon text,
  p_status text,
  p_target_date date
)
returns table (
  source_entry_id uuid,
  source_revision integer,
  goal_entry_id uuid,
  goal_revision integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  extraction_owner_id uuid := auth.uid();
  source public.entries;
  created_goal public.entries;
  existing_goal public.entries;
begin
  if extraction_owner_id is null then
    return;
  end if;

  p_title := nullif(btrim(p_title), '');
  if p_source_entry_id is null
    or p_source_revision is null
    or p_source_revision < 1
    or p_goal_id is null
    or p_source_entry_id = p_goal_id
    or p_title is null
    or length(p_title) > 200
    or p_horizon is null
    or p_horizon not in ('short_term', 'long_term', 'someday')
    or p_status is null
    or p_status not in ('considering', 'active', 'paused', 'achieved', 'let_go')
    or (p_target_date is not null and (
      not isfinite(p_target_date)
      or p_target_date < date '0001-01-01'
      or p_target_date > date '9999-12-31'
    ))
  then
    raise exception using errcode = '22023', message = 'invalid_goal_extraction';
  end if;

  -- The caller chooses the target id so a lost successful response can be
  -- retried without creating a second Goal.
  select goal_entry.*
  into existing_goal
  from public.entries as goal_entry
  join public.goals as goal
    on goal.entry_id = goal_entry.id
    and goal.owner_id = goal_entry.owner_id
  where goal_entry.id = p_goal_id
    and goal_entry.owner_id = extraction_owner_id
    and goal_entry.deleted_at is null
    and goal_entry.item_kind = 'goal'
    and goal_entry.item_subtype = 'goal'
    and goal_entry.title = p_title
    and goal.horizon = p_horizon
    and goal.status = p_status
    and goal.target_date is not distinct from p_target_date
    and exists (
      select 1
      from public.entry_links as link
      where link.owner_id = extraction_owner_id
        and link.source_entry_id = p_source_entry_id
        and link.target_entry_id = goal_entry.id
        and link.relationship = 'derived'
    );

  if found then
    return query
    select source_entry.id, source_entry.revision, existing_goal.id, existing_goal.revision
    from public.entries as source_entry
    where source_entry.id = p_source_entry_id
      and source_entry.owner_id = extraction_owner_id;
    return;
  end if;

  if exists (select 1 from public.entries where id = p_goal_id) then
    return;
  end if;

  select *
  into source
  from public.entries
  where id = p_source_entry_id
    and owner_id = extraction_owner_id
    and revision = p_source_revision
    and item_kind <> 'goal'
    and deleted_at is null
  for update;

  if not found then
    return;
  end if;

  insert into public.entries (
    id,
    owner_id,
    title,
    body,
    metadata,
    source_language,
    entry_type,
    item_kind,
    item_subtype,
    inbox_status,
    date_precision,
    occurred_timezone
  )
  values (
    p_goal_id,
    extraction_owner_id,
    p_title,
    source.body,
    case
      when source.metadata ? 'body_rich'
        then jsonb_build_object('body_rich', source.metadata->'body_rich')
      else '{}'::jsonb
    end,
    source.source_language,
    'goal',
    'goal',
    'goal',
    'organized',
    'unknown',
    'UTC'
  )
  returning * into created_goal;

  insert into public.goals (
    entry_id,
    owner_id,
    horizon,
    status,
    target_date
  )
  values (
    created_goal.id,
    extraction_owner_id,
    p_horizon,
    p_status,
    p_target_date
  );

  insert into public.entry_links (
    source_entry_id,
    target_entry_id,
    owner_id,
    relationship
  )
  values
    (source.id, created_goal.id, extraction_owner_id, 'derived'),
    (created_goal.id, source.id, extraction_owner_id, 'derived_from');

  return query
  select source.id, source.revision, created_goal.id, created_goal.revision;
end;
$$;

revoke all on function public.extract_goal_from_item(uuid,integer,uuid,text,text,text,date) from public, anon;
grant execute on function public.extract_goal_from_item(uuid,integer,uuid,text,text,text,date) to authenticated;

comment on function public.extract_goal_from_item(uuid,integer,uuid,text,text,text,date) is
  'Creates an idempotent, separately editable Goal linked to a preserved source Wiki Item.';

comment on function public.convert_entry_to_goal(uuid,integer,text,text,text,date) is
  'Deprecated compatibility RPC for older native clients. New clients must create and link a distinct Goal with extract_goal_from_item.';
