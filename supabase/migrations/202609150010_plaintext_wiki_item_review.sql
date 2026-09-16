-- Native clients that edit canonical plaintext need the semantic Kind boundary
-- without deleting rich-text metadata they do not render or author.

create function public.review_wiki_item_with_photo_place(
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
  p_photo_place jsonb
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
  from public.review_entry_with_photo_place(
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
    p_photo_place
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

revoke all on function public.review_wiki_item_with_photo_place(uuid,integer,text,text,text,text,timestamptz,text,text[],text[],boolean,timestamptz,text,text,jsonb) from public, anon;
grant execute on function public.review_wiki_item_with_photo_place(uuid,integer,text,text,text,text,timestamptz,text,text[],text[],boolean,timestamptz,text,text,jsonb) to authenticated;

comment on function public.review_wiki_item_with_photo_place(uuid,integer,text,text,text,text,timestamptz,text,text[],text[],boolean,timestamptz,text,text,jsonb) is
  'Reviews a Capture or same-Kind Wiki Item from a plaintext client while preserving rich metadata it cannot author.';
