begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users(id,email) values
  ('10000000-0000-0000-0000-000000000099','birth-date-owner@memotrail.local'),
  ('10000000-0000-0000-0000-000000000100','birth-date-other@memotrail.local');

select has_column('public','profiles','birth_date','Profiles store a private birth date');

set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000099',true);
update public.profiles set birth_date='1994-04-18' where user_id=auth.uid();
select is(
  (select birth_date from public.profiles where user_id=auth.uid()),
  date '1994-04-18',
  'An owner can save their own birth date'
);
select is(
  (select count(*) from public.profiles where user_id='10000000-0000-0000-0000-000000000100'),
  0::bigint,
  'Another profile remains private'
);
reset role;

select throws_ok(
  $$update public.profiles set birth_date='1799-12-31' where user_id='10000000-0000-0000-0000-000000000099'$$,
  '22023',
  'invalid_birth_date',
  'Implausibly early birth dates are rejected'
);
select throws_ok(
  $$update public.profiles set birth_date=(timezone('utc',now())::date + 1) where user_id='10000000-0000-0000-0000-000000000099'$$,
  '22023',
  'invalid_birth_date',
  'Future birth dates are rejected'
);

select * from finish();
rollback;
