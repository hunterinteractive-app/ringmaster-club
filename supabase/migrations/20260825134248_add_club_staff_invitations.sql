create table public.club_staff_invitations (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  email text not null,
  role_id uuid not null references public.club_roles(id) on delete restrict,
  status text not null default 'pending'
    check (status in ('pending', 'claimed', 'cancelled')),
  invited_by uuid not null references auth.users(id) on delete restrict,
  claimed_by uuid references auth.users(id) on delete set null,
  claimed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (club_id, email)
);

create index club_staff_invitations_club_status_idx
  on public.club_staff_invitations (club_id, status, created_at desc);

alter table public.club_staff_invitations enable row level security;

create policy "Club staff can view invitations"
  on public.club_staff_invitations for select to authenticated
  using (public.is_club_staff(club_id, auth.uid()));

create or replace function public.create_club_staff_invitation(
  p_club_id uuid,
  p_email text,
  p_role_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_email text := lower(trim(p_email));
  v_invitation_id uuid;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in to invite club staff.';
  end if;

  if v_email = '' or position('@' in v_email) = 0 then
    raise exception 'Enter a valid email address.';
  end if;

  if not exists (
    select 1
    from public.club_staff_assignments assignment
    join public.club_roles role on role.id = assignment.role_id
    where assignment.club_id = p_club_id
      and assignment.user_id = auth.uid()
      and assignment.status = 'active'
      and lower(role.code) in ('owner', 'club_owner', 'admin', 'club_admin')
  ) then
    raise exception 'You do not have permission to invite staff for this club.';
  end if;

  if not exists (
    select 1 from public.club_roles role
    where role.id = p_role_id
  ) then
    raise exception 'The selected staff role was not found.';
  end if;

  insert into public.club_staff_invitations (
    club_id, email, role_id, status, invited_by, claimed_by, claimed_at
  ) values (
    p_club_id, v_email, p_role_id, 'pending', auth.uid(), null, null
  )
  on conflict (club_id, email) do update
    set role_id = excluded.role_id,
        status = 'pending',
        invited_by = excluded.invited_by,
        claimed_by = null,
        claimed_at = null,
        updated_at = now()
  returning id into v_invitation_id;

  return v_invitation_id;
end;
$$;

create or replace function public.claim_pending_club_staff_invitations()
returns integer
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_email text := lower(coalesce(auth.email(), ''));
  v_claimed_count integer := 0;
begin
  if auth.uid() is null or v_email = '' then
    return 0;
  end if;

  insert into public.club_staff_assignments (club_id, user_id, role_id, status)
  select invitation.club_id, auth.uid(), invitation.role_id, 'active'
  from public.club_staff_invitations invitation
  where invitation.status = 'pending'
    and lower(invitation.email) = v_email
    and not exists (
      select 1 from public.club_staff_assignments assignment
      where assignment.club_id = invitation.club_id
        and assignment.user_id = auth.uid()
    );

  get diagnostics v_claimed_count = row_count;

  update public.club_staff_invitations
  set status = 'claimed', claimed_by = auth.uid(), claimed_at = now(), updated_at = now()
  where status = 'pending' and lower(email) = v_email;

  return v_claimed_count;
end;
$$;

revoke all on function public.create_club_staff_invitation(uuid, text, uuid) from public;
revoke all on function public.claim_pending_club_staff_invitations() from public;
grant execute on function public.create_club_staff_invitation(uuid, text, uuid) to authenticated;
grant execute on function public.claim_pending_club_staff_invitations() to authenticated;
