-- Photo context is identified by a digest of owner-checked preview bytes and attachment IDs.
-- Text-only callers retain their existing cache and service-only signature.
create or replace function public.claim_entry_ai_suggestion(p_owner_id uuid,p_entry_id uuid,p_revision integer,p_scope text,p_retry boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare suggestion public.ai_suggestions; inserted_id uuid;
begin
  if p_revision is null or p_revision < 1 or p_scope is null or (
    p_scope not in ('classification','tagging','classification_tagging') and
    p_scope !~ '^(classification|tagging|classification_tagging)_photos_[a-f0-9]{64}$'
  ) then
    raise exception using errcode='22023',message='invalid_suggestion_request';
  end if;
  perform 1 from public.entries where id=p_entry_id and owner_id=p_owner_id and revision=p_revision and deleted_at is null and inbox_status='unreviewed' for share;
  if not found then raise exception using errcode='P0001',message='entry_changed'; end if;
  if strpos(p_scope,'_photos_') > 0 then
    perform 1 from public.ai_preferences where owner_id=p_owner_id and enabled and photo_analysis
      and (classification or tagging);
    if not found then raise exception using errcode='P0001',message='ai_disabled'; end if;
  end if;
  insert into public.ai_suggestions(owner_id,entry_id,entry_revision,request_scope,suggestions,status,started_at)
  values(p_owner_id,p_entry_id,p_revision,p_scope,'{}','generating',now())
  on conflict(entry_id,entry_revision,request_scope) where entry_revision>0 do nothing returning id into inserted_id;
  select * into suggestion from public.ai_suggestions where entry_id=p_entry_id and entry_revision=p_revision and request_scope=p_scope for update;
  if inserted_id is null and suggestion.status='generating' and suggestion.started_at < now()-interval '2 minutes' then
    update public.ai_suggestions set status='failed',resolved_at=now() where id=suggestion.id returning * into suggestion;
  end if;
  if inserted_id is null and p_retry and suggestion.status='failed' then
    update public.ai_suggestions set status='generating',started_at=now(),resolved_at=null where id=suggestion.id returning * into suggestion;
    inserted_id:=suggestion.id;
  end if;
  return jsonb_build_object('claimed',inserted_id is not null,'suggestion',to_jsonb(suggestion)-'owner_id');
end;
$$;
revoke all on function public.claim_entry_ai_suggestion(uuid,uuid,integer,text,boolean) from public,anon,authenticated;
grant execute on function public.claim_entry_ai_suggestion(uuid,uuid,integer,text,boolean) to service_role;
