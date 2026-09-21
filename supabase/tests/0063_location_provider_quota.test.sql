begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email) values
  ('10000000-0000-0000-0000-000000000126','location-quota@memotrail.local'),
  ('10000000-0000-0000-0000-000000000127','location-quota-other@memotrail.local');

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000126',true);

select ok(public.consume_location_provider_quota('search'),'First address search consumes one quota unit');
reset role;
select is((select request_count from public.location_provider_usage where kind='search'),1,'Search usage is counted atomically');
set local role authenticated;
select ok(public.consume_location_provider_quota('preview'),'Map preview has an independent quota');

do $test$
declare counter integer;
begin
  for counter in 2..120 loop
    if not public.consume_location_provider_quota('search') then
      raise exception 'Search quota was exhausted early at %',counter;
    end if;
  end loop;
end;
$test$;

select ok(not public.consume_location_provider_quota('search'),'Search is rejected after 120 requests in the hour');
reset role;
select is((select request_count from public.location_provider_usage where kind='search'),120,'A rejected request never advances the counter');
set local role authenticated;
select ok(public.consume_location_provider_quota('tiles'),'Tile requests remain available after search quota is exhausted');
select throws_ok($$select public.consume_location_provider_quota('unknown')$$,'22023','invalid_location_quota_kind','Unknown provider actions cannot consume quota');

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000127',true);
select ok(public.consume_location_provider_quota('search'),'Another user has an independent hourly quota');
reset role;
select is((select request_count from public.location_provider_usage where owner_id=auth.uid() and kind='search'),1,'Another user starts at one request');

select ok(not has_table_privilege('authenticated','public.location_provider_usage','SELECT'),'Usage counters are inaccessible as user data');
select ok(not has_function_privilege('anon','public.consume_location_provider_quota(text)','execute'),'Anonymous quota use is denied');
select * from finish();
rollback;
