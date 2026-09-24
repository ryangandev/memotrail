-- Entries are the common record. A First Time is a focused Entry, while a
-- Timeline placement determines whether an Entry is shown as a point or span.
-- The old Writing, Event, Story, and Capture classes are migrated into Entry.

begin;

create function pg_temp.rewrite_entry_function(
  function_name text,
  old_fragments text[],
  new_fragments text[]
)
returns void
language plpgsql
as $$
declare
  function_count integer;
  definition text;
  fragment_index integer;
begin
  if cardinality(old_fragments) is distinct from cardinality(new_fragments) then
    raise exception 'mismatched replacements for %', function_name;
  end if;
  select count(*), min(pg_get_functiondef(oid))
  into function_count, definition
  from pg_proc
  where pronamespace = 'public'::regnamespace and proname = function_name;
  if function_count <> 1 then
    raise exception 'expected one definition for %, found %', function_name, function_count;
  end if;
  for fragment_index in 1..cardinality(old_fragments) loop
    if position(old_fragments[fragment_index] in definition) = 0 then
      raise exception 'missing fragment % in %', fragment_index, function_name;
    end if;
    definition := replace(
      definition,
      old_fragments[fragment_index],
      new_fragments[fragment_index]
    );
  end loop;
  execute definition;
end;
$$;

-- Keep the former descriptive choices as optional tags on existing records.
create temporary table legacy_entry_tags as
select id as entry_id, owner_id,
  case
    when item_kind = 'story' then 'Story'
    when item_kind = 'writing' and item_subtype in ('journal','reflection','lesson','idea')
      then initcap(item_subtype)
    when item_kind = 'event' and item_subtype in ('memory','milestone','trip')
      then initcap(item_subtype)
  end as tag_name
from public.entries
where deleted_at is null;

delete from legacy_entry_tags where tag_name is null;

insert into public.tags (owner_id, name)
select distinct owner_id, tag_name from legacy_entry_tags as legacy
where not exists (
  select 1 from public.tags as tag
  where tag.owner_id = legacy.owner_id
    and lower(tag.name) = lower(legacy.tag_name)
)
on conflict do nothing;

insert into public.entry_tags (entry_id, owner_id, tag_id)
select legacy.entry_id, legacy.owner_id, tag.id
from legacy_entry_tags as legacy
join public.tags as tag
  on tag.owner_id = legacy.owner_id
 and lower(tag.name) = lower(legacy.tag_name)
on conflict do nothing;

alter table public.entries drop constraint entries_item_kind_valid;
alter table public.entries
  add constraint entries_item_kind_valid
  check (item_kind in ('entry', 'entity', 'goal')) not valid;

alter table public.entries
  alter column item_kind set default 'entry',
  alter column item_subtype set default 'entry';

alter table public.entries disable trigger archive_entry_before_change;
update public.entries
set item_kind = 'entry',
    item_subtype = case item_subtype
      when 'first_time' then 'first_time'
      when 'life_stage' then 'period'
      when 'source_capture' then 'source_capture'
      else 'entry'
    end
where item_kind in ('capture', 'writing', 'event', 'story');

-- A deliberate Timeline point remains distinguishable from an ordinary Entry.
update public.entries as entry
set item_subtype = 'moment'
where entry.item_kind = 'entry' and entry.item_subtype = 'entry'
  and exists (
    select 1 from public.timeline_items as placement
    where placement.entry_id = entry.id and placement.timeline_kind = 'event'
  );
alter table public.entries enable trigger archive_entry_before_change;

alter table public.entries validate constraint entries_item_kind_valid;

alter table public.entries add constraint entries_entry_subtype_valid
check (item_kind <> 'entry' or item_subtype in ('entry', 'moment', 'first_time', 'period', 'source_capture'));

comment on column public.entries.item_kind is
  'Entry is the common content record; Entity and Goal have focused data and behavior.';
comment on column public.entries.item_subtype is
  'Only focused Entry behavior such as first_time or period remains; descriptive labels are tags.';

create index entries_owner_resurfacing_entry_idx
  on public.entries (owner_id, occurred_start desc, id)
  where deleted_at is null and occurred_start is not null
    and inbox_status = 'organized'
    and not (item_kind = 'entry' and item_subtype = 'period');
drop index if exists public.entries_owner_resurfacing_idx;

create or replace function public.default_item_subtype(p_item_kind text)
returns text language sql immutable set search_path = ''
as $$
  select case p_item_kind
    when 'entry' then 'entry'
    when 'goal' then 'goal'
    else null
  end;
