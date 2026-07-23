create or replace function public.save_club_sweepstakes_season(
  p_season_id uuid,
  p_club_id uuid,
  p_name text,
  p_status text,
  p_start_date date,
  p_end_date date,
  p_description text,
  p_points_notes text,
  p_publication_mode text default 'manual',
  p_visibility text default 'members',
  p_public_display_format text default 'name_state'
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_season_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required.';
  end if;
  if not public.is_club_staff(p_club_id, auth.uid()) then
    raise exception 'You do not have permission to manage sweepstakes for this club.';
  end if;
  if nullif(trim(p_name), '') is null then
    raise exception 'Season name is required.';
  end if;
  if p_status not in ('draft', 'active', 'finalized', 'archived') then
    raise exception 'Invalid sweepstakes season status: %', p_status;
  end if;
  if p_publication_mode not in ('live', 'manual') then
    raise exception 'Invalid publication mode: %', p_publication_mode;
  end if;
  if p_visibility not in ('public', 'members') then
    raise exception 'Invalid visibility: %', p_visibility;
  end if;
  if p_public_display_format not in ('name_only', 'name_state', 'name_city_state') then
    raise exception 'Invalid public display format: %', p_public_display_format;
  end if;
  if p_start_date is null or p_end_date is null or p_end_date < p_start_date then
    raise exception 'A valid season start and end date are required.';
  end if;

  if p_season_id is null then
    insert into public.club_sweepstakes_seasons (
      club_id, name, status, start_date, end_date, description, points_notes,
      publication_mode, visibility, public_display_format
    ) values (
      p_club_id, trim(p_name), p_status, p_start_date, p_end_date,
      nullif(trim(p_description), ''), nullif(trim(p_points_notes), ''),
      p_publication_mode, p_visibility, p_public_display_format
    ) returning id into v_season_id;
  else
    update public.club_sweepstakes_seasons
    set name = trim(p_name),
        status = p_status,
        start_date = p_start_date,
        end_date = p_end_date,
        description = nullif(trim(p_description), ''),
        points_notes = nullif(trim(p_points_notes), ''),
        publication_mode = p_publication_mode,
        visibility = p_visibility,
        public_display_format = p_public_display_format,
        updated_at = now()
    where id = p_season_id and club_id = p_club_id
    returning id into v_season_id;
    if v_season_id is null then
      raise exception 'Sweepstakes season % was not found.', p_season_id;
    end if;
  end if;
  return v_season_id;
end;
$$;
