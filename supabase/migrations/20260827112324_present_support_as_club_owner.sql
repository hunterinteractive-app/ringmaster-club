-- Support remains invisible in club staff lists, but the support dashboard
-- opens every club using the same owner-facing workspace affordances.
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
      'support'::text, 'owner'::text, 'Club Account Owner'::text,
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

revoke all on function public.get_my_clubs() from public;
grant execute on function public.get_my_clubs() to authenticated;
