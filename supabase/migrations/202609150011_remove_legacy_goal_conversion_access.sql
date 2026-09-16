-- Goal creation now preserves and links its source Wiki Item. Keep the legacy
-- function for historical recovery only, but remove all shipped client access.

revoke execute on function public.convert_entry_to_goal(uuid,integer,text,text,text,date)
  from authenticated;

comment on function public.convert_entry_to_goal(uuid,integer,text,text,text,date) is
  'Deprecated administrative recovery function. Shipped clients must create and link a distinct Goal with extract_goal_from_item.';
