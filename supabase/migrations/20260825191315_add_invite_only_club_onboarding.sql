create table public.club_onboarding_drafts (
  id uuid primary key default gen_random_uuid(),
  invited_email text not null,
  status text not null default 'in_progress'
    check (status in ('in_progress', 'ready_for_review', 'approved', 'cancelled', 'expired')),
  current_step text not null default 'club',
  answers jsonb not null default '{}'::jsonb,
  submitted_at timestamptz,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.club_onboarding_invitations (
  id uuid primary key default gen_random_uuid(),
  draft_id uuid not null references public.club_onboarding_drafts(id) on delete cascade,
  email text not null,
  token_hash text not null unique,
  status text not null default 'pending'
    check (status in ('pending', 'opened', 'submitted', 'cancelled', 'expired')),
  expires_at timestamptz not null default (now() + interval '14 days'),
  created_at timestamptz not null default now(),
  opened_at timestamptz,
  submitted_at timestamptz,
  unique (draft_id, email)
);

create index club_onboarding_invitations_token_idx
  on public.club_onboarding_invitations (token_hash);

alter table public.club_onboarding_drafts enable row level security;
alter table public.club_onboarding_invitations enable row level security;

-- Invitation creation is deliberately not granted to app users. RingMaster
-- staff create the invitation from the secure admin workflow or SQL console.
create or replace function public.issue_club_onboarding_invitation(
  p_email text,
  p_expires_in_days integer default 14
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
begin
  if v_email = '' or position('@' in v_email) = 0 then
    raise exception 'Enter a valid club email.';
  end if;
  if p_expires_in_days not between 1 and 90 then
    raise exception 'Invite expiry must be between 1 and 90 days.';
  end if;

  insert into public.club_onboarding_drafts (invited_email)
  values (v_email)
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
    'expires_at', v_invitation.expires_at
  );
end;
$$;

create or replace function public.save_club_onboarding_draft(
  p_token text,
  p_current_step text,
  p_answers jsonb
)
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
  if auth.uid() is null then raise exception 'Sign in to save onboarding progress.'; end if;
  select * into v_invitation from public.club_onboarding_invitations
  where token_hash=encode(digest(trim(p_token),'sha256'),'hex') for update;
  if not found or v_invitation.expires_at <= now() or v_invitation.status in ('cancelled','expired') then
    raise exception 'This onboarding invitation is no longer available.';
  end if;
  if lower(v_invitation.email) <> v_email then raise exception 'Use the invited club email.'; end if;
  select * into v_draft from public.club_onboarding_drafts where id=v_invitation.draft_id for update;
  if v_draft.status not in ('in_progress','ready_for_review') then raise exception 'This onboarding draft is closed.'; end if;
  update public.club_onboarding_drafts
  set current_step=coalesce(nullif(trim(p_current_step),''),'club'),
      answers=coalesce(p_answers,'{}'::jsonb),
      status=case when v_draft.status='ready_for_review' then 'in_progress' else v_draft.status end,
      updated_at=now()
  where id=v_draft.id
  returning * into v_draft;
  return jsonb_build_object('draft_id',v_draft.id,'status',v_draft.status,'current_step',v_draft.current_step,'answers',v_draft.answers);
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
  set status='ready_for_review', current_step='review', submitted_at=now(), updated_at=now()
  where id=v_invitation.draft_id returning * into v_draft;
  update public.club_onboarding_invitations set status='submitted',submitted_at=now() where id=v_invitation.id;
  return jsonb_build_object('draft_id',v_draft.id,'status',v_draft.status);
end;
$$;

revoke all on function public.issue_club_onboarding_invitation(text, integer) from public;
revoke all on function public.get_club_onboarding_invitation(text) from public;
revoke all on function public.save_club_onboarding_draft(text, text, jsonb) from public;
revoke all on function public.submit_club_onboarding_draft(text) from public;
grant execute on function public.get_club_onboarding_invitation(text) to authenticated;
grant execute on function public.save_club_onboarding_draft(text, text, jsonb) to authenticated;
grant execute on function public.submit_club_onboarding_draft(text) to authenticated;
