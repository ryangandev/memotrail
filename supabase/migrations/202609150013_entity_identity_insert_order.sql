-- Canonical Entity rows must exist before their immediate foreign keys are
-- checked. Split creation from the after-change synchronization trigger.

drop trigger people_sync_wiki_item on public.people;
drop trigger places_sync_wiki_item on public.places;

create trigger people_create_wiki_item
before insert on public.people
for each row execute function public.sync_person_wiki_item();

create trigger people_sync_wiki_item
after update or delete on public.people
for each row execute function public.sync_person_wiki_item();

create trigger places_create_wiki_item
before insert on public.places
for each row execute function public.sync_place_wiki_item();

create trigger places_sync_wiki_item
after update or delete on public.places
for each row execute function public.sync_place_wiki_item();
