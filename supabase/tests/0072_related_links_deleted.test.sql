begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email) values
  ('10000000-0000-0000-0000-000000000172','related-links-owner@memotrail.local');
insert into public.entries(id,owner_id,title,body,date_precision) values
  ('99720000-0000-4000-8000-000000000001','10000000-0000-0000-0000-000000000172','Source','Keep my words','unknown'),
  ('99720000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000172','Extracted','Later idea','unknown');

select hasnt_function('public','entry_relations','General link browsing is gone');
select hasnt_function('public','set_entry_relation','General link editing is gone');
select is(
  (select count(*) from public.entry_links where relationship = 'related'),
  0::bigint,
  'No general related link remains'
);
select is(
  (select count(*) from public.entry_versions
   where snapshot ? 'related_entry_ids'
      or exists (
        select 1 from jsonb_array_elements(case when jsonb_typeof(snapshot->'links') = 'array' then snapshot->'links' else '[]' end) as link
        where link->>'relationship' = 'related'
      )),
  0::bigint,
  'No history version can restore a general related link'
);
select throws_ok(
  $$insert into public.entry_links(source_entry_id,target_entry_id,owner_id,relationship)
    values('99720000-0000-4000-8000-000000000001','99720000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000172','related')$$,
  '23514',
  null,
  'A general related link cannot be stored'
);
select throws_ok(
  $$insert into public.entry_links(source_entry_id,target_entry_id,owner_id)
    values('99720000-0000-4000-8000-000000000001','99720000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000172')$$,
  '23502',
  null,
  'Every link names its relationship'
);

-- Provenance links stay in history and restore like before.
insert into public.entry_links(source_entry_id,target_entry_id,owner_id,relationship) values
  ('99720000-0000-4000-8000-000000000001','99720000-0000-4000-8000-000000000002','10000000-0000-0000-0000-000000000172','derived');
update public.entries set body = 'Edited words' where id = '99720000-0000-4000-8000-000000000001';
select is(
  (select snapshot->'links'->0->>'relationship' from public.entry_versions
   where entry_id = '99720000-0000-4000-8000-000000000001' and version = 1),
  'derived',
  'History records the provenance link'
);
select ok(
  not ((select snapshot from public.entry_versions
        where entry_id = '99720000-0000-4000-8000-000000000001' and version = 1) ? 'related_entry_ids'),
  'History no longer records general related links'
);
delete from public.entry_links where source_entry_id = '99720000-0000-4000-8000-000000000001';
update public.entries set body = 'Without the link' where id = '99720000-0000-4000-8000-000000000001';
update public.entries set deleted_at = now() where id = '99720000-0000-4000-8000-000000000002';

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000172',true);
select throws_ok(
  $$select public.restore_entry_version('99720000-0000-4000-8000-000000000001',1,3)$$,
  'P0001',
  'history_reference_unavailable',
  'History restore refuses a link to an Entry in Trash'
);
reset role;
update public.entries set deleted_at = null where id = '99720000-0000-4000-8000-000000000002';
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000172',true);
select is(
  public.restore_entry_version('99720000-0000-4000-8000-000000000001',1,3),
  4,
  'History restores the provenance link once its target is back'
);
select is(
  (select relationship from public.entry_links where source_entry_id = '99720000-0000-4000-8000-000000000001'),
  'derived',
  'The restored link keeps its relationship'
);

reset role;
select ok(not has_table_privilege('authenticated','public.entry_links','insert'),'Clients cannot write links directly');
select ok(not has_table_privilege('authenticated','public.entry_links','update'),'Clients cannot rewrite link provenance');
select ok(not has_table_privilege('authenticated','public.entry_links','delete'),'Clients cannot delete links around history');

select * from finish();
rollback;
