begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select ok(
  not has_function_privilege(
    'authenticated',
    'public.convert_entry_to_goal(uuid,integer,text,text,text,date)',
    'execute'
  ),
  'Authenticated clients cannot mutate an existing Wiki Item into a Goal'
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
