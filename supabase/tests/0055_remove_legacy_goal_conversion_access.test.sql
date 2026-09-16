begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select hasnt_function(
  'public',
  'convert_entry_to_goal',
  array['uuid','integer','text','text','text','date'],
  'The in-place Goal conversion contract is removed'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.extract_goal_from_item(uuid,integer,uuid,text,text,text,date)',
    'execute'
  ),
  'Authenticated clients can create a separate linked Goal'
);

select * from finish();
rollback;
