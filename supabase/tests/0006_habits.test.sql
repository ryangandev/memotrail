begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

select hasnt_table('public', 'habits', 'Deferred Habits do not occupy the product schema');
select hasnt_table('public', 'habit_occurrences', 'Habit check-ins are removed with the feature');
select hasnt_table('public', 'habit_versions', 'Unused Habit history is removed');
select hasnt_table(
  'public',
  'habit_occurrence_versions',
  'Unused Habit check-in history is removed'
);
select hasnt_function('public', 'habits_workspace', array['date'], 'Habit workspace RPC is removed');
select hasnt_function(
  'public',
  'save_habit',
  array['uuid','integer','text','text','text','numeric','jsonb','date','date'],
  'Habit mutation RPC is removed'
);

select * from finish();
rollback;
