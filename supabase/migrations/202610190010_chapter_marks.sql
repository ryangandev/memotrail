-- Chapters and First Times become two marks on an ordinary Entry. A Chapter is a named stretch
-- of time (an Entry with item_subtype `chapter`), and a First Time is a flag any Entry can
-- carry, a Chapter included. This file adds only the pieces the next files build on: the
-- First Time column, a subtype constraint wide enough for the conversion, a First Time index,
-- and the two date-window helpers that Chapter membership, Timeline, and search share.
--
-- Which Entries sit inside a Chapter is never stored. It is computed from recorded dates, so
-- moving a Chapter to Trash or giving it an end changes no Entry.

begin;

-- Chapters build on the Someday removal, which dropped Goals and narrowed the Kinds.
do $$
begin
  if to_regclass('public.goals') is not null then
    raise exception using message = 'chapters_require_someday_removal';
  end if;
end;
$$;

alter table public.entries add column is_first_time boolean not null default false;

alter table public.entries drop constraint entries_entry_subtype_valid;
alter table public.entries add constraint entries_entry_subtype_valid
  check (item_kind <> 'entry' or item_subtype in ('entry', 'chapter'));

create index entries_owner_first_time_idx
  on public.entries (owner_id, occurred_start desc nulls last, id)
  where is_first_time and deleted_at is null;

-- The days a Chapter spans, in its recorded time zone. A Chapter without an end is still
-- going on, so its window has no upper bound. Month and year precision cover the whole first
-- and last month or year. Unknown, and Age or Not sure without a rough date, have no window.
create function public.chapter_window(
  p_start timestamptz,
  p_end timestamptz,
  p_precision text,
  p_timezone text
)
returns daterange
language sql
stable
set search_path = ''
as $$
  select public.wiki_item_occurrence_window(p_start, p_end, p_precision, p_timezone, true);
$$;

-- The days an Entry's recorded date covers, in its recorded time zone: one day for a day or
-- exact time, the whole month or year for Month or Year, start through end for a range or a
-- Not sure date with an end, and no upper bound for an onward range.
create function public.entry_date_window(
  p_start timestamptz,
  p_end timestamptz,
  p_precision text,
  p_timezone text
)
returns daterange
language sql
stable
set search_path = ''
as $$
  select public.wiki_item_occurrence_window(p_start, p_end, p_precision, p_timezone, false);
$$;

revoke all on function public.chapter_window(timestamptz, timestamptz, text, text) from public, anon;
grant execute on function public.chapter_window(timestamptz, timestamptz, text, text) to authenticated, service_role;
revoke all on function public.entry_date_window(timestamptz, timestamptz, text, text) from public, anon;
grant execute on function public.entry_date_window(timestamptz, timestamptz, text, text) to authenticated, service_role;

commit;
