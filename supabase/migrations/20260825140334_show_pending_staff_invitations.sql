create or replace function public.get_club_staff_permissions_dashboard(
  p_club_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_result jsonb;
begin
  if v_user_id is null then
    raise exception 'Authentication is required.';
  end if;

  if not public.is_club_staff(p_club_id, v_user_id) then
    raise exception 'You do not have permission to view staff permissions for this club.';
  end if;

  select jsonb_build_object(
    'staff', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', item.id,
          'user_id', item.user_id,
          'role_id', item.role_id,
          'email', item.email,
          'display_name', item.display_name,
          'role_name', item.role_name,
          'status', item.status,
          'created_at', item.created_at,
          'is_invitation', item.is_invitation
        )
        order by
          case when item.status = 'active' then 0 when item.status = 'pending' then 1 else 2 end,
          item.role_name,
          item.email
      )
      from (
        select
          assignment.id,
          assignment.user_id,
          assignment.role_id,
          user_account.email,
          coalesce(
            nullif(user_account.raw_user_meta_data->>'full_name', ''),
            nullif(user_account.raw_user_meta_data->>'name', ''),
            nullif(user_account.email, ''),
            'Unknown Staff'
          ) as display_name,
          role.name as role_name,
          coalesce(assignment.status, 'active') as status,
          assignment.created_at,
          false as is_invitation
        from public.club_staff_assignments assignment
        left join auth.users user_account on user_account.id = assignment.user_id
        left join public.club_roles role on role.id = assignment.role_id
        where assignment.club_id = p_club_id

        union all

        select
          invitation.id,
          null::uuid as user_id,
          invitation.role_id,
          invitation.email,
          invitation.email as display_name,
          role.name as role_name,
          'pending' as status,
          invitation.created_at,
          true as is_invitation
        from public.club_staff_invitations invitation
        join public.club_roles role on role.id = invitation.role_id
        where invitation.club_id = p_club_id
          and invitation.status = 'pending'
      ) item
    ), '[]'::jsonb),

    'roles', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', role.id,
          'name', role.name,
          'code', coalesce(role.code, lower(regexp_replace(role.name, '[^a-zA-Z0-9]+', '_', 'g'))),
          'description', role.description,
          'is_system', coalesce(role.is_system, false)
        )
        order by coalesce(role.is_system, false) desc, role.name
      )
      from public.club_roles role
      where role.club_id = p_club_id
         or role.club_id is null
    ), '[]'::jsonb),

    'permissions', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', permission.id,
          'code', permission.code,
          'label', coalesce(permission.label, initcap(replace(permission.code, '_', ' '))),
          'description', permission.description,
          'category', permission.category
        )
        order by permission.category nulls last, coalesce(permission.label, permission.code)
      )
      from public.club_permissions permission
    ), '[]'::jsonb),

    'role_permissions', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'role_id', role_permission.role_id,
          'permission_id', coalesce(role_permission.permission_id, permission.id)
        )
      )
      from public.club_role_permissions role_permission
      join public.club_roles role on role.id = role_permission.role_id
      left join public.club_permissions permission
        on permission.id = role_permission.permission_id
        or permission.code = role_permission.permission_key
      where role.club_id = p_club_id
         or role.club_id is null
    ), '[]'::jsonb)
  )
  into v_result;

  return v_result;
end;
$$;
