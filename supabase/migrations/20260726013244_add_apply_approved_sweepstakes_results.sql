-- Each approved report row is applied at most once.  This preserves the
-- source-to-standing audit trail and makes the final application idempotent.
create table public.club_sweepstakes_result_applications (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  import_id uuid not null references public.club_sweepstakes_result_imports(id) on delete cascade,
  result_row_id uuid not null unique references public.club_sweepstakes_result_import_rows(id) on delete cascade,
  standing_id uuid not null references public.club_sweepstakes_standings(id) on delete restrict,
  points_applied numeric not null,
  applied_by uuid references auth.users(id) on delete set null,
  applied_at timestamptz not null default now()
);

create index club_sweepstakes_result_applications_import_idx
  on public.club_sweepstakes_result_applications(import_id);

alter table public.club_sweepstakes_result_applications enable row level security;

create policy "Club staff can manage sweepstakes result applications"
  on public.club_sweepstakes_result_applications for all to authenticated
  using (is_club_staff(club_id, auth.uid()))
  with check (is_club_staff(club_id, auth.uid()));

create or replace function public.apply_club_sweepstakes_result_import(
  p_import_id uuid
)
returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_import public.club_sweepstakes_result_imports%rowtype;
  v_row public.club_sweepstakes_result_import_rows%rowtype;
  v_standing_id uuid;
  v_applied_rows integer := 0;
  v_updated_standings integer := 0;
  v_publication_mode text;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required.';
  end if;

  select * into v_import
  from public.club_sweepstakes_result_imports
  where id = p_import_id
  for update;

  if not found then
    raise exception 'Results draft not found.';
  end if;
  if not public.is_club_staff(v_import.club_id, auth.uid()) then
    raise exception 'You do not have permission to apply these results.';
  end if;
  if v_import.season_id is null then
    raise exception 'Match this report to a sweepstakes season before applying results.';
  end if;
  if v_import.status = 'applied' then
    raise exception 'These results have already been applied to standings.';
  end if;
  if not exists (
    select 1 from public.club_sweepstakes_result_import_rows
    where import_id = p_import_id
  ) then
    raise exception 'There are no result rows to apply.';
  end if;
  if exists (
    select 1 from public.club_sweepstakes_result_import_rows
    where import_id = p_import_id and status <> 'approved'
  ) then
    raise exception 'Approve or reject every result row before applying this report.';
  end if;

  for v_row in
    select * from public.club_sweepstakes_result_import_rows
    where import_id = p_import_id and status = 'approved'
    order by created_at, id
  loop
    if exists (
      select 1 from public.club_sweepstakes_result_applications
      where result_row_id = v_row.id
    ) then
      raise exception 'An approved result has already been applied.';
    end if;

    select id into v_standing_id
    from public.club_sweepstakes_standings
    where club_id = v_import.club_id
      and season_id = v_import.season_id
      and division_id is not distinct from v_row.division_id
      and lower(trim(exhibitor_name)) = lower(trim(v_row.exhibitor_name))
    order by created_at
    limit 1
    for update;

    if v_standing_id is null then
      insert into public.club_sweepstakes_standings (
        club_id, season_id, division_id, exhibitor_name, membership_number,
        species, breed, variety, points_from_results, points_adjusted,
        total_points, show_count, last_points_at, created_by, updated_by
      ) values (
        v_import.club_id, v_import.season_id, v_row.division_id,
        trim(v_row.exhibitor_name), v_row.membership_number, v_row.species,
        v_row.breed, v_row.variety, v_row.calculated_points, 0,
        v_row.calculated_points, 1, now(), auth.uid(), auth.uid()
      ) returning id into v_standing_id;
    else
      update public.club_sweepstakes_standings
      set points_from_results = points_from_results + v_row.calculated_points,
          total_points = points_from_results + v_row.calculated_points + points_adjusted,
          show_count = show_count + 1,
          last_points_at = now(),
          updated_by = auth.uid(),
          updated_at = now()
      where id = v_standing_id;
    end if;

    insert into public.club_sweepstakes_result_applications (
      club_id, import_id, result_row_id, standing_id, points_applied, applied_by
    ) values (
      v_import.club_id, p_import_id, v_row.id, v_standing_id,
      v_row.calculated_points, auth.uid()
    );
    v_applied_rows := v_applied_rows + 1;
    v_updated_standings := v_updated_standings + 1;
  end loop;

  update public.club_sweepstakes_result_imports
  set status = 'applied', applied_by = auth.uid(), applied_at = now(), updated_at = now()
  where id = p_import_id;

  update public.club_sweepstakes_report_packages
  set status = 'processed', processed_by = auth.uid(), processed_at = now(), updated_at = now()
  where id = v_import.report_package_id;

  if v_import.expected_report_id is not null then
    update public.club_sweepstakes_expected_reports
    set status = 'processed', updated_at = now()
    where id = v_import.expected_report_id;
  end if;

  select publication_mode into v_publication_mode
  from public.club_sweepstakes_seasons
  where id = v_import.season_id;

  if v_publication_mode = 'live' then
    update public.club_sweepstakes_seasons
    set published_at = now(), updated_at = now()
    where id = v_import.season_id;
  end if;

  return jsonb_build_object(
    'applied_rows', v_applied_rows,
    'updated_standings', v_updated_standings,
    'published_live', v_publication_mode = 'live'
  );
end;
$$;

revoke execute on function public.apply_club_sweepstakes_result_import(uuid) from public;
grant execute on function public.apply_club_sweepstakes_result_import(uuid) to authenticated;
