-- RingMaster-internal access is deliberately separate from club roles. The
-- allowlist is checked server-side, so this panel is neither a club feature nor
-- discoverable by ordinary authenticated users.
create table public.club_operations_users (
  email text primary key,
  created_at timestamptz not null default now()
);

alter table public.club_operations_users enable row level security;
revoke all on public.club_operations_users from anon, authenticated;
grant all on public.club_operations_users to service_role;

insert into public.club_operations_users (email)
values ('zaynetort2@gmail.com')
on conflict (email) do nothing;

create or replace function public.is_club_operations_user()
returns boolean
language sql
security definer
set search_path = public, auth, pg_temp
as $$
  select auth.uid() is not null
    and exists (
      select 1 from public.club_operations_users user_access
      where user_access.email = lower(auth.email())
    );
$$;

create or replace function public.get_club_operations_dashboard()
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_drafts jsonb;
begin
  if not public.is_club_operations_user() then
    raise exception 'RingMaster Operations access is required.';
  end if;

  select coalesce(jsonb_agg(row_data order by (row_data->>'updated_at') desc), '[]'::jsonb)
  into v_drafts
  from (
    select jsonb_build_object(
      'id', draft.id,
      'status', draft.status,
      'email', draft.invited_email,
      'club_name', coalesce(nullif(draft.answers #>> '{club,name}', ''), 'Untitled club'),
      'current_step', draft.current_step,
      'created_at', draft.created_at,
      'updated_at', draft.updated_at,
      'submitted_at', invitation.submitted_at,
      'approved_at', draft.approved_at,
      'payment_provider', coalesce(nullif(draft.answers #>> '{setup,payment_provider}', ''), 'not_ready'),
      'plan_key', coalesce(draft.purchased_entitlements->>'plan_key', 'small_club_base'),
      'provisioned_club_id', draft.provisioned_club_id,
      'payment_status', payment.account_status,
      'payment_provider_connected', payment.provider
    ) as row_data
    from public.club_onboarding_drafts draft
    left join lateral (
      select submitted_at from public.club_onboarding_invitations invitation
      where invitation.draft_id = draft.id
      order by invitation.created_at desc limit 1
    ) invitation on true
    left join lateral (
      select account_status, provider from public.club_payment_accounts account
      where account.club_id = draft.provisioned_club_id
      order by account.updated_at desc limit 1
    ) payment on true
  ) rows;

  return jsonb_build_object(
    'drafts', v_drafts,
    'ready_for_review_count', (select count(*) from public.club_onboarding_drafts where status = 'ready_for_review'),
    'approved_count', (select count(*) from public.club_onboarding_drafts where status = 'approved')
  );
end;
$$;

create or replace function public.approve_club_onboarding_from_operations(p_draft_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
begin
  if not public.is_club_operations_user() then
    raise exception 'RingMaster Operations access is required.';
  end if;
  return public.approve_club_onboarding_draft(p_draft_id);
end;
$$;

revoke all on function public.is_club_operations_user() from public;
revoke all on function public.get_club_operations_dashboard() from public;
revoke all on function public.approve_club_onboarding_from_operations(uuid) from public;
grant execute on function public.is_club_operations_user() to authenticated;
grant execute on function public.get_club_operations_dashboard() to authenticated;
grant execute on function public.approve_club_onboarding_from_operations(uuid) to authenticated;
