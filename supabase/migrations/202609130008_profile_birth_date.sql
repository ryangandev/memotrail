alter table public.profiles
add column birth_date date;

comment on column public.profiles.birth_date is
  'Private date of birth used to establish the beginning of the owner timeline.';

create or replace function public.validate_profile_birth_date()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.birth_date is not null and (
    new.birth_date < date '1800-01-01'
    or new.birth_date > timezone('utc', now())::date
  ) then
    raise exception using errcode = '22023', message = 'invalid_birth_date';
  end if;

  return new;
end;
$$;

revoke all on function public.validate_profile_birth_date() from public;

create trigger profiles_validate_birth_date
before insert or update of birth_date on public.profiles
for each row execute function public.validate_profile_birth_date();
