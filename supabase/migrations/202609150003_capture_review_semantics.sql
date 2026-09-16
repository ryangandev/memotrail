-- Let the Web organizer write Kind and subtype atomically through the existing
-- content, rich-text, organization, occurrence, and photo review transaction.

create or replace function public.sync_entry_information_model()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  model_changed boolean;
  legacy_type_changed boolean;
  semantic_kind text;
  semantic_subtype text;
begin
  if tg_op = 'INSERT' then
    if new.item_kind is null then
      new.item_kind := public.legacy_item_kind(new.entry_type, new.inbox_status);
    end if;
    if new.item_subtype is null then
      if new.item_kind = public.legacy_item_kind(new.entry_type, new.inbox_status) then
        new.item_subtype := public.legacy_item_subtype(new.entry_type, new.inbox_status);
      else
        new.item_subtype := public.default_item_subtype(new.item_kind);
      end if;
    end if;
    if new.item_kind is not null and new.item_subtype is not null then
      new.entry_type := public.legacy_entry_type_for_item(new.item_kind, new.item_subtype);
    end if;
    return new;
  end if;

  semantic_kind := nullif(current_setting('memotrail.review_item_kind', true), '');
  semantic_subtype := nullif(current_setting('memotrail.review_item_subtype', true), '');

  if semantic_kind is not null or semantic_subtype is not null then
    if semantic_kind is null or semantic_subtype is null then
      raise exception using errcode = '22023', message = 'invalid_review_semantic_context';
    end if;
    new.item_kind := semantic_kind;
    new.item_subtype := semantic_subtype;
    new.entry_type := public.legacy_entry_type_for_item(semantic_kind, semantic_subtype);
    return new;
  end if;

  model_changed := new.item_kind is distinct from old.item_kind
    or new.item_subtype is distinct from old.item_subtype;
  legacy_type_changed := new.entry_type is distinct from old.entry_type;

  if legacy_type_changed and not model_changed then
    new.item_kind := public.legacy_item_kind(new.entry_type, new.inbox_status);
    new.item_subtype := public.legacy_item_subtype(new.entry_type, new.inbox_status);
  elsif model_changed then
    if new.item_kind is null then
      raise exception using errcode = '22023', message = 'invalid_item_kind';
    end if;
    if new.item_subtype is null then
      new.item_subtype := public.default_item_subtype(new.item_kind);
    end if;
    new.entry_type := public.legacy_entry_type_for_item(new.item_kind, new.item_subtype);
  elsif old.item_kind = 'capture'
    and old.item_subtype = 'quick_capture'
    and old.inbox_status = 'unreviewed'
    and new.inbox_status = 'organized'
  then
    new.item_kind := 'writing';
    new.item_subtype := 'note';
    new.entry_type := 'standard';
  end if;

  return new;
end;
$$;

revoke all on function public.sync_entry_information_model() from public, anon, authenticated;

-- The legacy review implementation only knew Standard and First Time. Memory,
-- Milestone, Trip, and other Event presets share the existing life_stage
-- compatibility type until every client reads item_kind directly.
do $$
declare
  definition text;
  old_validation text := E'if p_entry_type not in (''standard'', ''first_time'') then';
  new_validation text := E'if p_entry_type not in (''standard'', ''first_time'', ''life_stage'') then';
  old_filter text := E'and entry.entry_type in (''standard'',''first_time'')';
  new_filter text := E'and entry.entry_type in (''standard'',''first_time'',''life_stage'')';
begin
  select pg_get_functiondef(p.oid)
  into strict definition
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'review_entry_with_occurrence_rich';

  if (length(definition) - length(replace(definition, old_validation, ''))) <> length(old_validation) then
    raise exception 'Expected exactly one review Entry type validation replacement';
  end if;
  definition := replace(definition, old_validation, new_validation);

  if (length(definition) - length(replace(definition, old_filter, ''))) <> length(old_filter) then
    raise exception 'Expected exactly one review Entry type filter replacement';
  end if;
  execute replace(definition, old_filter, new_filter);
end;
$$;

create function public.review_wiki_item_with_photo_place_rich(
  p_entry_id uuid,
  p_expected_revision integer,
  p_title text,
  p_body text,
  p_item_kind text,
  p_item_subtype text,
  p_occurred_start timestamptz,
  p_occurred_timezone text,
  p_collection_names text[],
  p_tag_names text[],
  p_mark_done boolean,
  p_occurred_end timestamptz,
  p_occurred_label text,
  p_date_precision text,
  p_photo_place jsonb,
  p_body_rich jsonb
)
returns table(entry_id uuid, revision integer, inbox_status text)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  review_owner_id uuid := auth.uid();
  source public.entries;
  reviewed record;
