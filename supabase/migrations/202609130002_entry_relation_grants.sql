-- All shipped clients mutate links through revisioned definer functions.
-- Direct table writes could bypass history and forge protected achievement/AI provenance.
-- These established RPCs already derive ownership from auth.uid(), validate every
-- target owner, and guard the source revision explicitly; keep their atomic writes working.
alter function public.save_goal_entry(text,text,text,text,date,text[],text[],uuid[],uuid,integer) security definer;
alter function public.achieve_goal_with_occurrence(uuid,integer,timestamptz,text,text,text,timestamptz) security definer;
revoke insert,update,delete on public.entry_links from authenticated;
grant select on public.entry_links to authenticated;