$$;

select pg_temp.rewrite_entry_function('archive_wiki_search_evidence',
  array['array[''writing'', ''event'', ''story'', ''entity'', ''goal'']::text[]'],
  array['array[''entry'', ''entity'', ''goal'']::text[]']);
select pg_temp.rewrite_entry_function('capture_extraction_source',
  array['entry.item_kind = ''capture''', 'entry.item_subtype = ''quick_capture'''],
  array['entry.item_kind = ''entry''', 'entry.inbox_status = ''unreviewed''']);
select pg_temp.rewrite_entry_function('editable_entry',
  array['e.item_kind in (''writing'', ''event'', ''story'')'],
  array['e.item_kind = ''entry'' and e.item_subtype in (''entry'', ''source_capture'')']);
select pg_temp.rewrite_entry_function('first_times_workspace_with_occurrence',
  array['entries.item_kind = ''event'' and entries.item_subtype = ''first_time'''],
  array['entries.item_kind = ''entry'' and entries.item_subtype = ''first_time''']);
select pg_temp.rewrite_entry_function('home_resurfaced_memory',
  array['item.item_kind = ''event'' and item.item_subtype = ''life_stage'''],
  array['item.item_kind = ''entry'' and item.item_subtype = ''period''']);
select pg_temp.rewrite_entry_function('home_workspace',
  array['item_kind = ''event'' and item_subtype = ''first_time'''],
  array['item_kind = ''entry'' and item_subtype = ''first_time''']);
select pg_temp.rewrite_entry_function('register_first_time_attachment',
  array['item_kind=''event'' and item_subtype=''first_time'''],
  array['item_kind=''entry'' and item_subtype=''first_time''']);
select pg_temp.rewrite_entry_function('trash_first_time_attachment',
  array['e.item_kind=''event'' and e.item_subtype=''first_time'''],
  array['e.item_kind=''entry'' and e.item_subtype=''first_time''']);
select pg_temp.rewrite_entry_function('trash_first_time_entry',
  array['entries.item_kind = ''event'' and entries.item_subtype = ''first_time'''],
  array['entries.item_kind = ''entry'' and entries.item_subtype = ''first_time''']);
select pg_temp.rewrite_entry_function('wiki_item_occurrence_window',
  array['p_item_kind = ''event'' and p_item_subtype = ''life_stage'''],
  array['p_item_kind = ''entry'' and p_item_subtype = ''period''']);
select pg_temp.rewrite_entry_function('wiki_items_workspace',
  array['(''capture'', ''writing'', ''entity'', ''event'', ''story'', ''goal'')'],
  array['(''entry'', ''entity'', ''goal'')']);

select pg_temp.rewrite_entry_function('save_first_time_with_occurrence',
  array[
    E'''event'',\n      ''first_time'',',
    'entries.item_kind = ''event'' and entries.item_subtype = ''first_time'''
  ],
  array[
    E'''entry'',\n      ''first_time'',',
    'entries.item_kind = ''entry'' and entries.item_subtype = ''first_time'''
  ]);

select pg_temp.rewrite_entry_function('save_timeline_entry_with_occurrence',
  array[
    'when p_timeline_kind = ''stage'' then ''life_stage''',
    'else ''other''',
    E'''event'',\n      expected_item_subtype,',
    'item_kind = ''event'',',
    'entries.item_kind = ''event'' and entries.item_subtype in (''life_stage'', ''other'')'
  ],
  array[
    'when p_timeline_kind = ''stage'' then ''period''',
    'else ''moment''',
    E'''entry'',\n      expected_item_subtype,',
    'item_kind = ''entry'',',
    'entries.item_kind = ''entry'' and entries.item_subtype in (''period'', ''moment'')'
  ]);

select pg_temp.rewrite_entry_function('review_wiki_item_with_location_rich',
  array['item.item_kind in (''capture'', p_item_kind)'],
  array['item.item_kind = ''entry'' and item.item_subtype = ''entry''']);

