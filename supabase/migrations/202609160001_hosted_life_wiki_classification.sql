-- Curate the small pre-Life-Wiki hosted dataset after the structural backfill.
-- UUIDs are stable production identities; no user-authored body text is copied
-- into migration history. Missing rows are intentionally harmless in clean and
-- test databases.

alter table public.entries disable trigger archive_entry_before_change;

with classifications(id, item_kind, item_subtype) as (
  values
    ('11262dea-a93b-4408-90ac-4d87df12eef0'::uuid, 'writing', 'reflection'),
    ('155851ca-b28b-4ff1-9b6c-a91ac51d2c00'::uuid, 'writing', 'idea'),
    ('7d83ebb4-dde2-47b1-8bbd-e8f13aa3cfe4'::uuid, 'writing', 'journal'),
    ('5941c621-6a88-413c-9bc1-d3f698bac5b7'::uuid, 'event', 'life_stage'),
    ('89363017-1af2-413a-80fb-ababf5a4e69c'::uuid, 'event', 'life_stage'),
    ('8ab53390-7e93-4406-aba4-d1c2cdbc8cba'::uuid, 'story', 'chapter'),
    ('3ad47f1a-4466-430f-8969-80c9bf9ba606'::uuid, 'event', 'life_stage'),
    ('019b1648-b42d-4f06-a4c9-ef6ee91f6421'::uuid, 'event', 'life_stage'),
    ('d974d0d6-1030-4a20-8f0e-c86e5c661055'::uuid, 'entity', 'vehicle'),
    ('e4025908-213d-4837-a2f6-586ffe512a68'::uuid, 'entity', 'vehicle'),
    ('2cccbd93-9e28-432a-b742-d400d5204de9'::uuid, 'event', 'memory'),
    ('7a265252-a317-4344-9837-fa67a5813bd4'::uuid, 'entity', 'home'),
    ('bf983506-b605-4aaf-96a4-bab165b77ca9'::uuid, 'event', 'other'),
    ('b98c2979-ec86-47a6-bd57-ac3f18ce1c1e'::uuid, 'capture', 'quick_capture')
)
update public.entries as entry
set
  item_kind = classification.item_kind,
  item_subtype = classification.item_subtype,
  entry_type = public.legacy_entry_type_for_item(
    classification.item_kind,
    classification.item_subtype
  )
from classifications as classification
where entry.id = classification.id;

update public.entries
set title = 'Undergraduate - Drexel University'
where id = '5941c621-6a88-413c-9bc1-d3f698bac5b7'::uuid
  and title = 'Undergraduate - Drexel Univeristy';

insert into public.entry_links (
  source_entry_id,
  target_entry_id,
  owner_id,
  relationship
)
select
  story.id,
  home.id,
  story.owner_id,
  'related'
from public.entries as story
join public.entries as home
  on home.id = '7a265252-a317-4344-9837-fa67a5813bd4'::uuid
  and home.owner_id = story.owner_id
where story.id = '8ab53390-7e93-4406-aba4-d1c2cdbc8cba'::uuid
on conflict do nothing;

alter table public.entries enable trigger archive_entry_before_change;
