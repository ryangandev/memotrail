alter table public.habits
  add column if not exists revision integer not null default 1 check (revision > 0),
  add column if not exists deleted_at timestamptz;

alter table public.habit_occurrences
  add column if not exists revision integer not null default 1 check (revision > 0),
  add constraint habit_occurrences_id_owner_unique unique (id, owner_id);

create index if not exists habits_owner_active_name_idx
  on public.habits (owner_id, lower(name), id)
  where archived_at is null and deleted_at is null;

create table public.habit_versions (
  id bigint generated always as identity primary key,
  habit_id uuid not null,
  owner_id uuid not null,
  version integer not null,
  operation text not null check (operation in ('update', 'delete')),
  changed_by uuid,
  snapshot jsonb not null,
  created_at timestamptz not null default timezone('utc', now()),
  foreign key (habit_id, owner_id) references public.habits(id, owner_id) on delete cascade,
  unique (habit_id, version)
);

create table public.habit_occurrence_versions (
  id bigint generated always as identity primary key,
  occurrence_id uuid not null,
  habit_id uuid not null,
  owner_id uuid not null,
  version integer not null,
  operation text not null check (operation in ('update', 'delete')),
  changed_by uuid,
  snapshot jsonb not null,
  created_at timestamptz not null default timezone('utc', now()),
  foreign key (occurrence_id, owner_id)
    references public.habit_occurrences(id, owner_id) on delete cascade,
  foreign key (habit_id, owner_id) references public.habits(id, owner_id) on delete cascade,
  unique (occurrence_id, version)
);

create index habit_versions_owner_habit_idx
  on public.habit_versions (owner_id, habit_id, version desc);

create index habit_occurrence_versions_owner_occurrence_idx
  on public.habit_occurrence_versions (owner_id, occurrence_id, version desc);

alter table public.habit_versions enable row level security;
alter table public.habit_occurrence_versions enable row level security;

create policy "Users can view their own habit history"
on public.habit_versions for select
to authenticated
using ((select auth.uid()) = owner_id);

create policy "Users can view their own habit occurrence history"
on public.habit_occurrence_versions for select
to authenticated
using ((select auth.uid()) = owner_id);

revoke all on public.habit_versions, public.habit_occurrence_versions from authenticated;
grant select on public.habit_versions, public.habit_occurrence_versions to authenticated;
revoke all on public.habit_versions, public.habit_occurrence_versions from anon;

create or replace function public.archive_habit_version()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.habit_versions (
    habit_id,
    owner_id,
    version,
    operation,
    changed_by,
    snapshot
  )
  values (
    old.id,
    old.owner_id,
    old.revision,
    lower(tg_op),
    auth.uid(),
    to_jsonb(old)
  );

  if tg_op = 'UPDATE' then
    new.revision = old.revision + 1;
    new.updated_at = timezone('utc', now());
    return new;
  end if;

  return old;
end;
$$;

create or replace function public.archive_habit_occurrence_version()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.habit_occurrence_versions (
    occurrence_id,
    habit_id,
    owner_id,
    version,
    operation,
    changed_by,
    snapshot
  )
  values (
    old.id,
    old.habit_id,
    old.owner_id,
    old.revision,
    lower(tg_op),
    auth.uid(),
    to_jsonb(old)
  );

  if tg_op = 'UPDATE' then
    new.revision = old.revision + 1;
    new.updated_at = timezone('utc', now());
    return new;
  end if;

  return old;
end;
$$;

revoke all on function public.archive_habit_version() from public;
revoke all on function public.archive_habit_occurrence_version() from public;

create trigger archive_habit_before_change
before update or delete on public.habits
for each row execute function public.archive_habit_version();

create trigger archive_habit_occurrence_before_change
before update or delete on public.habit_occurrences
for each row execute function public.archive_habit_occurrence_version();

create or replace function public.habit_schedule_is_valid(p_schedule jsonb)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  schedule_kind text;
  item jsonb;
  seen integer[] := array[]::integer[];
  numeric_value integer;
