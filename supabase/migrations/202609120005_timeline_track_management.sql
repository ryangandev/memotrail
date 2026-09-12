-- Track visibility is presentation only. No Entries or placements are removed.
alter table public.timeline_tracks add column revision integer not null default 1 check (revision > 0);

create function public.advance_timeline_track_revision() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.revision := old.revision + 1;
  return new;
end;
$$;
revoke all on function public.advance_timeline_track_revision() from public;
create trigger timeline_track_revision before update on public.timeline_tracks
for each row execute function public.advance_timeline_track_revision();

create function public.timeline_track_settings(p_limit integer default 50, p_offset integer default 0)
returns table(id uuid, name text, system_key text, sort_order integer, is_hidden boolean,
  revision integer, entry_count bigint, total_count bigint)
language plpgsql stable security invoker set search_path = '' as $$
begin
  if auth.uid() is null then return; end if;
  if p_limit is null or p_limit < 1 or p_limit > 100 or p_offset is null or p_offset < 0 then
    raise exception using errcode = '22023', message = 'invalid_track_page';
  end if;
  return query select t.id, t.name, t.system_key, t.sort_order, t.is_hidden, t.revision,
    (select count(*) from public.timeline_items ti join public.entries e
      on e.id = ti.entry_id and e.owner_id = ti.owner_id
      where ti.track_id = t.id and ti.owner_id = auth.uid() and e.deleted_at is null),
    count(*) over()
  from public.timeline_tracks t where t.owner_id = auth.uid()
  order by t.sort_order, lower(t.name), t.id limit p_limit offset p_offset;
end;
$$;

create function public.save_timeline_track(p_name text, p_sort_order integer, p_is_hidden boolean,
  p_track_id uuid default null, p_expected_revision integer default null)
returns uuid language plpgsql security invoker set search_path = '' as $$
declare saved_id uuid;
begin
  if auth.uid() is null then return null; end if;
  if nullif(btrim(p_name), '') is null or length(btrim(p_name)) > 100
    or p_sort_order is null or p_sort_order < -1000000 or p_sort_order > 1000000
    or p_is_hidden is null then
    raise exception using errcode = '22023', message = 'invalid_track_details';
  end if;
  if (p_track_id is null and p_expected_revision is not null)
    or (p_track_id is not null and (p_expected_revision is null or p_expected_revision < 1)) then
    raise exception using errcode = '22023', message = 'invalid_revision';
  end if;
  if p_track_id is null then
    insert into public.timeline_tracks(owner_id,name,sort_order,is_hidden)
    values(auth.uid(),btrim(p_name),p_sort_order,p_is_hidden) returning id into saved_id;
  else
    update public.timeline_tracks set name=btrim(p_name),sort_order=p_sort_order,is_hidden=p_is_hidden
    where id=p_track_id and owner_id=auth.uid() and revision=p_expected_revision
    returning id into saved_id;
  end if;
  return saved_id;
end;
$$;
revoke all on function public.timeline_track_settings(integer,integer) from public, anon;
revoke all on function public.save_timeline_track(text,integer,boolean,uuid,integer) from public, anon;
grant execute on function public.timeline_track_settings(integer,integer) to authenticated;
grant execute on function public.save_timeline_track(text,integer,boolean,uuid,integer) to authenticated;
