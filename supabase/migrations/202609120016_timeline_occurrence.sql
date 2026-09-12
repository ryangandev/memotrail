create or replace function public.save_timeline_entry_with_occurrence(
  p_track_id uuid,
  p_timeline_kind text,
  p_title text,
  p_body text,
  p_occurred_start timestamptz,
  p_occurred_end timestamptz,
  p_date_precision text,
  p_occurred_label text,
  p_occurred_timezone text,
  p_entry_id uuid,
  p_expected_revision integer
)
returns table (
  entry_id uuid,
  revision integer,
  was_created boolean
)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  timeline_owner_id uuid := auth.uid();
  saved_entry_id uuid;
  saved_revision integer;
  normalized_title text := nullif(btrim(p_title), '');
  normalized_body text := btrim(coalesce(p_body, ''));
  normalized_label text := nullif(btrim(p_occurred_label), '');
  normalized_timezone text := nullif(btrim(p_occurred_timezone), '');
  expected_entry_type text;
begin
  if timeline_owner_id is null then
    return;
  end if;

  if not exists (
    select 1
    from public.timeline_tracks as tracks
    where tracks.id = p_track_id
      and tracks.owner_id = timeline_owner_id
  ) then
    return;
  end if;

  if p_timeline_kind is null or p_timeline_kind not in ('stage', 'event') then
    raise exception using errcode = '22023', message = 'invalid_timeline_kind';
  end if;

  if normalized_title is null or length(normalized_title) > 200
    or length(normalized_body) > 50000
  then
    raise exception using errcode = '22023', message = 'invalid_timeline_content';
  end if;

  if (p_occurred_start is not null and not isfinite(p_occurred_start))
    or (p_occurred_end is not null and not isfinite(p_occurred_end))
    or (p_date_precision in ('exact','day','month','year','range') and p_occurred_start is null)
    or (p_date_precision='unknown' and (p_occurred_start is not null or p_occurred_end is not null))
    or (p_date_precision in ('age','approximate') and normalized_label is null)
    or (p_occurred_end is not null and p_occurred_start is null)
  then raise exception using errcode='22023',message='invalid_timeline_occurrence'; end if;
  if p_occurred_start is null then normalized_timezone := null;
  else
    if normalized_timezone is null or length(normalized_timezone)>100 then
      raise exception using errcode='22023',message='invalid_timeline_occurrence';
    end if;
    begin perform pg_catalog.timezone(normalized_timezone,p_occurred_start);
    exception when invalid_parameter_value then
      raise exception using errcode='22023',message='invalid_timeline_timezone';
    end;
  end if;

  if p_timeline_kind = 'event' and p_occurred_end is not null then
    raise exception using errcode = '22023', message = 'event_cannot_have_end';
  end if;

  if p_occurred_end is not null and p_occurred_end < p_occurred_start then
    raise exception using errcode = '22023', message = 'invalid_timeline_range';
  end if;

  if p_date_precision is null or p_date_precision not in (
    'exact',
    'day',
    'month',
    'year',
    'approximate',
    'age',
    'range',
    'unknown'
  ) then
    raise exception using errcode = '22023', message = 'invalid_date_precision';
  end if;

  if length(coalesce(normalized_label, '')) > 200 then
    raise exception using errcode = '22023', message = 'timeline_label_too_long';
  end if;

  expected_entry_type := case
    when p_timeline_kind = 'stage' then 'life_stage'
    else 'standard'
  end;

  if p_entry_id is null then
    if p_expected_revision is not null then
      raise exception using errcode = '22023', message = 'unexpected_revision';
    end if;

    insert into public.entries (
      owner_id,
      title,
      body,
      entry_type,
      inbox_status,
      occurred_start,
      occurred_end,
      date_precision,
      occurred_label,
      occurred_timezone
    )
    values (
      timeline_owner_id,
      normalized_title,
      normalized_body,
      expected_entry_type,
      'organized',
      p_occurred_start,
      p_occurred_end,
      p_date_precision,
      normalized_label,
      normalized_timezone
    )
    returning id, entries.revision into saved_entry_id, saved_revision;

    insert into public.timeline_items (
      entry_id,
      track_id,
      owner_id,
      timeline_kind
    )
    values (
      saved_entry_id,
      p_track_id,
      timeline_owner_id,
      p_timeline_kind
    );

    return query select saved_entry_id, saved_revision, true;
    return;
  end if;

  if p_expected_revision is null or p_expected_revision < 1 then
    raise exception using errcode = '22023', message = 'invalid_revision';
  end if;

  update public.entries as entries
  set
    title = normalized_title,
    body = normalized_body,
    entry_type = expected_entry_type,
    inbox_status = 'organized',
    occurred_start = p_occurred_start,
    occurred_end = p_occurred_end,
    date_precision = p_date_precision,
    occurred_label = normalized_label,
    occurred_timezone = normalized_timezone
  where entries.id = p_entry_id
    and entries.owner_id = timeline_owner_id
    and entries.revision = p_expected_revision
    and entries.deleted_at is null
    and entries.entry_type in ('life_stage', 'standard')
    and exists (
      select 1
      from public.timeline_items as items
      where items.entry_id = entries.id
        and items.owner_id = timeline_owner_id
    )
  returning entries.id, entries.revision into saved_entry_id, saved_revision;

  if saved_entry_id is null then
    return;
  end if;

  delete from public.timeline_items as items
  where items.entry_id = saved_entry_id
    and items.owner_id = timeline_owner_id;

  insert into public.timeline_items (
    entry_id,
    track_id,
    owner_id,
    timeline_kind
  )
  values (
    saved_entry_id,
    p_track_id,
    timeline_owner_id,
    p_timeline_kind
  );

  return query select saved_entry_id, saved_revision, false;
