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
  input jsonb := jsonb_build_object('title','Writer ' || p_kind,'body','Memories',
    'datePrecision','unknown','tagNames','[]'::jsonb,
    'id',p_id,'revision',(select revision from public.entries where id = p_id));
begin
  if p_kind = 'first_time' then
    select entry_id into result from public.save_first_time_with_location(input, p_location);
  elsif p_kind = 'vehicle' then
    select entry_id into result from public.save_vehicle_with_location(input, p_location);
  elsif p_kind = 'home' then
    select entry_id into result from public.save_home_with_location(input, p_location);
  else
    select entry_id into result from public.save_entry(
      p_id,(select revision from public.entries where id = p_id),'Writer entry','Memories',null,null,null,'UTC',null,'unknown','{}',p_location,null);
  end if;
  return result;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
insert into writers values
  ('first_time', pg_temp.save_primary('first_time',null,pg_temp.provider())),
  ('vehicle', pg_temp.save_primary('vehicle',null,pg_temp.provider())),
  ('home', pg_temp.save_primary('home',null,pg_temp.provider()));
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

-- Goal saves leave Entry links alone and skip unchanged Goal details.
insert into writers
select 'goal', entry_id from public.save_goal_entry('Goal','Memories','active',null,'{}',null,null);
reset role;
insert into public.entry_links (source_entry_id, target_entry_id, owner_id, relationship)
values ((select id from writers where kind = 'goal'), (select id from writers where kind = 'entry'), auth.uid(), 'achievement');
update public.entry_links set created_at = '2000-01-01' where source_entry_id = (select id from writers where kind = 'goal');
alter table public.goals disable trigger goals_set_updated_at;
update public.goals set updated_at = '2000-01-01' where entry_id = (select id from writers where kind = 'goal');
alter table public.goals enable trigger goals_set_updated_at;
set local role authenticated;
select entry_id from public.save_goal_entry('Renamed Goal','Memories','active',null,'{}',
  (select id from writers where kind = 'goal'),1);
select is((select created_at from public.entry_links where source_entry_id = (select id from writers where kind = 'goal')),
  '2000-01-01'::timestamptz,'Goal saves leave Entry links unchanged');
select is((select updated_at from public.goals where entry_id = (select id from writers where kind = 'goal')),
  '2000-01-01'::timestamptz,'Title-only Goal saves do not update specialized details');

-- Timeline saves preserve presentation order when only writing changes.
insert into writers
select 'timeline', entry_id from public.save_timeline_entry_with_occurrence(
  (select id from public.timeline_tracks where owner_id = auth.uid() and system_key = 'other_events'),
  'event','Moment','Memories',null,null,'unknown',null,'UTC',null,null);
reset role;
update public.timeline_items set created_at = '2000-01-01', sort_order = 7 where entry_id = (select id from writers where kind = 'timeline');
set local role authenticated;
select entry_id from public.save_timeline_entry_with_occurrence(
  (select id from public.timeline_tracks where owner_id = auth.uid() and system_key = 'other_events'),
  'event','Renamed Moment','Memories',null,null,'unknown',null,'UTC',(select id from writers where kind = 'timeline'),1);
select is((select created_at from public.timeline_items where entry_id = (select id from writers where kind = 'timeline')),
  '2000-01-01'::timestamptz,'Moment saves retain unchanged Timeline created_at');
select is((select sort_order from public.timeline_items where entry_id = (select id from writers where kind = 'timeline')),
  7,'Moment saves preserve existing Timeline presentation order');
select entry_id from public.save_timeline_entry_with_occurrence(
  (select id from public.timeline_tracks where owner_id = auth.uid() and system_key = 'homes'),
  'event','Renamed Moment','Memories',null,null,'unknown',null,'UTC',(select id from writers where kind = 'timeline'),2);
select is((select count(*) from public.timeline_items where entry_id = (select id from writers where kind = 'timeline')),
  1::bigint,'Changing a Moment track removes the old placement');
select is((select track_id from public.timeline_items where entry_id = (select id from writers where kind = 'timeline')),
  (select id from public.timeline_tracks where owner_id = auth.uid() and system_key = 'homes'),
  'Changing a Moment track selects the requested track');
reset role;
select * from finish();
rollback;
