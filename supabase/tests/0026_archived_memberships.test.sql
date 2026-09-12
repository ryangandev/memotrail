begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
insert into auth.users(id,email,raw_user_meta_data) values
 ('10000000-0000-0000-0000-000000000095','membership-owner@memotrail.local','{}'),
 ('10000000-0000-0000-0000-000000000096','membership-other@memotrail.local','{}');

create function pg_temp.save_specialized(kind text, names text[], entry_id uuid default null, revision integer default null)
returns uuid language plpgsql as $$
declare saved_id uuid;
begin
 case kind
 when 'first_time' then
  select s.entry_id into saved_id from public.save_first_time_with_occurrence(
    'Memory','Original writing','2017-07-08','day',null,'UTC',names,'{}',entry_id,revision,null) s;
 when 'home' then
  select s.entry_id into saved_id from public.save_home_entry(
    'Memory','Original writing','2017-07-08',null,'day',null,'UTC',null,
    'Test home',null,null,null,null,null,null,'','','',names,'{}',entry_id,revision) s;
 when 'vehicle' then
  select s.entry_id into saved_id from public.save_vehicle_entry(
    'Memory','Original writing','2017-07-08',null,'day',null,'UTC','Test','Car',null,'',names,'{}',entry_id,revision) s;
 when 'goal' then
  select s.entry_id into saved_id from public.save_goal_entry(
    'Memory','Original writing','someday','active',null,names,'{}','{}',entry_id,revision) s;
 end case;
 return saved_id;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000095',true);
create temporary table fixture as
 select kind,pg_temp.save_specialized(kind,array['Recoverable','Visible']) as id
 from unnest(array['first_time','home','vehicle','goal']) kind;
select is(count(*),4::bigint,'All four specialized fixtures exist') from fixture where id is not null;
select public.trash_collection(id,revision) from public.collections where owner_id=auth.uid() and name='Recoverable';
select is(count(*),4::bigint,'Collection Trash retains original links') from public.entry_collections ec
 join public.collections c on c.id=ec.collection_id where c.owner_id=auth.uid() and c.name='Recoverable';

select is(pg_temp.save_specialized(f.kind,array['Visible'],f.id,e.revision),f.id,
 f.kind || ' mutation succeeds without submitting the hidden Collection')
 from fixture f join public.entries e on e.id=f.id;
select is((select count(*) from public.entry_collections ec join public.collections c on c.id=ec.collection_id
 where ec.entry_id=f.id and c.archived_at is not null),1::bigint,f.kind || ' keeps archived membership') from fixture f;
select ok(exists(select 1 from public.entry_versions v, jsonb_array_elements(v.snapshot->'collections') c
 where v.entry_id=f.id and c->>'name'='Recoverable'),f.kind || ' history retains hidden grouping') from fixture f;
select is(pg_temp.save_specialized(f.kind,'{}',f.id,e.revision),f.id,
 f.kind || ' permits explicit removal of active grouping') from fixture f join public.entries e on e.id=f.id;
select is((select count(*) from public.entry_collections ec where ec.entry_id=f.id),1::bigint,
 f.kind || ' removes active links only') from fixture f;
select is(pg_temp.save_specialized(f.kind,'{}',f.id,1),null::uuid,
 f.kind || ' rejects stale revision without touching grouping') from fixture f;
select is(count(*),1::bigint,'Hidden Collection was not recreated under a new ID') from public.collections
 where owner_id=auth.uid() and name='Recoverable';

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000096',true);
select is(pg_temp.save_specialized(f.kind,'{}',f.id,1),null::uuid,
 f.kind || ' rejects another account') from fixture f;
select is(count(*),0::bigint,'Other account cannot read memberships') from public.entry_collections;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000095',true);
select * from public.restore_trash_item('collection',
 (select id from public.collections where owner_id=auth.uid() and name='Recoverable'),
 (select revision from public.collections where owner_id=auth.uid() and name='Recoverable'),
 (select archived_at from public.collections where owner_id=auth.uid() and name='Recoverable'));
select is((select count(*) from public.entry_collections ec join public.collections c on c.id=ec.collection_id
 where ec.entry_id=f.id and c.archived_at is null and c.name='Recoverable'),1::bigint,
 f.kind || ' reappears under the original restored Collection') from fixture f;
reset role;
select ok(not prosecdef,p.proname || ' keeps security invoker') from pg_proc p
 join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'
 and p.proname in ('save_first_time_with_occurrence','save_home_entry','save_vehicle_entry','save_goal_entry');
select * from finish();
rollback;
