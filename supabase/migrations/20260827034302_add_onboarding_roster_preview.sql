-- A roster is staged before a club is provisioned. It is never imported by
-- merely uploading it: both the invitee and RingMaster Operations can review
-- the normalized member preview first.
create table public.club_onboarding_roster_previews (
  id uuid primary key default gen_random_uuid(),
  draft_id uuid not null unique references public.club_onboarding_drafts(id) on delete cascade,
  source_file_name text not null,
  headers jsonb not null default '[]'::jsonb,
  total_rows integer not null default 0 check (total_rows >= 0),
  valid_rows integer not null default 0 check (valid_rows >= 0),
  error_rows integer not null default 0 check (error_rows >= 0),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.club_onboarding_roster_preview_rows (
  id uuid primary key default gen_random_uuid(),
  preview_id uuid not null references public.club_onboarding_roster_previews(id) on delete cascade,
  row_number integer not null check (row_number > 0),
  source_row jsonb not null,
  proposed_member jsonb not null,
  errors jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  unique (preview_id, row_number)
);

create index club_onboarding_roster_preview_rows_preview_idx
  on public.club_onboarding_roster_preview_rows(preview_id, row_number);

alter table public.club_onboarding_roster_previews enable row level security;
alter table public.club_onboarding_roster_preview_rows enable row level security;

-- Access is only through the token-validated and Operations-validated RPCs.
revoke all on public.club_onboarding_roster_previews from anon, authenticated;
revoke all on public.club_onboarding_roster_preview_rows from anon, authenticated;

create or replace function public.save_club_onboarding_roster_preview(
  p_token text,
  p_file_name text,
  p_headers jsonb,
  p_rows jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, auth, pg_temp
as $$
declare
  v_invitation public.club_onboarding_invitations%rowtype;
  v_preview_id uuid;
  v_total integer;
  v_valid integer;
  v_errors integer;
begin
  if auth.uid() is null then raise exception 'Sign in to upload a roster.'; end if;
  if jsonb_typeof(p_headers) <> 'array' or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'Roster data must be a list of columns and rows.';
  end if;
  if jsonb_array_length(p_rows) > 1000 then
    raise exception 'Upload up to 1,000 roster rows at a time.';
  end if;
  select * into v_invitation from public.club_onboarding_invitations
  where token_hash = encode(digest(trim(p_token), 'sha256'), 'hex')
    and lower(email) = lower(coalesce(auth.email(), ''))
    and status not in ('cancelled', 'expired')
    and expires_at > now()
  for update;
  if not found then raise exception 'This onboarding invitation is not available.'; end if;

  insert into public.club_onboarding_roster_previews (
    draft_id, source_file_name, headers, total_rows, valid_rows, error_rows, created_by, updated_at
  ) values (
    v_invitation.draft_id, left(trim(coalesce(p_file_name, 'membership-roster.csv')), 255), p_headers,
    jsonb_array_length(p_rows), 0, 0, auth.uid(), now()
  ) on conflict (draft_id) do update set
    source_file_name = excluded.source_file_name, headers = excluded.headers,
    total_rows = excluded.total_rows, valid_rows = 0, error_rows = 0,
    created_by = excluded.created_by, updated_at = now()
  returning id into v_preview_id;

  delete from public.club_onboarding_roster_preview_rows where preview_id = v_preview_id;
  insert into public.club_onboarding_roster_preview_rows (preview_id, row_number, source_row, proposed_member, errors)
  select v_preview_id,
         coalesce((item->>'row_number')::integer, ordinal::integer),
         coalesce(item->'source_row', '{}'::jsonb),
         coalesce(item->'proposed_member', '{}'::jsonb),
         coalesce(item->'errors', '[]'::jsonb)
  from jsonb_array_elements(p_rows) with ordinality as rows(item, ordinal);

  select count(*), count(*) filter (where jsonb_array_length(errors) = 0),
         count(*) filter (where jsonb_array_length(errors) > 0)
  into v_total, v_valid, v_errors
  from public.club_onboarding_roster_preview_rows where preview_id = v_preview_id;
  update public.club_onboarding_roster_previews
  set total_rows = v_total, valid_rows = v_valid, error_rows = v_errors, updated_at = now()
  where id = v_preview_id;

  return public.get_club_onboarding_roster_preview(p_token);
end;
$$;

create or replace function public.get_club_onboarding_roster_preview(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, auth, pg_temp
as $$
declare
  v_draft_id uuid;
  v_preview public.club_onboarding_roster_previews%rowtype;
begin
  if auth.uid() is null then raise exception 'Sign in to view the roster.'; end if;
  select invitation.draft_id into v_draft_id
  from public.club_onboarding_invitations invitation
  where invitation.token_hash = encode(digest(trim(p_token), 'sha256'), 'hex')
    and lower(invitation.email) = lower(coalesce(auth.email(), ''))
    and invitation.status not in ('cancelled', 'expired')
    and invitation.expires_at > now();
  if v_draft_id is null then raise exception 'This onboarding invitation is not available.'; end if;
  select * into v_preview from public.club_onboarding_roster_previews where draft_id = v_draft_id;
  if not found then return jsonb_build_object('has_preview', false); end if;
  return jsonb_build_object(
    'has_preview', true, 'file_name', v_preview.source_file_name, 'headers', v_preview.headers,
    'total_rows', v_preview.total_rows, 'valid_rows', v_preview.valid_rows, 'error_rows', v_preview.error_rows,
    'rows', coalesce((select jsonb_agg(jsonb_build_object(
      'row_number', row.row_number, 'source_row', row.source_row,
      'proposed_member', row.proposed_member, 'errors', row.errors
    ) order by row.row_number) from public.club_onboarding_roster_preview_rows row where row.preview_id = v_preview.id), '[]'::jsonb)
  );
end;
$$;

create or replace function public.get_club_operations_roster_preview(p_draft_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_preview public.club_onboarding_roster_previews%rowtype;
begin
  if not public.is_club_operations_user() then raise exception 'RingMaster Operations access is required.'; end if;
  select * into v_preview from public.club_onboarding_roster_previews where draft_id = p_draft_id;
  if not found then return jsonb_build_object('has_preview', false); end if;
  return jsonb_build_object(
    'has_preview', true, 'file_name', v_preview.source_file_name, 'headers', v_preview.headers,
    'total_rows', v_preview.total_rows, 'valid_rows', v_preview.valid_rows, 'error_rows', v_preview.error_rows,
    'rows', coalesce((select jsonb_agg(jsonb_build_object(
      'row_number', row.row_number, 'source_row', row.source_row,
      'proposed_member', row.proposed_member, 'errors', row.errors
    ) order by row.row_number) from public.club_onboarding_roster_preview_rows row where row.preview_id = v_preview.id), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.save_club_onboarding_roster_preview(text, text, jsonb, jsonb) from public;
revoke all on function public.get_club_onboarding_roster_preview(text) from public;
revoke all on function public.get_club_operations_roster_preview(uuid) from public;
grant execute on function public.save_club_onboarding_roster_preview(text, text, jsonb, jsonb) to authenticated;
grant execute on function public.get_club_onboarding_roster_preview(text) to authenticated;
grant execute on function public.get_club_operations_roster_preview(uuid) to authenticated;
