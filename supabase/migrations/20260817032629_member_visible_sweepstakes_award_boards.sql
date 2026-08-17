-- The staff leaderboard query deliberately needs full club access.  Members
-- receive this narrower, explicitly authorized view instead: active boards for
-- their club, and only the public leaderboard fields for each board.

create or replace function public.get_member_club_sweepstakes_award_boards(
  p_club_id uuid
)
returns table (
  id uuid,
  season_id uuid,
  season_name text,
  season_starts_on date,
  season_ends_on date,
  name text,
  board_grouping text,
  top_n integer,
  sort_order integer
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
      select 1
      from public.club_memberships m
      where m.club_id = p_club_id
        and m.user_id = auth.uid()
        and m.status = 'active'
    ) then
    raise exception 'You do not have permission to view these award boards.';
  end if;

  return query
  select b.id, b.season_id, s.name, s.start_date, s.end_date,
         b.name, b.grouping::text, b.top_n, b.sort_order
  from public.club_sweepstakes_award_boards b
  join public.club_sweepstakes_seasons s on s.id = b.season_id
  where b.club_id = p_club_id
    and b.is_active
    -- A club can intentionally expose an in-progress season to members by
    -- selecting member/public visibility.  Published seasons remain visible.
    and (
      s.published_at is not null
      or s.status = 'published'
      or s.visibility in ('members', 'public')
    )
  order by s.start_date desc, b.sort_order, b.name;
end;
$$;

