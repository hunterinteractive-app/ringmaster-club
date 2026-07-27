-- Report providers commonly write names as "Last First", while the club's
-- membership list uses "First Last". Treat either order as the same person,
-- without weakening the active-member or membership-type requirements.
create or replace function public.club_sweepstakes_names_match(
  p_member_name text,
  p_report_name text
)
returns boolean
language sql
immutable
set search_path = pg_catalog
as $$
  with names as (
    select
      trim(regexp_replace(lower(coalesce(p_member_name, '')), '[^a-z0-9]+', ' ', 'g')) as member_name,
      trim(regexp_replace(lower(coalesce(p_report_name, '')), '[^a-z0-9]+', ' ', 'g')) as report_name
  )
  select
    member_name <> ''
    and report_name <> ''
    and (
      member_name = report_name
      or concat_ws(
        ' ',
        regexp_replace(report_name, '^\\S+\\s*', ''),
        split_part(report_name, ' ', 1)
      ) = member_name
    )
  from names;
$$;

revoke all on function public.club_sweepstakes_names_match(text, text) from public;
grant execute on function public.club_sweepstakes_names_match(text, text) to authenticated;

create or replace function public.get_club_sweepstakes_award_board_entries(
  p_award_board_id uuid
)
returns table (
  rank integer,
  exhibitor_name text,
  membership_type_name text,
  breed text,
  points numeric
)
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_board public.club_sweepstakes_award_boards%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required.';
  end if;

  select * into v_board
  from public.club_sweepstakes_award_boards
  where id = p_award_board_id;

  if not found then
    raise exception 'Award board not found.';
  end if;
  if not public.is_club_staff(v_board.club_id, auth.uid()) then
    raise exception 'You do not have permission to view these award standings.';
  end if;

  if v_board.grouping = 'overall' then
    return query
    with eligible_members as (
      select m.id, m.showing_name, m.first_name, m.last_name, m.membership_type_id,
             mt.name as membership_type_name
      from public.club_memberships m
      join public.club_membership_types mt on mt.id = m.membership_type_id
      where m.club_id = v_board.club_id
        and m.status = 'active'
        and (m.current_term_end is null or m.current_term_end >= current_date)
        and (cardinality(v_board.membership_type_ids) = 0 or m.membership_type_id = any(v_board.membership_type_ids))
        and (
          v_board.residency_requirement = 'any'
          or (v_board.residency_requirement = 'in_state' and upper(coalesce(m.state, '')) = upper(coalesce(v_board.eligibility_state, '')))
          or (v_board.residency_requirement = 'out_of_state' and upper(coalesce(m.state, '')) <> upper(coalesce(v_board.eligibility_state, '')))
        )
    ), ranked as (
      select
        row_number() over (order by sum(s.total_points) desc, min(s.exhibitor_name))::integer as entry_rank,
        coalesce(nullif(e.showing_name, ''), nullif(concat_ws(' ', e.first_name, e.last_name), ''), min(s.exhibitor_name)) as entry_name,
        min(e.membership_type_name) as entry_type,
        sum(s.total_points) as entry_points
      from public.club_sweepstakes_standings s
      join eligible_members e on (
        public.club_sweepstakes_names_match(e.showing_name, s.exhibitor_name)
        or public.club_sweepstakes_names_match(concat_ws(' ', e.first_name, e.last_name), s.exhibitor_name)
      )
      where s.club_id = v_board.club_id and s.season_id = v_board.season_id
      group by e.id, e.showing_name, e.first_name, e.last_name
    )
    select entry_rank, entry_name, entry_type, null::text, entry_points
    from ranked
    where entry_rank <= v_board.top_n
    order by entry_rank;
  else
    return query
    with eligible_members as (
      select m.id, m.showing_name, m.first_name, m.last_name, m.membership_type_id,
             mt.name as membership_type_name
      from public.club_memberships m
      join public.club_membership_types mt on mt.id = m.membership_type_id
      where m.club_id = v_board.club_id
        and m.status = 'active'
        and (m.current_term_end is null or m.current_term_end >= current_date)
        and (cardinality(v_board.membership_type_ids) = 0 or m.membership_type_id = any(v_board.membership_type_ids))
        and (
          v_board.residency_requirement = 'any'
          or (v_board.residency_requirement = 'in_state' and upper(coalesce(m.state, '')) = upper(coalesce(v_board.eligibility_state, '')))
          or (v_board.residency_requirement = 'out_of_state' and upper(coalesce(m.state, '')) <> upper(coalesce(v_board.eligibility_state, '')))
        )
    ), ranked as (
      select
        row_number() over (partition by r.breed order by sum(a.points_applied) desc, min(r.exhibitor_name))::integer as entry_rank,
        coalesce(nullif(e.showing_name, ''), nullif(concat_ws(' ', e.first_name, e.last_name), ''), min(r.exhibitor_name)) as entry_name,
        min(e.membership_type_name) as entry_type,
        r.breed as entry_breed,
        sum(a.points_applied) as entry_points
      from public.club_sweepstakes_result_applications a
      join public.club_sweepstakes_result_import_rows r on r.id = a.result_row_id
      join public.club_sweepstakes_result_imports i on i.id = a.import_id
      join eligible_members e on (
        public.club_sweepstakes_names_match(e.showing_name, r.exhibitor_name)
        or public.club_sweepstakes_names_match(concat_ws(' ', e.first_name, e.last_name), r.exhibitor_name)
      )
      where a.club_id = v_board.club_id and i.season_id = v_board.season_id
        and nullif(trim(coalesce(r.breed, '')), '') is not null
      group by e.id, e.showing_name, e.first_name, e.last_name, r.breed
    )
    select entry_rank, entry_name, entry_type, entry_breed, entry_points
    from ranked
    where entry_rank <= v_board.top_n
    order by entry_breed, entry_rank;
  end if;
end;
$$;
