drop function if exists public.get_my_clubs();

create function public.get_my_clubs()
returns table(
  club_id uuid,
  club_name text,
  club_short_name text,
  club_slug text,
  club_type text,
  logo_url text,
  relationship_type text,
  role_key text,
  role_name text,
  membership_id uuid,
  membership_status text,
  sanction_requests_addon_enabled boolean
)
language sql
stable
security definer
set search_path = public
as $$
  with staff_clubs as (
    select
      club.id as club_id,
      club.name as club_name,
      club.short_name as club_short_name,
      club.slug as club_slug,
      club.club_type,
      club.logo_url,
      'staff'::text as relationship_type,
      role.role_key,
      role.name as role_name,
      membership.id as membership_id,
      membership.status as membership_status,
      club.sanction_requests_addon_enabled
    from public.club_staff_assignments assignment
    join public.clubs club on club.id = assignment.club_id
    join public.club_roles role on role.id = assignment.role_id
    left join public.club_memberships membership
      on membership.club_id = club.id
      and membership.user_id = auth.uid()
      and membership.status not in ('denied', 'cancelled')
    where assignment.user_id = auth.uid()
      and assignment.status = 'active'
      and club.status <> 'archived'
  ),
  member_clubs as (
    select
      club.id as club_id,
      club.name as club_name,
      club.short_name as club_short_name,
      club.slug as club_slug,
      club.club_type,
      club.logo_url,
      'member'::text as relationship_type,
      null::text as role_key,
      null::text as role_name,
      membership.id as membership_id,
      membership.status as membership_status,
      club.sanction_requests_addon_enabled
    from public.club_memberships membership
    join public.clubs club on club.id = membership.club_id
    where membership.user_id = auth.uid()
      and membership.status not in ('denied', 'cancelled')
      and club.status <> 'archived'
  )
  select * from staff_clubs
  union all
  select member.*
  from member_clubs member
  where not exists (
    select 1 from staff_clubs staff where staff.club_id = member.club_id
  )
  order by club_name;
$$;

revoke all on function public.get_my_clubs() from public;
grant execute on function public.get_my_clubs() to authenticated;
