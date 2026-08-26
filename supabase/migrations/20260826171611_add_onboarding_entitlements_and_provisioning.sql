-- An onboarding invitation is issued after a club has selected and paid for
-- its plan/add-ons.  The invitee can see those entitlements but cannot alter
-- them during onboarding.
alter table public.club_onboarding_drafts
  add column if not exists purchased_entitlements jsonb not null default
    '{"plan_key":"small_club_base","addons":[]}'::jsonb,
  add column if not exists submitted_by_user_id uuid references auth.users(id) on delete set null,
  add column if not exists provisioned_club_id uuid references public.clubs(id) on delete set null;

alter table public.club_staff_invitations
  add column if not exists permission_profile text;

-- Profiles keep onboarding simple while preserving the ability to tailor
-- permissions later in Staff & Permissions.
create or replace function public.apply_club_staff_permission_profile(
  p_club_id uuid,
  p_assignment_id uuid,
  p_profile text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  delete from public.club_staff_permission_overrides
  where staff_assignment_id = p_assignment_id;

  if coalesce(p_profile, 'club_admin') = 'club_admin' then
    return;
  end if;

  insert into public.club_staff_permission_overrides (
    club_id, staff_assignment_id, permission_id, access_granted
  )
  select p_club_id,
         p_assignment_id,
         permission.id,
         case p_profile
           when 'membership_read_newsletter' then permission.code in (
             'club.view', 'members.view', 'communications.view',
             'communications.send', 'communications.manage_templates'
           )
           when 'read_only' then permission.code in ('club.view', 'members.view')
           else false
         end
  from public.club_permissions permission
  on conflict (staff_assignment_id, permission_id) do update
    set access_granted = excluded.access_granted,
        updated_at = now();
end;
$$;

-- Claiming a staff invitation applies its initial profile only once the
-- recipient creates/signs in to their RingMaster Club account.
create or replace function public.claim_pending_club_staff_invitations()
returns integer
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_email text := lower(coalesce(auth.email(), ''));
  v_claimed_count integer := 0;
  v_invitation record;
  v_assignment_id uuid;
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

  for v_invitation in
    select * from public.club_staff_invitations
    where status = 'pending'
      and lower(email) = v_email
      and permission_profile is not null
  loop
    select id into v_assignment_id
    from public.club_staff_assignments
    where club_id = v_invitation.club_id and user_id = auth.uid();
    if v_assignment_id is not null then
      perform public.apply_club_staff_permission_profile(
        v_invitation.club_id, v_assignment_id, v_invitation.permission_profile
      );
    end if;
  end loop;

  update public.club_staff_invitations
  set status = 'claimed', claimed_by = auth.uid(), claimed_at = now(), updated_at = now()
  where status = 'pending' and lower(email) = v_email;
  return v_claimed_count;
end;
$$;

drop function if exists public.issue_club_onboarding_invitation(text, integer);
create function public.issue_club_onboarding_invitation(
  p_email text,
  p_expires_in_days integer default 14,
  p_purchased_entitlements jsonb default '{"plan_key":"small_club_base","addons":[]}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_email text := lower(trim(p_email));
  v_token text := encode(gen_random_bytes(32), 'hex');
  v_draft_id uuid;
  v_invitation_id uuid;
  v_entitlements jsonb := coalesce(p_purchased_entitlements, '{}'::jsonb);
  v_plan_key text := coalesce(v_entitlements->>'plan_key', 'small_club_base');
  v_addon text;
begin
  if v_email = '' or position('@' in v_email) = 0 then
    raise exception 'Enter a valid club email.';
  end if;
  if p_expires_in_days not between 1 and 90 then
    raise exception 'Invite expiry must be between 1 and 90 days.';
  end if;
  if v_plan_key not in ('small_club_base', 'standard_club_base', 'standard_club_complete') then
    raise exception 'Unknown club plan: %', v_plan_key;
  end if;
  for v_addon in select jsonb_array_elements_text(coalesce(v_entitlements->'addons', '[]'::jsonb)) loop
    if v_addon not in ('membership_management', 'sanction_requests', 'events_meetings', 'email', 'sweepstakes', 'storage_20gb') then
      raise exception 'Unknown club add-on: %', v_addon;
    end if;
  end loop;

  v_entitlements := jsonb_build_object(
    'plan_key', v_plan_key,
    'addons', coalesce(v_entitlements->'addons', '[]'::jsonb)
  );

  insert into public.club_onboarding_drafts (invited_email, purchased_entitlements)
  values (v_email, v_entitlements)
  returning id into v_draft_id;

  insert into public.club_onboarding_invitations (
    draft_id, email, token_hash, expires_at
  ) values (
    v_draft_id, v_email,
    encode(digest(v_token, 'sha256'), 'hex'),
    now() + make_interval(days => p_expires_in_days)
  ) returning id into v_invitation_id;

  return jsonb_build_object(
    'invitation_id', v_invitation_id,
    'draft_id', v_draft_id,
    'token', v_token,
    'email', v_email,
    'purchased_entitlements', v_entitlements,
    'expires_at', now() + make_interval(days => p_expires_in_days)
  );
end;
$$;

create or replace function public.get_club_onboarding_invitation(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, auth, pg_temp
as $$
declare
  v_email text := lower(coalesce(auth.email(), ''));
  v_invitation public.club_onboarding_invitations%rowtype;
  v_draft public.club_onboarding_drafts%rowtype;
begin
  if auth.uid() is null then raise exception 'Sign in to continue onboarding.'; end if;
  select * into v_invitation from public.club_onboarding_invitations
  where token_hash = encode(digest(trim(p_token), 'sha256'), 'hex')
  for update;
  if not found then raise exception 'This onboarding invitation is not valid.'; end if;
  if v_invitation.status in ('cancelled', 'expired') or v_invitation.expires_at <= now() then
    update public.club_onboarding_invitations set status='expired'
    where id=v_invitation.id and status not in ('cancelled','expired');
    raise exception 'This onboarding invitation has expired.';
  end if;
  if lower(v_invitation.email) <> v_email then
    raise exception 'Sign in with the invited club email to continue.';
  end if;
  select * into v_draft from public.club_onboarding_drafts where id=v_invitation.draft_id;
  update public.club_onboarding_invitations
  set status=case when status='pending' then 'opened' else status end,
      opened_at=coalesce(opened_at,now())
  where id=v_invitation.id;
  return jsonb_build_object(
    'draft_id', v_draft.id, 'email', v_draft.invited_email, 'status', v_draft.status,
    'current_step', v_draft.current_step, 'answers', v_draft.answers,
    'purchased_entitlements', v_draft.purchased_entitlements,
    'provisioned_club_id', v_draft.provisioned_club_id,
    'expires_at', v_invitation.expires_at
  );
end;
$$;

create or replace function public.submit_club_onboarding_draft(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, auth, pg_temp
as $$
declare
  v_email text := lower(coalesce(auth.email(), ''));
  v_invitation public.club_onboarding_invitations%rowtype;
  v_draft public.club_onboarding_drafts%rowtype;
begin
  if auth.uid() is null then raise exception 'Sign in to submit onboarding.'; end if;
  select * into v_invitation from public.club_onboarding_invitations
  where token_hash=encode(digest(trim(p_token),'sha256'),'hex') for update;
  if not found or v_invitation.expires_at <= now() then raise exception 'This onboarding invitation is no longer available.'; end if;
  if lower(v_invitation.email) <> v_email then raise exception 'Use the invited club email.'; end if;
  update public.club_onboarding_drafts
  set status='ready_for_review', current_step='review', submitted_at=now(),
      submitted_by_user_id=auth.uid(), updated_at=now()
  where id=v_invitation.draft_id returning * into v_draft;
  update public.club_onboarding_invitations set status='submitted',submitted_at=now() where id=v_invitation.id;
  return jsonb_build_object('draft_id',v_draft.id,'status',v_draft.status);
end;
$$;

-- This is deliberately not granted to authenticated users. RingMaster staff
-- approve a reviewed draft from their secure administrative workflow/SQL.
create function public.approve_club_onboarding_draft(p_draft_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_draft public.club_onboarding_drafts%rowtype;
  v_answers jsonb;
  v_entitlements jsonb;
  v_club_id uuid;
  v_owner_role_id uuid;
  v_admin_role_id uuid;
  v_treasurer_role_id uuid;
  v_name text;
  v_slug_base text;
  v_slug text;
  v_provider text;
  v_officer jsonb;
  v_officer_email text;
  v_officer_name text;
  v_officer_title text;
  v_officer_profile text;
  v_assignment_id uuid;
  v_addon text;
begin
  select * into v_draft
  from public.club_onboarding_drafts
  where id = p_draft_id
  for update;
  if not found then raise exception 'Onboarding draft not found.'; end if;
  if v_draft.status <> 'ready_for_review' then
    raise exception 'Only a submitted onboarding draft can be approved.';
  end if;
  if v_draft.submitted_by_user_id is null then
    raise exception 'The invited club account must submit this draft before approval.';
  end if;

  v_answers := coalesce(v_draft.answers, '{}'::jsonb);
  v_entitlements := coalesce(v_draft.purchased_entitlements, '{}'::jsonb);
  v_name := nullif(trim(v_answers #>> '{club,name}'), '');
  if v_name is null then raise exception 'The club name is required before approval.'; end if;
  v_slug_base := trim(both '-' from regexp_replace(lower(v_name), '[^a-z0-9]+', '-', 'g'));
  if v_slug_base = '' then v_slug_base := 'club'; end if;
  v_slug := v_slug_base || '-' || left(replace(v_draft.id::text, '-', ''), 8);
  v_provider := coalesce(nullif(trim(v_answers #>> '{setup,payment_provider}'), ''), 'not_ready');

  insert into public.clubs (
    name, short_name, slug, club_type, species_scope, description, website_url,
    mailing_address_line1, mailing_city, mailing_state, mailing_postal_code,
    contact_name, contact_email, contact_phone, owner_user_id,
    billing_plan_key, billing_status, membership_management_addon_enabled,
    sanction_requests_addon_enabled, events_meetings_addon_enabled,
    email_addon_enabled, email_communications_addon_enabled,
    sweepstakes_addon_enabled, accepts_member_online_payments,
    allow_membership_check_payments, allow_sanction_check_payments,
    treasurer_name, treasurer_email, treasurer_address_line1,
    communication_sender_name, communication_reply_to_email
  ) values (
    v_name,
    nullif(trim(v_answers #>> '{club,short_name}'), ''),
    v_slug,
    coalesce(nullif(trim(v_answers #>> '{club,type}'), ''), 'local'),
    coalesce(nullif(trim(v_answers #>> '{club,species_scope}'), ''), 'both'),
    nullif(trim(v_answers #>> '{club,description}'), ''),
    nullif(trim(v_answers #>> '{club,website_url}'), ''),
    nullif(trim(v_answers #>> '{club,address_line1}'), ''),
    nullif(trim(v_answers #>> '{club,city}'), ''),
    nullif(trim(v_answers #>> '{club,state}'), ''),
    nullif(trim(v_answers #>> '{club,postal_code}'), ''),
    nullif(trim(v_answers #>> '{club,contact_name}'), ''),
    v_draft.invited_email,
    nullif(trim(v_answers #>> '{club,contact_phone}'), ''),
    v_draft.submitted_by_user_id,
    coalesce(v_entitlements->>'plan_key', 'small_club_base'), 'active',
    (v_entitlements->'addons') ? 'membership_management',
    (v_entitlements->'addons') ? 'sanction_requests',
    (v_entitlements->'addons') ? 'events_meetings',
    (v_entitlements->'addons') ? 'email',
    (v_entitlements->'addons') ? 'email',
    (v_entitlements->'addons') ? 'sweepstakes',
    false,
    coalesce((v_answers #>> '{setup,mailed_checks}')::boolean, false),
    false,
    nullif(trim(v_answers #>> '{treasurer,name}'), ''),
    nullif(trim(v_answers #>> '{treasurer,email}'), ''),
    nullif(trim(v_answers #>> '{treasurer,address}'), ''),
    coalesce(nullif(trim(v_answers #>> '{club,short_name}'), ''), v_name),
    v_draft.invited_email
  ) returning id into v_club_id;

  insert into public.club_plan_subscriptions (club_id, plan_key, status)
  values (v_club_id, coalesce(v_entitlements->>'plan_key', 'small_club_base'), 'active');
  for v_addon in select jsonb_array_elements_text(coalesce(v_entitlements->'addons', '[]'::jsonb)) loop
    insert into public.club_addon_subscriptions (club_id, add_on_key, status)
    values (v_club_id, v_addon, 'active');
  end loop;

  insert into public.club_roles (club_id, role_key, name, code, description, role_rank, is_system, is_active)
  values
    (v_club_id, 'owner', 'Club Account Owner', 'club_owner', 'The shared club account that holds ownership of this club workspace.', 1000, true, true),
    (v_club_id, 'admin', 'Club Administrator', 'club_admin', 'Administrative access for club officers.', 900, true, true),
    (v_club_id, 'treasurer', 'Treasurer', 'treasurer', 'Manages club financial information.', 0, true, true),
    (v_club_id, 'sanction_coordinator', 'Sanction & Sweepstakes Secretary', 'sanctions_sweepstakes_secretary', 'Manages sanction and sweepstakes work.', 600, true, true);

  select id into v_owner_role_id from public.club_roles where club_id=v_club_id and code='club_owner';
  select id into v_admin_role_id from public.club_roles where club_id=v_club_id and code='club_admin';
  select id into v_treasurer_role_id from public.club_roles where club_id=v_club_id and code='treasurer';
  insert into public.club_role_permissions (role_id, permission_id, permission_key)
  select role.id, permission.id, permission.permission_key
  from public.club_roles role cross join public.club_permissions permission
  where role.club_id=v_club_id and role.code in ('club_owner','club_admin');
  insert into public.club_role_permissions (role_id, permission_id, permission_key)
  select v_treasurer_role_id, permission.id, permission.permission_key
  from public.club_permissions permission
  where permission.code in ('payments.view','payments.manage','payments.refund');

  insert into public.club_staff_assignments (
    club_id, user_id, role_id, status, display_name, invited_email, accepted_at, created_by
  ) values (
    v_club_id, v_draft.submitted_by_user_id, v_owner_role_id, 'active',
    nullif(trim(v_answers #>> '{club,contact_name}'), ''), v_draft.invited_email, now(), v_draft.submitted_by_user_id
  ) returning id into v_assignment_id;

  for v_officer in select value from jsonb_array_elements(coalesce(v_answers->'officers', '[]'::jsonb)) loop
    v_officer_email := lower(nullif(trim(v_officer->>'email'), ''));
    v_officer_name := nullif(trim(v_officer->>'name'), '');
    v_officer_title := nullif(trim(v_officer->>'title'), '');
    v_officer_profile := coalesce(nullif(trim(v_officer->>'access_template'), ''), 'read_only');
    if v_officer_email is null or v_officer_title is null then continue; end if;
    if v_officer_email = lower(v_draft.invited_email) then
      update public.club_staff_assignments
      set display_name=coalesce(v_officer_name, display_name), title_override=v_officer_title
      where id=v_assignment_id;
      continue;
    end if;
    insert into public.club_staff_invitations (
      club_id, display_name, email, role_id, title_override, permission_profile, status, invited_by
    ) values (
      v_club_id, coalesce(v_officer_name, v_officer_email), v_officer_email, v_admin_role_id,
      v_officer_title, v_officer_profile, 'pending', v_draft.submitted_by_user_id
    ) on conflict (club_id, email) do nothing;
  end loop;

  if nullif(trim(v_answers #>> '{treasurer,email}'), '') is not null
     and lower(v_answers #>> '{treasurer,email}') <> lower(v_draft.invited_email) then
    insert into public.club_staff_invitations (
      club_id, display_name, email, role_id, title_override, status, invited_by
    ) values (
      v_club_id,
      coalesce(nullif(trim(v_answers #>> '{treasurer,name}'), ''), v_answers #>> '{treasurer,email}'),
      lower(trim(v_answers #>> '{treasurer,email}')), v_treasurer_role_id,
      'Treasurer', 'pending', v_draft.submitted_by_user_id
    ) on conflict (club_id, email) do nothing;
  end if;

  if v_provider in ('stripe', 'square', 'paypal') then
    insert into public.club_payment_accounts (
      club_id, provider, account_status, created_by_user_id
    ) values (
      v_club_id, v_provider, 'pending_onboarding', v_draft.submitted_by_user_id
    ) on conflict (club_id, provider) do nothing;
  end if;

  if (v_entitlements->'addons') ? 'membership_management' then
    insert into public.club_membership_types (
      club_id, name, code, description, membership_scope, billing_type, term_type,
      price, currency, minimum_age, maximum_age, requires_approval, allow_auto_renew,
      is_public, is_active, sort_order, settings, require_arba_number
    ) values
      (v_club_id, 'Individual', 'IND', 'One adult membership.', 'individual', 'one_time', 'rolling_year', 10, 'usd', 19, null, false, false, true, true, 10, '{}'::jsonb, true),
      (v_club_id, 'Family', 'FAM', 'Family membership for members of the same household.', 'family', 'one_time', 'rolling_year', 15, 'usd', null, null, false, false, true, true, 20, '{"included_adults":2,"included_youth":3,"additional_youth_price":0}'::jsonb, true),
      (v_club_id, 'Youth', 'YTH', 'Youth membership.', 'youth', 'one_time', 'rolling_year', 5, 'usd', null, 18, false, false, true, true, 30, '{}'::jsonb, true);
  end if;

  update public.club_onboarding_drafts
  set status='approved', approved_at=now(), provisioned_club_id=v_club_id, updated_at=now()
  where id=v_draft.id;

  return jsonb_build_object(
    'draft_id', v_draft.id,
    'club_id', v_club_id,
    'payment_provider', v_provider,
    'stripe_connect_required', v_provider = 'stripe'
  );
end;
$$;

revoke all on function public.apply_club_staff_permission_profile(uuid, uuid, text) from public;
revoke all on function public.approve_club_onboarding_draft(uuid) from public;
revoke all on function public.issue_club_onboarding_invitation(text, integer, jsonb) from public;
revoke all on function public.apply_club_staff_permission_profile(uuid, uuid, text) from anon, authenticated;
revoke all on function public.approve_club_onboarding_draft(uuid) from anon, authenticated;
revoke all on function public.issue_club_onboarding_invitation(text, integer, jsonb) from anon, authenticated;
grant execute on function public.get_club_onboarding_invitation(text) to authenticated;
grant execute on function public.save_club_onboarding_draft(text, text, jsonb) to authenticated;
grant execute on function public.submit_club_onboarding_draft(text) to authenticated;
