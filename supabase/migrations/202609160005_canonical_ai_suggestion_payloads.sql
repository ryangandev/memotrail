with legacy_suggestions as (
  select
    id,
    case lower(nullif(btrim(suggestions ->> 'entryType'), ''))
      when 'standard' then jsonb_build_object('itemKind', 'writing', 'itemSubtype', 'note')
      when 'first_time' then jsonb_build_object('itemKind', 'event', 'itemSubtype', 'first_time')
      when 'life_stage' then jsonb_build_object('itemKind', 'event', 'itemSubtype', 'life_stage')
      when 'home' then jsonb_build_object('itemKind', 'entity', 'itemSubtype', 'home')
      when 'vehicle' then jsonb_build_object('itemKind', 'entity', 'itemSubtype', 'vehicle')
      when 'goal' then jsonb_build_object('itemKind', 'goal', 'itemSubtype', 'goal')
      when 'person' then jsonb_build_object('itemKind', 'entity', 'itemSubtype', 'person')
      when 'place' then jsonb_build_object('itemKind', 'entity', 'itemSubtype', 'place')
      else null
    end as classification
  from public.ai_suggestions
  where suggestions ? 'entryType'
)
update public.ai_suggestions as suggestion
set suggestions = (suggestion.suggestions - 'entryType')
  || case
    when legacy.classification is null or suggestion.suggestions ? 'classification'
      then '{}'::jsonb
    else jsonb_build_object('classification', legacy.classification)
  end
from legacy_suggestions as legacy
where suggestion.id = legacy.id;

alter table public.ai_suggestions
  add constraint ai_suggestions_canonical_payload_check
  check (
    jsonb_typeof(suggestions) = 'object'
    and not (suggestions ? 'entryType')
    and (
      not (suggestions ? 'classification')
      or suggestions -> 'classification' = 'null'::jsonb
      or (
        jsonb_typeof(suggestions -> 'classification') = 'object'
        and jsonb_typeof(suggestions -> 'classification' -> 'itemKind') = 'string'
        and jsonb_typeof(suggestions -> 'classification' -> 'itemSubtype') = 'string'
        and (
          (suggestions #>> '{classification,itemKind}') in (
            'capture', 'writing', 'entity', 'event', 'story', 'goal'
          )
        )
        and nullif(btrim(suggestions #>> '{classification,itemSubtype}'), '') is not null
      )
    )
  );

comment on constraint ai_suggestions_canonical_payload_check on public.ai_suggestions is
  'AI organization payloads use canonical itemKind/itemSubtype classification and never legacy entryType.';
