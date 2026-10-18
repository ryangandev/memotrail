-- Indexing functions for the Web server, which drains stale Entries with the signed-in
-- user's session. A user can only index their own Entries; storing nonsense vectors
-- would only degrade their own search.

create function public.claim_entry_search_index_jobs(p_model text, p_limit integer)
returns table(entry_id uuid, source_hash text, title text, body text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  claim_owner_id uuid := auth.uid();
begin
  if claim_owner_id is null then
    return;
  end if;
  if p_model is null or p_model !~ '^[A-Za-z0-9._/@:-]{1,120}$' then
    raise exception using errcode = '22023', message = 'invalid_search_model';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 16 then
    raise exception using errcode = '22023', message = 'invalid_search_limit';
  end if;

  return query
  with due as (
    select state.entry_id as due_entry_id
    from public.entry_search_index_state as state
    join public.entries as item
      on item.id = state.entry_id and item.owner_id = state.owner_id
    where state.owner_id = claim_owner_id
      and state.status <> 'disabled'
      and state.next_attempt_at <= timezone('utc', now())
      and (state.leased_until is null or state.leased_until <= timezone('utc', now()))
      and (
        state.status in ('pending', 'failed')
        or (state.status = 'indexed' and state.indexed_model is distinct from p_model)
      )
    -- Active Entries first, newest writing first, so recent work becomes searchable soonest.
    order by (item.deleted_at is not null), item.updated_at desc, item.id
    limit p_limit
    for update of state skip locked
  ),
  leased as (
    update public.entry_search_index_state as state
    set leased_until = timezone('utc', now()) + interval '2 minutes',
        updated_at = timezone('utc', now())
    from due
    where state.entry_id = due.due_entry_id
    returning state.entry_id as leased_entry_id, state.source_hash as leased_hash
  )
  select leased.leased_entry_id, encode(leased.leased_hash, 'hex'), item.title, item.body
  from leased
  join public.entries as item
    on item.id = leased.leased_entry_id and item.owner_id = claim_owner_id
  order by (item.deleted_at is not null), item.updated_at desc, item.id;
end;
$$;

create function public.store_entry_search_chunks(
  p_entry_id uuid,
  p_source_hash text,
  p_model text,
  p_chunks jsonb
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  store_owner_id uuid := auth.uid();
  state_row public.entry_search_index_state%rowtype;
  body_length integer;
  chunk jsonb;
  chunk_start integer;
  chunk_end integer;
  expected_index integer := 0;
  component_total integer;
  component_numbers integer;
  component_largest numeric;
  component_energy numeric;
begin
  if store_owner_id is null then
    return false;
  end if;
  if p_model is null or p_model !~ '^[A-Za-z0-9._/@:-]{1,120}$' then
    raise exception using errcode = '22023', message = 'invalid_search_model';
  end if;
  if p_source_hash is null or p_source_hash !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'invalid_source_hash';
  end if;
  if p_chunks is null or jsonb_typeof(p_chunks) <> 'array' or jsonb_array_length(p_chunks) > 200 then
    raise exception using errcode = '22023', message = 'invalid_chunks';
  end if;

  select * into state_row
  from public.entry_search_index_state as state
  where state.entry_id = p_entry_id and state.owner_id = store_owner_id
  for update;

  -- Missing, switched off, or edited while it was being embedded: leave it for a later drain.
  if not found
    or state_row.status = 'disabled'
    or state_row.source_hash is distinct from decode(p_source_hash, 'hex')
  then
    return false;
  end if;

  select length(item.body) into body_length
  from public.entries as item
  where item.id = p_entry_id and item.owner_id = store_owner_id;

  for chunk in select value from jsonb_array_elements(p_chunks) loop
    if jsonb_typeof(chunk) <> 'object'
      or jsonb_typeof(chunk -> 'index') <> 'number'
      or jsonb_typeof(chunk -> 'start') <> 'number'
      or jsonb_typeof(chunk -> 'end') <> 'number'
      or jsonb_typeof(chunk -> 'embedding') <> 'array'
      or (chunk ->> 'index') !~ '^[0-9]{1,3}$'
      or (chunk ->> 'start') !~ '^[0-9]{1,9}$'
      or (chunk ->> 'end') !~ '^[0-9]{1,9}$'
    then
      raise exception using errcode = '22023', message = 'invalid_chunks';
    end if;
    chunk_start := (chunk ->> 'start')::integer;
    chunk_end := (chunk ->> 'end')::integer;
    if (chunk ->> 'index')::integer <> expected_index
      or chunk_start > chunk_end
      or chunk_end > body_length
    then
      raise exception using errcode = '22023', message = 'invalid_chunks';
    end if;
    expected_index := expected_index + 1;

    -- Exactly 1024 finite numbers with a non-zero norm.
    select count(*), count(parts.number), coalesce(max(abs(parts.number)), 0),
           coalesce(sum(parts.number * parts.number), 0)
    into component_total, component_numbers, component_largest, component_energy
    from (
      select case
        when jsonb_typeof(component.value) = 'number' then (component.value #>> '{}')::numeric
      end as number
      from jsonb_array_elements(chunk -> 'embedding') as component(value)
    ) as parts;
    if component_total <> 1024
      or component_numbers <> 1024
      or component_largest > 1000000
      or component_energy <= 0
    then
      raise exception using errcode = '22023', message = 'invalid_chunks';
    end if;
  end loop;

  delete from public.entry_search_chunks
  where entry_id = p_entry_id and owner_id = store_owner_id;

  insert into public.entry_search_chunks (
    entry_id, owner_id, chunk_index, source_hash, model, char_start, char_end, embedding
  )
  select
    p_entry_id,
    store_owner_id,
    (item.value ->> 'index')::smallint,
    state_row.source_hash,
    p_model,
    (item.value ->> 'start')::integer,
    (item.value ->> 'end')::integer,
    (array(
      select (component.value #>> '{}')::real
      from jsonb_array_elements(item.value -> 'embedding') with ordinality as component(value, position)
      order by component.position
    )::extensions.vector(1024))::extensions.halfvec(1024)
  from jsonb_array_elements(p_chunks) as item(value);

  update public.entry_search_index_state as state
  set status = case when jsonb_array_length(p_chunks) = 0 then 'empty' else 'indexed' end,
      indexed_hash = state_row.source_hash,
      indexed_model = p_model,
      attempts = 0,
      last_error = null,
      leased_until = null,
      updated_at = timezone('utc', now())
  where state.entry_id = p_entry_id;
  return true;
end;
$$;

-- Only for a failure about one Entry, such as the service rejecting its text. An
-- unavailable service never calls this, so an outage does not use up attempts.
create function public.fail_entry_search_index_job(
  p_entry_id uuid,
  p_source_hash text,
  p_error text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  fail_owner_id uuid := auth.uid();
begin
  if fail_owner_id is null then
    return;
  end if;
  if p_error is null or p_error !~ '^[a-z_]{1,64}$' then
    raise exception using errcode = '22023', message = 'invalid_search_error';
  end if;
  if p_source_hash is null or p_source_hash !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'invalid_source_hash';
  end if;

  update public.entry_search_index_state as state
  set status = 'failed',
      attempts = state.attempts + 1,
      last_error = p_error,
      leased_until = null,
      next_attempt_at = timezone('utc', now())
        + least(interval '6 hours', interval '1 minute' * power(2, least(state.attempts, 9))),
      updated_at = timezone('utc', now())
  where state.entry_id = p_entry_id
    and state.owner_id = fail_owner_id
    and state.status <> 'disabled'
    and state.source_hash = decode(p_source_hash, 'hex');
end;
$$;

create function public.search_index_status(p_model text)
returns table(enabled boolean, pending integer)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  status_owner_id uuid := auth.uid();
begin
  if status_owner_id is null then
    return;
  end if;
  if p_model is null or p_model !~ '^[A-Za-z0-9._/@:-]{1,120}$' then
    raise exception using errcode = '22023', message = 'invalid_search_model';
  end if;

  return query
  select
    coalesce((
      select profile.semantic_search_enabled
      from public.profiles as profile
      where profile.user_id = status_owner_id
    ), true),
    (
      select count(*)::integer
      from public.entry_search_index_state as state
      join public.entries as item
        on item.id = state.entry_id and item.owner_id = state.owner_id
      where state.owner_id = status_owner_id
        and state.status <> 'disabled'
        and item.deleted_at is null
        and not (
          state.status = 'empty'
          or (state.status = 'indexed' and state.indexed_model = p_model)
        )
    );
end;
$$;

revoke all on function public.claim_entry_search_index_jobs(text, integer) from public, anon;
revoke all on function public.store_entry_search_chunks(uuid, text, text, jsonb) from public, anon;
revoke all on function public.fail_entry_search_index_job(uuid, text, text) from public, anon;
revoke all on function public.search_index_status(text) from public, anon;
grant execute on function public.claim_entry_search_index_jobs(text, integer) to authenticated;
grant execute on function public.store_entry_search_chunks(uuid, text, text, jsonb) to authenticated;
grant execute on function public.fail_entry_search_index_job(uuid, text, text) to authenticated;
grant execute on function public.search_index_status(text) to authenticated;
