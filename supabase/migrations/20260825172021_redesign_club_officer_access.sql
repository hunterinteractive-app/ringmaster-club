-- Clubs operate through a shared club account, while officers retain their
-- real-world office title and receive only the access the club grants them.

alter table public.club_staff_invitations
  add column if not exists display_name text,
  add column if not exists title_override text;

alter table public.club_staff_assignments
  add column if not exists display_name text;

create table public.club_staff_permission_overrides (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  staff_assignment_id uuid not null references public.club_staff_assignments(id) on delete cascade,
  permission_id uuid not null references public.club_permissions(id) on delete cascade,
  access_granted boolean not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  unique (staff_assignment_id, permission_id)
);

create index club_staff_permission_overrides_assignment_idx
  on public.club_staff_permission_overrides (club_id, staff_assignment_id);

alter table public.club_staff_permission_overrides enable row level security;

create policy "Club staff can view staff permission overrides"
  on public.club_staff_permission_overrides for select to authenticated
  using (public.is_club_staff(club_id, auth.uid()));

-- Rename access roles to club language.  Office names such as President and
-- Secretary are stored on the staff assignment, not hard-coded roles.
update public.club_roles
set name = 'Club Account Owner',
    description = 'The shared club account that holds ownership of this club workspace.'
where code = 'club_owner';

update public.club_roles
set name = 'Club Administrator',
    description = 'Administrative access for club officers such as the President, Secretary, Vice President, or Director.'
where code = 'club_admin';

update public.club_roles
set name = 'Sanction & Sweepstakes Secretary',
    code = 'sanctions_sweepstakes_secretary',
    description = 'Manages sanction requests, sweepstakes reports, rules, and standings.'
where code = 'sanction_coordinator';

insert into public.club_role_permissions (role_id, permission_id, permission_key)
select sanction_role.id, sweepstakes_permission.id, sweepstakes_permission.permission_key
from public.club_roles sanction_role
join public.club_roles sweepstakes_role
  on sweepstakes_role.club_id = sanction_role.club_id
 and sweepstakes_role.code = 'sweepstakes_secretary'
join public.club_role_permissions sweepstakes_mapping
  on sweepstakes_mapping.role_id = sweepstakes_role.id
join public.club_permissions sweepstakes_permission
  on sweepstakes_permission.id = sweepstakes_mapping.permission_id
where sanction_role.code = 'sanctions_sweepstakes_secretary'
on conflict do nothing;

update public.club_roles
set is_active = false,
    description = 'Retired. Use Club Administrator with an officer title instead.'
where code in ('membership_secretary', 'document_manager', 'sweepstakes_secretary');

insert into public.club_roles (club_id, role_key, name, code, description, role_rank, is_system, is_active)
select club.id,
       'treasurer',
       'Treasurer',
       'treasurer',
       'Manages membership dues, payment records, refunds, and other club financial information.',
       0,
       true,
       true
from public.clubs club
where not exists (
  select 1 from public.club_roles role
  where role.club_id = club.id and role.code = 'treasurer'
);

insert into public.club_role_permissions (role_id, permission_id, permission_key)
select treasurer.id, permission.id, permission.permission_key
from public.club_roles treasurer
join public.club_permissions permission
  on permission.code in ('payments.view', 'payments.manage', 'payments.refund')
