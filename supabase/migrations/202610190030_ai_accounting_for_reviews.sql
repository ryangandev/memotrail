-- Chapter and year reviews and Chapter suggestions are written by a third-party model, so the
-- accounting that already bounds AI requests learns two things.
--
-- 1. Prices belong to a model. Haiku 4.5 stays for the paused features, and Sonnet 5.5 writes
--    reviews and suggestions. A completed request is charged at the prices of its own model.
-- 2. The server-wide cap becomes a monthly cap. Until now it summed every request ever made,
--    which a few reviews would exhaust for good. The per-user monthly cap for reviews and
--    suggestions comes from the server (an environment value), so it is easy to change without
--    touching anyone's saved preferences; the paused features still read the saved value.
--
-- A new advisory check, ai_budget_allows, lets the server refuse a whole job up front when it
-- could not finish under either monthly budget. Every call still reserves on its own.

begin;

-- Prices in micro-dollars per token, matching Anthropic's published first-party rates.
create function public.ai_model_price(p_model text)
returns table (input_micros integer, output_micros integer)
language sql
immutable
set search_path = ''
as $$
  select price.input_micros, price.output_micros
  from (values
    ('claude-haiku-4-5-20251001', 1, 5),
    ('claude-sonnet-5-5', 2, 10)
  ) as price(model, input_micros, output_micros)
  where price.model = p_model;
$$;

alter table public.ai_usage drop constraint ai_usage_feature_check;
alter table public.ai_usage add constraint ai_usage_feature_check check (feature in (
  'connection', 'classification', 'tagging', 'search', 'explore', 'resurfacing', 'photo_analysis',
  'review', 'chapter_suggestion'
));
alter table public.ai_usage drop constraint ai_usage_reserved_micros_check;
alter table public.ai_usage add constraint ai_usage_reserved_micros_check
  check (reserved_micros between 1 and 2000000);
create index ai_usage_created on public.ai_usage (created_at);

drop function public.reserve_ai_usage(uuid, text, text, bigint, bigint);

