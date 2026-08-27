-- RingMaster staff support is a platform-level capability.  It deliberately
-- does not create club_staff_assignments, so clubs never see support staff in
-- their Staff & Permissions roster.
create table public.ringmaster_support_users (
  id uuid primary key default gen_random_uuid(),
  email text not null unique,
  access_level text not null default 'full' check (access_level in ('read_only', 'full')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (email = lower(trim(email)))
);

alter table public.ringmaster_support_users enable row level security;
revoke all on public.ringmaster_support_users from anon, authenticated;

insert into public.ringmaster_support_users (email, access_level, is_active)
values ('support@ringmasterone.com', 'full', true)
on conflict (email) do update set access_level = excluded.access_level, is_active = true, updated_at = now();

create or replace function public.is_ringmaster_support_user(
  p_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public, auth, pg_temp
as $$
  select p_user_id is not null
    and p_user_id = auth.uid()
    and exists (
      select 1 from public.ringmaster_support_users support
      where support.email = lower(coalesce(auth.email(), ''))
        and support.is_active
    );
$$;

create or replace function public.is_club_staff(
  p_club_id uuid,
  p_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.is_ringmaster_support_user(p_user_id)
  or exists (
    select 1 from public.club_staff_assignments assignment
    where assignment.club_id = p_club_id
      and assignment.user_id = p_user_id
      and assignment.status = 'active'
  );
$$;

create or replace function public.has_club_permission(
  p_club_id uuid,
  p_permission_key text,
  p_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.is_ringmaster_support_user(p_user_id)
  or exists (
    select 1 from public.clubs club
    where club.id = p_club_id and club.owner_user_id = p_user_id
  )
  or exists (
    select 1
    from public.club_staff_assignments assignment
    join public.club_roles role
      on role.id = assignment.role_id
     and role.club_id = assignment.club_id
     and role.is_active = true
    join public.club_permissions permission
      on permission.code = p_permission_key
    left join public.club_role_permissions role_permission
      on role_permission.role_id = role.id
     and (role_permission.permission_id = permission.id
          or role_permission.permission_key = permission.permission_key)
    left join public.club_staff_permission_overrides override
      on override.staff_assignment_id = assignment.id
     and override.permission_id = permission.id
    where assignment.club_id = p_club_id
      and assignment.user_id = p_user_id
      and assignment.status = 'active'
      and coalesce(override.access_granted, role_permission.role_id is not null)
  );
$$;

create or replace function public.get_my_clubs()
returns table(
  club_id uuid, club_name text, club_short_name text, club_slug text,
  club_type text, logo_url text, relationship_type text, role_key text,
  role_name text, membership_id uuid, membership_status text,
  sanction_requests_addon_enabled boolean
)
language sql
stable
security definer
set search_path = public, auth, pg_temp
as $$
  with staff_clubs(club_id, club_name, club_short_name, club_slug, club_type, logo_url, relationship_type, role_key, role_name, membership_id, membership_status, sanction_requests_addon_enabled) as (
    select club.id, club.name, club.short_name, club.slug, club.club_type, club.logo_url,
      'staff'::text, role.role_key, role.name, membership.id, membership.status, club.sanction_requests_addon_enabled
    from public.club_staff_assignments assignment
    join public.clubs club on club.id = assignment.club_id
    join public.club_roles role on role.id = assignment.role_id
    left join public.club_memberships membership on membership.club_id = club.id
      and membership.user_id = auth.uid() and membership.status not in ('denied', 'cancelled')
    where assignment.user_id = auth.uid() and assignment.status = 'active' and club.status <> 'archived'
  ), member_clubs(club_id, club_name, club_short_name, club_slug, club_type, logo_url, relationship_type, role_key, role_name, membership_id, membership_status, sanction_requests_addon_enabled) as (
    select club.id, club.name, club.short_name, club.slug, club.club_type, club.logo_url,
      'member'::text, null::text, null::text, membership.id, membership.status,
      club.sanction_requests_addon_enabled
    from public.club_memberships membership
    join public.clubs club on club.id = membership.club_id
    where membership.user_id = auth.uid() and membership.status not in ('denied', 'cancelled') and club.status <> 'archived'
  ), support_clubs(club_id, club_name, club_short_name, club_slug, club_type, logo_url, relationship_type, role_key, role_name, membership_id, membership_status, sanction_requests_addon_enabled) as (
    select club.id, club.name, club.short_name, club.slug, club.club_type, club.logo_url,
      'support'::text, 'ringmaster_support'::text, 'RingMaster Support'::text,
      null::uuid, null::text, club.sanction_requests_addon_enabled
    from public.clubs club
    where public.is_ringmaster_support_user() and club.status <> 'archived'
  )
  select * from support_clubs
  union all
  select * from staff_clubs where not public.is_ringmaster_support_user()
  union all
  select member.* from member_clubs member
  where not public.is_ringmaster_support_user()
    and not exists (select 1 from staff_clubs staff where staff.club_id = member.club_id)
  order by club_name;
$$;

-- A few staff-management RPCs intentionally use the Club Account Owner / Club
-- Administrator role directly. Let support pass those same checks without
-- inserting a visible staff assignment.
do $$
declare
  v_definition text;
begin
  v_definition := pg_get_functiondef(
    'public.create_club_staff_invitation(uuid,text,text,uuid,text)'::regprocedure
  );
  v_definition := replace(
    v_definition,
    '  if not v_is_owner then',
    '  v_is_owner := v_is_owner or public.is_ringmaster_support_user();' || E'\n' ||
    '  if not v_is_owner then'
  );
  execute v_definition;

  v_definition := pg_get_functiondef(
    'public.set_club_staff_permission_overrides(uuid,uuid,uuid[])'::regprocedure
  );
  v_definition := replace(
    v_definition,
    '  if not exists (',
    '  if not public.is_ringmaster_support_user() and not exists ('
  );
  execute v_definition;

  v_definition := pg_get_functiondef(
    'public.save_club_staff_assignment(uuid,uuid,text,uuid,text,text)'::regprocedure
  );
  v_definition := replace(
    v_definition,
    '  if not exists (',
    '  if not public.is_ringmaster_support_user() and not exists ('
  );
  execute v_definition;
end;
$$;

revoke all on function public.is_ringmaster_support_user(uuid) from public;
grant execute on function public.is_ringmaster_support_user(uuid) to authenticated;