where treasurer.code = 'treasurer'
on conflict do nothing;

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
  select exists (
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

drop function if exists public.create_club_staff_invitation(uuid, text, uuid);

create function public.create_club_staff_invitation(
  p_club_id uuid,
  p_display_name text,
  p_email text,
  p_role_id uuid,
  p_title_override text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_email text := lower(trim(p_email));
  v_display_name text := nullif(trim(p_display_name), '');
  v_title_override text := nullif(trim(p_title_override), '');
  v_invitation_id uuid;
  v_role public.club_roles%rowtype;
  v_is_owner boolean;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in to invite club staff.';
  end if;
  if v_email = '' or position('@' in v_email) = 0 then
    raise exception 'Enter a valid email address.';
  end if;
  if v_display_name is null then
    raise exception 'Staff name is required.';
  end if;

  select exists (
    select 1 from public.club_staff_assignments assignment
    join public.club_roles role on role.id = assignment.role_id
    where assignment.club_id = p_club_id
      and assignment.user_id = auth.uid()
      and assignment.status = 'active'
      and role.code in ('club_owner', 'club_admin')
  ) into v_is_owner;
  if not v_is_owner then
    raise exception 'You do not have permission to invite staff for this club.';
  end if;

  select * into v_role from public.club_roles
  where id = p_role_id and club_id = p_club_id and is_active = true;
  if not found then
    raise exception 'The selected staff role was not found.';
  end if;

  if v_role.code = 'club_owner' then
    if not exists (
      select 1 from public.clubs club
      where club.id = p_club_id
        and lower(coalesce(club.contact_email, '')) = v_email
    ) then
      raise exception 'The Club Account Owner must use the club contact email.';
    end if;
    if not exists (
      select 1 from public.club_staff_assignments assignment
      join public.club_roles role on role.id = assignment.role_id
      where assignment.club_id = p_club_id
        and assignment.user_id = auth.uid()
        and assignment.status = 'active'
        and role.code = 'club_owner'
    ) then
      raise exception 'Only the current Club Account Owner can transfer ownership.';
    end if;
  end if;

  insert into public.club_staff_invitations (
    club_id, display_name, email, role_id, title_override, status, invited_by, claimed_by, claimed_at
  ) values (
    p_club_id, v_display_name, v_email, p_role_id, v_title_override, 'pending', auth.uid(), null, null
  )
  on conflict (club_id, email) do update
    set display_name = excluded.display_name,
        role_id = excluded.role_id,
        title_override = excluded.title_override,
        status = 'pending', invited_by = excluded.invited_by,
        claimed_by = null, claimed_at = null, updated_at = now()
  returning id into v_invitation_id;
  return v_invitation_id;
end;
$$;

create or replace function public.claim_pending_club_staff_invitations()
returns integer
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_email text := lower(coalesce(auth.email(), ''));
  v_claimed_count integer := 0;
begin
  if auth.uid() is null or v_email = '' then return 0; end if;

  insert into public.club_staff_assignments (
    club_id, user_id, role_id, status, display_name, title_override, invited_email, invited_at, accepted_at
  )
  select invitation.club_id, auth.uid(), invitation.role_id, 'active', invitation.display_name,
         invitation.title_override, invitation.email, invitation.created_at, now()
  from public.club_staff_invitations invitation
  where invitation.status = 'pending' and lower(invitation.email) = v_email
  and not exists (
    select 1 from public.club_staff_assignments assignment
    where assignment.club_id = invitation.club_id and assignment.user_id = auth.uid()
  );
  get diagnostics v_claimed_count = row_count;

  -- A club-owner invitation must be the club's shared contact email.  Move
  -- ownership to that account and retain the former owner as an administrator.
  update public.club_staff_assignments prior_owner
  set role_id = administrator.id, updated_at = now(), updated_by = auth.uid()
  from public.club_staff_invitations invitation
  join public.club_roles owner_role on owner_role.id = invitation.role_id
  join public.club_roles administrator
    on administrator.club_id = invitation.club_id and administrator.code = 'club_admin'
  where invitation.status = 'pending'
    and lower(invitation.email) = v_email
    and owner_role.code = 'club_owner'
    and prior_owner.club_id = invitation.club_id
    and prior_owner.user_id <> auth.uid()
    and prior_owner.role_id = owner_role.id;

  update public.clubs club
  set owner_user_id = auth.uid(), updated_at = now()
  from public.club_staff_invitations invitation
  join public.club_roles owner_role on owner_role.id = invitation.role_id
  where invitation.status = 'pending'
    and lower(invitation.email) = v_email
    and owner_role.code = 'club_owner'
    and club.id = invitation.club_id;

  update public.club_staff_invitations
  set status = 'claimed', claimed_by = auth.uid(), claimed_at = now(), updated_at = now()
  where status = 'pending' and lower(email) = v_email;
  return v_claimed_count;
end;
$$;

create or replace function public.set_club_staff_permission_overrides(
  p_club_id uuid,
  p_assignment_id uuid,
  p_permission_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_assignment public.club_staff_assignments%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication is required.'; end if;
  if not exists (
    select 1 from public.club_staff_assignments manager
    join public.club_roles role on role.id = manager.role_id
    where manager.club_id = p_club_id and manager.user_id = auth.uid()
      and manager.status = 'active' and role.code in ('club_owner', 'club_admin')
  ) then raise exception 'You do not have permission to manage staff access for this club.'; end if;
  select * into v_assignment from public.club_staff_assignments
  where id = p_assignment_id and club_id = p_club_id;
  if not found then raise exception 'Staff assignment was not found.'; end if;

  if exists (
    select 1 from unnest(coalesce(p_permission_ids, '{}'::uuid[])) requested
    where not exists (select 1 from public.club_permissions permission where permission.id = requested)
  ) then raise exception 'One or more permissions are not valid.'; end if;

  delete from public.club_staff_permission_overrides
  where staff_assignment_id = p_assignment_id;

  insert into public.club_staff_permission_overrides (
    club_id, staff_assignment_id, permission_id, access_granted, created_by, updated_by
  )
  select p_club_id, p_assignment_id, permission.id,
         permission.id = any(coalesce(p_permission_ids, '{}'::uuid[])), auth.uid(), auth.uid()
  from public.club_permissions permission
  where (permission.id = any(coalesce(p_permission_ids, '{}'::uuid[]))) is distinct from exists (
    select 1 from public.club_role_permissions mapping
    where mapping.role_id = v_assignment.role_id
      and (mapping.permission_id = permission.id or mapping.permission_key = permission.permission_key)
  );
end;
$$;

drop function if exists public.save_club_staff_assignment(uuid, uuid, text, uuid, text);

create function public.save_club_staff_assignment(
  p_assignment_id uuid,
  p_club_id uuid,
  p_email text,
  p_role_id uuid,
  p_status text,
  p_title_override text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_target_user_id uuid;
  v_assignment_id uuid;
  v_role public.club_roles%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication is required.'; end if;
  if not exists (
    select 1 from public.club_staff_assignments manager
    join public.club_roles manager_role on manager_role.id = manager.role_id
    where manager.club_id = p_club_id and manager.user_id = auth.uid()
      and manager.status = 'active' and manager_role.code in ('club_owner', 'club_admin')
  ) then raise exception 'You do not have permission to manage staff for this club.'; end if;
  if nullif(trim(p_email), '') is null then raise exception 'Staff email is required.'; end if;
  if p_status not in ('active','inactive') then raise exception 'Invalid staff assignment status.'; end if;
  select * into v_role from public.club_roles
  where id=p_role_id and club_id=p_club_id and is_active=true;
  if not found then raise exception 'The selected role is not available for this club.'; end if;
  if v_role.code = 'club_owner' then
    raise exception 'Transfer the Club Account Owner by inviting the club contact email.';
  end if;
  select id into v_target_user_id from auth.users
  where lower(email)=lower(trim(p_email)) limit 1;
  if v_target_user_id is null then raise exception 'No RingMaster Club account was found for %.', trim(p_email); end if;
  if p_assignment_id is null then
    insert into public.club_staff_assignments (club_id,user_id,role_id,status,title_override)
    values (p_club_id,v_target_user_id,p_role_id,p_status,nullif(trim(p_title_override),''))
    on conflict (club_id,user_id,role_id) where status='active'
    do update set status=excluded.status,title_override=excluded.title_override,updated_at=now(),updated_by=auth.uid()
    returning id into v_assignment_id;
  else
    update public.club_staff_assignments
    set role_id=p_role_id,status=p_status,title_override=nullif(trim(p_title_override),''),updated_at=now(),updated_by=auth.uid()
    where id=p_assignment_id and club_id=p_club_id returning id into v_assignment_id;
    if v_assignment_id is null then raise exception 'Staff assignment was not found.'; end if;
  end if;
  return v_assignment_id;
end;
$$;

create or replace function public.get_club_staff_permissions_dashboard(p_club_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_user_id uuid := auth.uid(); v_result jsonb;
begin
  if v_user_id is null then raise exception 'Authentication is required.'; end if;
  if not public.is_club_staff(p_club_id, v_user_id) then
    raise exception 'You do not have permission to view staff permissions for this club.';
  end if;
  select jsonb_build_object(
    'staff', coalesce((select jsonb_agg(jsonb_build_object(
      'id', item.id, 'user_id', item.user_id, 'role_id', item.role_id,
      'email', item.email, 'display_name', item.display_name,
      'title_override', item.title_override, 'role_name', item.role_name,
      'status', item.status, 'created_at', item.created_at, 'is_invitation', item.is_invitation
    ) order by case when item.status = 'active' then 0 when item.status = 'pending' then 1 else 2 end, item.role_name, item.email)
    from (
      select assignment.id, assignment.user_id, assignment.role_id, user_account.email,
        coalesce(nullif(assignment.display_name,''), nullif(user_account.raw_user_meta_data->>'full_name',''), nullif(user_account.raw_user_meta_data->>'name',''), nullif(user_account.email,''), 'Unknown Staff') display_name,
        assignment.title_override, role.name role_name, coalesce(assignment.status,'active') status,
        assignment.created_at, false is_invitation
      from public.club_staff_assignments assignment
      left join auth.users user_account on user_account.id = assignment.user_id
      join public.club_roles role on role.id = assignment.role_id
      where assignment.club_id = p_club_id
      union all
      select invitation.id, null::uuid, invitation.role_id, invitation.email,
        coalesce(invitation.display_name, invitation.email), invitation.title_override,
        role.name, 'pending', invitation.created_at, true
      from public.club_staff_invitations invitation
      join public.club_roles role on role.id = invitation.role_id
      where invitation.club_id = p_club_id and invitation.status = 'pending'
    ) item), '[]'::jsonb),
    'roles', coalesce((select jsonb_agg(jsonb_build_object(
      'id', role.id, 'name', role.name, 'code', role.code, 'description', role.description, 'is_system', coalesce(role.is_system,false)
    ) order by role.name) from public.club_roles role where role.club_id = p_club_id and role.is_active = true), '[]'::jsonb),
    'permissions', coalesce((select jsonb_agg(jsonb_build_object(
      'id', permission.id, 'code', permission.code, 'label', coalesce(permission.label,initcap(replace(permission.code,'_',' '))), 'description',permission.description,'category',permission.category
    ) order by permission.category nulls last, coalesce(permission.label,permission.code)) from public.club_permissions permission), '[]'::jsonb),
    'role_permissions', coalesce((select jsonb_agg(jsonb_build_object('role_id',mapping.role_id,'permission_id',coalesce(mapping.permission_id,permission.id)))
      from public.club_role_permissions mapping join public.club_roles role on role.id=mapping.role_id
      left join public.club_permissions permission on permission.id=mapping.permission_id or permission.code=mapping.permission_key
      where role.club_id = p_club_id and role.is_active = true), '[]'::jsonb),
    'permission_overrides', coalesce((select jsonb_agg(jsonb_build_object(
      'staff_assignment_id', override.staff_assignment_id, 'permission_id', override.permission_id, 'access_granted', override.access_granted
    )) from public.club_staff_permission_overrides override where override.club_id=p_club_id), '[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$$;

revoke all on function public.create_club_staff_invitation(uuid, text, text, uuid, text) from public;
revoke all on function public.set_club_staff_permission_overrides(uuid, uuid, uuid[]) from public;
revoke all on function public.save_club_staff_assignment(uuid, uuid, text, uuid, text, text) from public;
grant execute on function public.create_club_staff_invitation(uuid, text, text, uuid, text) to authenticated;
grant execute on function public.set_club_staff_permission_overrides(uuid, uuid, uuid[]) to authenticated;
grant execute on function public.save_club_staff_assignment(uuid, uuid, text, uuid, text, text) to authenticated;