begin
  if review_owner_id is null then
    return;
  end if;

  if p_expected_revision is null or p_expected_revision < 1
    or p_item_kind not in ('writing', 'event', 'story')
    or p_item_subtype is null
    or p_item_subtype !~ '^[a-z][a-z0-9_]{0,63}$'
    or not (case p_item_kind
      when 'writing' then p_item_subtype in ('note', 'journal', 'reflection', 'lesson', 'idea')
      when 'event' then p_item_subtype in ('memory', 'first_time', 'milestone', 'trip', 'life_stage', 'other')
      when 'story' then p_item_subtype in ('chapter', 'story')
      else false
    end)
  then
    raise exception using errcode = '22023', message = 'invalid_item_classification';
  end if;

  select *
  into source
  from public.entries as entry
  where entry.id = p_entry_id
    and entry.owner_id = review_owner_id
    and entry.revision = p_expected_revision
    and entry.deleted_at is null;

  if not found then
    return;
  end if;

  if source.item_kind <> 'capture' and source.item_kind <> p_item_kind then
    raise exception using errcode = '22023', message = 'invalid_item_kind_transition';
  end if;

  if p_item_kind = 'event' and p_item_subtype = 'first_time'
    and nullif(btrim(p_title), '') is null
  then
    raise exception using errcode = '22023', message = 'first_time_requires_title';
  end if;

  perform pg_catalog.set_config('memotrail.review_item_kind', p_item_kind, true);
  perform pg_catalog.set_config('memotrail.review_item_subtype', p_item_subtype, true);

  select *
  into reviewed
  from public.review_entry_with_photo_place_rich(
    p_entry_id,
    p_expected_revision,
    p_title,
    p_body,
    public.legacy_entry_type_for_item(p_item_kind, p_item_subtype),
    p_occurred_start,
    p_occurred_timezone,
    p_collection_names,
    p_tag_names,
    p_mark_done,
    p_occurred_end,
    p_occurred_label,
    p_date_precision,
    p_photo_place,
    p_body_rich
  );

  perform pg_catalog.set_config('memotrail.review_item_kind', '', true);
  perform pg_catalog.set_config('memotrail.review_item_subtype', '', true);

  if reviewed.entry_id is null then
    return;
  end if;

  return query
  select reviewed.entry_id, reviewed.revision, reviewed.inbox_status;
end;
$$;

revoke all on function public.review_wiki_item_with_photo_place_rich(uuid,integer,text,text,text,text,timestamptz,text,text[],text[],boolean,timestamptz,text,text,jsonb,jsonb) from public, anon;
grant execute on function public.review_wiki_item_with_photo_place_rich(uuid,integer,text,text,text,text,timestamptz,text,text[],text[],boolean,timestamptz,text,text,jsonb,jsonb) to authenticated;

comment on function public.review_wiki_item_with_photo_place_rich(uuid,integer,text,text,text,text,timestamptz,text,text[],text[],boolean,timestamptz,text,text,jsonb,jsonb) is
  'Atomically reviews a raw Capture or edits a same-Kind Writing, Event, or Story with rich text, organization, occurrence, and optional photo Place adoption.';

create or replace function public.editable_entry(p_entry_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(e) || jsonb_build_object(
    'collection_names', coalesce(
      (
        select jsonb_agg(c.name order by c.name)
        from public.entry_collections ec
        join public.collections c
          on c.id = ec.collection_id
          and c.owner_id = ec.owner_id
        where ec.entry_id = e.id
          and ec.owner_id = auth.uid()
          and c.archived_at is null
      ),
      '[]'::jsonb
    ),
    'tag_names', coalesce(
      (
        select jsonb_agg(t.name order by t.name)
        from public.entry_tags et
        join public.tags t
          on t.id = et.tag_id
          and t.owner_id = et.owner_id
        where et.entry_id = e.id
          and et.owner_id = auth.uid()
      ),
      '[]'::jsonb
    )
  )
  from public.entries e
  where e.id = p_entry_id
    and e.owner_id = auth.uid()
    and e.deleted_at is null
    and e.item_kind in ('writing', 'event', 'story');
$$;

revoke all on function public.editable_entry(uuid) from public, anon;
grant execute on function public.editable_entry(uuid) to authenticated;