create or replace function public.get_member_club_sweepstakes_award_board_entries(
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
security definer
set search_path = public, pg_temp
as $$
declare
  v_board public.club_sweepstakes_award_boards%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required.';
  end if;

  select b.* into v_board
  from public.club_sweepstakes_award_boards b
  join public.club_sweepstakes_seasons s on s.id = b.season_id
  where b.id = p_award_board_id
    and b.is_active
    and (
      s.published_at is not null
      or s.status = 'published'
      or s.visibility in ('members', 'public')
    );

  if not found then
    raise exception 'Award board not found or is not visible to members.';
  end if;

  if not public.is_club_staff(v_board.club_id, auth.uid())
    and not exists (
      select 1
      from public.club_memberships m
      where m.club_id = v_board.club_id
        and m.user_id = auth.uid()
        and m.status = 'active'
    ) then
    raise exception 'You do not have permission to view these award standings.';
  end if;

  if v_board.grouping = 'overall' then
    return query
    with all_active_members as (
      select m.id, m.showing_name, m.first_name, m.last_name, m.membership_type_id,
             mt.name as membership_type_name, m.state
      from public.club_memberships m
      join public.club_membership_types mt on mt.id = m.membership_type_id
      where m.club_id = v_board.club_id
        and m.status = 'active'
        and (m.current_term_end is null or m.current_term_end >= current_date)
    ), eligible_members as (
      select * from all_active_members m
      where (cardinality(v_board.membership_type_ids) = 0 or m.membership_type_id = any(v_board.membership_type_ids))
        and (v_board.residency_requirement = 'any'
          or (v_board.residency_requirement = 'in_state' and upper(coalesce(m.state, '')) = upper(coalesce(v_board.eligibility_state, '')))
          or (v_board.residency_requirement = 'out_of_state' and upper(coalesce(m.state, '')) <> upper(coalesce(v_board.eligibility_state, ''))))
    ), shared_rules as (
      select r.id, r.rule_type, r.match_value, r.replacement_value
      from public.club_sweepstakes_parser_rules r
      cross join all_active_members a
      left join eligible_members e on e.id = a.id
      where r.club_id = v_board.club_id and r.is_active
        and r.rule_type in ('name_alias', 'name_pattern')
        and nullif(trim(coalesce(r.replacement_value, '')), '') is not null
      group by r.id, r.rule_type, r.match_value, r.replacement_value
      having count(a.id) filter (where public.club_sweepstakes_name_contains_all_words(coalesce(nullif(a.showing_name, ''), concat_ws(' ', a.first_name, a.last_name)), r.replacement_value)) >= 2
        and count(a.id) filter (where public.club_sweepstakes_name_contains_all_words(coalesce(nullif(a.showing_name, ''), concat_ws(' ', a.first_name, a.last_name)), r.replacement_value))
          = count(e.id) filter (where public.club_sweepstakes_name_contains_all_words(coalesce(nullif(e.showing_name, ''), concat_ws(' ', e.first_name, e.last_name)), r.replacement_value))
    ), entries as (
      select 'member:' || e.id::text as entry_key,
             coalesce(nullif(e.showing_name, ''), nullif(concat_ws(' ', e.first_name, e.last_name), ''), s.exhibitor_name) as entry_name,
             e.membership_type_name as entry_type, s.total_points as entry_points
      from public.club_sweepstakes_standings s
      join eligible_members e on (public.club_sweepstakes_names_match(e.showing_name, s.exhibitor_name) or public.club_sweepstakes_names_match(concat_ws(' ', e.first_name, e.last_name), s.exhibitor_name))
      where s.club_id = v_board.club_id and s.season_id = v_board.season_id
      union all
      select * from (
        select distinct on (s.id) 'shared:' || sr.id::text || ':' || s.id::text,
               coalesce(nullif(sr.replacement_value, ''), s.exhibitor_name),
               'Combined active members'::text, s.total_points
        from public.club_sweepstakes_standings s
        join shared_rules sr on ((sr.rule_type = 'name_alias' and public.club_sweepstakes_names_match(sr.match_value, s.exhibitor_name)) or (sr.rule_type = 'name_pattern' and public.club_sweepstakes_name_contains_all_words(sr.match_value, s.exhibitor_name)))
        where s.club_id = v_board.club_id and s.season_id = v_board.season_id
        order by s.id, sr.id
      ) as shared_entries
    ), ranked as (
      select row_number() over (order by sum(entry_points) desc, min(entry_name))::integer as entry_rank,
             min(entry_name) as entry_name, min(entry_type) as entry_type, sum(entry_points) as entry_points
      from entries group by entry_key
    )
    select entry_rank, entry_name, entry_type, null::text, entry_points
    from ranked where entry_rank <= v_board.top_n order by entry_rank;
  else
    return query
    with all_active_members as (
      select m.id, m.showing_name, m.first_name, m.last_name, m.membership_type_id,
             mt.name as membership_type_name, m.state
      from public.club_memberships m
      join public.club_membership_types mt on mt.id = m.membership_type_id
      where m.club_id = v_board.club_id and m.status = 'active'
        and (m.current_term_end is null or m.current_term_end >= current_date)
    ), eligible_members as (
      select * from all_active_members m
      where (cardinality(v_board.membership_type_ids) = 0 or m.membership_type_id = any(v_board.membership_type_ids))
        and (v_board.residency_requirement = 'any'
          or (v_board.residency_requirement = 'in_state' and upper(coalesce(m.state, '')) = upper(coalesce(v_board.eligibility_state, '')))
          or (v_board.residency_requirement = 'out_of_state' and upper(coalesce(m.state, '')) <> upper(coalesce(v_board.eligibility_state, ''))))
    ), shared_rules as (
      select r.id, r.rule_type, r.match_value, r.replacement_value
      from public.club_sweepstakes_parser_rules r
      cross join all_active_members a
      left join eligible_members e on e.id = a.id
      where r.club_id = v_board.club_id and r.is_active
        and r.rule_type in ('name_alias', 'name_pattern')
        and nullif(trim(coalesce(r.replacement_value, '')), '') is not null
      group by r.id, r.rule_type, r.match_value, r.replacement_value
      having count(a.id) filter (where public.club_sweepstakes_name_contains_all_words(coalesce(nullif(a.showing_name, ''), concat_ws(' ', a.first_name, a.last_name)), r.replacement_value)) >= 2
        and count(a.id) filter (where public.club_sweepstakes_name_contains_all_words(coalesce(nullif(a.showing_name, ''), concat_ws(' ', a.first_name, a.last_name)), r.replacement_value))
          = count(e.id) filter (where public.club_sweepstakes_name_contains_all_words(coalesce(nullif(e.showing_name, ''), concat_ws(' ', e.first_name, e.last_name)), r.replacement_value))
    ), entries as (
      select 'member:' || e.id::text || ':' || r.breed as entry_key,
             coalesce(nullif(e.showing_name, ''), nullif(concat_ws(' ', e.first_name, e.last_name), ''), r.exhibitor_name) as entry_name,
             e.membership_type_name as entry_type, r.breed as entry_breed, a.points_applied as entry_points
      from public.club_sweepstakes_result_applications a
      join public.club_sweepstakes_result_import_rows r on r.id = a.result_row_id
      join public.club_sweepstakes_result_imports i on i.id = a.import_id
      join eligible_members e on (public.club_sweepstakes_names_match(e.showing_name, r.exhibitor_name) or public.club_sweepstakes_names_match(concat_ws(' ', e.first_name, e.last_name), r.exhibitor_name))
      where a.club_id = v_board.club_id and i.season_id = v_board.season_id
        and nullif(trim(coalesce(r.breed, '')), '') is not null
      union all
      select * from (
        select distinct on (a.id) 'shared:' || sr.id::text || ':' || r.breed,
               coalesce(nullif(sr.replacement_value, ''), r.exhibitor_name),
               'Combined active members'::text, r.breed, a.points_applied
        from public.club_sweepstakes_result_applications a
        join public.club_sweepstakes_result_import_rows r on r.id = a.result_row_id
        join public.club_sweepstakes_result_imports i on i.id = a.import_id
        join shared_rules sr on ((sr.rule_type = 'name_alias' and public.club_sweepstakes_names_match(sr.match_value, r.exhibitor_name)) or (sr.rule_type = 'name_pattern' and public.club_sweepstakes_name_contains_all_words(sr.match_value, r.exhibitor_name)))
        where a.club_id = v_board.club_id and i.season_id = v_board.season_id
          and nullif(trim(coalesce(r.breed, '')), '') is not null
        order by a.id, sr.id
      ) as shared_entries
    ), ranked as (
      select row_number() over (partition by entry_breed order by sum(entry_points) desc, min(entry_name))::integer as entry_rank,
             min(entry_name) as entry_name, min(entry_type) as entry_type, entry_breed, sum(entry_points) as entry_points
      from entries group by entry_key, entry_breed
    )
    select entry_rank, entry_name, entry_type, entry_breed, entry_points
    from ranked where entry_rank <= v_board.top_n order by entry_breed, entry_rank;
  end if;
end;
$$;

revoke all on function public.get_member_club_sweepstakes_award_boards(uuid) from public;
revoke all on function public.get_member_club_sweepstakes_award_board_entries(uuid) from public;
grant execute on function public.get_member_club_sweepstakes_award_boards(uuid) to authenticated;
grant execute on function public.get_member_club_sweepstakes_award_board_entries(uuid) to authenticated;