end;
$$;

revoke all on function public.save_timeline_entry_with_occurrence(uuid,text,text,text,timestamptz,timestamptz,text,text,text,uuid,integer) from public,anon;
grant execute on function public.save_timeline_entry_with_occurrence(uuid,text,text,text,timestamptz,timestamptz,text,text,text,uuid,integer) to authenticated;

-- Older date-only clients cannot overwrite exact or unanchored memories.
create or replace function public.save_timeline_entry(
  p_track_id uuid,
  p_timeline_kind text,
  p_title text,
  p_body text,
  p_occurred_start timestamptz,
  p_occurred_end timestamptz,
  p_date_precision text,
  p_occurred_label text,
  p_occurred_timezone text,
  p_entry_id uuid,
  p_expected_revision integer
)
returns table (
  entry_id uuid,
  revision integer,
  was_created boolean
)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  timeline_owner_id uuid := auth.uid();
  normalized_title text := nullif(btrim(p_title), '');
  normalized_body text := btrim(coalesce(p_body, ''));
  normalized_label text := nullif(btrim(p_occurred_label), '');
  normalized_timezone text := nullif(btrim(p_occurred_timezone), '');
begin
  if timeline_owner_id is null then
    return;
  end if;

  if not exists (
    select 1
    from public.timeline_tracks as tracks
    where tracks.id = p_track_id
      and tracks.owner_id = timeline_owner_id
  ) then
    return;
  end if;

  if exists(select 1 from public.entries e where e.id=p_entry_id and e.owner_id=timeline_owner_id
    and e.deleted_at is null and (e.occurred_start is null or e.date_precision='exact')) then
    raise exception using errcode='22023',message='timeline_requires_current_editor';
  end if;

  if p_timeline_kind not in ('stage', 'event') then
    raise exception using errcode = '22023', message = 'invalid_timeline_kind';
  end if;

  if normalized_title is null or length(normalized_title) > 200
    or length(normalized_body) > 50000
  then
    raise exception using errcode = '22023', message = 'invalid_timeline_content';
  end if;

  if p_occurred_start is null
    or normalized_timezone is null
    or length(normalized_timezone) > 100
  then
    raise exception using errcode = '22023', message = 'invalid_timeline_occurrence';
  end if;

  begin
    perform pg_catalog.timezone(normalized_timezone, p_occurred_start);
  exception
    when invalid_parameter_value then
      raise exception using errcode = '22023', message = 'invalid_timeline_timezone';
  end;

  if p_timeline_kind = 'event' and p_occurred_end is not null then
    raise exception using errcode = '22023', message = 'event_cannot_have_end';
  end if;

  if p_occurred_end is not null and p_occurred_end < p_occurred_start then
    raise exception using errcode = '22023', message = 'invalid_timeline_range';
  end if;

  if p_date_precision not in (
    'exact',
    'day',
    'month',
    'year',
    'approximate',
    'age',
    'range',
    'unknown'
  ) then
    raise exception using errcode = '22023', message = 'invalid_date_precision';
  end if;

  if length(coalesce(normalized_label, '')) > 200 then
    raise exception using errcode = '22023', message = 'timeline_label_too_long';
  end if;

  return query select * from public.save_timeline_entry_with_occurrence(
    p_track_id,p_timeline_kind,p_title,p_body,p_occurred_start,p_occurred_end,
    p_date_precision,p_occurred_label,p_occurred_timezone,p_entry_id,p_expected_revision);
end;
$$;
