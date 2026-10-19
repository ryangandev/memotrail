-- Homes, Vehicles, and Timeline Periods become Chapters, and First Time Moments become
-- ordinary Entries marked First Time. Nothing a person wrote is lost: every converted record
-- keeps its Entry ID, so its writing, photos, tags, Location, Trash state, and timestamps
-- stay attached.
--
-- A Period becomes a Chapter. A Home or Vehicle becomes a Chapter whose typed facts (reasons
-- for moving, make, model, model year, color) are appended to its note as readable lines.
-- A First Time Moment stays the Entry it was and gains the First Time mark. The Work and
-- study lane, which Chapters no longer have, is kept as a `work and study` tag on those
-- Periods. Other Moments only lose their Shape.
--
-- This is the only migration of the Chapters change that depends on data, so it holds every
-- data step and checks its own result before it commits.

begin;

-- Block writes from the old Web so none slips between the counts and the conversion.
lock table public.entries, public.milestones, public.homes, public.vehicles in exclusive mode;

-- Record what the conversion must produce.
create temporary table chapter_conversion_expected as
select
  (select count(*) from public.entries) as entries,
  (select count(*) from public.homes)
    + (select count(*) from public.vehicles)
    + (select count(*) from public.milestones where shape = 'period') as chapters,
  (select count(*) from public.milestones where is_first_time) as first_times;

-- The Records whose notes gain fact lines, so the check below looks only at them.
create temporary table chapter_conversion_records as
select entry_id from public.homes
union all
select entry_id from public.vehicles;

-- Prepared export snapshots describe datasets that no longer exist, so they are discarded
-- exactly as when version history was removed. A new export works immediately.
delete from public.export_snapshot_rows
where snapshot_id in (select id from public.export_snapshots where purged_at is null);
update public.export_snapshots
set purged_at = clock_timestamp(), datasets = '{}', row_count = 0, json_bytes = 0
where purged_at is null;

-- The Work and study lane survives as a tag. Tag names are unique per owner without regard to
-- case, so an existing "Work and study" tag is reused. An Entry keeps within the 70-tag limit
-- so its next save stays valid; a Period that already has 70 tags keeps them and goes untagged.
insert into public.tags (owner_id, name)
select distinct milestone.owner_id, 'work and study'
from public.milestones as milestone
where milestone.shape = 'period'
  and milestone.lane = 'work_study'
  and not exists (
    select 1
    from public.tags
    where tags.owner_id = milestone.owner_id and lower(tags.name) = 'work and study'
  )
on conflict do nothing;

insert into public.entry_tags (entry_id, tag_id, owner_id)
select milestone.entry_id, tag.id, milestone.owner_id
from public.milestones as milestone
join public.tags as tag
  on tag.owner_id = milestone.owner_id and lower(tag.name) = 'work and study'
where milestone.shape = 'period'
  and milestone.lane = 'work_study'
  and (
    select count(*) from public.entry_tags as membership
    where membership.entry_id = milestone.entry_id
  ) < 70
on conflict do nothing;

-- Keep the user's last-changed time. The revision advances by hand so an editor opened before
-- the migration reports a conflict instead of overwriting the converted Entry.
alter table public.entries disable trigger advance_entry_revision;

-- Milestones: a Period becomes a Chapter, and the First Time mark moves onto the Entry. A
-- Moment that is not a First Time changes nothing on its Entry.
update public.entries as entry
set
  item_subtype = case when milestone.shape = 'period' then 'chapter' else 'entry' end,
  is_first_time = milestone.is_first_time,
  revision = entry.revision + 1
from public.milestones as milestone
where milestone.entry_id = entry.id
  and milestone.owner_id = entry.owner_id
  and (milestone.shape = 'period' or milestone.is_first_time);

-- Homes and Vehicles: each becomes a Chapter, and its typed facts become lines appended to the
-- note after a blank line. Formatting stays valid only while the rich text matches the
-- plaintext exactly, so the document gains the same lines as paragraphs: an empty paragraph
-- for the blank line, then one paragraph per line, where an empty line is an empty paragraph.
with record_facts as (
  select
    home.entry_id,
    array_remove(array[
      'Reason for moving in: ' || nullif(btrim(home.move_in_reason), ''),
      'Reason for leaving: ' || nullif(btrim(home.move_out_reason), '')
    ], null) as lines
  from public.homes as home
  union all
  select
    vehicle.entry_id,
    array_remove(array[
      'Make: ' || nullif(btrim(vehicle.make), ''),
      'Model: ' || nullif(btrim(vehicle.model), ''),
      'Model year: ' || vehicle.model_year::text,
      'Color: ' || nullif(btrim(vehicle.color), '')
    ], null)
  from public.vehicles as vehicle
),
record_notes as (
  select
    entry_id,
    case when cardinality(lines) > 0 then
      replace(replace(array_to_string(lines, E'\n'), E'\r\n', E'\n'), E'\r', E'\n')
    end as facts
  from record_facts
)
update public.entries as entry
set
  item_kind = 'entry',
  item_subtype = 'chapter',
  revision = entry.revision + 1,
  body = case
    when note.facts is null then entry.body
    when btrim(entry.body) = '' then note.facts
    else entry.body || E'\n\n' || note.facts
  end,
  metadata = case
    when note.facts is not null
      and btrim(entry.body) <> ''
      and entry.metadata ? 'body_rich'
      and entry.metadata->'body_rich'->>'text' = entry.body
      and jsonb_typeof(entry.metadata->'body_rich'->'document'->'content') = 'array'
    then jsonb_set(
      jsonb_set(
        entry.metadata,
        '{body_rich,text}',
        to_jsonb(entry.body || E'\n\n' || note.facts)
      ),
      '{body_rich,document,content}',
      (entry.metadata->'body_rich'->'document'->'content')
        || jsonb_build_array(jsonb_build_object('type', 'paragraph'))
        || (
          select jsonb_agg(
            case when piece.line = ''
              then jsonb_build_object('type', 'paragraph')
              else jsonb_build_object(
                'type', 'paragraph',
                'content', jsonb_build_array(jsonb_build_object('type', 'text', 'text', piece.line))
              )
            end
            order by piece.position
          )
          from unnest(string_to_array(note.facts, E'\n')) with ordinality as piece(line, position)
        )
    )
    else entry.metadata
  end
from record_notes as note
where note.entry_id = entry.id
  and entry.item_kind = 'entity';

alter table public.entries enable trigger advance_entry_revision;

-- Check the result and abort the whole file if anything is off. The 50,000-character check
-- matches save_entry, so every converted Chapter stays editable. The formatting check covers
-- only converted Homes and Vehicles, so older rows elsewhere cannot abort the migration.
do $$
declare
  expected record;
begin
  select * into expected from chapter_conversion_expected;
  if (select count(*) from public.entries) <> expected.entries
    or (select count(*) from public.entries where item_subtype = 'chapter') <> expected.chapters
    or (select count(*) from public.entries where is_first_time) <> expected.first_times
    or exists (select 1 from public.entries where item_kind <> 'entry')
    or exists (
      select 1
      from public.entries as entry
      join chapter_conversion_records as record on record.entry_id = entry.id
      where entry.item_subtype <> 'chapter'
        or length(entry.body) > 50000
        or (
          entry.metadata ? 'body_rich'
          and entry.metadata->'body_rich'->>'text' is distinct from entry.body
        )
    )
  then
    raise exception using message = 'chapter_conversion_mismatch';
  end if;
end;
$$;

drop table chapter_conversion_records;
drop table chapter_conversion_expected;

commit;
