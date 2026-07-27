alter table public.club_memberships
  add column if not exists recommendation text;

alter table public.club_membership_applications
  add column if not exists recommendation text;

comment on column public.club_memberships.recommendation is
  'Optional recommendation supplied with a membership application or one-time membership list import.';

comment on column public.club_membership_applications.recommendation is
  'Optional recommendation supplied with a membership application.';

create or replace function public.copy_membership_application_recommendation()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.status = 'approved' and nullif(trim(new.recommendation), '') is not null then
    update public.club_memberships membership
    set recommendation = new.recommendation,
        updated_at = now()
    where membership.club_id = new.club_id
      and (
        (new.user_id is not null and membership.user_id = new.user_id)
        or (
          new.user_id is null
          and nullif(trim(new.email), '') is not null
          and lower(trim(membership.email)) = lower(trim(new.email))
        )
      );
  end if;
  return new;
end;
$$;

drop trigger if exists copy_membership_application_recommendation
  on public.club_membership_applications;

create trigger copy_membership_application_recommendation
after update of status on public.club_membership_applications
for each row
execute function public.copy_membership_application_recommendation();
