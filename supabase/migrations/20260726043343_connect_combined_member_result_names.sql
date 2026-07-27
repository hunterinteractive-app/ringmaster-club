-- A club may have separate active members whose results are reported together
-- under a shared exhibitor name.  Existing Club Rules already preserve those
-- names (for example, "Jeff Batchler / Paula Keller").  The award boards use
-- those rules to treat a shared name as eligible only when every named person
-- is an active, eligible club member.
create or replace function public.club_sweepstakes_name_contains_all_words(
  p_member_name text,
  p_report_name text
)
returns boolean
language sql
immutable
set search_path = pg_catalog
as $$
  with normalized as (
    select
      trim(regexp_replace(lower(coalesce(p_member_name, '')), '[^a-z0-9]+', ' ', 'g')) as member_name,
      trim(regexp_replace(lower(coalesce(p_report_name, '')), '[^a-z0-9]+', ' ', 'g')) as report_name
  ), member_words as (
    select word
    from normalized,
      regexp_split_to_table(member_name, '\\s+') as word
    where word <> ''
  )
  select
    (select count(*) from member_words) >= 2
    and not exists (
      select 1
      from member_words
      where position(' ' || word || ' ' in ' ' || (select report_name from normalized) || ' ') = 0
    )
  from normalized;
$$;

