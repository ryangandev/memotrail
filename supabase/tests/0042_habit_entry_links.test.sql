begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select hasnt_function(
  'public',
  'habit_entry_choices',
  array['uuid','date','text','integer'],
  'Retired Habit-to-Entry choices are removed'
);
select hasnt_function(
  'public',
  'save_habit_check_in',
  array['uuid','date','text','numeric','text','uuid','integer'],
  'Retired Habit check-in mutation is removed'
);
select hasnt_function(
  'public',
  'archive_habit_evidence',
  array['date','date','date'],
  'AI evidence no longer has a parallel Habit channel'
);

select * from finish();
rollback;
