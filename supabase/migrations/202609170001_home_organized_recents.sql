-- Home previews unreviewed Captures separately, so Recent Entries represents
-- content that has already entered the Life Wiki.
do $$
declare
  definition text;
  recent_source text := E'    from active_entries as entries\n    order by entries.created_at desc, entries.id\n    limit p_recent_limit';
  recent_replacement text := E'    from active_entries as entries\n    where entries.inbox_status = ''organized''\n    order by entries.created_at desc, entries.id\n    limit p_recent_limit';
  count_source text := '      count(*) as entry_count,';
  count_replacement text := '      count(*) filter (where inbox_status = ''organized'') as entry_count,';
begin
  select pg_get_functiondef(
    'public.home_workspace(date,text,integer)'::regprocedure
  ) into definition;

  if length(definition) - length(replace(definition, recent_source, '')) <> length(recent_source) then
    raise exception 'Expected exactly one Home recent Entry source';
  end if;

  if length(definition) - length(replace(definition, count_source, '')) <> length(count_source) then
    raise exception 'Expected exactly one Home Entry count source';
  end if;

  definition := replace(definition, recent_source, recent_replacement);
  definition := replace(definition, count_source, count_replacement);
  execute definition;
end;
$$;

comment on function public.home_workspace(date,text,integer) is
  'Returns an owner-scoped Home snapshot with Inbox counts, organized recent Wiki Items, and current stages.';
