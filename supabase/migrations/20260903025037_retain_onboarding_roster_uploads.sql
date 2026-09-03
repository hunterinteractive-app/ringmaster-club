-- Keep each currently staged onboarding roster in private storage so both the
-- invited club contact and RingMaster Operations can retrieve the original CSV.
alter table public.club_onboarding_roster_previews
  add column if not exists storage_bucket text,
  add column if not exists storage_path text,
  add column if not exists storage_uploaded_at timestamptz;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'club-onboarding-rosters',
  'club-onboarding-rosters',
  false,
  10485760,
  array['text/csv', 'application/csv', 'application/vnd.ms-excel']
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.can_access_club_onboarding_roster_storage(
  p_object_name text
)
returns boolean
language sql
security definer
set search_path = public, auth, pg_temp
as $$
  select auth.uid() is not null
    and p_object_name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/'
    and exists (
      select 1
      from public.club_onboarding_invitations invitation
      where invitation.draft_id = split_part(p_object_name, '/', 1)::uuid
        and lower(invitation.email) = lower(coalesce(auth.email(), ''))
        and invitation.status not in ('cancelled', 'expired')
        and invitation.expires_at > now()
    );
$$;

revoke all on function public.can_access_club_onboarding_roster_storage(text) from public;
grant execute on function public.can_access_club_onboarding_roster_storage(text) to authenticated;

drop policy if exists "Onboarding contacts can read their roster uploads" on storage.objects;
drop policy if exists "Onboarding contacts can upload their roster" on storage.objects;
drop policy if exists "Onboarding contacts can update their roster uploads" on storage.objects;
drop policy if exists "Onboarding contacts can delete their roster uploads" on storage.objects;

create policy "Onboarding contacts can read their roster uploads"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'club-onboarding-rosters'
    and (
      public.is_club_operations_user()
      or public.can_access_club_onboarding_roster_storage(name)
    )
  );

create policy "Onboarding contacts can upload their roster"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'club-onboarding-rosters'
    and public.can_access_club_onboarding_roster_storage(name)
  );

create policy "Onboarding contacts can update their roster uploads"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'club-onboarding-rosters'
    and public.can_access_club_onboarding_roster_storage(name)
  )
  with check (
    bucket_id = 'club-onboarding-rosters'
    and public.can_access_club_onboarding_roster_storage(name)
  );

create policy "Onboarding contacts can delete their roster uploads"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'club-onboarding-rosters'
    and public.can_access_club_onboarding_roster_storage(name)
  );

drop function if exists public.save_club_onboarding_roster_preview(text, text, jsonb, jsonb);
create function public.save_club_onboarding_roster_preview(
  p_token text,
  p_file_name text,
  p_headers jsonb,
  p_rows jsonb,
  p_storage_bucket text,
  p_storage_path text
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
  if p_storage_bucket <> 'club-onboarding-rosters'
     or p_storage_path !~ ('^' || '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' || '/') then
    raise exception 'A valid private roster upload is required.';
  end if;
  select * into v_invitation from public.club_onboarding_invitations
  where token_hash = encode(digest(trim(p_token), 'sha256'), 'hex')
    and lower(email) = lower(coalesce(auth.email(), ''))
    and status not in ('cancelled', 'expired')
    and expires_at > now()
  for update;
  if not found then raise exception 'This onboarding invitation is not available.'; end if;
  if split_part(p_storage_path, '/', 1)::uuid <> v_invitation.draft_id then
    raise exception 'The roster upload does not belong to this invitation.';
  end if;
  if not exists (
    select 1 from storage.objects
    where bucket_id = p_storage_bucket and name = p_storage_path
  ) then
    raise exception 'The roster file could not be found in private storage.';
  end if;

  insert into public.club_onboarding_roster_previews (
    draft_id, source_file_name, headers, total_rows, valid_rows, error_rows,
    storage_bucket, storage_path, storage_uploaded_at, created_by, updated_at
  ) values (
    v_invitation.draft_id, left(trim(coalesce(p_file_name, 'membership-roster.csv')), 255), p_headers,
    jsonb_array_length(p_rows), 0, 0, p_storage_bucket, p_storage_path, now(), auth.uid(), now()
  ) on conflict (draft_id) do update set
    source_file_name = excluded.source_file_name, headers = excluded.headers,
    total_rows = excluded.total_rows, valid_rows = 0, error_rows = 0,
    storage_bucket = excluded.storage_bucket, storage_path = excluded.storage_path,
    storage_uploaded_at = excluded.storage_uploaded_at,
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
    'storage_bucket', v_preview.storage_bucket, 'storage_path', v_preview.storage_path,
    'storage_uploaded_at', v_preview.storage_uploaded_at,
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
    'storage_bucket', v_preview.storage_bucket, 'storage_path', v_preview.storage_path,
    'storage_uploaded_at', v_preview.storage_uploaded_at,
    'rows', coalesce((select jsonb_agg(jsonb_build_object(
      'row_number', row.row_number, 'source_row', row.source_row,
      'proposed_member', row.proposed_member, 'errors', row.errors
    ) order by row.row_number) from public.club_onboarding_roster_preview_rows row where row.preview_id = v_preview.id), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.save_club_onboarding_roster_preview(text, text, jsonb, jsonb, text, text) from public;
revoke all on function public.get_club_onboarding_roster_preview(text) from public;
revoke all on function public.get_club_operations_roster_preview(uuid) from public;
grant execute on function public.save_club_onboarding_roster_preview(text, text, jsonb, jsonb, text, text) to authenticated;
grant execute on function public.get_club_onboarding_roster_preview(text) to authenticated;
grant execute on function public.get_club_operations_roster_preview(uuid) to authenticated;
