-- The dedicated Home and Vehicle forms, the Timeline Shape and lane, and the Entity Kind they
-- needed are retired. Their data became Chapters and First Times in the previous file, so the
-- functions that saved and listed them, the three tables, and the Entity constraints and
-- indexes are removed. From here on every Entry has the Entry Kind, and its subtype is either
-- `entry` or `chapter`.

begin;

drop function public.homes_workspace(integer, integer);
drop function public.vehicles_workspace(integer, integer);
drop function public.save_home_with_location(jsonb, jsonb);
drop function public.save_vehicle_with_location(jsonb, jsonb);
drop function public.save_home_entry_with_occurrence(text, text, timestamptz, timestamptz, text, text, text, text, text, text[], uuid, integer);
drop function public.save_vehicle_entry_with_occurrence(text, text, timestamptz, timestamptz, text, text, text, text, text, integer, text, text[], uuid, integer);
drop function public.trash_home_entry(uuid, integer);
drop function public.trash_vehicle_entry(uuid, integer);
drop function public.replace_entry_milestone(uuid, jsonb);

drop table public.milestones;
drop table public.homes;
drop table public.vehicles;
drop function public.enforce_milestone_entry();

drop index public.entries_owner_home_occurrence_idx;
drop index public.entries_owner_vehicle_occurrence_idx;

alter table public.entries drop constraint entries_entity_subtype_valid;
alter table public.entries drop constraint entries_entry_subtype_valid;
alter table public.entries drop constraint entries_item_subtype_valid;
alter table public.entries add constraint entries_item_subtype_valid
  check (item_subtype in ('entry', 'chapter'));
alter table public.entries drop constraint entries_item_kind_valid;
alter table public.entries add constraint entries_item_kind_valid
  check (item_kind = 'entry');

-- create_export_snapshot reads every listed table, so the list changes with the table drops.
create or replace function public.export_dataset_names()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array[
    'profiles','entries','tags','entry_tags',
    'locations','entry_locations','attachments','entry_links',
    'ai_preferences','ai_usage','ai_suggestions','ai_exploration_turns','ai_exploration_saves','media_objects'
  ]::text[];
$$;

commit;
