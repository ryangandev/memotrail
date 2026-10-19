-- Settings > Search by meaning. Off means MemoTrail keeps no meaning index for the user;
-- on marks every Entry due again so the next search starts re-indexing.
create function public.apply_semantic_search_preference()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.semantic_search_enabled is not distinct from old.semantic_search_enabled then
    return null;
  end if;
  if new.semantic_search_enabled then
    update public.entry_search_index_state
    set status = 'pending', attempts = 0, last_error = null, leased_until = null,
        next_attempt_at = timezone('utc', now()), updated_at = timezone('utc', now())
    where owner_id = new.user_id;
  else
    delete from public.entry_search_chunks where owner_id = new.user_id;
    update public.entry_search_index_state
    set status = 'disabled', indexed_hash = null, indexed_model = null, leased_until = null,
        updated_at = timezone('utc', now())
    where owner_id = new.user_id;
  end if;
  return null;
end;
$$;
revoke all on function public.apply_semantic_search_preference() from public, anon, authenticated;

create trigger profiles_apply_semantic_search_preference
after update of semantic_search_enabled on public.profiles
for each row execute function public.apply_semantic_search_preference();
