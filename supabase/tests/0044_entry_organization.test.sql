begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email,raw_user_meta_data) values
  ('10000000-0000-0000-0000-000000000101','entry-organization-owner@memotrail.local','{}'),
  ('10000000-0000-0000-0000-000000000102','entry-organization-other@memotrail.local','{}');

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000101',true);

create temporary table organized_moment as
select entry_id
from public.save_timeline_entry_with_organization(
  (select id from public.timeline_tracks where owner_id=auth.uid() order by sort_order limit 1),
  'event',
  'Graduation day',
  'A chapter worth finding again.',
  '2023-06-15 12:00:00Z',
  null,
  'day',
  null,
  'America/Los_Angeles',
  array['Drexel Years'],
  array['Milestone','College'],
  null,
  null
);

select is(
  (select collection_names from public.timeline_workspace_with_organization(false) where entry_id=(select entry_id from organized_moment)),
  array['Drexel Years']::text[],
  'Timeline workspace returns Collection membership'
);
select is(
  (select tag_names from public.timeline_workspace_with_organization(false) where entry_id=(select entry_id from organized_moment)),
  array['College','Milestone']::text[],
  'Timeline workspace returns tag membership'
);

insert into public.tags(owner_id,name) values(auth.uid(),'milestones');
select is(
  public.merge_tags(
    (select id from public.tags where owner_id=auth.uid() and name='Milestone'),
    (select revision from public.tags where owner_id=auth.uid() and name='Milestone'),
    (select id from public.tags where owner_id=auth.uid() and name='milestones'),
    (select revision from public.tags where owner_id=auth.uid() and name='milestones')
  ),
  (select id from public.tags where owner_id=auth.uid() and name='milestones'),
  'Tags merge into one stable target'
);
select is(
  (select count(*) from public.tags where owner_id=auth.uid() and name='Milestone'),
  0::bigint,
  'The merged source tag is removed'
);
select is(
  (select count(*) from public.entry_tags where owner_id=auth.uid() and entry_id=(select entry_id from organized_moment)
    and tag_id=(select id from public.tags where owner_id=auth.uid() and name='milestones')),
  1::bigint,
  'Merged Entry membership points to the target once'
);

insert into public.tags(owner_id,name) values(auth.uid(),'unused');
create temporary table unused_tag as
select id, revision from public.tags where owner_id=auth.uid() and name='unused';
select is(
  public.delete_unused_tag(
    (select id from unused_tag),
    (select revision from unused_tag)
  ),
  (select id from unused_tag),
  'Unused tag deletion returns its stable ID'
);
select is(
  (select count(*) from public.tags where owner_id=auth.uid() and name='unused'),
  0::bigint,
  'An unused tag can be deleted'
);
select is(
  public.delete_unused_tag(
    (select id from public.tags where owner_id=auth.uid() and name='College'),
    (select revision from public.tags where owner_id=auth.uid() and name='College')
  ),
  null::uuid,
  'A used tag cannot be deleted without removing or merging its memberships'
);

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000102',true);
select is(
  (select count(*) from public.timeline_workspace_with_organization(false) where entry_id is not null),
  0::bigint,
  'Another owner cannot read organized Timeline Entries'
);
select is(
  public.merge_tags(
    '10000000-0000-4000-8000-000000000002',
    1,
    '10000000-0000-4000-8000-000000000001',
    1
  ),
  null::uuid,
  'Another owner cannot merge tags they do not own'
);

reset role;
select ok(
  not has_function_privilege('anon','public.save_timeline_entry_with_organization(uuid,text,text,text,timestamptz,timestamptz,text,text,text,text[],text[],uuid,integer)','execute'),
  'Anonymous Timeline organization writes are denied'
);
select ok(
  not has_function_privilege('anon','public.merge_tags(uuid,integer,uuid,integer)','execute'),
  'Anonymous tag merges are denied'
);
select * from finish();
rollback;
