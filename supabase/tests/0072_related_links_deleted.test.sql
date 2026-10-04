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

reset role;
select ok(not has_table_privilege('authenticated','public.entry_links','insert'),'Clients cannot write links directly');
select ok(not has_table_privilege('authenticated','public.entry_links','update'),'Clients cannot rewrite link provenance');
select ok(not has_table_privilege('authenticated','public.entry_links','delete'),'Clients cannot delete links directly');

select * from finish();
rollback;