select pg_temp.rewrite_entry_function('review_wiki_item_with_occurrence_rich',
  array[
    'p_item_kind not in (''writing'', ''event'', ''story'')',
    E'or not (case p_item_kind\n      when ''writing'' then p_item_subtype in (''note'', ''journal'', ''reflection'', ''lesson'', ''idea'')\n      when ''event'' then p_item_subtype in (''memory'', ''first_time'', ''milestone'', ''trip'', ''life_stage'', ''other'')\n      when ''story'' then p_item_subtype in (''chapter'', ''story'')\n      else false\n    end)',
    E'  if p_item_kind = ''event'' and p_item_subtype = ''first_time'' and p_title is null then\n    raise exception using errcode = ''22023'', message = ''first_time_requires_title'';\n  end if;\n',
    'item.item_kind in (''writing'', ''event'', ''story'')',
    'and item.item_kind <> ''capture''',
    'item.item_kind in (''capture'', p_item_kind)'
  ],
  array[
    'p_item_kind <> ''entry''',
    'or p_item_subtype <> ''entry''',
    '',
    'item.item_kind = ''entry'' and item.item_subtype = ''entry''',
    '',
    'item.item_kind = ''entry'' and item.item_subtype = ''entry'''
  ]);

select pg_temp.rewrite_entry_function('extract_capture_item',
  array[
    'p_item_kind not in (''writing'', ''event'', ''story'')',
    'p_item_kind = ''event'' and p_item_subtype = ''first_time''',
    'item_kind = ''capture'''
  ],
  array[
    'p_item_kind <> ''entry'' or p_item_subtype not in (''entry'', ''first_time'')',
    'p_item_kind = ''entry'' and p_item_subtype = ''first_time''',
    'item_kind = ''entry'' and inbox_status = ''unreviewed'''
  ]);

select pg_temp.rewrite_entry_function('organize_capture',
  array[
    'p_item_kind not in (''writing'', ''event'', ''story'')',
    'p_item_kind = ''event'' and p_item_subtype = ''first_time''',
    'entry.item_kind = ''capture'''
  ],
  array[
    'p_item_kind <> ''entry'' or p_item_subtype <> ''entry''',
    'p_item_kind = ''entry'' and p_item_subtype = ''first_time''',
    'entry.item_kind = ''entry'' and entry.inbox_status = ''unreviewed'''
  ]);

select pg_temp.rewrite_entry_function('extract_capture_to_home',
  array[
    'item_kind = ''capture''',
    'item_subtype = ''quick_capture'''
  ],
  array[
    'item_kind = ''entry''',
    'inbox_status = ''unreviewed'''
  ]);
select pg_temp.rewrite_entry_function('extract_capture_to_vehicle',
  array[
    'item_kind = ''capture''',
    'item_subtype = ''quick_capture'''
  ],
  array[
    'item_kind = ''entry''',
    'inbox_status = ''unreviewed'''
  ]);
select pg_temp.rewrite_entry_function('extract_capture_to_goal',
  array[
    'item_kind = ''capture''',
    'item_subtype = ''quick_capture'''
  ],
  array[
    'item_kind = ''entry''',
    'inbox_status = ''unreviewed'''
  ]);

select pg_temp.rewrite_entry_function('restore_entry_version',
  array[
    'not in (''capture'', ''writing'', ''entity'', ''event'', ''story'', ''goal'')',
    'item_kind = snapshot->>''item_kind'',',
    'item_subtype = snapshot->>''item_subtype'','
  ],
  array[
    'not in (''capture'', ''writing'', ''event'', ''story'', ''entry'', ''entity'', ''goal'')',
    E'item_kind = case when snapshot->>''item_kind'' in (''capture'', ''writing'', ''event'', ''story'') then ''entry'' else snapshot->>''item_kind'' end,',
    E'item_subtype = case when snapshot->>''item_kind'' in (''capture'', ''writing'', ''event'', ''story'') then case snapshot->>''item_subtype'' when ''first_time'' then ''first_time'' when ''life_stage'' then ''period'' when ''source_capture'' then ''source_capture'' when ''other'' then case when exists (select 1 from jsonb_array_elements(coalesce(timeline_items, ''[]''::jsonb)) as placement where placement->>''timeline_kind'' = ''event'') then ''moment'' else ''entry'' end else ''entry'' end else snapshot->>''item_subtype'' end,'
  ]);

-- Old AI classification payloads become optional labels, not mandatory types.
update public.ai_suggestions
set suggestions = suggestions - 'classification'
where suggestions ? 'classification';

alter table public.ai_suggestions drop constraint if exists ai_suggestions_canonical_payload_check;
alter table public.ai_suggestions
  add constraint ai_suggestions_entry_payload_check
  check (jsonb_typeof(suggestions) = 'object'
    and not (suggestions ? 'entryType')
    and not (suggestions ? 'classification'));

drop table legacy_entry_tags;

commit;
