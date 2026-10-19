-- The Map destination is retired, and with it the authenticated tile proxy that was the only
-- caller of the `tiles` provider quota. Address search and the static Location preview keep
-- their hourly quotas.

delete from public.location_provider_usage where kind = 'tiles';

alter table public.location_provider_usage drop constraint location_provider_usage_kind_check;
alter table public.location_provider_usage add constraint location_provider_usage_kind_check
  check (kind in ('search', 'preview'));

create or replace function public.consume_location_provider_quota(p_kind text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  request_owner uuid := auth.uid();
  request_limit integer;
  current_window timestamptz := date_trunc('hour', now());
  saved_count integer;
begin
  if request_owner is null then return false; end if;
  request_limit := case p_kind
    when 'search' then 120
    when 'preview' then 300
    else null
  end;
  if request_limit is null then
    raise exception using errcode = '22023', message = 'invalid_location_quota_kind';
  end if;

  insert into public.location_provider_usage as usage (
    owner_id, kind, window_started, request_count
  ) values (request_owner, p_kind, current_window, 1)
  on conflict (owner_id, kind) do update
    set window_started = current_window,
        request_count = case
          when usage.window_started = current_window
            then usage.request_count + 1
          else 1
        end
    where usage.window_started <> current_window
      or usage.request_count < request_limit
  returning request_count into saved_count;

  return saved_count is not null;
end;
$$;
