create or replace function public.update_club_operations_roster_preview_row(
  p_draft_id uuid,
  p_row_number integer,
  p_proposed_member jsonb,
  p_errors jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_preview_id uuid;
  v_total integer;
  v_valid integer;
  v_errors integer;
begin
  if not public.is_club_operations_user() then
    raise exception 'RingMaster Operations access is required.';
  end if;
  if jsonb_typeof(p_proposed_member) <> 'object' or jsonb_typeof(p_errors) <> 'array' then
    raise exception 'Roster updates require a member object and an errors array.';
  end if;

  select id into v_preview_id
  from public.club_onboarding_roster_previews
  where draft_id = p_draft_id;
  if v_preview_id is null then raise exception 'No staged roster was found.'; end if;

  update public.club_onboarding_roster_preview_rows
  set proposed_member = p_proposed_member, errors = p_errors
  where preview_id = v_preview_id and row_number = p_row_number;
  if not found then raise exception 'The selected roster row was not found.'; end if;

  select count(*), count(*) filter (where jsonb_array_length(errors) = 0),
         count(*) filter (where jsonb_array_length(errors) > 0)
  into v_total, v_valid, v_errors
  from public.club_onboarding_roster_preview_rows
  where preview_id = v_preview_id;
  update public.club_onboarding_roster_previews
  set total_rows = v_total, valid_rows = v_valid, error_rows = v_errors, updated_at = now()
  where id = v_preview_id;

  return public.get_club_operations_roster_preview(p_draft_id);
end;
$$;

revoke all on function public.update_club_operations_roster_preview_row(uuid, integer, jsonb, jsonb) from public;
grant execute on function public.update_club_operations_roster_preview_row(uuid, integer, jsonb, jsonb) to authenticated;
