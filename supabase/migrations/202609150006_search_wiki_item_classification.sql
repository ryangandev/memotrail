-- Search keeps its established RPC signatures for older clients while the
-- filter values adopt the Life Wiki Kind and subtype vocabulary.

do $$
declare
  definition text;
  old_filter text := E'        cardinality(normalized_entry_types) = 0\n        or entries.entry_type = any(normalized_entry_types)';
  new_filter text := E'        cardinality(normalized_entry_types) = 0\n        or entries.entry_type = any(normalized_entry_types)\n        or entries.item_kind = any(normalized_entry_types)\n        or entries.item_subtype = any(normalized_entry_types)';
  old_searchable text := E'        replace(entries.entry_type, ''_'', '' ''),';
  new_searchable text := E'        replace(entries.entry_type, ''_'', '' ''),\n        replace(entries.item_kind, ''_'', '' ''),\n        replace(entries.item_subtype, ''_'', '' ''),';
begin
  select pg_get_functiondef(p.oid)
  into strict definition
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'search_entries_ordered';

  if (length(definition) - length(replace(definition, old_filter, ''))) <> length(old_filter) then
    raise exception 'Expected exactly one semantic search filter replacement';
  end if;
  definition := replace(definition, old_filter, new_filter);

  if (length(definition) - length(replace(definition, old_searchable, ''))) <> length(old_searchable) then
    raise exception 'Expected exactly one semantic search text replacement';
  end if;
  definition := replace(definition, old_searchable, new_searchable);

  execute definition;
end;
$$;

comment on function public.search_entries_ordered(text,text[],text[],text[],date,date,integer,integer,text) is
  'Owner-scoped Wiki Item search. p_entry_types is retained for client compatibility and accepts item Kind, subtype, or legacy entry_type values.';

-- AI evidence uses the same filter parameter. Let semantic Entity filters
-- include the legacy Person and Place registries until they share canonical
-- Wiki Item storage.
do $$
declare
  definition text;
  old_scope text := E'if coalesce(cardinality(p_entry_types),0)=0 and coalesce(cardinality(p_collection_names),0)=0 and coalesce(cardinality(p_tag_names),0)=0 and p_date_from is null and p_date_to is null and not p_before_latest_home then';
  new_scope text := E'if (coalesce(cardinality(p_entry_types),0)=0 or p_entry_types && array[''entity'',''person'',''place'']::text[]) and coalesce(cardinality(p_collection_names),0)=0 and coalesce(cardinality(p_tag_names),0)=0 and p_date_from is null and p_date_to is null and not p_before_latest_home then';
  old_person text := E'where p.owner_id=auth.uid() and p.deleted_at is null and exists(select 1 from unnest(queries) q';
  new_person text := E'where p.owner_id=auth.uid() and p.deleted_at is null and (coalesce(cardinality(p_entry_types),0)=0 or ''entity''=any(p_entry_types) or ''person''=any(p_entry_types)) and exists(select 1 from unnest(queries) q';
  old_place text := E'where p.owner_id=auth.uid() and p.deleted_at is null and exists(select 1 from unnest(queries) q';
  new_place text := E'where p.owner_id=auth.uid() and p.deleted_at is null and (coalesce(cardinality(p_entry_types),0)=0 or ''entity''=any(p_entry_types) or ''place''=any(p_entry_types)) and exists(select 1 from unnest(queries) q';
  first_match integer;
begin
  select pg_get_functiondef(p.oid)
  into strict definition
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'archive_search_evidence';

  if (length(definition) - length(replace(definition, old_scope, ''))) <> length(old_scope) then
    raise exception 'Expected exactly one AI semantic Entity scope replacement';
  end if;
  definition := replace(definition, old_scope, new_scope);

  -- The source has the same owner predicate once for People and once for
  -- Places. Replace them in order so each subtype remains independently scoped.
  first_match := strpos(definition, old_person);
  if first_match = 0 then
    raise exception 'Expected AI People source predicate';
  end if;
  definition := overlay(definition placing new_person from first_match for length(old_person));

  first_match := strpos(definition, old_place);
  if first_match = 0 then
    raise exception 'Expected AI Place source predicate';
  end if;
  definition := overlay(definition placing new_place from first_match for length(old_place));

  if strpos(definition, old_person) > 0 then
    raise exception 'Unexpected additional AI Entity source predicate';
  end if;

  execute definition;
end;
$$;

comment on function public.archive_search_evidence(text[],text[],text[],text[],date,date,boolean,boolean,text,date) is
  'Returns bounded owner-scoped evidence using semantic Wiki Item filters while retaining the legacy p_entry_types parameter name.';