create function public.reserve_ai_usage(
  p_owner_id uuid,
  p_feature text,
  p_model text,
  p_reserved_micros bigint,
  p_global_budget_micros bigint,
  p_user_budget_micros bigint default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  prefs public.ai_preferences;
  request_id uuid;
  month_start timestamptz := date_trunc('month', now() at time zone 'UTC') at time zone 'UTC';
  user_budget bigint;
begin
  if p_feature is null
    or p_feature not in (
      'connection', 'classification', 'tagging', 'search', 'explore', 'resurfacing', 'photo_analysis',
      'review', 'chapter_suggestion'
    )
    or not exists (select 1 from public.ai_model_price(p_model))
    or p_reserved_micros is null or p_reserved_micros not between 1 and 2000000
    or p_global_budget_micros is null or p_global_budget_micros not between 1 and 1000000000
    or (p_user_budget_micros is not null and p_user_budget_micros not between 1 and 100000000)
  then
    raise exception using errcode = '22023', message = 'invalid_ai_reservation';
  end if;

  perform pg_advisory_xact_lock(741924);
  select * into prefs from public.ai_preferences where owner_id = p_owner_id;

  if prefs.owner_id is null
    or (p_feature = 'review' and not (prefs.reviews_enabled and prefs.review_disclosure_version is not null))
    or (p_feature = 'chapter_suggestion' and not (prefs.chapter_suggestions_enabled and prefs.review_disclosure_version is not null))
    or (
      p_feature not in ('review', 'chapter_suggestion')
      and (not prefs.enabled or (p_feature <> 'connection' and not coalesce((to_jsonb(prefs) ->> p_feature)::boolean, false)))
    )
  then
    raise exception using errcode = '42501', message = 'ai_disabled';
  end if;

  if (select count(*) from public.ai_usage where owner_id = p_owner_id and created_at > now() - interval '1 hour') >= 60 then
    raise exception using errcode = 'P0001', message = 'ai_rate_limit';
  end if;

  user_budget := case
    when p_feature in ('review', 'chapter_suggestion') then coalesce(p_user_budget_micros, prefs.monthly_budget_micros)
    else prefs.monthly_budget_micros
  end;

  if (select coalesce(sum(charged_micros), 0) from public.ai_usage where created_at >= month_start) + p_reserved_micros > p_global_budget_micros
    or (select coalesce(sum(charged_micros), 0) from public.ai_usage where owner_id = p_owner_id and created_at >= month_start) + p_reserved_micros > user_budget
  then
    raise exception using errcode = 'P0001', message = 'ai_budget_exceeded';
  end if;

  insert into public.ai_usage (owner_id, feature, model, reserved_micros, charged_micros)
  values (p_owner_id, p_feature, p_model, p_reserved_micros, p_reserved_micros)
  returning id into request_id;
  return request_id;
end;
$$;

create or replace function public.finish_ai_usage(
  p_id uuid,
  p_status text,
  p_input_tokens integer,
  p_output_tokens integer,
  p_error_code text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  affected integer;
begin
  if p_status is null or p_status not in ('completed', 'failed', 'uncertain')
    or (p_status = 'completed' and (p_input_tokens is null or p_output_tokens is null or p_input_tokens < 0 or p_output_tokens < 0))
    or (p_error_code is not null and (length(p_error_code) > 64 or p_error_code !~ '^[a-z0-9_]+$'))
  then
    raise exception using errcode = '22023', message = 'invalid_ai_completion';
  end if;

  perform pg_advisory_xact_lock(741924);
  update public.ai_usage
  set status = p_status,
      input_tokens = p_input_tokens,
      output_tokens = p_output_tokens,
      charged_micros = case
        when p_status = 'completed' then
          p_input_tokens::bigint * (select price.input_micros from public.ai_model_price(ai_usage.model) as price)
          + p_output_tokens::bigint * (select price.output_micros from public.ai_model_price(ai_usage.model) as price)
        when p_status = 'failed' then 0
        else reserved_micros
      end,
      error_code = p_error_code,
      finished_at = now()
  where id = p_id and status = 'reserved';
  get diagnostics affected = row_count;
  return affected = 1;
end;
$$;

-- Whether a whole job of estimated cost fits both monthly budgets right now. Advisory: every
-- call still reserves, but a job that could not finish should not start.
create function public.ai_budget_allows(
  p_owner_id uuid,
  p_estimated_micros bigint,
  p_global_budget_micros bigint,
  p_user_budget_micros bigint default null
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  month_start timestamptz := date_trunc('month', now() at time zone 'UTC') at time zone 'UTC';
  user_budget bigint;
begin
  if p_owner_id is null
    or p_estimated_micros is null or p_estimated_micros < 0
    or p_global_budget_micros is null or p_global_budget_micros not between 1 and 1000000000
    or (p_user_budget_micros is not null and p_user_budget_micros not between 1 and 100000000)
  then
    raise exception using errcode = '22023', message = 'invalid_ai_reservation';
  end if;

  user_budget := coalesce(
    p_user_budget_micros,
    (select prefs.monthly_budget_micros from public.ai_preferences as prefs where prefs.owner_id = p_owner_id),
    0
  );

  return (select coalesce(sum(charged_micros), 0) from public.ai_usage where owner_id = p_owner_id and created_at >= month_start) + p_estimated_micros <= user_budget
    and (select coalesce(sum(charged_micros), 0) from public.ai_usage where created_at >= month_start) + p_estimated_micros <= p_global_budget_micros;
end;
$$;

revoke all on function public.ai_model_price(text) from public, anon, authenticated;
grant execute on function public.ai_model_price(text) to service_role;
revoke all on function public.reserve_ai_usage(uuid, text, text, bigint, bigint, bigint) from public, anon, authenticated;
grant execute on function public.reserve_ai_usage(uuid, text, text, bigint, bigint, bigint) to service_role;
revoke all on function public.ai_budget_allows(uuid, bigint, bigint, bigint) from public, anon, authenticated;
grant execute on function public.ai_budget_allows(uuid, bigint, bigint, bigint) to service_role;

commit;
