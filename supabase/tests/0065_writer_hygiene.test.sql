begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

create function pg_temp.provider(p_name text default '10 Maple Street') returns jsonb language sql as $$
  select jsonb_build_object('kind','provider','provider','geoapify',
    'providerLocationId',p_name,'formattedAddress',p_name,
    'address',p_name,'city','Philadelphia','country','United States',
    'latitude',39.95,'longitude',-75.16);
$$;
create temporary table writers(kind text primary key, id uuid);
grant all on writers to authenticated;

create function pg_temp.save_primary(p_kind text, p_id uuid, p_location jsonb) returns uuid language plpgsql as $$
declare
  result uuid;
begin
  if p_kind = 'first_time' then
    select entry_id into result from public.save_entry(
      coalesce(p_id, gen_random_uuid()),(select revision from public.entries where id = p_id),'Writer first time','Memories',
      null,null,null,'UTC',null,'unknown','{}',p_location,null,false,true);
  elsif p_kind = 'chapter' then
    select entry_id into result from public.save_entry(
      coalesce(p_id, gen_random_uuid()),(select revision from public.entries where id = p_id),'Writer chapter','Memories',
      null,null,null,'UTC',null,'unknown','{}',p_location,null,true,false);
  else
    select entry_id into result from public.save_entry(
      p_id,(select revision from public.entries where id = p_id),'Writer entry','Memories',null,null,null,'UTC',null,'unknown','{}',p_location,null, false, false);
  end if;
  return result;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
insert into writers values
  ('first_time', pg_temp.save_primary('first_time',null,pg_temp.provider())),
  ('chapter', pg_temp.save_primary('chapter',null,pg_temp.provider()));
insert into public.entries(owner_id,title) values(auth.uid(),'Writer Entry') returning id \gset entry_
insert into writers values('entry',pg_temp.save_primary('entry',:'entry_id',pg_temp.provider()));
reset role;
update public.entry_locations set created_at = '2000-01-01' where entry_id in (select id from writers);
set local role authenticated;
select is(pg_temp.save_primary(kind,id,(
  select jsonb_build_object('kind','existing','id',location.id,'revision',location.revision)
  from public.entry_locations as link join public.locations as location on location.id = link.location_id
  where link.entry_id = writers.id and link.relationship = 'primary'
)),id,'Saving the same ' || kind || ' Location succeeds') from writers;
select is((select created_at from public.entry_locations where entry_id = writers.id and relationship = 'primary'),
  '2000-01-01'::timestamptz,kind || ' retains unchanged primary Location membership') from writers;
select is(pg_temp.save_primary(kind,id,pg_temp.provider('20 Maple Street')),id,'Changing the ' || kind || ' Location succeeds') from writers;
select is((select count(*) from public.entry_locations where entry_id = writers.id and relationship = 'primary'),
  1::bigint,kind || ' replaces the primary relationship rather than retaining both') from writers;
select is((select formatted_address from public.locations where id = (select location_id from public.entry_locations where entry_id = writers.id and relationship = 'primary')),
  '20 Maple Street',kind || ' points at the changed Location') from writers;
select is(pg_temp.save_primary(kind,id,null),id,'Removing the ' || kind || ' Location succeeds') from writers;
select is((select count(*) from public.entry_locations where entry_id = writers.id and relationship = 'primary'),
  0::bigint,kind || ' removes only the active primary relationship') from writers;

-- A save writes both marks, so checking and unchecking First Time is one save.
select is(pg_temp.save_primary('first_time',(select id from writers where kind = 'first_time'),null),
  (select id from writers where kind = 'first_time'),'An Entry with an unchanged First Time mark saves');
select is((select is_first_time from public.entries where id = (select id from writers where kind = 'first_time')),
  true,'Saving keeps the First Time mark');
select entry_id from public.save_entry(
  (select id from writers where kind = 'first_time'),
  (select revision from public.entries where id = (select id from writers where kind = 'first_time')),
  'Writer first time','Memories',null,null,null,'UTC',null,'unknown','{}',null,null,
  false,false);
select is((select is_first_time from public.entries where id = (select id from writers where kind = 'first_time')),
  false,'Unchecking First Time removes the mark');
reset role;
select * from finish();
rollback;
