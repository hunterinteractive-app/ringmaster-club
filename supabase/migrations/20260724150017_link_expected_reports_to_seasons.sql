-- Approved sanctions create an expected report and are automatically placed in
-- the club's season whose date range contains the show date.
create or replace function public.sync_expected_sweepstakes_report_from_sanction()
returns trigger
language plpgsql
as $$
declare
  report_due_days integer;
  matched_season_id uuid;
begin
  if new.status <> 'approved' then
    return new;
  end if;

  select id into matched_season_id
  from public.club_sweepstakes_seasons
  where club_id = new.club_id
    and new.show_date between start_date and end_date
  order by case when status = 'active' then 0 else 1 end, start_date desc
  limit 1;

  select coalesce(settings.report_due_days, 30)
  into report_due_days
  from public.club_sweepstakes_settings settings
  where settings.club_id = new.club_id;

  insert into public.club_sweepstakes_expected_reports (
    club_id, season_id, sanction_request_id, club_sanction_number,
    arba_sanction_number, show_name, show_date, show_end_date, show_location,
    show_secretary_name, show_secretary_email, due_date, expected_sections,
    expected_report_types
  ) values (
    new.club_id, matched_season_id, new.id, new.sanction_number,
    coalesce(new.request_details ->> 'arba_sanction_number', new.sanction_number),
    new.show_name, new.show_date, new.show_end_date, new.location_name,
    new.contact_name, new.contact_email,
    coalesce(new.show_end_date, new.show_date) + coalesce(report_due_days, 30),
    coalesce(new.request_details -> 'expected_sections', '[]'::jsonb),
    coalesce(new.request_details -> 'expected_report_types', '[]'::jsonb)
  ) on conflict (sanction_request_id) do update
    set season_id = excluded.season_id,
        club_sanction_number = excluded.club_sanction_number,
        arba_sanction_number = excluded.arba_sanction_number,
        show_name = excluded.show_name,
        show_date = excluded.show_date,
        show_end_date = excluded.show_end_date,
        show_location = excluded.show_location,
        show_secretary_name = excluded.show_secretary_name,
        show_secretary_email = excluded.show_secretary_email,
        expected_sections = excluded.expected_sections,
        expected_report_types = excluded.expected_report_types,
        due_date = excluded.due_date,
        updated_at = now();
  return new;
end;
$$;

-- Assign existing expected reports when a season now covers their show date.
update public.club_sweepstakes_expected_reports expected_report
set season_id = (
      select season.id
      from public.club_sweepstakes_seasons season
      where season.club_id = expected_report.club_id
        and expected_report.show_date between season.start_date and season.end_date
      order by case when season.status = 'active' then 0 else 1 end, season.start_date desc
      limit 1
    ),
    updated_at = now()
where expected_report.season_id is null
  and exists (
    select 1
    from public.club_sweepstakes_seasons season
    where season.club_id = expected_report.club_id
      and expected_report.show_date between season.start_date and season.end_date
  );