revoke all on function public.club_sweepstakes_name_contains_all_words(text, text) from public;
grant execute on function public.club_sweepstakes_name_contains_all_words(text, text) to authenticated;

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
    with all_active_members as (
      select m.id, m.showing_name, m.first_name, m.last_name, m.membership_type_id,
             mt.name as membership_type_name, m.state
      from public.club_memberships m
      join public.club_membership_types mt on mt.id = m.membership_type_id
      where m.club_id = v_board.club_id
        and m.status = 'active'
        and (m.current_term_end is null or m.current_term_end >= current_date)
    ), eligible_members as (
      select *
      from all_active_members m
      where (cardinality(v_board.membership_type_ids) = 0 or m.membership_type_id = any(v_board.membership_type_ids))
        and (
          v_board.residency_requirement = 'any'
          or (v_board.residency_requirement = 'in_state' and upper(coalesce(m.state, '')) = upper(coalesce(v_board.eligibility_state, '')))
          or (v_board.residency_requirement = 'out_of_state' and upper(coalesce(m.state, '')) <> upper(coalesce(v_board.eligibility_state, '')))
        )
    ), shared_rules as (
      select r.id, r.rule_type, r.match_value, r.replacement_value,
             count(a.id) filter (
               where public.club_sweepstakes_name_contains_all_words(
                 coalesce(nullif(a.showing_name, ''), concat_ws(' ', a.first_name, a.last_name)),
                 r.replacement_value
               )
             ) as all_member_count,
             count(e.id) filter (
               where public.club_sweepstakes_name_contains_all_words(
                 coalesce(nullif(e.showing_name, ''), concat_ws(' ', e.first_name, e.last_name)),
                 r.replacement_value
               )
             ) as eligible_member_count
      from public.club_sweepstakes_parser_rules r
      cross join all_active_members a
      left join eligible_members e on e.id = a.id
      where r.club_id = v_board.club_id
        and r.is_active
        and r.rule_type in ('name_alias', 'name_pattern')
        and nullif(trim(coalesce(r.replacement_value, '')), '') is not null
      group by r.id, r.rule_type, r.match_value, r.replacement_value
      having count(a.id) filter (
        where public.club_sweepstakes_name_contains_all_words(
          coalesce(nullif(a.showing_name, ''), concat_ws(' ', a.first_name, a.last_name)),
          r.replacement_value
        )
      ) >= 2
      and count(a.id) filter (
        where public.club_sweepstakes_name_contains_all_words(
          coalesce(nullif(a.showing_name, ''), concat_ws(' ', a.first_name, a.last_name)),
          r.replacement_value
        )
      ) = count(e.id) filter (
        where public.club_sweepstakes_name_contains_all_words(
          coalesce(nullif(e.showing_name, ''), concat_ws(' ', e.first_name, e.last_name)),
          r.replacement_value
        )
      )
    ), direct_entries as (
      select
        'member:' || e.id::text as entry_key,
        coalesce(nullif(e.showing_name, ''), nullif(concat_ws(' ', e.first_name, e.last_name), ''), s.exhibitor_name) as entry_name,
        e.membership_type_name as entry_type,
        s.total_points as entry_points
      from public.club_sweepstakes_standings s
      join eligible_members e on (
        public.club_sweepstakes_names_match(e.showing_name, s.exhibitor_name)
        or public.club_sweepstakes_names_match(concat_ws(' ', e.first_name, e.last_name), s.exhibitor_name)
      )
      where s.club_id = v_board.club_id and s.season_id = v_board.season_id
    ), shared_entries as (
      select distinct on (s.id)
        'shared:' || sr.id::text || ':' || s.id::text as entry_key,
        coalesce(nullif(sr.replacement_value, ''), s.exhibitor_name) as entry_name,
        'Combined active members'::text as entry_type,
        s.total_points as entry_points
      from public.club_sweepstakes_standings s
      join shared_rules sr on (
        (sr.rule_type = 'name_alias' and public.club_sweepstakes_names_match(sr.match_value, s.exhibitor_name))
        or (
          sr.rule_type = 'name_pattern'
          and public.club_sweepstakes_name_contains_all_words(sr.match_value, s.exhibitor_name)
        )
      )
      where s.club_id = v_board.club_id and s.season_id = v_board.season_id
      order by s.id, sr.id
    ), ranked as (
      select
        row_number() over (order by sum(entry_points) desc, min(entry_name))::integer as entry_rank,
        min(entry_name) as entry_name,
        min(entry_type) as entry_type,
        sum(entry_points) as entry_points
      from (
        select * from direct_entries
        union all
        select * from shared_entries
      ) entries
      group by entry_key
    )
    select entry_rank, entry_name, entry_type, null::text, entry_points
    from ranked
    where entry_rank <= v_board.top_n
    order by entry_rank;
  else
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
      select *
      from all_active_members m
      where (cardinality(v_board.membership_type_ids) = 0 or m.membership_type_id = any(v_board.membership_type_ids))
        and (
          v_board.residency_requirement = 'any'
          or (v_board.residency_requirement = 'in_state' and upper(coalesce(m.state, '')) = upper(coalesce(v_board.eligibility_state, '')))
          or (v_board.residency_requirement = 'out_of_state' and upper(coalesce(m.state, '')) <> upper(coalesce(v_board.eligibility_state, '')))
        )
    ), shared_rules as (
      select r.id, r.rule_type, r.match_value, r.replacement_value,
             count(a.id) filter (
               where public.club_sweepstakes_name_contains_all_words(
                 coalesce(nullif(a.showing_name, ''), concat_ws(' ', a.first_name, a.last_name)),
                 r.replacement_value
               )
             ) as all_member_count,
             count(e.id) filter (
               where public.club_sweepstakes_name_contains_all_words(
                 coalesce(nullif(e.showing_name, ''), concat_ws(' ', e.first_name, e.last_name)),
                 r.replacement_value
               )
             ) as eligible_member_count
      from public.club_sweepstakes_parser_rules r
      cross join all_active_members a
      left join eligible_members e on e.id = a.id
      where r.club_id = v_board.club_id
        and r.is_active
        and r.rule_type in ('name_alias', 'name_pattern')
        and nullif(trim(coalesce(r.replacement_value, '')), '') is not null
      group by r.id, r.rule_type, r.match_value, r.replacement_value
      having count(a.id) filter (
        where public.club_sweepstakes_name_contains_all_words(
          coalesce(nullif(a.showing_name, ''), concat_ws(' ', a.first_name, a.last_name)),
          r.replacement_value
        )
      ) >= 2
      and count(a.id) filter (
        where public.club_sweepstakes_name_contains_all_words(
          coalesce(nullif(a.showing_name, ''), concat_ws(' ', a.first_name, a.last_name)),
          r.replacement_value
        )
      ) = count(e.id) filter (
        where public.club_sweepstakes_name_contains_all_words(
          coalesce(nullif(e.showing_name, ''), concat_ws(' ', e.first_name, e.last_name)),
          r.replacement_value
        )
      )
    ), direct_entries as (
      select
        'member:' || e.id::text || ':' || r.breed as entry_key,
        coalesce(nullif(e.showing_name, ''), nullif(concat_ws(' ', e.first_name, e.last_name), ''), r.exhibitor_name) as entry_name,
        e.membership_type_name as entry_type,
        r.breed as entry_breed,
        a.points_applied as entry_points
      from public.club_sweepstakes_result_applications a
      join public.club_sweepstakes_result_import_rows r on r.id = a.result_row_id
      join public.club_sweepstakes_result_imports i on i.id = a.import_id
      join eligible_members e on (
        public.club_sweepstakes_names_match(e.showing_name, r.exhibitor_name)
        or public.club_sweepstakes_names_match(concat_ws(' ', e.first_name, e.last_name), r.exhibitor_name)
      )
      where a.club_id = v_board.club_id and i.season_id = v_board.season_id
        and nullif(trim(coalesce(r.breed, '')), '') is not null
    ), shared_entries as (
      select distinct on (a.id)
        'shared:' || sr.id::text || ':' || r.breed as entry_key,
        coalesce(nullif(sr.replacement_value, ''), r.exhibitor_name) as entry_name,
        'Combined active members'::text as entry_type,
        r.breed as entry_breed,
        a.points_applied as entry_points
      from public.club_sweepstakes_result_applications a
      join public.club_sweepstakes_result_import_rows r on r.id = a.result_row_id
      join public.club_sweepstakes_result_imports i on i.id = a.import_id
      join shared_rules sr on (
        (sr.rule_type = 'name_alias' and public.club_sweepstakes_names_match(sr.match_value, r.exhibitor_name))
        or (
          sr.rule_type = 'name_pattern'
          and public.club_sweepstakes_name_contains_all_words(sr.match_value, r.exhibitor_name)
        )
      )
      where a.club_id = v_board.club_id and i.season_id = v_board.season_id
        and nullif(trim(coalesce(r.breed, '')), '') is not null
      order by a.id, sr.id
    ), ranked as (
      select
        row_number() over (partition by entry_breed order by sum(entry_points) desc, min(entry_name))::integer as entry_rank,
        min(entry_name) as entry_name,
        min(entry_type) as entry_type,
        entry_breed,
        sum(entry_points) as entry_points
      from (
        select * from direct_entries
        union all
        select * from shared_entries
      ) entries
      group by entry_key, entry_breed
    )
    select entry_rank, entry_name, entry_type, entry_breed, entry_points
    from ranked
    where entry_rank <= v_board.top_n
    order by entry_breed, entry_rank;
  end if;
end;
$$;