begin
  if jsonb_typeof(p_schedule) <> 'object' then
    return false;
  end if;

  schedule_kind := p_schedule ->> 'kind';

  if schedule_kind = 'daily' then
    return true;
  end if;

  if schedule_kind = 'weekdays' then
    if jsonb_typeof(p_schedule -> 'weekdays') <> 'array'
      or jsonb_array_length(p_schedule -> 'weekdays') < 1
      or jsonb_array_length(p_schedule -> 'weekdays') > 7 then
      return false;
    end if;

    for item in select value from jsonb_array_elements(p_schedule -> 'weekdays') loop
      if jsonb_typeof(item) <> 'number' or (item #>> '{}') !~ '^[1-7]$' then
        return false;
      end if;
      numeric_value := (item #>> '{}')::integer;
      if numeric_value = any(seen) then
        return false;
      end if;
      seen := array_append(seen, numeric_value);
    end loop;

    return true;
  end if;

  if schedule_kind = 'weekly_target' then
    return coalesce(p_schedule ->> 'target', '') ~ '^[1-7]$';
  end if;

  if schedule_kind = 'interval' then
    if coalesce(p_schedule ->> 'every_days', '') !~ '^[1-9][0-9]{0,2}$' then
      return false;
    end if;
    return (p_schedule ->> 'every_days')::integer <= 365;
  end if;

  return false;
end;
$$;

create or replace function public.habit_is_scheduled(
  p_schedule jsonb,
  p_starts_on date,
  p_ends_on date,
  p_local_date date
)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  schedule_kind text;
begin
  if p_local_date is null
    or p_starts_on is null
    or p_local_date < p_starts_on
    or (p_ends_on is not null and p_local_date > p_ends_on)
    or not public.habit_schedule_is_valid(p_schedule) then
    return false;
  end if;

  schedule_kind := p_schedule ->> 'kind';

  if schedule_kind = 'daily' then
    return true;
  end if;

  if schedule_kind = 'weekdays' then
    return (extract(isodow from p_local_date)::integer)::text in (
      select value #>> '{}'
      from jsonb_array_elements(p_schedule -> 'weekdays')
    );
  end if;

  if schedule_kind = 'interval' then
    return (p_local_date - p_starts_on) % (p_schedule ->> 'every_days')::integer = 0;
  end if;

  -- Weekly targets are open choices within a week rather than fixed daily occurrences.
  return false;
end;
$$;

revoke all on function public.habit_schedule_is_valid(jsonb) from public, anon;
revoke all on function public.habit_is_scheduled(jsonb, date, date, date) from public, anon;
grant execute on function public.habit_schedule_is_valid(jsonb) to authenticated;
grant execute on function public.habit_is_scheduled(jsonb, date, date, date) to authenticated;

create or replace function public.save_habit(
  p_habit_id uuid,
  p_expected_revision integer,
  p_name text,
  p_tracking_mode text,
  p_measurement_unit text,
  p_target_value numeric,
  p_schedule jsonb,
  p_starts_on date,
  p_ends_on date
)
returns table (
  habit_id uuid,
  revision integer,
  was_created boolean
)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  normalized_name text := btrim(coalesce(p_name, ''));
  normalized_unit text := nullif(btrim(coalesce(p_measurement_unit, '')), '');
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;

  if length(normalized_name) < 1 or length(normalized_name) > 120 then
    raise exception using errcode = '22023', message = 'invalid_habit_name';
  end if;

  if p_tracking_mode not in ('check', 'measure') then
    raise exception using errcode = '22023', message = 'invalid_tracking_mode';
  end if;

  if p_tracking_mode = 'check' and (normalized_unit is not null or p_target_value is not null) then
    raise exception using errcode = '22023', message = 'check_habit_cannot_measure';
  end if;

  if p_tracking_mode = 'measure'
    and (normalized_unit is null or length(normalized_unit) > 40
      or p_target_value is null or p_target_value <= 0) then
    raise exception using errcode = '22023', message = 'invalid_measurement';
  end if;

  if not public.habit_schedule_is_valid(p_schedule) then
    raise exception using errcode = '22023', message = 'invalid_habit_schedule';
  end if;

  if p_starts_on is null or (p_ends_on is not null and p_ends_on < p_starts_on) then
    raise exception using errcode = '22023', message = 'invalid_habit_dates';
  end if;

  if p_habit_id is null then
    if p_expected_revision is not null then
      raise exception using errcode = '22023', message = 'unexpected_habit_revision';
    end if;

    return query
    insert into public.habits (
      owner_id,
      name,
      tracking_mode,
      measurement_unit,
      target_value,
      schedule,
      starts_on,
      ends_on
    )
    values (
      auth.uid(),
      normalized_name,
      p_tracking_mode,
      normalized_unit,
      p_target_value,
      p_schedule,
      p_starts_on,
      p_ends_on
    )
    returning habits.id, habits.revision, true;
    return;
  end if;

  if p_expected_revision is null or p_expected_revision < 1 then
    raise exception using errcode = '22023', message = 'invalid_habit_revision';
  end if;

  return query
  update public.habits
  set
    name = normalized_name,
    tracking_mode = p_tracking_mode,
    measurement_unit = normalized_unit,
    target_value = p_target_value,
    schedule = p_schedule,
    starts_on = p_starts_on,
    ends_on = p_ends_on
  where id = p_habit_id
    and owner_id = auth.uid()
    and archived_at is null
    and deleted_at is null
    and habits.revision = p_expected_revision
  returning habits.id, habits.revision, false;
end;
$$;

create or replace function public.record_habit_occurrence(
  p_habit_id uuid,
  p_local_date date,
  p_status text,
  p_measured_value numeric,
  p_note text,
  p_entry_id uuid,
  p_expected_revision integer
)
returns table (
  occurrence_id uuid,
  revision integer,
  was_created boolean
)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  current_habit public.habits%rowtype;
  normalized_note text := nullif(btrim(coalesce(p_note, '')), '');
  existing_occurrence public.habit_occurrences%rowtype;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;

  select * into current_habit
  from public.habits
  where id = p_habit_id
    and owner_id = auth.uid()
    and archived_at is null
    and deleted_at is null;

  if not found then
    raise exception using errcode = '22023', message = 'habit_unavailable';
  end if;

  if p_local_date is null
    or p_local_date < current_habit.starts_on
    or (current_habit.ends_on is not null and p_local_date > current_habit.ends_on) then
    raise exception using errcode = '22023', message = 'occurrence_outside_habit_dates';
  end if;

  if p_status not in ('completed', 'missed', 'skipped') then
    raise exception using errcode = '22023', message = 'invalid_occurrence_status';
  end if;

  if current_habit.schedule ->> 'kind' <> 'weekly_target'
    and not public.habit_is_scheduled(
      current_habit.schedule,
      current_habit.starts_on,
      current_habit.ends_on,
      p_local_date
    ) then
    raise exception using errcode = '22023', message = 'occurrence_not_scheduled';
  end if;

  if current_habit.tracking_mode = 'check' and p_measured_value is not null then
    raise exception using errcode = '22023', message = 'check_occurrence_cannot_measure';
  end if;

  if current_habit.tracking_mode = 'measure'
    and p_status = 'completed'
    and (p_measured_value is null or p_measured_value < 0) then
    raise exception using errcode = '22023', message = 'completed_measure_required';
  end if;

  if p_status <> 'completed' and p_measured_value is not null then
    raise exception using errcode = '22023', message = 'inactive_occurrence_cannot_measure';
  end if;

  if normalized_note is not null and length(normalized_note) > 2000 then
    raise exception using errcode = '22023', message = 'occurrence_note_too_long';
  end if;

  if p_entry_id is not null and not exists (
    select 1
    from public.entries
    where id = p_entry_id
      and owner_id = auth.uid()
      and deleted_at is null
  ) then
    raise exception using errcode = '22023', message = 'linked_entry_unavailable';
  end if;

  select * into existing_occurrence
  from public.habit_occurrences
  where habit_id = p_habit_id
    and owner_id = auth.uid()
    and local_date = p_local_date;

  if not found then
    if p_expected_revision is not null then
      raise exception using errcode = '22023', message = 'unexpected_occurrence_revision';
    end if;

    return query
    insert into public.habit_occurrences (
      habit_id,
      owner_id,
      local_date,
      status,
      measured_value,
      note,
      entry_id
    )
    values (
      p_habit_id,
      auth.uid(),
      p_local_date,
      p_status,
      p_measured_value,
      normalized_note,
      p_entry_id
    )
    returning habit_occurrences.id, habit_occurrences.revision, true;
    return;
  end if;

  if p_expected_revision is null or p_expected_revision <> existing_occurrence.revision then
    return;
  end if;

  return query
  update public.habit_occurrences
  set
    status = p_status,
    measured_value = p_measured_value,
    note = normalized_note,
    entry_id = p_entry_id
  where id = existing_occurrence.id
    and owner_id = auth.uid()
    and habit_occurrences.revision = p_expected_revision
  returning habit_occurrences.id, habit_occurrences.revision, false;
end;
$$;

create or replace function public.trash_habit(
  p_habit_id uuid,
  p_expected_revision integer
)
returns table (
  habit_id uuid,
  revision integer
)
language sql
security invoker
set search_path = ''
as $$
  update public.habits
  set deleted_at = timezone('utc', now())
  where id = p_habit_id
    and owner_id = auth.uid()
    and archived_at is null
    and deleted_at is null
    and revision = p_expected_revision
  returning id, revision;
$$;

create or replace function public.habits_workspace(p_local_date date)
returns table (
  habit_id uuid,
  name text,
  tracking_mode text,
  measurement_unit text,
  target_value numeric,
  schedule jsonb,
  starts_on date,
  ends_on date,
  habit_revision integer,
  occurrence_id uuid,
  occurrence_revision integer,
  local_status text,
  measured_value numeric,
  note text,
  entry_id uuid,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    habits.id,
    habits.name,
    habits.tracking_mode,
    habits.measurement_unit,
    habits.target_value,
    habits.schedule,
    habits.starts_on,
    habits.ends_on,
    habits.revision,
    occurrences.id,
    occurrences.revision,
    case
      when occurrences.id is not null then occurrences.status
      when p_local_date < habits.starts_on
        or (habits.ends_on is not null and p_local_date > habits.ends_on)
        then 'not_scheduled'
      when habits.schedule ->> 'kind' = 'weekly_target' then 'pending'
      when public.habit_is_scheduled(
        habits.schedule,
        habits.starts_on,
        habits.ends_on,
        p_local_date
      ) then 'pending'
      else 'not_scheduled'
    end,
    occurrences.measured_value,
    occurrences.note,
    occurrences.entry_id,
    habits.created_at,
    habits.updated_at
  from public.habits
  left join public.habit_occurrences as occurrences
    on occurrences.habit_id = habits.id
    and occurrences.owner_id = habits.owner_id
    and occurrences.local_date = p_local_date
  where habits.owner_id = auth.uid()
    and habits.archived_at is null
    and habits.deleted_at is null
  order by lower(habits.name), habits.id;
$$;

create or replace function public.habit_year_calendar(
  p_habit_id uuid,
  p_year integer,
  p_as_of_date date
)
returns table (
  local_date date,
  is_scheduled boolean,
  status text,
  measured_value numeric,
  note text,
  entry_id uuid,
  occurrence_id uuid,
  occurrence_revision integer
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  if p_year is null or p_year < 1900 or p_year > 2200 or p_as_of_date is null then
    raise exception using errcode = '22023', message = 'invalid_habit_calendar_request';
  end if;

  return query
  with selected_habit as (
    select habits.*
    from public.habits
    where habits.id = p_habit_id
      and habits.owner_id = auth.uid()
      and habits.archived_at is null
      and habits.deleted_at is null
  ), calendar_dates as (
    select generated_date::date as local_date
    from generate_series(
      make_date(p_year, 1, 1),
      make_date(p_year, 12, 31),
      interval '1 day'
    ) as generated_date
  )
  select
    calendar_dates.local_date,
    case
      when selected_habit.schedule ->> 'kind' = 'weekly_target'
        then occurrences.id is not null
      else public.habit_is_scheduled(
        selected_habit.schedule,
        selected_habit.starts_on,
        selected_habit.ends_on,
        calendar_dates.local_date
      )
    end,
    case
      when occurrences.id is not null then occurrences.status
      when selected_habit.schedule ->> 'kind' = 'weekly_target' then 'not_scheduled'
      when not public.habit_is_scheduled(
        selected_habit.schedule,
        selected_habit.starts_on,
        selected_habit.ends_on,
        calendar_dates.local_date
      ) then 'not_scheduled'
      when calendar_dates.local_date > p_as_of_date then 'upcoming'
      when calendar_dates.local_date = p_as_of_date then 'pending'
      else 'missed'
    end,
    occurrences.measured_value,
    occurrences.note,
    occurrences.entry_id,
    occurrences.id,
    occurrences.revision
  from selected_habit
  cross join calendar_dates
  left join public.habit_occurrences as occurrences
    on occurrences.habit_id = selected_habit.id
    and occurrences.owner_id = selected_habit.owner_id
    and occurrences.local_date = calendar_dates.local_date
  order by calendar_dates.local_date;
end;
$$;

revoke all on function public.save_habit(uuid, integer, text, text, text, numeric, jsonb, date, date) from public, anon;
revoke all on function public.record_habit_occurrence(uuid, date, text, numeric, text, uuid, integer) from public, anon;
revoke all on function public.trash_habit(uuid, integer) from public, anon;
revoke all on function public.habits_workspace(date) from public, anon;
revoke all on function public.habit_year_calendar(uuid, integer, date) from public, anon;

grant execute on function public.save_habit(uuid, integer, text, text, text, numeric, jsonb, date, date) to authenticated;
grant execute on function public.record_habit_occurrence(uuid, date, text, numeric, text, uuid, integer) to authenticated;
grant execute on function public.trash_habit(uuid, integer) to authenticated;
grant execute on function public.habits_workspace(date) to authenticated;
grant execute on function public.habit_year_calendar(uuid, integer, date) to authenticated;

comment on function public.habits_workspace(date) is
  'Returns every active owned Habit plus its explicit or computed state for one local calendar date.';

comment on function public.habit_year_calendar(uuid, integer, date) is
  'Returns one owned Habit year as explicit completions and computed missed, pending, upcoming, or not-scheduled dates.';
