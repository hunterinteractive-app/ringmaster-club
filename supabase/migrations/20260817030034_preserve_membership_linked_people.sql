alter table public.club_memberships
  add column if not exists linked_people jsonb not null default '{}'::jsonb;

alter table public.club_memberships
  drop constraint if exists club_memberships_linked_people_is_object;

alter table public.club_memberships
  add constraint club_memberships_linked_people_is_object
  check (jsonb_typeof(linked_people) = 'object');

comment on column public.club_memberships.linked_people is
  'Saved primary and additional exhibitor links for a couple or family membership. Copied only when staff approves an application.';

-- Preserve links already approved through the application flow when there is
-- an unambiguous linked-people payload. Imported memberships remain unchanged.
update public.club_memberships membership
set linked_people = (
  select application.application_details -> 'linked_people'
  from public.club_membership_applications application
  where application.club_id = membership.club_id
    and application.status = 'approved'
    and jsonb_typeof(application.application_details -> 'linked_people') = 'object'
    and (
      (membership.user_id is not null and application.user_id = membership.user_id)
      or (
        membership.user_id is null
        and nullif(trim(membership.email), '') is not null
        and lower(trim(application.email)) = lower(trim(membership.email))
      )
    )
  order by application.reviewed_at desc nulls last, application.created_at desc
  limit 1
)
where membership.linked_people = '{}'::jsonb
  and exists (
    select 1
    from public.club_membership_applications application
    where application.club_id = membership.club_id
      and application.status = 'approved'
      and jsonb_typeof(application.application_details -> 'linked_people') = 'object'
      and (
        (membership.user_id is not null and application.user_id = membership.user_id)
        or (
          membership.user_id is null
          and nullif(trim(membership.email), '') is not null
          and lower(trim(application.email)) = lower(trim(membership.email))
        )
      )
  );

create or replace function public.copy_membership_application_linked_people()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_linked_people jsonb;
begin
  if new.status <> 'approved' or old.status = 'approved' then
    return new;
  end if;

  v_linked_people := new.application_details -> 'linked_people';
  if jsonb_typeof(v_linked_people) <> 'object' then
    return new;
  end if;

  update public.club_memberships membership
  set linked_people = v_linked_people,
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

  return new;
end;
$$;

revoke all on function public.copy_membership_application_linked_people() from public;

drop trigger if exists copy_membership_application_linked_people
  on public.club_membership_applications;

-- Deferred execution lets the approval RPC create or update the membership
-- before this trigger copies the approved couple/family links onto it.
create constraint trigger copy_membership_application_linked_people
after update of status on public.club_membership_applications
deferrable initially deferred
for each row
execute function public.copy_membership_application_linked_people();
