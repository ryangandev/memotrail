revoke all on all tables in schema public from authenticated;

grant select, update on public.profiles to authenticated;
grant select on public.entry_versions, public.attachments to authenticated;

grant select, insert, update, delete on
  public.entries,
  public.collections,
  public.tags,
  public.entry_collections,
  public.entry_tags,
  public.places,
  public.people,
  public.entry_places,
  public.entry_people,
  public.timeline_tracks,
  public.timeline_items,
  public.homes,
  public.vehicles,
  public.goals,
  public.habits,
  public.habit_occurrences,
  public.entry_links,
  public.ai_suggestions
to authenticated;

comment on table public.attachments is
  'Private Entry media metadata. Client writes must use validated attachment functions.';
