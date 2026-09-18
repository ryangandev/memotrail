begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email) values
  ('10000000-0000-0000-0000-000000000124','places-owner@memotrail.local'),
  ('10000000-0000-0000-0000-000000000125','places-other@memotrail.local');

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000124',true);

select is(
  (
    select count(*)
    from public.save_place(
      '  Golden Gate Park  ','501 Stanyan Street','San Francisco','California',
      'United States',37.769400,-122.486200,'Autumn light.','{}',null,null
    )
  ),
  1::bigint,
  'A Place can be created independently'
);

select is(
  (select name from public.places where owner_id=auth.uid()),
  'Golden Gate Park',
  'Place names are normalized'
);

select is(
  (select count(*) from public.entries where id=(select id from public.places where owner_id=auth.uid())),
  0::bigint,
  'A Place has no duplicate canonical Entry'
);

select is(
  (select linked_entry_count || ':' || home_count from public.places_workspace(50,0)),
  '0:0',
  'The Place workspace exposes no relationships'
);

select is(
  (select jsonb_array_length(linked_entries) from public.places_workspace(50,0)),
  0,
  'The Place workspace returns no linked Entry payload'
);

select is(
  (
    select count(*)
    from public.save_place(
      'Golden Gate Park and Presidio','501 Stanyan Street','San Francisco','California',
      'United States',37.769400,-122.486200,'Two neighboring places.','{}',
      (select id from public.places where owner_id=auth.uid()),1
    )
  ),
  1::bigint,
  'A Place can be edited with optimistic revision control'
);

select is(
  (select revision from public.places where owner_id=auth.uid()),
  2,
  'Editing advances the Place revision'
);

select throws_ok(
  $$select * from public.save_place(
    'Linked',null,null,null,null,null,null,null,
    array['83000000-0000-4000-8000-000000000001']::uuid[],null,null
  )$$,
  '22023',
  'place_relationships_removed',
  'Place relationships are rejected'
);

select is(
  (
    select count(*)
    from public.trash_place(
      (select id from public.places where owner_id=auth.uid()),2
    )
  ),
  1::bigint,
  'A Place moves to Trash without relationship protection'
);

select is(
  (select count(*) from public.trash_workspace(50,0) where item_kind='place'),
  1::bigint,
  'Trash lists the independent Place once'
);

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000125',true);
select is(
  (select count(*) from public.places_workspace(50,0)),
  0::bigint,
  'Place browsing remains owner scoped'
);

reset role;
select ok(
  not has_function_privilege('anon','public.places_workspace(integer,integer)','execute'),
  'Anonymous Place browsing is denied'
);
select ok(
  not has_function_privilege(
    'anon','public.save_place(text,text,text,text,text,numeric,numeric,text,uuid[],uuid,integer)',
    'execute'
  ),
  'Anonymous Place writes are denied'
);

select * from finish();
rollback;
