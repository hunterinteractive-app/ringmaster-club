-- Read-only member views. Original PDFs and sender details remain staff-only;
-- members see only the show-level status and the reports already reflected in
-- published/member-visible points.

create or replace function public.get_member_club_sweepstakes_applied_reports(
  p_club_id uuid
)
returns table (
  import_id uuid,
  show_name text,
  show_date date,
  season_name text,
  source_type text,
  source_total_points numeric,
  calculated_total_points numeric,
  applied_at timestamptz
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication is required.';
  end if;

  if not public.is_club_staff(p_club_id, auth.uid())
    and not exists (
      select 1 from public.club_memberships m
      where m.club_id = p_club_id and m.user_id = auth.uid() and m.status = 'active'
    ) then
    raise exception 'You do not have permission to view these report summaries.';
  end if;

  return query
  select i.id,
         coalesce(nullif(e.show_name, ''), nullif(p.source_subject, ''), 'Unnamed show'),
         e.show_date,
         s.name,
         p.source_type,
         i.source_total_points,
         i.calculated_total_points,
         i.applied_at
  from public.club_sweepstakes_result_imports i
  join public.club_sweepstakes_report_packages p on p.id = i.report_package_id
  left join public.club_sweepstakes_expected_reports e on e.id = i.expected_report_id
  left join public.club_sweepstakes_seasons s on s.id = i.season_id
  where i.club_id = p_club_id and i.status = 'applied'
  order by e.show_date desc nulls last, i.applied_at desc;
end;
$$;

create or replace function public.get_member_club_sweepstakes_outstanding_reports(
  p_club_id uuid
)
returns table (
  expected_report_id uuid,
  show_name text,
  show_date date,
  due_date date,
  status text,
  package_status text,
  received_at timestamptz
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication is required.';
  end if;

  if not public.is_club_staff(p_club_id, auth.uid())
    and not exists (
      select 1 from public.club_memberships m
      where m.club_id = p_club_id and m.user_id = auth.uid() and m.status = 'active'
    ) then
    raise exception 'You do not have permission to view these report statuses.';
  end if;

  return query
  select e.id, e.show_name, e.show_date, e.due_date, e.status,
         p.status, p.source_received_at
  from public.club_sweepstakes_expected_reports e
  left join lateral (
    select rp.status, rp.source_received_at
    from public.club_sweepstakes_report_packages rp
    where rp.expected_report_id = e.id
    order by rp.source_received_at desc nulls last, rp.created_at desc
    limit 1
  ) p on true
  where e.club_id = p_club_id
    and e.status not in ('processed', 'waived')
  order by e.show_date desc, e.due_date asc;
end;
$$;

revoke all on function public.get_member_club_sweepstakes_applied_reports(uuid) from public;
revoke all on function public.get_member_club_sweepstakes_outstanding_reports(uuid) from public;
grant execute on function public.get_member_club_sweepstakes_applied_reports(uuid) to authenticated;
grant execute on function public.get_member_club_sweepstakes_outstanding_reports(uuid) to authenticated;
